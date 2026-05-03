"""Tests for level-up helpers (real ``JsonDatabase`` JSON under ``game/dnd_5e_data``)."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from core.utils import level_up_utils as lu


def test_can_level_up_none_player() -> None:
    assert lu.can_level_up(None) is False


def test_can_level_up_max_level() -> None:
    assert lu.can_level_up(SimpleNamespace(level=20, xp=999_999)) is False


@pytest.mark.parametrize(
    ("level", "xp", "expected"),
    [
        (1, 299, False),
        (1, 300, True),
        (2, 899, False),
        (2, 900, True),
    ],
)
def test_can_level_up_against_rules(level: int, xp: int, expected: bool) -> None:
    player = SimpleNamespace(level=level, xp=xp)
    assert lu.can_level_up(player) is expected


@pytest.mark.parametrize(
    ("level", "xp", "expected_next_threshold"),
    [
        (1, 0, 300),
        (2, 500, 900),
        (19, 0, 355000),
    ],
)
def test_get_next_level_xp_required(level: int, xp: int, expected_next_threshold: int) -> None:
    player = SimpleNamespace(level=level, xp=xp)
    assert lu.get_next_level_xp_required(player) == expected_next_threshold


def test_get_next_level_xp_required_max_level() -> None:
    assert lu.get_next_level_xp_required(SimpleNamespace(level=20, xp=0)) is None


def test_get_level_data_fighter_level_2() -> None:
    data = lu.get_level_data("fighter", 2)
    assert data is not None
    assert data.get("level") == 2


def test_get_level_data_missing_returns_none(monkeypatch: pytest.MonkeyPatch) -> None:
    class BrokenDb:
        def get(self, *_a, **_k):
            raise ValueError("missing")

    monkeypatch.setattr(lu, "JsonDatabase", BrokenDb)
    assert lu.get_level_data("no-such-class", 99) is None
