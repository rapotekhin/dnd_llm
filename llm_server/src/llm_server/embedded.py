"""The server a game started by itself (ADR-0014): one listening socket on a port the system picks, the port told
through a file once the app is up, and an end together with the game that started it."""

import logging
import os
import socket
import sys
import threading
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

log = logging.getLogger("llm_server")

LOOPBACK = "127.0.0.1"
LOG_BYTES = 1024 * 1024
_SYNCHRONIZE = 0x00100000
_INFINITE = 0xFFFFFFFF


def bind() -> socket.socket:
    """Listening already: a client that comes before uvicorn's accept loop waits in the backlog."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind((LOOPBACK, 0))
    sock.listen(128)
    return sock


def publish_port(path: Path, port: int) -> None:
    """Atomic: the game never reads half a number."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(str(port), encoding="ascii")
    os.replace(tmp, path)


def setup_logging(path: Path) -> None:
    """No console in the build: the log file is the only trace of a crash."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(path, maxBytes=LOG_BYTES, backupCount=1, encoding="utf-8")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s", handlers=[handler])
    sys.excepthook = lambda kind, value, tb: log.critical("crash", exc_info=(kind, value, tb))


def _wait_for_exit(pid: int) -> None:
    if sys.platform == "win32":
        import ctypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = ctypes.c_void_p
        kernel32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        handle = kernel32.OpenProcess(_SYNCHRONIZE, False, pid)
        if handle:  # no handle — the parent is gone already
            kernel32.WaitForSingleObject(handle, _INFINITE)
        return
    while os.getppid() == pid:
        time.sleep(1.0)


def watch_parent(pid: int) -> None:
    """The game kills the server at exit; this covers the game's own crash and a kill from the task manager."""

    def run() -> None:
        _wait_for_exit(pid)
        log.info("the game is gone, stopping")
        logging.shutdown()
        os._exit(0)

    threading.Thread(target=run, name="parent-watch", daemon=True).start()
