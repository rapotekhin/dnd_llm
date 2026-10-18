"""Between the Rolls LLM backend: stateless, talks to the Godot client over WebSocket + JSON-RPC 2.0."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


def _read_version() -> str:
    # The server ships from the repository, so it reports the project version from the root VERSION file.
    try:
        return (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        return "0.0.0+unknown"


__version__ = _read_version()
