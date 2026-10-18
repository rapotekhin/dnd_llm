"""Тут хранятся все данные игры, локации, персонаж, NPC, etc.
Этот фаил в случае сохранения игры будет сохраняться в файл save_{i}.pkl, где i - номер сохранения
Аналогично в случае загрузки игры будет загружаться из файла save_{i}.pkl, где i - номер сохранения

Глобальное состояние: ``game_state`` — экземпляр MainGameState.
Доступ из любого файла: ``from core.data import game_state`` или
``import core.data`` и ``core.data.game_state``.
"""

import dataclasses
from typing import Optional, List, Dict
from core.entities.base import ID
from core.entities.character import Character
import pickle
import os
import datetime
from core.data.quest import Quest, QuestStatus, ObjectiveStatus
from core.entities.npc import NPC
from core.entities.location import Location, IndoorLevel, Room
from core.entities.player import Player
from core.loaders.locations_loader import load_locations_from_jsonl
from core.loaders.npcs_loader import load_npcs_from_jsonl
from core.entities.treasure import Treasure

# AppData path
if os.name == "nt":
    # if Windows
    SAVE_DIR = os.path.join(os.path.expanduser("~"), "AppData", "Local", "DnD_LLM_Game", "saves")
else:
    SAVE_DIR = os.path.join(os.path.expanduser("~"), ".local", "share", "DnD_LLM_Game", "saves")

if not os.path.exists(SAVE_DIR):
    os.makedirs(SAVE_DIR)

SAVE_SLOTS = range(1, 11)


def _slot_path(i: int) -> str:
    if i not in SAVE_SLOTS:
        raise ValueError(f"save slot must be {SAVE_SLOTS.start}..{SAVE_SLOTS.stop - 1}, got {i}")
    return os.path.join(SAVE_DIR, f"save_{i}.pkl")

@dataclasses.dataclass
class MainGameState:
    """Game session and world state. Created at startup, player set after creation."""

    player: Optional[Player] = None
    quests: Dict[ID, Quest] = dataclasses.field(default_factory=dict)
    npcs: Dict[ID, NPC] = dataclasses.field(default_factory=dict)
    locations: Dict[ID, Location] = dataclasses.field(default_factory=dict)
    levels: Dict[ID, IndoorLevel] = dataclasses.field(default_factory=dict)
    rooms: Dict[ID, Room] = dataclasses.field(default_factory=dict)
    treasures: Dict[ID, Treasure] = dataclasses.field(default_factory=dict)
    current_location_id: Optional[ID] = None
    current_room_id: Optional[ID] = None
    # game_history: List[str] = dataclasses.field(default_factory=list)

    save_datetime: Optional[datetime.datetime] = None

    # def __init__(self, *args, **kwargs):
    #     super().__init__(*args, **kwargs)

    def load_start_data(self):

        print("Loading locations and npcs...")
        start_locations = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ru", "start_locations.jsonl")
        start_npcs = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ru", "start_npcs.jsonl")

        if not os.path.exists(start_locations):
            raise FileNotFoundError(f"Start locations file not found: {start_locations}")
        if not os.path.exists(start_npcs):
            raise FileNotFoundError(f"Start npcs file not found: {start_npcs}")

        load_locations_from_jsonl(start_locations)
        load_npcs_from_jsonl(start_npcs)

        self.current_location_id = "tawern-001"
        self.current_room_id = "tavern-room-001"

    @staticmethod
    def list_saves() -> "list[tuple[int, datetime.datetime]]":
        """Return [(slot_index, save_datetime), ...] for slots 1..10 that have a save file."""
        out = []
        for i in SAVE_SLOTS:
            path = _slot_path(i)
            if os.path.isfile(path):
                mtime = os.path.getmtime(path)
                out.append((i, datetime.datetime.fromtimestamp(mtime)))
        return out

    @staticmethod
    def first_free_slot() -> int | None:
        """Lowest slot without a save file, or None if all slots are taken."""
        for i in SAVE_SLOTS:
            if not os.path.isfile(_slot_path(i)):
                return i
        return None

    def save(self, i: int | None = None) -> int:
        """Save to slot ``i`` (or the first free one) atomically; returns the slot."""
        if i is None:
            i = self.first_free_slot()
            if i is None:
                raise ValueError("all save slots are taken; pick a slot to overwrite")
        path = _slot_path(i)

        self.save_datetime = datetime.datetime.now()
        # Write a temp file first so a crash mid-write never corrupts the slot.
        tmp_path = path + ".tmp"
        with open(tmp_path, "wb") as f:
            pickle.dump(self, f)
        os.replace(tmp_path, path)
        return i

    def load(self, i: int):
        with open(_slot_path(i), "rb") as f:
            return pickle.load(f)


if __name__ == "__main__":
    import core.data as data_module
    gs = MainGameState()
    data_module.game_state = gs  # loaders import from core.data — must set the module attribute
    gs.load_start_data()
    print(gs)