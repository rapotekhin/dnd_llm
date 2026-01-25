"""Тут хранятся все данные игры, локации, персонаж, NPC, etc.
Этот фаил в случае сохранения игры будет сохраняться в файл save_{i}.pkl, где i - номер сохранения
Аналогично в случае загрузки игры будет загружаться из файла save_{i}.pkl, где i - номер сохранения

Глобальное состояние: ``game_state`` — экземпляр MainGameState.
Доступ из любого файла: ``from core.data import game_state`` или
``import core.data`` и ``core.data.game_state``.
"""

import dataclasses
from typing import Optional, List
from core.entities.character import Character
import pickle
import os
import datetime
from core.data.quest import Quest, QuestStatus, ObjectiveStatus
from core.entities.npc import NPC

# AppData path
if os.name == "nt":
    # if Windows
    SAVE_DIR = os.path.join(os.path.expanduser("~"), "AppData", "Local", "DnD_LLM_Game", "saves")
else:
    SAVE_DIR = os.path.join(os.path.expanduser("~"), ".local", "share", "DnD_LLM_Game", "saves")

if not os.path.exists(SAVE_DIR):
    os.makedirs(SAVE_DIR)

# Global game state. Initialized at startup in Game; use ``from core.data import game_state``.
game_state: Optional["MainGameState"] = None


@dataclasses.dataclass
class MainGameState:
    """Game session and world state. Created at startup, player set after creation."""

    player: Optional[Character] = None
    quests: List[Quest] = dataclasses.field(default_factory=list)
    npcs: List[NPC] = dataclasses.field(default_factory=list)
    game_history: List[str] = dataclasses.field(default_factory=list)

    save_datetime: Optional[datetime.datetime] = None

    def _get_number_of_saves(self):
        return len([f for f in os.listdir(SAVE_DIR) if f.startswith("save_")])

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

    def save(self, i: int | None = None):
        if i is None:
            i = self._get_number_of_saves() + 1

        self.save_datetime = datetime.datetime.now()
        with open(os.path.join(SAVE_DIR, f"save_{i}.pkl"), "wb") as f:
            pickle.dump(self, f)

    def load(self, i: int):
        with open(os.path.join(SAVE_DIR, f"save_{i}.pkl"), "rb") as f:
            return pickle.load(f)