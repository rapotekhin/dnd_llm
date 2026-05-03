"""Loading start locations/NPCs from JSONL into ``MainGameState``."""

from __future__ import annotations

from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]

from core.loaders.locations_loader import load_locations_from_jsonl
from core.loaders.npcs_loader import fill_npc_inventory, load_npcs_from_jsonl
from core.entities.npc import NPC


START_LOC = PROJECT_ROOT / "game" / "assets" / "ru" / "start_locations.jsonl"
START_NPCS = PROJECT_ROOT / "game" / "assets" / "ru" / "start_npcs.jsonl"


@pytest.mark.skipif(not START_LOC.is_file(), reason="start_locations.jsonl missing")
def test_load_start_locations_jsonl(patched_game_state) -> None:
    load_locations_from_jsonl(str(START_LOC))
    assert len(patched_game_state.locations) >= 1
    assert len(patched_game_state.rooms) >= 1
    assert len(patched_game_state.levels) >= 1


@pytest.mark.skipif(not START_NPCS.is_file(), reason="start_npcs.jsonl missing")
def test_load_start_npcs_jsonl(patched_game_state) -> None:
    load_npcs_from_jsonl(str(START_NPCS))
    assert len(patched_game_state.npcs) >= 1


def test_fill_npc_inventory_alchemist_gets_stock() -> None:
    npc = NPC.create_random_character(name="Alchy", race="human", class_type="cleric", level=1)
    npc.role = "alchemist"
    npc.inventory = []
    fill_npc_inventory(npc)
    assert len(npc.inventory) >= 1


def test_fill_npc_inventory_miner_empty_rules() -> None:
    npc = NPC.create_random_character(name="Miner", race="dwarf", class_type="fighter", level=1)
    npc.role = "miner"
    npc.inventory = []
    fill_npc_inventory(npc)
    assert npc.inventory == []
