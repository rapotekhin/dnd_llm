"""Between the Rolls LLM backend: stateless, talks to the Godot client over WebSocket + JSON-RPC 2.0."""

import sys
from pathlib import Path

# A frozen server (tools/build_game.py) has no repository: its root is the bundle, with VERSION and no .env.
REPO_ROOT = Path(sys._MEIPASS) if getattr(sys, "frozen", False) else Path(__file__).resolve().parents[3]


def _read_version() -> str:
    # The server ships from the repository, so it reports the project version from the root VERSION file.
    try:
        return (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        return "0.0.0+unknown"


__version__ = _read_version()
