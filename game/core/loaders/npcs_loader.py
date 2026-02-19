# Load NPCs from JSONL file stored in assets/ru/start_npcs.jsonl

from typing import List
from core.utils.load_functions import load_jsonl_file
from core.entities.npc import NPC


def load_npcs_from_jsonl(file_path: str):
    """Load NPCs from JSONL file and add them to game_state.npcs"""
    from core.data import game_state

    if game_state.npcs is None:
        assert False, "game_state.npcs is not initialized"

    npcs = load_jsonl_file(file_path)
    for npc_data in npcs:
        npc = NPC.create_random_character(
            name=npc_data.get("name"),
            race=npc_data.get("race"),
            class_type=npc_data.get("class_type"),
            level=npc_data.get("level", 1),
        )
        if npc_data.get("id") is not None:
            npc.id = npc_data["id"]
        game_state.npcs[npc.id] = npc
