"""
Система квестов (Quest System) в стиле D&D / RPG
=================================================

Этот модуль описывает структуры данных для реализации системы квестов,
как в ролевых играх (D&D, Skyrim, Witcher).

Квест (Quest) — это многошаговая задача, выдаваемая игроку NPC.
Квест состоит из последовательных подзадач (Objectives) и даёт награду (Reward)
за выполнение.

------------------------------------------------------------
Основные сущности
------------------------------------------------------------

Quest (Квест)
    Большая задача для игрока.
    Содержит информацию о том, кто выдал квест, где, сложность,
    дедлайн и список подзадач (Objectives).

Objective (Подзадача / шаг квеста)
    Один конкретный шаг квеста. Примеры:
        - Убить 3 волков
        - Поговорить с кузнецом
        - Принести магическую траву

Reward (Награда)
    То, что получает игрок за завершение квеста:
        - Золото
        - Опыт
        - Предметы
        - Репутация

QuestGiver (Выдающий квест)
    NPC, который выдал квест.

------------------------------------------------------------
Жизненный цикл квеста
------------------------------------------------------------

1. Квест создаётся со статусом NOT_STARTED.
2. Когда игрок принимает квест → статус становится IN_PROGRESS.
3. Подзадачи открываются по порядку.
4. Выполнение подзадач продвигает квест.
5. Когда все подзадачи завершены → квест становится COMPLETED.
6. Если истёк дедлайн → квест может стать FAILED.

------------------------------------------------------------
Пример использования
------------------------------------------------------------

from datetime import datetime, timedelta

# NPC, выдавший квест
giver = QuestGiver(
    npc_id="npc_001",
    name="Гандрен Роксикер",
    location_id="phandalin"
)

# Подзадачи
obj1 = Objective(
    id="kill_wolves",
    description="Убить 3 лесных волков",
    order=1,
    status=ObjectiveStatus.AVAILABLE,
    target_type="kill",
    target_id="wolf",
    required_amount=3
)

obj2 = Objective(
    id="return_to_gandren",
    description="Вернуться к Гандрену",
    order=2,
    target_type="talk",
    target_id="npc_001"
)

# Награда
reward = Reward(
    coins=500,
    experience=200,
    items=["healing_potion"]
)

# Сам квест
quest = Quest(
    id="quest_wolf_problem",
    name="Волчья проблема",
    description="Волки нападают на торговцев возле дороги.",
    giver=giver,
    location_id="phandalin",
    difficulty=Difficulty.EASY,
    objectives=[obj1, obj2],
    reward=reward,
    created_at=datetime.now(),
    expires_at=datetime.now() + timedelta(days=2)
)

------------------------------------------------------------
Пример обновления прогресса
------------------------------------------------------------

# Игрок убил волка
obj1.current_amount += 1

# Проверка завершения шага
if obj1.current_amount >= obj1.required_amount:
    obj1.status = ObjectiveStatus.COMPLETED

# Открыть следующий шаг
if obj1.status == ObjectiveStatus.COMPLETED:
    obj2.status = ObjectiveStatus.AVAILABLE

------------------------------------------------------------
Возможные расширения системы
------------------------------------------------------------

- Требуемые квесты (prerequisites)
- Ограничения по фракции
- Повторяемые квесты
- Ветвящиеся подзадачи
- Условия провала
- Автоматическое обновление прогресса из боевой/диалоговой системы

------------------------------------------------------------
Система не зависит от движка и может использоваться в:
- Текстовых RPG
- Discord-ботах
- Игровых движках
- Менеджерах D&D-кампаний
"""


import dataclasses
from enum import Enum
from typing import Optional
from datetime import datetime
from core.entities.base import ID
from typing import List

class ObjectiveStatus(Enum):
    LOCKED = "locked"
    AVAILABLE = "available"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"

class Difficulty(Enum):
    TRIVIAL = 1
    EASY = 2
    MEDIUM = 3
    HARD = 4
    DEADLY = 5

@dataclasses.dataclass
class QuestGiver:
    npc_id: str
    name: str
    location_id: str

@dataclasses.dataclass
class Reward:
    coins: int = 0
    experience: int = 0
    items: list[str] = dataclasses.field(default_factory=list)
    reputation: dict[str, int] = dataclasses.field(default_factory=dict)  # фракция → очки

@dataclasses.dataclass
class Objective:
    id: str
    description: str
    order: int  # порядок выполнения
    status: ObjectiveStatus = ObjectiveStatus.LOCKED

    # для геймплейной логики (опционально)
    target_type: Optional[str] = None      # "kill", "talk", "collect"
    target_id: Optional[str] = None        # id моба, НПС или предмета
    required_amount: int = 1
    current_amount: int = 0


class QuestStatus(Enum):
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    HIDDEN = "hidden"


@dataclasses.dataclass
class Quest:
    id: str
    name: str
    description: str

    giver: QuestGiver
    location_id: ID  # где выдали (str или UUID)
    difficulty: Difficulty

    objectives: List[Objective]

    reward: Reward

    created_at: datetime
    expires_at: Optional[datetime] = None  # дедлайн

    status: QuestStatus = QuestStatus.HIDDEN
    ways_to_unhidden: List[str] = dataclasses.field(default_factory=list)

    def is_open(self) -> bool:
        return self.status == QuestStatus.IN_PROGRESS

    def is_completed(self) -> bool:
        return self.status == QuestStatus.COMPLETED

    def is_failed(self) -> bool:
        return self.status == QuestStatus.FAILED

    def is_hidden(self) -> bool:
        return self.status == QuestStatus.HIDDEN