"""Pickle save/load round-trip for ``MainGameState`` (world + NPC + quest, not only player name)."""

from __future__ import annotations

from datetime import datetime

from core.data import game_state_base as gsb
from core.data.quest import (
    Difficulty,
    Objective,
    ObjectiveStatus,
    Quest,
    QuestGiver,
    QuestStatus,
    Reward,
)
from core.entities.location import Location, Room
from core.entities.npc import NPC
from core.entities.player import Player


def test_save_load_roundtrip(tmp_path, monkeypatch, patched_game_state) -> None:
    monkeypatch.setattr(gsb, "SAVE_DIR", str(tmp_path))

    hero = Player.create_random_character(name="SaveMe", race="human", class_type="fighter")
    patched_game_state.player = hero

    patched_game_state.locations["loc1"] = Location(
        id="loc1",
        name="Inn",
        description="A place.",
        type="town",
        subtype="tavern",
        region="FR",
        city="NW",
        location_history_summary="visited",
    )
    patched_game_state.rooms["r1"] = Room(
        id="r1",
        name="Hall",
        level=0,
        description="Main.",
        location_id="loc1",
    )
    patched_game_state.current_location_id = "loc1"
    patched_game_state.current_room_id = "r1"

    npc = NPC.create_random_character(name="Saved NPC", race="elf", class_type="rogue", level=1)
    npc.id = "npc-save-1"
    patched_game_state.npcs[npc.id] = npc

    giver = QuestGiver(npc_id=npc.id, name=npc.name, location_id="loc1")
    obj = Objective(
        id="step1",
        description="Talk",
        order=1,
        status=ObjectiveStatus.AVAILABLE,
    )
    quest = Quest(
        id="quest-keep",
        name="Keep quest",
        description="Do not lose",
        giver=giver,
        location_id="loc1",
        difficulty=Difficulty.EASY,
        objectives=[obj],
        reward=Reward(coins=25),
        created_at=datetime(2026, 1, 1, 12, 0, 0),
        status=QuestStatus.IN_PROGRESS,
    )
    patched_game_state.quests[quest.id] = quest

    patched_game_state.save(slot := 4)
    loaded = patched_game_state.load(slot)

    assert loaded.player is not None
    assert loaded.player.name == "SaveMe"
    assert loaded.player.class_type.index == hero.class_type.index

    assert loaded.current_location_id == "loc1"
    assert loaded.current_room_id == "r1"
    assert loaded.locations["loc1"].name == "Inn"
    assert loaded.locations["loc1"].location_history_summary == "visited"
    assert loaded.rooms["r1"].location_id == "loc1"

    assert "npc-save-1" in loaded.npcs
    assert loaded.npcs["npc-save-1"].name == "Saved NPC"

    assert "quest-keep" in loaded.quests
    assert loaded.quests["quest-keep"].status == QuestStatus.IN_PROGRESS
    assert loaded.quests["quest-keep"].reward.coins == 25
