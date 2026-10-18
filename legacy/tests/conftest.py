"""Shared pytest setup: mirror ``game/main.py`` path layout for ``core.*`` imports."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_LEGACY = Path(__file__).resolve().parents[1]
_ROOT = _LEGACY.parent  # repository root (sibling checkouts live here)
PROJECT_ROOT = _LEGACY

_tests_dir = Path(__file__).resolve().parent
if str(_tests_dir) not in sys.path:
    sys.path.insert(0, str(_tests_dir))

for _path in (_LEGACY / "game", _ROOT / "dnd-5e-core", _ROOT / "DnD-5th-Edition-API"):
    _s = str(_path)
    if _path.is_dir() and _s not in sys.path:
        sys.path.insert(0, _s)


@pytest.fixture
def patched_game_state(monkeypatch: pytest.MonkeyPatch):
    """Patch ``core.data.game_state`` to a fresh ``MainGameState`` for loaders/trade."""
    import core.data as gd
    from core.data.game_state_base import MainGameState

    gs = MainGameState()
    monkeypatch.setattr(gd, "game_state", gs)
    return gs
