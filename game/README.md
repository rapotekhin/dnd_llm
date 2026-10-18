# game/ — Godot-клиент

**Статус:** каркас v0.4.0 — меню, настройки, сейвы, связь с мастером, черновой экран игры с чатом и бросками, dev-инструменты, gdUnit4 и живые сценарии. Устройство, команды и правила — [docs/tech/godot-client.md](../docs/tech/godot-client.md). Перенос правил и персонажа — v0.5.x ([roadmap](../docs/production/roadmap.md)).

Игра целиком: UI, состояние мира, сейвы и **все правила D&D 5e** ([ADR-0007](../docs/tech/adr/0007-godot-client-python-llm-backend.md) §1, [ADR-0008](../docs/tech/adr/0008-engine-decides-llm-narrates.md)). С ЛЛМ общается только через `llm_server/` по протоколу [ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md).

## Стек и соглашения

- Godot 4.7, GDScript со статической типизацией, тесты на gdUnit4.
- По образцу `hive_world_shop`: `autoload/` (EventBus, Catalog, SaveManager, GameState, Backend, Dev), чистый `core/` без нод, seeded RNG, данные в JSON, JSON-сейвы с `SAVE_VERSION` и миграциями, весь текст через `tr()` и `strings.csv`.
- Мир — пакеты вселенных поверх 5e ([ADR-0010](../docs/tech/adr/0010-game-decisions-worlds-tone-combat-death.md)); ничего про конкретный мир не хардкодится.

Прототип, с которым сверяется паритет, — [`legacy/`](../legacy/).
