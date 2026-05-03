# Модели данных

Описание главных классов и их взаимоотношений.

## Иерархия сущностей

```
BaseEntity (game/core/entities/base.py)
   │
   ├─ Character ─── extends ─── dnd_5e_core.Character
   │   └─ Player
   │
   ├─ NPC
   ├─ Location
   │   └─ IndoorLevel
   │       └─ Room
   ├─ Item
   │   └─ Equipment
   └─ Treasure
```

## Character (`game/core/entities/character.py`)

Игрок и потенциально NPC, которые ведут себя как полноценные D&D-существа.

Наследуется от `dnd_5e_core.Character` (внешний пакет) и добавляет game-специфичные поля:

```python
class Character(BaseEntity, CoreCharacter):
    role: str | None
    prepared_spells: List[Spell]
    alignment: Optional[str]
    background: Optional[str]
    coins: int  # внутренне в copper pieces
    
    damage_vulnerabilities: List[str]
    damage_resistances: List[str]
    damage_immunities: List[str]
    condition_advantages: List[str]
    condition_immunities: List[str]
    senses: Dict[str, str]  # darkvision, blindsight и т.д.
    
    features: List[str]               # выбранные feature/subfeature индексы
    class_specific: Dict[str, Any]    # action_surges, sorcery_points и т.п.
    icon_image_path: str
```

От `dnd_5e_core.Character` приходит: `name, race, subrace, class_type, abilities, proficiencies, hit_points, max_hit_points, speed, xp, level, inventory, gold, sc (spellcasting), conditions, st_advantages` и др.

## NPC (`game/core/entities/npc.py`)

Простые персонажи без полной D&D-механики (но могут быть расширены до `Character`-подобных, если нужны для боя).

Загружаются из `game/assets/ru/start_npcs.jsonl`.

## Location / IndoorLevel / Room (`game/core/entities/location.py`)

Иерархия мест:

```
Location
  ├─ name, description, type (town/dungeon/...), subtype
  ├─ region, city
  ├─ entrance_room_id
  ├─ is_indoors, can_leave
  ├─ connected_locations: List[LocationID]
  ├─ npcs: List[NPCID]               ← глобальные NPC локации
  ├─ quests_in_location: List[Quest] ← открытые/скрытые квесты
  ├─ levels: List[IndoorLevel]
  ├─ location_history_summary: str   ← обновляется ЛЛМ
  └─ ...
  
IndoorLevel
  ├─ id, level_number, level_description, level_type (basement/ground/upper)
  └─ rooms: List[Room]
  
Room
  ├─ id, name, description, level
  ├─ can_leave
  ├─ npcs: List[NPCID]               ← NPC в этой комнате
  ├─ connections: List[RoomID]       ← с какими комнатами связана
  └─ treasures: List[TreasureID]
```

## Quest (`game/core/data/quest.py`)

```python
@dataclass
class Quest:
    id: ID
    name: str
    description: str
    status: QuestStatus       # hidden / open / completed / failed
    objectives: List[Objective]
    
class Objective:
    description: str
    status: ObjectiveStatus   # ...
```

## MainGameState (`game/core/data/game_state_base.py`)

Корневой объект — синглтон.

```python
@dataclass
class MainGameState:
    player: Optional[Player]
    quests: Dict[ID, Quest]
    npcs: Dict[ID, NPC]
    locations: Dict[ID, Location]
    levels: Dict[ID, IndoorLevel]
    rooms: Dict[ID, Room]
    treasures: Dict[ID, Treasure]
    current_location_id: Optional[ID]
    current_room_id: Optional[ID]
    save_datetime: Optional[datetime]
```

Методы:
- `load_start_data()` — загружает `start_locations.jsonl` и `start_npcs.jsonl`, ставит игрока в таверну
- `save(slot)` / `load(slot)` — pickle в `~/AppData/Local/DnD_LLM_Game/saves/save_{slot}.pkl`
- `list_saves()` — статический, возвращает список доступных слотов

## ID

Тип `ID = str`. Префиксы — для отладки:
- `tawern-001`, `market-001`, `caves-001` — локации
- `tavern-room-001` — комнаты
- `tavern-level-000` — уровни
- UUID-ы — NPC

Сейчас формат «свободный». Стандартизация — в техдолге.

## LLM-схемы (`game/core/gameplay/schemas/`)

Pydantic-модели для **структурированного вывода ЛЛМ**:

- `SceneDescription`, `ActionList`, `ActionOption` — exploration
- `AgentResolutionOutput`, `ActionMetadata` — главный вывод resolution agent
- `LocationSummary` — для архивариуса
- Аналогичные для social: `NpcGreeting`, `ResponseOptionList`, `SocialResolutionOutput`, `SocialSummary`

См. [llm-integration.md](llm-integration.md).

## Сериализация

Сейчас — **pickle** (`.pkl`). Это:
- ✅ Работает «из коробки» с любыми Python-классами
- ❌ **Хрупко к рефакторингу** — переименование класса ломает старые сейвы
- ❌ Не читаемо человеком
- ❌ Потенциальный security-риск (никогда не загружать чужой pkl)

См. [adr/0002-pickle-saves.md](adr/0002-pickle-saves.md).

## Builders (`game/core/builders/`)

Сложные сущности собираются через builder-классы:

- `CharacterBuilder` — пошаговое создание персонажа (используется в character creation screen)
- `LevelUpBuilder` (`LevelUpBuild`) — аккумулятор выбора при level up
- `LocationBuilder` — задел для автогенерации локаций (не подключён к ЛЛМ)
- `NpcBuilder` — задел для генерации NPC

В будущем builder'ы должны стать **инструментами для ЛЛМ** — это центральный пункт роадмапа.
