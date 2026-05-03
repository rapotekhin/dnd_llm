"""Pickle save/load round-trip for ``MainGameState``."""

from __future__ import annotations

from core.data import game_state_base as gsb
from core.entities.player import Player


def test_save_load_roundtrip(tmp_path, monkeypatch, patched_game_state) -> None:
    monkeypatch.setattr(gsb, "SAVE_DIR", str(tmp_path))

    hero = Player.create_random_character(name="SaveMe", race="human", class_type="fighter")
    patched_game_state.player = hero

    patched_game_state.save(slot := 4)
    loaded = patched_game_state.load(slot)

    assert loaded.player is not None
    assert loaded.player.name == "SaveMe"
    assert loaded.player.class_type.index == hero.class_type.index
