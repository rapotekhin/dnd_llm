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
        for i in range(1, 11):
            path = os.path.join(SAVE_DIR, f"save_{i}.pkl")
            if os.path.isfile(path):
                mtime = os.path.getmtime(path)
                out.append((i, datetime.datetime.fromtimestamp(mtime)))
        return out

    def _get_number_of_saves(self):
        return len([f for f in os.listdir(SAVE_DIR) if f.startswith("save_")])

    def save(self, i: int | None = None):
        if i is None:
            i = self._get_number_of_saves() + 1

        self.save_datetime = datetime.datetime.now()
        with open(os.path.join(SAVE_DIR, f"save_{i}.pkl"), "wb") as f:
            pickle.dump(self, f)

    def load(self, i: int):
        with open(os.path.join(SAVE_DIR, f"save_{i}.pkl"), "rb") as f:
            return pickle.load(f)


if __name__ == "__main__":
    import core.data as data_module
    gs = MainGameState()
    data_module.game_state = gs  # loaders import from core.data — must set the module attribute
    gs.load_start_data()
    print(gs)