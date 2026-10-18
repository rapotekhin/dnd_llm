"""`uv run llm_server` — start the backend with uvicorn."""

import asyncio
import logging
import os
import sys

import uvicorn

from .app import create_app
from .config import ConfigError, Settings

log = logging.getLogger("llm_server")


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


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")
    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        sys.exit(f"llm_server: {exc}")
    if settings.turn_handler == "agent":
        from .llm.catalog import check_openrouter_key

        left = asyncio.run(check_openrouter_key(settings.openrouter_api_key))
        if left is None:
            sys.exit("llm_server: OPENROUTER_API_KEY was rejected by OpenRouter")
        log.info("OpenRouter key ok, credits left $%.2f; default model %s", left, settings.model)
        if settings.langfuse:
            _setup_langfuse()
    else:
        log.info("turn handler: stub (no LLM)")
    uvicorn.run(
        create_app(settings, load_prices=settings.turn_handler == "agent"),
        host=settings.host,
        port=settings.port,
        ws="websockets-sansio",
        ws_max_size=settings.max_message_bytes,
        ws_ping_interval=settings.ws_ping_interval,
        ws_ping_timeout=settings.ws_ping_timeout,
        log_level="info",
    )


if __name__ == "__main__":
    main()
