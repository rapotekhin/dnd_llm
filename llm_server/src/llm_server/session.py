"""One WebSocket connection = one Session: JSON-RPC in both directions over a single socket (ADR-0009)."""

import asyncio
import itertools
import json
import logging
import time
from collections.abc import Awaitable, Callable
from typing import TYPE_CHECKING, Any

from fastapi import WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ValidationError

from . import __version__
from .protocol import (
    PROTOCOL_VERSION,
    RETRYABLE,
    Budget,
    SetBudgetParams,
    ErrorCode,
    HelloParams,
    HelloResult,
    ImageParams,
    ImageResult,
    Limits,
    OkResult,
    StatusResult,
    SummaryParams,
    SummaryResult,
    TurnCancelParams,
    TurnRequestParams,
    TurnResult,
    protocol_compatible,
)

if TYPE_CHECKING:
    from .services import Services

log = logging.getLogger("llm_server.session")

CLOSE_VERSION_MISMATCH = 4001
CLOSE_HELLO_TIMEOUT = 4002
CLOSE_MESSAGE_TOO_BIG = 1009

# Methods the backend may call on Godot, and only inside an active turn (ADR-0009 §3).
ENGINE_METHODS = frozenset({"engine.check", "engine.validate", "engine.lookup", "engine.find_items", "engine.find_npcs", "engine.find_places",
                            "engine.find_quests", "engine.find_teachers"})


class RpcError(Exception):
    def __init__(self, code: ErrorCode, message: str | None = None):
        super().__init__(message or code.name.lower())
        self.code = code
        self.engine_code: int | None = None  # the engine's own error code of an ENGINE_ERROR

    def to_json(self) -> dict[str, Any]:
        reason = self.code.name.lower()
        return {
            "code": int(self.code),
            "message": str(self),
            "data": {"reason": reason, "retryable": self.code in RETRYABLE},
        }


class EngineCallError(Exception):
    """Godot answered an engine.* call with an error."""

    def __init__(self, error: dict[str, Any]):
        super().__init__(error.get("message", "engine error"))
        self.error = error


TurnHandler = Callable[["Session", TurnRequestParams], Awaitable[TurnResult]]
SummaryHandler = Callable[["Session", SummaryParams], Awaitable[SummaryResult]]
ImageHandler = Callable[["Session", ImageParams], Awaitable[ImageResult]]


class TurnSlots:
    """Server-wide limit on concurrent turns (ADR-0009 §2, default 1)."""

    def __init__(self, limit: int):
        self.limit = limit
        self.active = 0

    def try_acquire(self) -> bool:
        if self.active >= self.limit:
            return False
        self.active += 1
        return True

    def release(self) -> None:
        self.active -= 1


