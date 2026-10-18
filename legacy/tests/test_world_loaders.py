"""Loading start locations/NPCs from JSONL into ``MainGameState``."""

from __future__ import annotations

from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]

from core.entities.npc import NPC
from core.loaders.locations_loader import load_locations_from_jsonl
from core.loaders.npcs_loader import fill_npc_inventory, load_npcs_from_jsonl


START_LOC = PROJECT_ROOT / "game" / "assets" / "ru" / "start_locations.jsonl"
START_NPCS = PROJECT_ROOT / "game" / "assets" / "ru" / "start_npcs.jsonl"


@pytest.mark.skipif(not START_LOC.is_file(), reason="start_locations.jsonl missing")
def test_load_start_locations_known_ids_and_links(patched_game_state) -> None:
    load_locations_from_jsonl(str(START_LOC))

    tavern = patched_game_state.locations["tawern-001"]
    assert tavern.name == "Серебряная Кружка"
    assert tavern.subtype == "tavern"
    assert tavern.entrance_room_id == "tavern-room-001"

    main_hall = patched_game_state.rooms["tavern-room-001"]
    assert main_hall.name == "Главный зал"
    assert main_hall.location_id == "tawern-001"
    assert "tavern-room-002" in main_hall.connections


@pytest.mark.skipif(not START_NPCS.is_file(), reason="start_npcs.jsonl missing")
def test_load_start_npcs_known_ids(patched_game_state) -> None:
    load_npcs_from_jsonl(str(START_NPCS))
    assert "mkt-npc-002" in patched_game_state.npcs
    assert patched_game_state.npcs["mkt-npc-002"].role == "alchemist"


def test_fill_npc_inventory_alchemist_has_potion_like_gear() -> None:
    npc = NPC.create_random_character(name="Alchy", race="human", class_type="cleric", level=1)
    npc.role = "alchemist"
    npc.inventory = []
    fill_npc_inventory(npc)
    indices = {getattr(it, "index", "") or "" for it in npc.inventory if it}
    assert any("potion" in ix for ix in indices), f"expected potion-like items, got {indices!r}"


def test_fill_npc_inventory_miner_empty_rules() -> None:
    npc = NPC.create_random_character(name="Miner", race="dwarf", class_type="fighter", level=1)
    npc.role = "miner"
    npc.inventory = []
    fill_npc_inventory(npc)
    assert npc.inventory == []
