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

## Жизненные циклы экранов

| Экран | Когда создаётся | Когда уничтожается |
|---|---|---|
| Title, Settings, CharCreation, Inventory, Character, Abilities, Journal, Map, Social, Trade | При инициализации `Game` | Никогда (живут всю сессию) |
| Main | При инициализации | Никогда, но фоновый поток exploration пересоздаётся |
| LevelUp | On-demand в `_handle_screen_result()` | После выхода из экрана |

При **изменении настроек** (resolution, language) экраны **пересоздаются** (`_init_screens()`).

## Особые потоки

- **Exploration** — main screen запускает фоновый thread `run_exploration()` через `start_exploration()`. Поток слушает очередь команд от UI и шлёт в обратную очередь сообщения типа `scene/actions/narration/transition`.
- **Social/Trade** — аналогично. Trade ставит social-поток на паузу, не убивает.

См. [tech/architecture.md](../../tech/architecture.md) для деталей.