class Session:
    def __init__(self, ws: WebSocket, services: "Services", slots: TurnSlots, turn_handler: TurnHandler,
                 summary_handler: SummaryHandler, image_handler: ImageHandler | None = None):
        self.ws = ws
        self.services = services
        self.settings = services.settings
        self.slots = slots
        self.turn_handler = turn_handler
        self.summary_handler = summary_handler
        self.image_handler = image_handler
        self.initialized = False
        self.closed = False
        self._send_lock = asyncio.Lock()
        self._ids = itertools.count(1)
        self._pending: dict[str, asyncio.Future[Any]] = {}
        self._tasks: set[asyncio.Task[None]] = set()
        self._turn_id: str | None = None
        self._turn_task: asyncio.Task[Any] | None = None

    # --- main loop -----------------------------------------------------------

    async def run(self) -> None:
        watchdog = asyncio.create_task(self._hello_watchdog())
        try:
            while True:
                raw = await self.ws.receive_text()
                if len(raw.encode("utf-8")) > self.settings.max_message_bytes:
                    await self.ws.close(code=CLOSE_MESSAGE_TOO_BIG)
                    return
                await self._on_message(raw)
        except WebSocketDisconnect:
            pass
        finally:
            watchdog.cancel()
            self._shutdown()

    async def _hello_watchdog(self) -> None:
        await asyncio.sleep(self.settings.hello_timeout)
        if not self.initialized:
            log.info("no session.hello in %.0fs, closing", self.settings.hello_timeout)
            await self.ws.close(code=CLOSE_HELLO_TIMEOUT)

    def _shutdown(self) -> None:
        # A dropped connection burns the turn: cancel it and fail every engine.* call still waiting.
        self.closed = True
        if self._turn_task:
            self._turn_task.cancel()
        for task in self._tasks:
            task.cancel()
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel()
        self._pending.clear()

    # --- incoming ------------------------------------------------------------

    async def _on_message(self, raw: str) -> None:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await self._send_error(None, RpcError(ErrorCode.PARSE_ERROR))
            return
        if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0":
            await self._send_error(None, RpcError(ErrorCode.INVALID_REQUEST))
            return
        if "method" in msg:
            if "id" not in msg:
                return  # notifications are not used by the protocol yet
            self._spawn(self._handle_request(msg))
        elif "id" in msg:
            self._on_response(msg)
        else:
            await self._send_error(None, RpcError(ErrorCode.INVALID_REQUEST))

    def _spawn(self, coro: Awaitable[None]) -> None:
        # Requests run as tasks so the receive loop keeps reading engine.* answers during a turn.
        task = asyncio.ensure_future(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _handle_request(self, msg: dict[str, Any]) -> None:
        req_id, method = msg["id"], msg["method"]
        params = msg.get("params") or {}
        started = time.monotonic()
        try:
            result = await self._dispatch(method, params)
        except RpcError as err:
            log.info("%s id=%s -> error %s (%.0f ms)", method, req_id, err.code.name, _ms(started))
            await self._send_error(req_id, err)
            if err.code is ErrorCode.VERSION_MISMATCH:
                await self.ws.close(code=CLOSE_VERSION_MISMATCH)
            return
        except Exception:
            log.exception("%s id=%s crashed", method, req_id)
            await self._send_error(req_id, RpcError(ErrorCode.INTERNAL_ERROR))
            return
        log.info("%s id=%s ok (%.0f ms)", method, req_id, _ms(started))
        await self._send({"jsonrpc": "2.0", "id": req_id, "result": result.model_dump(mode="json")})

    async def _dispatch(self, method: str, params: Any) -> BaseModel:
        if method == "session.hello":
            hello = _parse(HelloParams, params)
            if self.services.images:
                await self.services.images.refresh()  # an own Forge may have come up or gone since the last hello
            return self._hello(hello)
        if not self.initialized:
            raise RpcError(ErrorCode.NOT_INITIALIZED)
        if method == "turn.request":
            return await self._turn(_parse(TurnRequestParams, params))
        if method == "turn.cancel":
            return self._cancel(_parse(TurnCancelParams, params))
        if method == "session.status":
            return self._status()
        if method == "session.set_budget":
            self.services.budget.set_limit(_parse(SetBudgetParams, params).daily_usd)
            return self._status()
        if method == "summary.request":
            # Runs alongside a turn (ADR-0009 §2); it does not take a turn slot.
            return await self.summary_handler(self, _parse(SummaryParams, params))
        if method == "image.request":
            # Beside a turn like a summary (0.71.0): the player may draw while the master answers.
            if self.image_handler is None:
                raise RpcError(ErrorCode.METHOD_NOT_FOUND)
            return await self.image_handler(self, _parse(ImageParams, params))
        raise RpcError(ErrorCode.METHOD_NOT_FOUND)

    def _on_response(self, msg: dict[str, Any]) -> None:
        fut = self._pending.pop(str(msg["id"]), None)
        if fut is None or fut.done():
            return  # late answer to a call that already timed out
        if "error" in msg:
            fut.set_exception(EngineCallError(msg["error"] or {}))
        else:
            fut.set_result(msg.get("result"))

    # --- methods -------------------------------------------------------------

    def _hello(self, params: HelloParams) -> HelloResult:
        if not protocol_compatible(params.protocol_version):
            raise RpcError(
                ErrorCode.VERSION_MISMATCH,
                f"client protocol {params.protocol_version}, server {PROTOCOL_VERSION}",
            )
        self.initialized = True
        s = self.settings
        images = self.services.images
        return HelloResult(
            protocol_version=PROTOCOL_VERSION,
            server_version=__version__,
            model=s.model,
            models=self.services.models.infos(),
            limits=Limits(
                max_message_bytes=s.max_message_bytes,
                turn_timeout_s=s.turn_timeout,
                engine_timeout_s=s.engine_timeout,
                hello_timeout_s=s.hello_timeout,
            ),
            image_model=images.default if images else "",
            image_models=images.infos() if images else [],
        )

    def _status(self) -> StatusResult:
        budget = self.services.budget
        return StatusResult(
            server_version=__version__,
            model=self.settings.model,
            models=self.services.models.infos(),
            budget=Budget(daily_usd=budget.limit_usd, spent_today_usd=round(budget.spent_today(), 6)),
        )

    async def _turn(self, params: TurnRequestParams) -> TurnResult:
        if self._turn_id is not None:
            raise RpcError(ErrorCode.TURN_IN_PROGRESS)
        if not self.slots.try_acquire():
            raise RpcError(ErrorCode.SERVER_BUSY)
        self._turn_id = params.turn_id
        self._turn_task = asyncio.ensure_future(self.turn_handler(self, params))
        try:
            return await asyncio.wait_for(asyncio.shield(self._turn_task), self.settings.turn_timeout)
        except TimeoutError:
            self._turn_task.cancel()
            raise RpcError(ErrorCode.TURN_TIMEOUT) from None
        except asyncio.CancelledError:
            if self._turn_task.cancelled():
                raise RpcError(ErrorCode.TURN_CANCELLED) from None
            raise
        finally:
            self._turn_id = None
            self._turn_task = None
            self.slots.release()

    def _cancel(self, params: TurnCancelParams) -> OkResult:
        if self._turn_id == params.turn_id and self._turn_task:
            self._turn_task.cancel()
        return OkResult()

    # --- outgoing engine.* calls ---------------------------------------------

    async def call_engine(self, method: str, params: BaseModel) -> Any:
        """Call Godot from inside the active turn. Raises RpcError(ENGINE_TIMEOUT / ENGINE_ERROR)."""
        if method not in ENGINE_METHODS:
            raise ValueError(f"not an engine method: {method}")
        if self._turn_id is None:
            raise RuntimeError("engine.* calls are allowed only inside an active turn")
        call_id = f"s-{next(self._ids)}"
        fut: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
        self._pending[call_id] = fut
        started = time.monotonic()
        await self._send(
            {"jsonrpc": "2.0", "id": call_id, "method": method, "params": params.model_dump(mode="json", exclude_none=True)}
        )
        try:
            result = await asyncio.wait_for(fut, self.settings.engine_timeout)
        except TimeoutError:
            log.info("%s id=%s -> engine timeout", method, call_id)
            raise RpcError(ErrorCode.ENGINE_TIMEOUT) from None
        except EngineCallError as err:
            log.info("%s id=%s -> engine error %s", method, call_id, err.error.get("code"))
            failed = RpcError(ErrorCode.ENGINE_ERROR, str(err))
            failed.engine_code = err.error.get("code")  # INVALID_PARAMS — the engine refused the values, not a crash
            raise failed from None
        finally:
            self._pending.pop(call_id, None)
        log.info("%s id=%s ok (%.0f ms)", method, call_id, _ms(started))
        return result

    # --- sending -------------------------------------------------------------

    async def _send(self, msg: dict[str, Any]) -> None:
        raw = json.dumps(msg, ensure_ascii=False)
        if len(raw.encode("utf-8")) > self.settings.max_message_bytes:
            raise RpcError(ErrorCode.INTERNAL_ERROR, "outgoing message exceeds the size limit")
        if self.closed:
            return
        log.debug("-> %s", raw)
        async with self._send_lock:
            await self.ws.send_text(raw)

    async def _send_error(self, req_id: Any, err: RpcError) -> None:
        await self._send({"jsonrpc": "2.0", "id": req_id, "error": err.to_json()})


def _parse[M: BaseModel](model: type[M], params: Any) -> M:
    try:
        return model.model_validate(params)
    except ValidationError as exc:
        raise RpcError(ErrorCode.INVALID_PARAMS, exc.errors(include_url=False)[0]["msg"]) from None


def _ms(started: float) -> float:
    return (time.monotonic() - started) * 1000
