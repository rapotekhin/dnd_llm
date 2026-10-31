"""`uv run llm_server` — start the backend with uvicorn. A game's build starts it frozen, as server.exe (ADR-0014)."""

import asyncio
import logging
import os
import sys
from pathlib import Path

import uvicorn

from . import embedded
from .app import create_app
from .config import ConfigError, Settings

log = logging.getLogger("llm_server")

EXIT_KEY_REJECTED = 3  # the game asks the player to check the key; any other exit is a crash


def _setup_langfuse() -> None:
    """Traces of every agent run to Langfuse (LANGFUSE_ENABLED=1 + LANGFUSE_* keys), through OpenTelemetry."""
    try:
        from langfuse import get_client
        from pydantic_ai import Agent
    except ImportError:
        log.warning("LANGFUSE_ENABLED=1 but langfuse is not installed: uv sync --group observability")
        return
    if get_client().auth_check():
        Agent.instrument_all()
        log.info("Langfuse tracing on")
    else:
        log.warning("Langfuse keys rejected, tracing off")


def _check_key(settings: Settings) -> None:
    from .llm.catalog import KeyRejected, check_openrouter_key

    try:
        left = asyncio.run(check_openrouter_key(settings.openrouter_api_key))
    except KeyRejected:
        if settings.embedded:
            log.error("the OpenRouter key was rejected")
            logging.shutdown()
            sys.exit(EXIT_KEY_REJECTED)
        sys.exit("llm_server: OPENROUTER_API_KEY was rejected by OpenRouter")
    if left is not None:
        log.info("OpenRouter key ok, credits left $%.2f; default model %s", left, settings.model)
    elif settings.embedded:  # no network says nothing about the key, and the game copes with a failed turn itself
        log.warning("OpenRouter gave no answer, the key is not checked")
    else:
        sys.exit("llm_server: OPENROUTER_API_KEY could not be checked: no answer from OpenRouter")


def main() -> None:
    os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")
    log_file = os.environ.get("LLM_SERVER_LOG_FILE", "")
    if log_file:
        embedded.setup_logging(Path(log_file))
    else:
        logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        log.error("%s", exc)
        sys.exit(f"llm_server: {exc}")
    if settings.parent_pid:
        embedded.watch_parent(settings.parent_pid)
    if settings.turn_handler == "agent":
        _check_key(settings)
        if settings.langfuse:
            _setup_langfuse()
    else:
        log.info("turn handler: stub (no LLM)")
    sock = embedded.bind() if settings.embedded else None
    on_started = (lambda: embedded.publish_port(settings.port_file, sock.getsockname()[1])) if sock is not None else None
    app = create_app(settings, load_prices=settings.turn_handler == "agent", on_started=on_started)
    server = uvicorn.Server(uvicorn.Config(
        app,
        host=settings.host,
        port=settings.port,
        ws="websockets-sansio",
        ws_max_size=settings.max_message_bytes,
        ws_ping_interval=settings.ws_ping_interval,
        ws_ping_timeout=settings.ws_ping_timeout,
        log_level="info",
        log_config=None if log_file else uvicorn.config.LOGGING_CONFIG,
    ))
    server.run(sockets=[sock] if sock is not None else None)
    if not server.started:
        sys.exit(1)


if __name__ == "__main__":
    main()
