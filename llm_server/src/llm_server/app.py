"""FastAPI app: GET /healthz and the /ws endpoint (token check at upgrade, then a Session)."""

import hmac
import logging

from fastapi import FastAPI, WebSocket
from fastapi.responses import PlainTextResponse

from . import __version__
from .config import Settings
from .session import Session, TurnHandler, TurnSlots
from .turns import stub_turn

log = logging.getLogger("llm_server")


def create_app(settings: Settings, turn_handler: TurnHandler = stub_turn) -> FastAPI:
    app = FastAPI(title="Between the Rolls LLM backend", version=__version__, docs_url=None, redoc_url=None)
    slots = TurnSlots(settings.max_concurrent_turns)

    @app.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket) -> None:
        if not _authorized(ws.headers.get("authorization", ""), settings.token):
            log.info("rejected connection from %s: bad token", ws.client.host if ws.client else "?")
            await _deny(ws)
            return
        await ws.accept()
        log.info("connected %s", ws.client.host if ws.client else "?")
        await Session(ws, settings, slots, turn_handler).run()
        log.info("disconnected")

    return app


def _authorized(header: str, token: str) -> bool:
    scheme, _, value = header.partition(" ")
    return scheme.lower() == "bearer" and hmac.compare_digest(value.encode(), token.encode())


async def _deny(ws: WebSocket) -> None:
    # ADR-0009: a bad token gets HTTP 401 at the upgrade, the socket never opens.
    if "websocket.http.response" in ws.scope.get("extensions", {}):
        await ws.send_denial_response(PlainTextResponse("unauthorized", status_code=401))
    else:
        await ws.close(code=1008)  # servers without the denial extension answer 403
