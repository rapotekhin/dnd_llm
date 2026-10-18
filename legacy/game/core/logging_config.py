"""
Centralised logging for the game.

Sets up a single console handler with a compact format, an INFO level for
``game.*`` loggers, a WARNING level for noisy third-party libraries, and global
exception hooks so that no error in the main thread or any background gameplay
thread is silently swallowed.

Use it from any module:

    from core.logging_config import get_logger
    log = get_logger(__name__)
    log.info("scene generated for %s", room.name)
    log.exception("agent crashed")  # inside an except block

Logfire spans (in exploration/social) are orthogonal — they keep working as
structured observability; this module is the local terminal stream.
"""
from __future__ import annotations

import logging
import os
import sys
import threading
from typing import Optional

_CONFIGURED: bool = False

# Compact format: "12:34:56.789 INFO    exploration message"
_FORMAT = "%(asctime)s.%(msecs)03d %(levelname)-7s %(name)s | %(message)s"
_DATEFMT = "%H:%M:%S"

# Loggers we want at INFO; everything else stays at WARNING by default.
_GAME_LOGGER_PREFIXES = ("game", "core", "ui")

# Noisy libraries we explicitly suppress to WARNING.
_NOISY_LIBS = (
    "httpx", "httpcore", "urllib3", "asyncio",
    "openai", "anthropic", "pydantic_ai",
    "logfire", "opentelemetry",
)


def configure_logging(level: Optional[int] = None) -> None:
    """Initialise logging. Idempotent — safe to call multiple times."""
    global _CONFIGURED
    if _CONFIGURED:
        return

    if level is None:
        env = os.getenv("DND_LOG_LEVEL", "INFO").upper()
        level = getattr(logging, env, logging.INFO)

    root = logging.getLogger()
    # Reset any pre-existing handlers (e.g. installed by libraries on import).
    for h in list(root.handlers):
        root.removeHandler(h)

    handler = logging.StreamHandler(stream=sys.stderr)
    handler.setFormatter(logging.Formatter(_FORMAT, datefmt=_DATEFMT))
    root.addHandler(handler)
    root.setLevel(logging.WARNING)  # keep root at WARNING; raise game.* below

    for prefix in _GAME_LOGGER_PREFIXES:
        logging.getLogger(prefix).setLevel(level)

    for lib in _NOISY_LIBS:
        logging.getLogger(lib).setLevel(logging.WARNING)

    # Route Python warnings (DeprecationWarning, etc.) through logging
    logging.captureWarnings(True)

    _install_excepthooks()

    _CONFIGURED = True
    logging.getLogger("core.logging_config").info(
        "logging configured (level=%s)", logging.getLevelName(level)
    )


def get_logger(name: str) -> logging.Logger:
    """Return a logger for the given module name. Triggers configure_logging if needed."""
    if not _CONFIGURED:
        configure_logging()
    return logging.getLogger(name)


# ----------------------------------------------------------------------
# Global exception hooks — make sure NOTHING fails silently
# ----------------------------------------------------------------------

def _install_excepthooks() -> None:
    log = logging.getLogger("core.excepthook")

    def _sys_hook(exc_type, exc_value, exc_tb):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        log.critical(
            "uncaught exception in main thread",
            exc_info=(exc_type, exc_value, exc_tb),
        )

    sys.excepthook = _sys_hook

    # threading.excepthook is Python 3.8+; gameplay loops run in daemon threads
    # and otherwise lose their traceback on unhandled errors.
    if hasattr(threading, "excepthook"):
        def _thread_hook(args: "threading.ExceptHookArgs") -> None:  # type: ignore[name-defined]
            if issubclass(args.exc_type, SystemExit):
                return
            log.error(
                "uncaught exception in thread %r",
                args.thread.name if args.thread else "?",
                exc_info=(args.exc_type, args.exc_value, args.exc_traceback),
            )

        threading.excepthook = _thread_hook
