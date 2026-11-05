"""What the tools share (v0.8.4.29.7): the paths of the repo, Godot and the game's user dir, the backend traces of the
dev server and of the build's own server, a free port, a slug of a Russian name. Imported by the tools beside it."""

import os
import socket
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
USER_DIR = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Godot" / "app_userdata" / "Between the Rolls"
DEV_VAR = ROOT / "llm_server" / "var"  # the dev llm_server's data: traces, bills, the item library
GAME_VAR = USER_DIR / "master"  # the frozen server.exe of the build keeps its data in the game's user dir (ADR-0014)

TRANSLIT = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f",
                     "kh", "ts", "ch", "sh", "shch", "", "y", "", "e", "yu", "ya"]))


def godot() -> str:
    """The Godot binary: env GODOT or the Steam install."""
    return os.environ.get("GODOT", DEFAULT_GODOT)


def backend_trace_dirs() -> list[Path]:
    """Where the model side of a session is: the dev server's traces and the build's own (the author plays the build)."""
    return [d for d in (DEV_VAR / "traces", GAME_VAR / "traces") if d.exists()]


def port_busy(port: int) -> bool:
    # A bind, not a connect: Windows may reserve a port range (WinError 10013) that nobody listens on.
    with socket.socket() as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return True
        return False


def free_port(start: int, span: int = 300) -> int:
    """The first free port from `start` on (the player's own llm_server may hold it); `start + span` when all are busy."""
    port = start
    while port_busy(port) and port < start + span:
        port += 1
    return port


def slug(name: str, sep: str = "_", empty: str = "item") -> str:
    import re

    s = "".join(TRANSLIT.get(ch, ch) for ch in name.lower())
    return re.sub(r"[^a-z0-9]+", sep, s).strip(sep)[:40] or empty
