"""`uv run llm_server` — start the backend with uvicorn."""

import logging
import sys

import uvicorn

from .app import create_app
from .config import ConfigError, Settings


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        sys.exit(f"llm_server: {exc}")
    uvicorn.run(
        create_app(settings),
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
