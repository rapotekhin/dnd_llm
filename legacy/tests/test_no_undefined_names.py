"""Static check: no undefined names in legacy/game.

Screens split into mixins lost imports (SLOTS in trade/render.py, _sc in
level_up/mixins/events.py) and crashed only when drawn or clicked. pyflakes
cannot see through ``from ..colors import *``, so the star import is expanded
to the explicit color names before checking.
"""

from __future__ import annotations

import ast
import re
from pathlib import Path

import pytest

pyflakes_api = pytest.importorskip("pyflakes.api")
from pyflakes import messages as pyflakes_messages  # noqa: E402

GAME = Path(__file__).resolve().parents[1] / "game"
STAR_COLORS = re.compile(r"from (\.+)colors import \*")


def _color_names() -> list[str]:
    tree = ast.parse((GAME / "ui" / "colors.py").read_text(encoding="utf-8"))
    return [t.id for node in tree.body if isinstance(node, ast.Assign)
            for t in node.targets if isinstance(t, ast.Name)]


class _Collector:
    def __init__(self) -> None:
        self.messages: list = []

    def flake(self, message) -> None:
        self.messages.append(message)

    def syntaxError(self, filename, msg, lineno, offset, text) -> None:  # noqa: N802 — pyflakes API
        self.messages.append(f"{filename}:{lineno}: syntax error: {msg}")

    def unexpectedError(self, filename, msg) -> None:  # noqa: N802 — pyflakes API
        self.messages.append(f"{filename}: {msg}")


def test_no_undefined_names_in_legacy_game() -> None:
    explicit = ", ".join(_color_names())
    problems: list[str] = []
    for path in sorted(GAME.rglob("*.py")):
        if "dnd_5e_data" in path.parts or "__pycache__" in path.parts:
            continue
        source = STAR_COLORS.sub(lambda m: f"from {m.group(1)}colors import ({explicit})",
                                 path.read_text(encoding="utf-8"))
        collector = _Collector()
        pyflakes_api.check(source, str(path.relative_to(GAME)), collector)
        for msg in collector.messages:
            if isinstance(msg, str) or isinstance(msg, pyflakes_messages.UndefinedName):
                problems.append(str(msg))
    assert not problems, "undefined names:\n" + "\n".join(problems)
