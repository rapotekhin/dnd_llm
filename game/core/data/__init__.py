"""Тут хранятся все данные игры, локации, персонаж, NPC, etc.
Этот фаил в случае сохранения игры будет сохраняться в файл save_{i}.pkl, где i - номер сохранения
Аналогично в случае загрузки игры будет загружаться из файла save_{i}.pkl, где i - номер сохранения

Глобальное состояние: ``game_state`` — экземпляр MainGameState.
Доступ из любого файла: ``from core.data import game_state`` или
``import core.data`` и ``core.data.game_state``.
"""
from typing import Optional
from core.data.game_state_base import MainGameState

# Global game state. Initialized at startup in Game; use ``from core.data import game_state``.
game_state: Optional[MainGameState] = None
