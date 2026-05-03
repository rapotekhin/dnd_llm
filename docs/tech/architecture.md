# Архитектура

## Общая схема

```
┌──────────────────────────────────────────────────────────┐
│                    game/main.py                          │
│   (entry point, добавляет пути к sys.path)               │
└──────────────────────────┬───────────────────────────────┘
                           ▼
┌──────────────────────────────────────────────────────────┐
│                       Game                               │
│   (game/core/game.py — главный цикл, FPS, события)       │
│                                                          │
│   ┌──────────────┐   ┌──────────────┐  ┌──────────────┐  │
│   │ APIManager   │   │SettingsManager│  │ MainGameState│  │
│   │ (LLM client) │   │  (settings)  │  │  (singleton) │  │
│   └──────────────┘   └──────────────┘  └──────────────┘  │
│                                                          │
│   ┌──────────────────────────────────────────────────┐   │
│   │           UI Screens (game/ui/screens/)          │   │
│   │  Title / CharCreation / Main / Inventory /       │   │
│   │  Character / Abilities / Journal / Map /         │   │
│   │  Social / Trade / LevelUp / Settings             │   │
│   └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
                           │
                           │  fork background thread
                           ▼
┌──────────────────────────────────────────────────────────┐
│            Gameplay modules (фоновые потоки)             │
│                                                          │
│   exploration.py    social_interaction.py    trade.py    │
│         │                  │                    │        │
│         └────── communicate via Queues ─────────┘        │
│                           │                              │
│                           ▼                              │
│                ┌────────────────────┐                    │
│                │   Pydantic AI      │                    │
│                │   Agents + Tools   │                    │
│                │   (roll_dice,      │                    │
│                │    rule_db_lookup) │                    │
│                └─────────┬──────────┘                    │
└──────────────────────────┼───────────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │  OpenRouter API      │
                │  (Gemini Flash Lite) │
                └──────────────────────┘
```

## Слои

| Слой | Папка | Ответственность |
|---|---|---|
| **Entry** | `game/main.py` | Запуск, sys.path |
| **Core** | `game/core/game.py` | Главный цикл, события, навигация |
| **State** | `game/core/data/` | `MainGameState` — синглтон состояния мира |
| **Entities** | `game/core/entities/` | `Character`, `NPC`, `Location`, `Room`, `Item`, `Treasure` |
| **Gameplay** | `game/core/gameplay/` | Режимы игры (exploration, social, trade, combat) — фоновые потоки |
| **LLM** | `game/core/llm_engine/` | `APIManager` — обёртка над OpenRouter |
| **Prompts** | `game/core/prompts/` | Все системные промпты |
| **Tools** | `game/core/tools/` | Инструменты для ЛЛМ (`RollDiceTool`, `RuleDbLookupTool`) |
| **Builders** | `game/core/builders/` | Сборка сложных сущностей (Character, Location, NPC, LevelUp) |
| **Schemas** | `game/core/gameplay/schemas/` | Pydantic-схемы LLM-вывода |
| **UI** | `game/ui/screens/` | Pygame-экраны; крупные потоки вынесены в подпакеты (`character_creation/`, `level_up/`, `trade/`), точки входа `*_screen.py` реэкспортируют классы для стабильных импортов |
| **Localization** | `game/localization/` | Переводы (RU/EN) |
| **Assets** | `game/assets/` | JSONL-данные стартовых локаций и NPC |
| **External** | `dnd-5e-core/`, `DnD-5th-Edition-API/` | Правила и данные D&D 5e (отдельные репозитории) |

## Главный цикл

`Game.run()`:

```python
while running:
    for event in pygame.event.get():
        result = current_screen.handle_event(event)
        _handle_screen_result(result)
    
    update_result = current_screen.update()
    _handle_screen_result(update_result)
    
    current_screen.draw()
    pygame.display.flip()
    clock.tick(60)
```

Все переходы между экранами — через `_handle_screen_result()`. См. [design/ux/screens-flow.md](../design/ux/screens-flow.md).

## Фоновые потоки

LLM-вызовы — медленные (1-10 сек). Чтобы UI не замораживался, gameplay-модули работают в **отдельных потоках**.

**Контракт UI ↔ Thread:**

- **`ui_queue`** (thread → UI) — структурированные сообщения: `scene`, `actions`, `narration`, `question`, `thinking`, `transition`, `error`
- **`input_queue`** (UI → thread) — выбор/ввод игрока
- **`stop_event`** — `threading.Event` для прерывания

Примеры контрактов — в docstring каждого `run_*` функции.

**Особенность:** social/trade-потоки умеют **ставить себя на паузу** (через ожидание сообщения `resume`) вместо завершения. Это экономит на пересборке агентов и повторном `describe_scene` при возврате.

## Состояние

Глобальное — `MainGameState` (один экземпляр, создаётся в `Game.__init__`).

Доступ из любого файла:
```python
from core.data import game_state
```

Хранит: player, npcs, locations, levels, rooms, treasures, quests, current_location_id, current_room_id.

**Сохранение** — `pickle` в `~/AppData/Local/DnD_LLM_Game/saves/save_{1..10}.pkl` (Windows).

⚠️ Pickle хрупок к рефакторингу классов. Миграция на JSON/SQLite — в техдолге, см. [adr/0002-pickle-saves.md](adr/0002-pickle-saves.md).

## Зависимости (внешние)

- **Pygame** ≥ 2.6 — UI
- **Pydantic AI** ≥ 1.0 — LLM-агенты с инструментами
- **OpenAI SDK** — клиент для OpenRouter (косвенно через Pydantic AI)
- **Logfire** — трейсинг (рассматривается возврат на Langfuse)
- **dnd-5e-core** — правила и данные D&D (внешний git-pip-пакет)
- **DnD-5th-Edition-API** — расширенные данные D&D (внешний sibling-репозиторий)

## Точки расширения

Где обычно надо «добавить» что-то:

| Хочу… | Куда смотреть |
|---|---|
| Новый экран | `game/ui/screens/`, добавить в `Game._init_screens()` |
| Новый режим игры | `game/core/gameplay/` + новый экран + промпты |
| Новый инструмент для ЛЛМ | `game/core/tools/` + регистрация в `_build_*_agent()` |
| Новый тип сущности | `game/core/entities/` + builder в `core/builders/` |
| Новые правила D&D | НЕ сюда — в `dnd-5e-core` (внешний пакет) |
| Новый язык | `game/localization/` |
