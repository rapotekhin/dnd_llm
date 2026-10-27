"""FastAPI app: GET /healthz and the /ws endpoint (token check at upgrade, then a Session)."""

import hmac
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket
from fastapi.responses import PlainTextResponse

from . import __version__
from .config import Settings
from .services import Services
from .session import ImageHandler, Session, SummaryHandler, TurnHandler, TurnSlots

log = logging.getLogger("llm_server")


def create_app(
    settings: Settings,
    services: Services | None = None,
    turn_handler: TurnHandler | None = None,
    summary_handler: SummaryHandler | None = None,
    image_handler: ImageHandler | None = None,
    load_prices: bool = False,
) -> FastAPI:
    from .images import agent_image, stub_image
    from .turns import agent_summary, agent_turn, stub_summary, stub_turn

    if services is None:
        factory = None
        if settings.turn_handler == "agent":
            from .llm.catalog import openrouter_factory

            factory = openrouter_factory(settings.openrouter_api_key)
        services = Services.create(settings, factory)
    use_agent = services.model_factory is not None
    turn_handler = turn_handler or (agent_turn if use_agent else stub_turn)
    summary_handler = summary_handler or (agent_summary if use_agent else stub_summary)
    image_handler = image_handler or (agent_image if use_agent else stub_image)
    slots = TurnSlots(settings.max_concurrent_turns)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        if load_prices:
            await services.models.load_prices()
            await services.models.load_providers()
        yield

    app = FastAPI(title="Between the Rolls LLM backend", version=__version__, docs_url=None, redoc_url=None,
                  lifespan=lifespan)
    app.state.services = services

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
        await Session(ws, services, slots, turn_handler, summary_handler, image_handler).run()
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
