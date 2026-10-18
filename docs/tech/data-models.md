# Модели данных

Главные структуры Godot-клиента v0.5.4. Состояние игры — словари и массивы в чистом слое `game/core/` (без нод), в сейв они идут как есть. Подробности по системам — [godot-client.md](godot-client.md), сообщения мастеру — `llm_server/src/llm_server/protocol.py` ([ADR-0009](adr/0009-godot-backend-protocol.md)).

## Что где

| Данные | Где | Меняется |
|---|---|---|
| Правила 5e | `game/data/srd/*.json` (генерирует `tools/srd_import.py`), `rules.json`, `items.json` | при сборке |
| Мир | пакет `game/data/worlds/<id>/`: `pack.json`, `world.json`, `characters.json` ([формат](godot-client.md#пакеты-миров)) | только автором пакета |
| Игра | `GameSession` | ходом и кнопками движка |

Пакет мира в игре только читается (`WorldView`). Всё, что в мире поменялось, лежит в сессии поверх пакета: отношения NPC, флаги, найденное, запасы торговцев, выполненные задания.

## GameSession (`core/session/game_session.gd`)

Одно прохождение.

| Поле | Что |
|---|---|
| `game_seed`, `rng`, `turn_counter`, `check_counter`, `effect_counter` | детерминизм: все броски — из RNG сессии, id ходов `t-N` |
| `chat`, `options` | лента (`player`, `dm`, `npc`, `check`, `effect`, `system`) и варианты мастера |
| `world_id`, `world_version`, `settings` | мир и настройки новой игры: стиль мастера, режим смерти, жестокость, линии и вуали |
| `room_id`, `mode`, `npc_id` | где игрок и в каком режиме (`exploration` / `social` / `trade`), собеседник |
| `character` | персонаж (ниже) |
| `items` | предметы, созданные мастером и принятые движком: `{item_id: описание}` — сейв не зависит от библиотеки бэкенда |
| `attitudes`, `flags` | отношение NPC (−3…+3) и сюжетные флаги из эффектов |
| `locks`, `revealed`, `visited`, `day` | исследование: блоки проваленных проверок, найденные секреты по комнатам, карта, день |
| `merchants` | торговцы: кошелёк, запас, день пополнения, торг визита (`TradeRules`) |
| `quests_done` | выполненные задания пакета (`XpRules`) |
| `summaries`, `dialogue_log`, `location_log` | сводки `location:<id>` / `dialogue:<npc_id>` и события для следующих сводок |

`TurnSnapshot` собирает из сессии снимок хода — только то, что можно видеть мастеру: зацепки и уже найденное, но не секреты.

## Персонаж (`CharacterRules`)

Словарь в `session.character`, раскладка — в шапке `core/character/character_rules.gd`:

- **выборы** — имя, пол, раса и подраса, класс и подкласс, предыстория, `level`, `xp`, характеристики, владения (навыки, компетентность, спасброски, языки, инструменты, доспехи, оружие), черты, умения, заклинания (`cantrips`, `known`, `prepared`), экипировка (`armor`, `shield`, `main_hand`, `off_hand`), инвентарь, `gold_cp`;
- **состояние** — `hp`, `conditions`, `slots_used`, `hit_dice_used`;
- **кэш производных** — `max_hp`, `ac`, `prof_bonus`, `skills`, `saves`, `speed`, `passive_perception`, `slots_max`, `spell_dc`, `spell_attack` и названия.

Кэш пересчитывает `CharacterRules.refresh()` после любой смены выборов (старт, загрузка, экипировка, эффекты, уровень), поэтому `CheckEngine`, `EffectEngine` и снимок читают готовые числа. Создание — `CharacterBuilder` (шаги и проверка шага), рост — `LevelUp` (уровни 1–5). Монеты везде в медяках.

## Id

Строки из пакета и данных SRD: комнаты `brod-tavern-hall`, локации `brod`, NPC `npc_innkeeper`, задания `letter_to_ilva`, предметы и правила — id SRD (`longsword`, `perception`). Id созданных мастером предметов выдаёт движок. Ход — `t-N`, проверки и эффекты — от счётчиков сессии.

## Сейвы

- JSON в `<профиль>/saves/slot_1..10.json` и `autosave.json`, запись атомарная.
- Формат: `{save_version, game_version, saved_at, meta, session}`; `session` — `GameSession.to_dict()`, `meta` — для списка слотов.
- `SaveFormat.SAVE_VERSION = 7`, миграции по шагам в `SaveFormat.MIGRATIONS`, фикстура на каждую версию в `game/test/fixtures/saves/`. Сейвы старше v3 и новее игры не грузятся. История версий и порядок смены формата — [godot-client.md → «Сейвы»](godot-client.md#сейвы).
- Почему JSON, а не pickle прототипа: читается человеком, переживает рефакторинг, безопасен при загрузке чужих файлов ([ADR-0007](adr/0007-godot-client-python-llm-backend.md); старое решение — [ADR-0002](adr/0002-pickle-saves.md)).

## Протокол

Типы мастера — Pydantic-модели в `protocol.py`: `Snapshot` (`WorldInfo`, `Scene`, `CharacterSheet`, `HistoryLine`, `TradeInfo`, `QuestInfo`, `TurnLimits`), `TurnResult`, эффекты (`MoveEffect` … `FlagEffect`), параметры и ответы `engine.*`. JSON Schema для Godot — `contract/schema/` (`python -m llm_server.contract`). Устройство хода — [llm-integration.md](llm-integration.md).
