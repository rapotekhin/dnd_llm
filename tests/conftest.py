"""Shared pytest setup: mirror ``game/main.py`` path layout for ``core.*`` imports."""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]

for _path in (_ROOT / "game", _ROOT / "dnd-5e-core", _ROOT / "DnD-5th-Edition-API"):
    _s = str(_path)
    if _path.is_dir() and _s not in sys.path:
        sys.path.insert(0, _s)
