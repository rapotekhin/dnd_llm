# Мастер: интеграция ЛЛМ

Как устроен ЛЛМ-мастер в v0.5.4. Запуск и конфиг — [llm_server/README.md](../../llm_server/README.md), сообщения — [ADR-0009](adr/0009-godot-backend-protocol.md), сторона Godot — [godot-client.md → «Ход»](godot-client.md#ход).

## Главный принцип

> **Движок решает, ЛЛМ рассказывает** ([ADR-0008](adr/0008-engine-decides-llm-narrates.md), столп №1 в [vision/pillars.md](../vision/pillars.md)).

У мастера нет состояния игры и правил 5e. Он получает от Godot снимок хода, а всё, что меняет мир или требует броска, просит у движка обратными вызовами `engine.*`. Применяются только эффекты, которые движок принял и зарезервировал в этом ходе.

## Кто где

| Где | Что |
|---|---|
| Godot (`game/`) | состояние, сейвы, правила: `CheckEngine`, `EffectEngine`, `Lookup`, `ItemRules`, `TradeRules`, `XpRules` ([ADR-0007](adr/0007-godot-client-python-llm-backend.md)) |
| `llm_server/` | агенты Pydantic AI, промпты, выбор модели, бюджет, библиотека созданных предметов |
| `contract/` | JSON Schema протокола, генерируется из `protocol.py` (`PROTOCOL_VERSION = 0.5.0`) |

Связь — WebSocket + JSON-RPC 2.0 в обе стороны: Godot шлёт `turn.request` и `summary.request`, бэкенд во время хода вызывает `engine.*` у Godot.

## Ход

Один ход — один запуск агента (`agents.build_turn_agent`) с `output_type=TurnOutput`:

1. Godot присылает `turn.request`: `mode` (`exploration` / `social` / `trade`), `kind` (`enter`, `resume`, `action`, `rest`, `deal`, `haggle`, `quest`), ввод игрока, `npc_id`, `model` и снимок (`Snapshot`: мир и настройки мастера, сцена, лист персонажа, последние реплики, сводки, лимиты, торговец, задания).
2. Агент зовёт инструменты (ниже), каждый превращается в `engine.*`.
3. Итог `TurnOutput`: `narration`, `options` (1–3), `effect_ids`, `next_mode` + `npc_id`, `changes`. Валидатор вывода (`ModelRetry`) не пускает пустой текст, `changes` без эффектов, чужие `effect_ids` и `social` / `trade` без NPC сцены.
4. Godot применяет эффекты из `effect_ids`, остальные резервы сгорают; `next_mode` переключает режим.

Лимиты: `max_checks` = 1 и `max_effects` = 3 за ход (из снимка), не больше 10 запросов к модели (`TURN_USAGE_LIMITS`). Повторы OpenRouter при 408/429/5xx — только пока агент не обратился к движку, чтобы повтор не перебрасывал проверку.

## Инструменты

| Инструмент | Вызов движка | Что |
|---|---|---|
| `request_check(dc_tier, reason, skill \| save, target_id, advantage_reason)` | `engine.check` | проверка навыка или спасбросок. Мастер выбирает ступень сложности (`very_easy` … `nearly_impossible`), DC, бросок и nat 20/1 — у движка. Ответ: успех / провал, найденное скрытое (`revealed`), повтор проваленной проверки без броска (`blocked`), итог торга (`note`) |
| `propose_effect(effect)` | `engine.validate` | последствие: `move`, `damage`, `heal`, `coins`, `give_item`, `take_item`, `npc_attitude`, `flag`. Урон и лечение — ступенями тяжести, числа считает движок. Принятый эффект возвращает `effect_id`, отклонённый — причину, и мастер переписывает текст под отказ |
| `lookup(kind, id)` | `engine.lookup` | справка: `rule`, `spell`, `feature`, `condition`, `item`, `npc` — по id или русскому названию |
| `find_items(query, base, properties)` | `engine.find_items` | поиск в каталоге игры + библиотеке созданных предметов бэкенда. Без него `give_item` с новым предметом отклоняется |

Опыта среди эффектов нет: опыт дают только бой и задания пакета (`XpRules`). В торговле `coins` / `give_item` / `take_item` движок отклоняет — сделки идут панелью игрока, мастер их только отыгрывает (`kind=deal`, `haggle`).

## Промпты

Jinja2 со `StrictUndefined` в `llm_server/src/llm_server/prompts/`:

| Шаблон | Что |
|---|---|
| `_rules.md.j2` | как устроена игра: проверки до описания, последствия только эффектами, предметы через `find_items`, скрытое не выдумывать, бой пока не исходом; как писать: длина, род, без переспрашивания |
| `_world.md.j2` | мир пакета: лор, тон, магия, стиль мастера (`classic` / `literary` / `dry` / `ironic`), жестокость, линии и вуали |
| `_scene.md.j2` | лист персонажа, комната, выходы, NPC с отношением, зацепки, найденное, флаги, задания, сводки, последние реплики |
| `exploration` / `social` / `trade.md.j2` | системный промпт режима; в торговле — запас, цены и кошелёк торговца |
| `turn.md.j2` | пользовательское сообщение хода по `kind` |
| `summary.md.j2` | сводка |

Системный промпт собирает `prompts.system_prompt(mode, snapshot, npc)`, ход — `prompts.turn_prompt(...)`. Скрытое (секреты комнат) в промпт не попадает: мастер видит только зацепки и то, что движок уже открыл.

## Сводки

Вместо полной истории в снимок идут последние реплики (в пределах бюджета символов) и сводки. `summary.request` (`kind` = `location` / `dialogue`) делает отдельный агент `build_summary_agent` → `SummaryOutput` (2–4 предложения, `temperature` 0.3). Godot просит сводку разговора при его конце и сводку локации каждые 12 событий; в снимок попадают сводка текущей локации и сводки прошлых разговоров с NPC комнаты — так NPC помнят игрока между встречами.

## Модели

- OpenRouter через Pydantic AI, по умолчанию `anthropic/claude-haiku-5.5` ([ADR-0011](adr/0011-default-master-model.md)). Белый список (`LLM_SERVER_MODELS`) с ценами уходит в игру, игрок выбирает модель в «Настройки → Мастер».
- `MODEL_SETTINGS`: `temperature` 0.8, `max_tokens` 1500. Особенности моделей — в коде, не в промптах: `settings_for()` выключает размышления у Qwen, аргумент `propose_effect` принимает строку JSON.
- Дневной бюджет (`LLM_SERVER_DAILY_BUDGET_USD`), расход и остаток — в `usage` каждого ответа.
- Сменить модель по умолчанию — только после «золотых» сценариев с `--repeat 3` и живого плейтеста.

## Трейсинг и логи

- Langfuse по желанию (`LANGFUSE_ENABLED=1` + ключи) — трейсы всех запусков агента.
- Godot пишет журнал протокола в `<профиль>/logs/protocol.jsonl`; F12 сохраняет снимок бага с хвостом журнала.

## Тесты

- `llm_server/tests/` — агент через настоящий WebSocket, модель играет `FunctionModel`, тест играет Godot. Без сети и денег.
- `LLM_SERVER_TURN_HANDLER=stub` — ход без ЛЛМ для UI и протокольных тестов.
- «Золотые» сценарии — `python -m llm_server.golden` ([golden-scenarios.md](golden-scenarios.md)): настоящая модель против mock-движка, жёсткие проверки + судья.
- Живой плейтест — `python tools/godot_playtest.py --scenario live --real` (скилл `playtest`).

## Известные проблемы

- **Модели недетерминированы:** разброс «золотых» сценариев ±2 за прогон, выводы — только по `--repeat 3`.
- **Бой не реализован:** атаку мастер описывает только началом, сцена продолжается без исхода — до v0.6.1 ([roadmap](../production/roadmap.md)).
- **Заклинания бесплатны:** движок пока не тратит ячейки и не накладывает состояния — v0.6.0.
