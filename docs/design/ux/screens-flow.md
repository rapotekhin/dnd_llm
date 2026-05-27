# Поток экранов (Screens Flow)

## Граф переходов

```
                           ┌──────────────┐
                           │  TitleScreen │
                           └──────┬───────┘
                                  │
                  ┌───────────────┼─────────────────┐
                  │               │                 │
            new_game         continue/load      settings
                  │               │                 │
                  ▼               │                 ▼
       ┌────────────────────┐     │         ┌──────────────┐
       │CharacterCreation   │     │         │SettingsScreen│
       └────────┬───────────┘     │         └──────┬───────┘
                │ Character       │                │
                └─────────────────┤                │ apply
                                  ▼                │
                           ┌──────────────┐        │
                           │ MainScreen   │◄───────┘
                           │ (exploration)│
                           └──────┬───────┘
                                  │
       ┌──────────┬───────┬───────┼───────────┬──────────┬─────────┐
       │          │       │       │           │          │         │
   inventory character abilities map      journal     social    trade
       │          │       │       │           │           │        │
       ▼          ▼       ▼       ▼           ▼           ▼        ▼
   ...           │      ...    ...        ...         ...       ...
                 │
            level_up (если хватает XP)
                 │
                 ▼
            LevelUpScreen
```

## Принцип навигации

Все экраны наследуются от `BaseScreen` и реализуют `handle_event() / update() / draw()`.

**Переход — через возврат значения** из `handle_event()`:
- Строка `"main"`, `"inventory"` и т.д. → `Game.switch_screen()`
- Строка `"social:<npc_id>"` или `"trade:<npc_id>"` → передача параметра + переход
- Объект `Character` → сохранить как игрока + перейти в main
- `None` → ничего не происходит

Никаких прямых ссылок между экранами. Логика навигации **сосредоточена в `Game._handle_screen_result()`**.

Код экранов — в [`game/ui/screens/`](../../../game/ui/screens/): общие модули лежат прямо в папке, а создание персонажа, поднятие уровня и торговля оформлены как подпакеты; для совместимости `character_creation_screen.py`, `level_up_screen.py` и `trade_screen.py` по-прежнему импортируются из [`screens/__init__.py`](../../../game/ui/screens/__init__.py).

## Жизненные циклы экранов

| Экран | Когда создаётся | Когда уничтожается |
|---|---|---|
| Title, Settings, CharCreation, Inventory, Character, Abilities, Journal, Map, Social, Trade | При инициализации `Game` | Никогда (живут всю сессию) |
| Main | При инициализации | Никогда, но фоновый поток exploration пересоздаётся |
| LevelUp | On-demand в `_handle_screen_result()` | После выхода из экрана |

При **изменении настроек** (resolution, language) экраны **пересоздаются** (`_init_screens()`).

## Особые потоки

- **Exploration** — main screen запускает фоновый thread `run_exploration()` через `start_exploration()`. Поток слушает очередь команд от UI и шлёт в обратную очередь сообщения типа `scene/actions/narration/system_marker/transition`.
- **Social/Trade** — аналогично. Trade ставит social-поток на паузу, не убивает.
- **Возврат из side-сессии в exploration** — UI передаёт собранный side-loop'ом `summary` в сигнале `resume`. Exploration перед тем как пускать игрока в новый ход показывает маркер «Возвращение к исследованию» + summary как DM-реплику, заново описывает сцену, и только тогда генерирует действия. Контракт — [adr/0006](../../tech/adr/0006-exploration-side-session-summary.md).
- **Выход из social кнопкой «Уйти» / ESC** — `SocialScreen` не убивает поток через `stop_event`; вместо этого шлёт `{"type": "leave"}` в `input_queue` и остаётся на экране (с индикатором «думает…»), пока social-loop синхронно не сформирует summary и не пришлёт штатный `transition`. Это убрало race condition с async-summary.

См. [tech/architecture.md](../../tech/architecture.md) для деталей.
