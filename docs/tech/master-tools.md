# Инструменты мастера: справочник

Все способы, которыми ЛЛМ-мастер обращается к движку игры, в одном месте: инструменты агента, вызовы `engine.*`, 37 видов эффектов, итог хода и что клиент с ним делает. Сверено с кодом протокола 0.47.0 (v0.7.22.17). Как из этих инструментов складываются действия мастера (создать место, переместить героя, выдать вещь…) — [master-scenarios.md](master-scenarios.md). Общее устройство мастера — [llm-integration.md](llm-integration.md), сообщения и транзакция хода — [ADR-0009](adr/0009-godot-backend-protocol.md).

**Источники истины** (дока описывает их, а не заменяет):

| Что | Где |
|---|---|
| Инструменты агента и проверки бэкенда | [agents.py](../../llm_server/src/llm_server/agents.py) |
| Схемы эффектов, снимка, итога хода | [protocol.py](../../llm_server/src/llm_server/protocol.py) → JSON Schema в [contract/](../../contract/) |
| Обработчики `engine.*` в Godot | [game_state.gd](../../game/autoload/game_state.gd#L2205) (`handle_engine_*`) |
| Проверка, резерв и применение эффектов | [effect_engine.gd](../../game/core/rules/effect_engine.gd) (`validate` → `_plan`, `apply` → `_apply_one`) |
| Темы правил и что они открывают | [prompts/\_\_init\_\_.py](../../llm_server/src/llm_server/prompts/__init__.py#L94) (`TOPICS`) |

## Принцип

> **Движок решает, мастер рассказывает** ([ADR-0008](adr/0008-engine-decides-llm-narrates.md)).

У мастера нет состояния игры: он видит снимок хода ([TurnSnapshot.build](../../game/core/session/turn_snapshot.gd#L7) → `Snapshot` в [protocol.py](../../llm_server/src/llm_server/protocol.py#L377)), а всё, что требует броска или меняет мир, просит у движка. Движок проверяет просьбу и **резервирует** эффект; мир меняется, только когда мастер вернул `effect_id` в итоге хода. Неназванные резервы, ошибка или отмена хода сжигают все резервы этого хода ([ADR-0009 §5](adr/0009-godot-backend-protocol.md#5-транзакция-хода)).

## Путь вызова

```
инструмент агента (agents.py)
  → Session.call_engine("engine.<метод>", params)       session.py:277
  → WebSocket, JSON-RPC 2.0 (бэкенд → Godot)
  → Backend: register_handler("engine.<метод>", …)      game/autoload/backend.gd:48
  → GameState.handle_engine_<метод>(params)             только для хода в полёте (_active)
  → правила game/core/…                                 ответ — обратно модели строкой
```

Обработчик отвечает только на `turn_id` хода, который сейчас идёт (`GameState._active`); иначе — ошибка `-32041`.

## Инструменты агента

Восемь инструментов, список — в [build_turn_agent](../../llm_server/src/llm_server/agents.py#L422). Что вернуть модели, решает бэкенд: отказы — строкой с причиной, чтобы мастер переписал текст под них.

| Инструмент | Аргументы | Вызов движка → обработчик | Что делает | Ограничения бэкенда |
|---|---|---|---|---|
| [`request_check`](../../llm_server/src/llm_server/agents.py#L175) | `dc_tier`, `reason`, `skill` \| `save`, `target_id`, `advantage_reason`, `sense` (`sight` / `hearing`), `tool`, `argument` | `engine.check` → [handle_engine_check](../../game/autoload/game_state.gd#L2205) → [_engine_check](../../game/autoload/game_state.gd#L2224) | Проверка навыка или спасбросок. Мастер даёт только ступень сложности; DC, бросок, преимущество, помеха и автопровал — у движка | Не больше `max_checks` за ход; ровно одно из `skill` / `save`; неверная ступень или чувство — отказ строкой, а не ошибка схемы (v0.7.22.16: ошибки схемы съедали повторы инструмента и роняли ход) |
| [`propose_effect`](../../llm_server/src/llm_server/agents.py#L232) | `effect` — один из 37 видов ниже | `engine.validate` → [handle_engine_validate](../../game/autoload/game_state.gd#L2426) → [EffectEngine.validate](../../game/core/rules/effect_engine.gd#L100) | Предложить последствие. Принятый — `effect_id` и строка итога («−7 HP (колющий)»), отклонённый — причина | Не больше `max_effects` за ход; повтор того же эффекта — отказ; эффект не по схеме — отказ с причиной (после трёх — «заверши ход словами»); тема правил должна быть прочитана; перед `create_*` и новым предметом — свой `find_*` |
| [`rules`](../../llm_server/src/llm_server/agents.py#L349) | `topic` — ключ из `prompts.TOPICS` | — (бэкенд) | Подробные правила темы: состояния, заклинания, плата, кража, предметы, места, преступления, социальное, цели, снаряжение, невидимость, люди, задания, языки, инструменты, предыстория, контейнеры | Темы, которые сцена требует сама, уже в промпте ([auto_topics](../../llm_server/src/llm_server/prompts/__init__.py#L123)) |
| [`lookup`](../../llm_server/src/llm_server/agents.py#L355) | `kind` (`rule`, `spell`, `feature`, `condition`, `item`, `npc`), `id` (id или русское название) | `engine.lookup` → [handle_engine_lookup](../../game/autoload/game_state.gd#L2432) → [Lookup.find](../../game/core/rules/lookup.gd#L8) | Справка по белому списку: правила, SRD, вещи, NPC текущей комнаты. Другие локации и скрытое — никогда | — |
| [`find_items`](../../llm_server/src/llm_server/agents.py#L402) | `query`, `base`, `properties` | `engine.find_items` → [handle_engine_find_items](../../game/autoload/game_state.gd#L2462) → [ItemRules.find](../../game/core/items/item_rules.gd#L314) + библиотека бэкенда ([library.py](../../llm_server/src/llm_server/llm/library.py)) | Поиск вещей в каталоге игры и среди созданных мастером | Без него в этом ходе `give_item.item` (новая вещь) отклоняется |
| [`find_npcs`](../../llm_server/src/llm_server/agents.py#L364) | `query` | `engine.find_npcs` → [handle_engine_find_npcs](../../game/autoload/game_state.gd#L2447) → [WorldGen.find_npcs](../../game/core/world/world_gen.gd#L47) | Люди мира: пакет и созданные | Без него `create_npc` отклоняется |
| [`find_places`](../../llm_server/src/llm_server/agents.py#L390) | `query` | `engine.find_places` → [handle_engine_find_places](../../game/autoload/game_state.gd#L2439) → [WorldGen.find_places](../../game/core/world/world_gen.gd#L177) | Комнаты и локации пакета и созданные | Без него `create_place` отклоняется |
| [`find_quests`](../../llm_server/src/llm_server/agents.py#L376) | `query` | `engine.find_quests` → [handle_engine_find_quests](../../game/autoload/game_state.gd#L2454) → [QuestGen.find_quests](../../game/core/world/quest_gen.gd#L79) | Задания мира и сколько созданных открыто (`open_made` из `max_open`) | Без него `create_quest` отклоняется |

Обязательные поиски проверяют обе стороны: бэкенд (`TurnContext.searched_*`) и движок (`EffectEngine.searched*`, отметку ставит обработчик `find_*`).

### Что ещё делает `engine.check`

Один вызов — разные правила по положению ([_engine_check](../../game/autoload/game_state.gd#L2224)):

| Положение | Что движок делает | Код |
|---|---|---|
| Торговля, навык торга | Бросок торга: DC по отношению, процент скидки или запрет до завтра; итог — в `note` | [TradeRules.is_haggle](../../game/core/rules/trade_rules.gd#L331), `_haggle_check` |
| Бой, Убеждение или Запугивание | Переговоры в бою против DC переговоров | [CombatRules.can_parley](../../game/core/rules/combat_rules.gd#L2649), `_parley_check` |
| Разговор, социальный навык | DC по шаблону SRD собеседника; язык (нет общего — автопровал или помеха); чары на NPC дают преимущество; проверка закреплена за собеседником | [SocialRules.dc](../../game/core/rules/social_rules.gd#L43), [LanguageRules](../../game/core/rules/language_rules.gd) |
| Повтор той же проверки без перемен | Без броска: прежний итог, `blocked: true` (новый довод `argument`, заклинание, отношение — перемена) | [ExplorationRules.locked](../../game/core/rules/exploration_rules.gd#L51), `state_key` |
| Ловкость рук против NPC сцены (`target_id`) | Кража: движок выдаёт монеты или NPC замечает; итог — в `note` | `_theft`, [TheftRules](../../game/core/rules/theft_rules.gd) |
| Успешный поиск | Скрытое этой комнаты (`revealed`), тайники, продвижение заданий; в разговоре — тайны NPC по проверке | [ExplorationRules.active_reveal](../../game/core/rules/exploration_rules.gd#L125), `SocialRules.reveal_by_check` |
| Любая проверка | Бонус героя, состояния, темнота, инструменты, черты расы, вещи, заклинания-баффы, Вдохновение барда | [CheckEngine.bonus_for](../../game/core/rules/check_engine.gd#L63), `ConditionRules.check_mods` |

Успешная социальная проверка «склоняет» NPC на этот ход: от него становятся возможны скидка, услуга, `npc_follow`, `crime_release` (`EffectEngine.note_check`).

## Эффекты (`propose_effect`)

Схемы — классы `*Effect` в [protocol.py](../../llm_server/src/llm_server/protocol.py#L500) (объединение `Effect`, [строка 983](../../llm_server/src/llm_server/protocol.py#L984)). Проверка — ветка `match` в [EffectEngine._plan](../../game/core/rules/effect_engine.gd#L139), применение — [EffectEngine._apply_one](../../game/core/rules/effect_engine.gd#L648). Колонка «Тема» — тема `rules(...)`, без которой бэкенд эффект не отправит.

### Герой

| Эффект | Поля | Что проверяет движок | Правила | Тема | Ещё |
|---|---|---|---|---|---|
| [`damage`](../../llm_server/src/llm_server/protocol.py#L506) | `severity` (`unpleasant` / `dangerous` / `deadly`), `damage_type`, `reason`, `target_id` | Кубы по ступени и уровню (`rules.damage_dice_by_level`), сопротивления героя; с `target_id` в бою — урон врагу; **с `target_id` вне боя — отказ** (v0.7.22.16: такой урон доставался герою): нападение на NPC — только боем | [_plan](../../game/core/rules/effect_engine.gd#L193), [HeroDefense](../../game/core/rules/hero_defense.gd) | — | [godot-client: состояния и урон](godot-client.md#состояния-и-урон-по-герою-v078) |
| [`heal`](../../llm_server/src/llm_server/protocol.py#L514) | `tier` (`minor` / `moderate` / `major`), `reason` | Кубы по ступени (`rules.heal_dice`); здоровому — отказ | [_plan](../../game/core/rules/effect_engine.gd#L203) | — | |
| [`coins`](../../llm_server/src/llm_server/protocol.py#L520) | `delta_cp` (+ награда, − плата), `reason` | Плата — хватает ли; награда — предел уровня и бюджет до долгого отдыха; в торговле — отказ | [_plan](../../game/core/rules/effect_engine.gd#L211), `reward_left` | `pay` (по оглавлению) | [concepts: награда](../design/concepts.md#вещи-и-награды) |
| [`give_item`](../../llm_server/src/llm_server/protocol.py#L526) | `item_id` **или** `item` (новая вещь `GeneratedItem`), `qty` | Вещь задания — только с заданием; редкость по уровню; обычная вещь — в бюджете монет; магическая — одна до долгого отдыха и только в ходе с пройденной проверкой; новая — после `find_items`, по словарю свойств; товар собеседника-торговца — через торговлю | [_plan](../../game/core/rules/effect_engine.gd#L223), [_plan_give](../../game/core/rules/effect_engine.gd#L617), [ItemRules.check_generated](../../game/core/items/item_rules.gd#L350) | `items` для новой вещи (по оглавлению) | [godot-client: предметы](godot-client.md#предметы-по-5e-v0712) |
| [`take_item`](../../llm_server/src/llm_server/protocol.py#L773) | `item_id`, `qty` | Есть ли у героя; проклятую не отдать; вещь шага задания — только её адресату (закрывает шаг) | [_plan](../../game/core/rules/effect_engine.gd#L241), [_plan_quest_take](../../game/core/rules/effect_engine.gd#L602) | — | |
| [`drop_item`](../../llm_server/src/llm_server/protocol.py#L749) | `item_id` (вещь или сумка), `qty` | Вещь ложится в комнату, сумка — с содержимым | [ContainerRules.plan_drop](../../game/core/rules/container_rules.gd#L317) | `containers` | |
| [`cast`](../../llm_server/src/llm_server/protocol.py#L795) | `spell`, `slot_level` (нет — наименьшая подходящая), `on_self` | Знает ли, готово ли, есть ли ячейка; тратит ячейку; `on_self` снимает то, что заклинание лечит | [_plan](../../game/core/rules/effect_engine.gd#L263), [SpellRules.check](../../game/core/rules/spell_rules.gd#L51) | `spells` советуется после | [godot-client: магия](godot-client.md#правила-5e-магия-состояния-отдых-v060) |
| [`condition`](../../llm_server/src/llm_server/protocol.py#L811) | `condition`, `on`, `reason`, `save` {`ability`, `dc_tier`}, `tag`, `duration`, `repeat_save`, `cause`, `by`, `ends_on_damage`, `target_id` | Спасбросок героя (черты расы по `tag`); без спасброска — только `cause: player` в ходе по словам игрока; выводящее из строя вне боя — со сроком; с `target_id` — врагу, иммунитеты монстра; с `target_id` вне боя — отказ | [_plan_condition](../../game/core/rules/effect_engine.gd#L405), [ConditionRules](../../game/core/rules/condition_rules.gd) | `conditions` | [godot-client: состояния](godot-client.md#состояния-и-урон-по-герою-v078) |
| [`use_feature`](../../llm_server/src/llm_server/protocol.py#L829) | `feature`, `amount` | Есть ли использования (с учётом уже зарезервированных); лечение умения считает движок | [_plan](../../game/core/rules/effect_engine.gd#L276), [FeatureUses.can_use](../../game/core/character/feature_uses.gd#L73) | — | |
| [`use_item`](../../llm_server/src/llm_server/protocol.py#L835) | `item_id` | Есть ли и можно ли использовать (зелье, свиток, жезл с зарядами) | [_plan](../../game/core/rules/effect_engine.gd#L289), [ItemRules.can_use](../../game/core/items/item_rules.gd#L473) | — | |
| [`equip`](../../llm_server/src/llm_server/protocol.py#L858) | `slot` (`armor`, `shield`, `main_hand`, `off_hand`, `head` … `ring2`, `all`), `item_id` (нет — снять) | Как лист персонажа; проклятое не снять; в бою доспех, щит и носимое не меняют, оружие — раз за ход; переодевание тратит минуты | [_plan_equip](../../game/core/rules/effect_engine.gd#L524) | `equip` | |

### Место и мир

| Эффект | Поля | Что проверяет движок | Правила | Тема | Ещё |
|---|---|---|---|---|---|
| [`move`](../../llm_server/src/llm_server/protocol.py#L500) | `room_id`, `npcs` (кто идёт с героем) | Один переход за ход; есть открытый выход; в плену — нельзя; под стражей — любая комната той же локации; спутники — по правилу `npc_follow`; перегружен — отказ; найденная ловушка на выходе — отказ. Применяется как кнопка выхода: ловушка срабатывает, встреча комнаты — затаились или бой (v0.7.22.16) | [_plan](../../game/core/rules/effect_engine.gd#L163), [ExplorationRules.open_exits](../../game/core/rules/exploration_rules.gd#L138) | — | [design: исследование](../design/systems/exploration.md) |
| [`advance_time`](../../llm_server/src/llm_server/protocol.py#L879) | `minutes` (1…720), `reason` | Не в бою; один раз за ход; не больше `time.max_master_minutes`. Применяется как «Ждать»: в округе с законом — шагами `crime.wait_step`, после каждого заглядывает патруль; задержали — время дальше не идёт (v0.7.22.18) | [_plan](../../game/core/rules/effect_engine.gd#L330), [CrimeRules.wait](../../game/core/rules/crime_rules.gd) | — | |
| [`furnish`](../../llm_server/src/llm_server/protocol.py#L558) | `props` — до 10 вещей (`name`, `description`, `item_id`, `owner`, `text`, `container`, `contents`, `lock`, `key`) | Только необставленная комната; число вещей; цена переносных по уровню; хозяин — NPC комнаты; ничейное в контейнерах — в бюджете наград | [PropRules.plan_furnish](../../game/core/rules/prop_rules.gd#L85) | — | [godot-client: интерактивный мир](godot-client.md#интерактивный-мир-v070) |
| [`take_prop`](../../llm_server/src/llm_server/protocol.py#L758) | `prop_id` | Переносная вещь этой комнаты; хозяин рядом — реагирует по правилам кражи | [PropRules.plan_take](../../game/core/rules/prop_rules.gd#L150) | — | |
| [`prop_state`](../../llm_server/src/llm_server/protocol.py#L765) | `prop_id`, `state` (`open`, `closed`, `broken`, `burned`, `moved`) | Вещь этой комнаты | [PropRules.plan_state](../../game/core/rules/prop_rules.gd#L193) | — | |
| [`take_from`](../../llm_server/src/llm_server/protocol.py#L566) | `prop_id`, `item_id`, `qty` | Контейнер комнаты или сумка героя, не заперт и не закрыт, в нём есть столько; чужое на глазах у хозяина — он это видит | [ContainerRules.plan_take](../../game/core/rules/container_rules.gd#L121) | `containers` | |
| [`put_in`](../../llm_server/src/llm_server/protocol.py#L575) | `prop_id`, `item_id`, `qty` | Своя вещь, ёмкость контейнера | [ContainerRules.plan_put](../../game/core/rules/container_rules.gd#L156) | `containers` | |
| [`unlock`](../../llm_server/src/llm_server/protocol.py#L584) | `prop_id`, `how` (`key`, `pick`, `force`) | Ключ у героя; или пройденная в этом ходе проверка нужного навыка с итогом не ниже DC замка | [_plan_unlock](../../game/core/rules/effect_engine.gd#L565), [ContainerRules](../../game/core/rules/container_rules.gd) | `containers` | |
| [`create_place`](../../llm_server/src/llm_server/protocol.py#L654) | `edge`, `rooms` (1–4 `NewRoom`), `new_location`, `name`, `description`, `terrain` | После `find_places`; только на открытом краю пакета; один раз за ход; комнат на место и за игру — по `rules.world_gen`; новые имена; выходы внутри места; встреча — в бюджете опыта уровня | [WorldGen.plan_place](../../game/core/world/world_gen.gd#L193) | `places` | [concepts: мир](../design/concepts.md#мир) |
| [`flag`](../../llm_server/src/llm_server/protocol.py#L978) | `flag`, `value` | Только флаг, который знает пакет (задания, выборы, тайны) | [_plan](../../game/core/rules/effect_engine.gd#L338), `QuestRules.known_flags` | — | |
| [`note`](../../llm_server/src/llm_server/protocol.py#L846) | `text` (до 200 знаков), `npc_id` | Без `npc_id` — память мастера (журнал); с ним — что помнит NPC этой комнаты | [_plan](../../game/core/rules/effect_engine.gd#L384), `GameSession.remember` | — | |

### Люди

| Эффект | Поля | Что проверяет движок | Правила | Тема | Ещё |
|---|---|---|---|---|---|
| [`npc_attitude`](../../llm_server/src/llm_server/protocol.py#L779) | `npc_id`, `delta` (−2…+2), `reason` | NPC в этой комнате | [_plan](../../game/core/rules/effect_engine.gd#L254), `GameSession.shift_attitude` | — | [design: социальное](../design/systems/social.md) |
| [`npc_discount`](../../llm_server/src/llm_server/protocol.py#L903) | `npc_id`, `percent`, `reason` | Торговец сцены; отношение ≥ +1 или склонён проверкой в этом ходе | [SocialRules.plan_discount](../../game/core/rules/social_rules.gd#L81) | `social` | |
| [`npc_favor`](../../llm_server/src/llm_server/protocol.py#L914) | `npc_id`, `service`, `item_id`, `reason` | Услуга из `services` NPC; отношение ≥ +2 или склонён; раз в неделю | [SocialRules.plan_favor](../../game/core/rules/social_rules.gd#L105) | `social` | |
| [`reveal_secret`](../../llm_server/src/llm_server/protocol.py#L934) | `npc_id`, `secret_id` | Тайна этого NPC и нужное ей отношение (по проверке тайна приходит сама в `revealed`) | [SocialRules.plan_secret](../../game/core/rules/social_rules.gd#L199) | `social` | |
| [`npc_follow`](../../llm_server/src/llm_server/protocol.py#L960) | `npc_id`, `follow`, `home` | NPC этой комнаты, не враждебен; отношение от `followers.min_attitude` (+2, «дружески») или склонён проверкой в этом ходе; не больше `followers.max` (3) спутников; `follow: false` — остаётся здесь, с `home` — уходит к себе | [FollowRules.plan](../../game/core/rules/follow_rules.gd#L19) | `social` | |
| [`reputation`](../../llm_server/src/llm_server/protocol.py#L925) | `delta` (−3…+3), `reason` | Локация — поселение пакета; раз за ход; причина обязательна; задания, убийства и кражи движок считает сам | [ReputationRules.plan](../../game/core/rules/reputation_rules.gd#L102) | `social` | |
| [`create_npc`](../../llm_server/src/llm_server/protocol.py#L668) | `npc` (`NewNpc`: имя, роль, раса, пол, возраст, сложение, рост, описание, характер, шаблон SRD, комната, торговец и товар, связи) | После `find_npcs`; один за ход; новое имя; комната этой локации; лимиты на локацию и игру; шаблон людей с CR ≤ `max_cr`; облик — из списков `rules.body` | [WorldGen.plan_npc](../../game/core/world/world_gen.gd#L65), [BodyRules.check](../../game/core/character/body_rules.gd) | `people` | [concepts: люди](../design/concepts.md#люди) |

### Задания и цель

| Эффект | Поля | Что проверяет движок | Правила | Тема | Ещё |
|---|---|---|---|---|---|
| [`accept_quest`](../../llm_server/src/llm_server/protocol.py#L971) | `quest_id` | Как кнопка «Взять задание»: задание есть, не взято, даёт собеседник; лимит созданных | [_plan](../../game/core/rules/effect_engine.gd#L368), [QuestRules.can_accept](../../game/core/rules/quest_rules.gd#L79) | — | [narrative: задания](../narrative/quests.md) |
| [`create_quest`](../../llm_server/src/llm_server/protocol.py#L718) | `giver`, `board_prop_id`, `own`, `for_goal`, `title`, `description`, `offer_text`, `scale`, `steps` (1–4: `talk`, `visit`, `find`, `fight`), `reward_item_id`, `new_npcs`, `new_place`, `quest_item` | После `find_quests`; одно за ход; заказчик — NPC сцены, живой человек мира для доски или `new:<key>`; своё дело — без заказчика; не в розыске; глубина заказчика; лимиты открытых; шаги — факты мира; награду ставит движок по `scale` | [QuestGen.plan_quest](../../game/core/world/quest_gen.gd#L97) | `quests` | [concepts: дела](../design/concepts.md#дела-и-события) |
| [`goal_assess`](../../llm_server/src/llm_server/protocol.py#L943) | `scale`, `direction`, `concepts` | Масштаб и направление из списков; порог ставит движок | [GoalRules.plan_assess](../../game/core/character/goal_rules.gd#L33) | `goals` (по оглавлению) | |
| [`goal_hint`](../../llm_server/src/llm_server/protocol.py#L953) | — | Только за порогом цели; один за ход; движок считает намёки до задания цели | [GoalRules.plan_hint](../../game/core/character/goal_rules.gd#L101) | `goals` (по оглавлению) | |

### Бой и закон

| Эффект | Поля | Что проверяет движок | Правила | Тема | Ещё |
|---|---|---|---|---|---|
| [`start_combat`](../../llm_server/src/llm_server/protocol.py#L869) | `enemies` [{`monster`, `count`, `name`}], `side`, `reason` | **Только в бою — подкрепление** у края поля в бюджете опыта уровня. Вне боя — отказ: бой начинает игрок (`next_mode: combat`) или встреча мира | [_plan](../../game/core/rules/effect_engine.gd#L154), [_plan_fight](../../game/core/rules/effect_engine.gd#L494) | — | [design: бой](../design/systems/combat.md) |
| `damage` / `condition` с `target_id` | как выше | Только активный враг боя; иммунитеты монстра; другие эффекты на врага — отказ | [_plan_on_foe](../../game/core/rules/effect_engine.gd#L469) | — | |
| [`crime_known`](../../llm_server/src/llm_server/protocol.py#L888) | `victim_id` | Тайное убийство из хроники героя; движок разносит молву и розыск | [CrimeRules.plan_reveal](../../game/core/rules/crime_rules.gd#L206) | `crime` | [concepts: преступление](../design/concepts.md#дела-и-события) |
| [`crime_release`](../../llm_server/src/llm_server/protocol.py#L896) | — | Герой задержан; в этом ходе пройдена проверка Убеждения, Обмана или Запугивания на ступени движка; розыск остаётся | [CrimeRules.plan_release](../../game/core/rules/crime_rules.gd#L383) | `crime` | |
| [`owner`](../../llm_server/src/llm_server/protocol.py#L971) | `creature_id` или `item_id`, `owner_id`, `price_cp` | Существо: связанный пленник героя в этой комнате, не NPC пакета; новый хозяин — NPC сцены (или пусто — отпущен); с ценой — только неразумный (`creatures.slavery: false`), не дороже `sale_cp_per_xp` × опыт существа и кошелька торговца; деньги переводит и уводит существо к дому покупателя движок. Вещь: чужая вещь героя, хозяин здесь, `owner_id: "hero"` — хозяин уступает её. Одна смена хозяина за ход | [OwnerRules.plan](../../game/core/rules/owner_rules.gd#L87) | `captives` | [concepts: пленник](../design/concepts.md#пленник) |

### Запреты по режиму

Проверяются первыми в [EffectEngine._plan](../../game/core/rules/effect_engine.gd#L145):

- **Бой:** `move`, `coins`, `give_item`, `take_item`, `npc_attitude`, `advance_time`, `furnish`, `take_prop` — отказ (исход боя, переходы и добычу ведёт движок). Эффект с `target_id` — только `damage` и `condition` врагу.
- **Торговля:** `coins`, `give_item`, `take_item` — отказ: сделки идут панелью игрока.
- **Разговор с торговцем:** `give_item` его товара — отказ: купить можно только в торговле (`next_mode: trade`).

## Итог хода

Мастер заканчивает ход объектом [`TurnOutput`](../../llm_server/src/llm_server/agents.py#L115) (бэкенд превращает его в `TurnResult`, [protocol.py](../../llm_server/src/llm_server/protocol.py#L420)). Валидатор вывода ([agents.py](../../llm_server/src/llm_server/agents.py#L434)) возвращает модели на доработку пустой текст, `changes` без эффектов, чужие `effect_ids` и `social` / `trade` / `combat` без NPC сцены. Клиент применяет итог в [GameState._apply_result](../../game/autoload/game_state.gd#L2037).

| Поле | Что значит | Что делает клиент |
|---|---|---|
| `narration` | Текст мастера или реплика NPC | Строка в чате (от NPC — в разговоре) |
| `options` (до 3) | Варианты действий от первого лица | Кнопки под чатом; нажатие — новый ход `action` |
| `option_costs` | Цена каждого варианта в мм | Платный вариант: движок сначала списывает монеты ([choose_option](../../game/autoload/game_state.gd#L1231)), мастер получает «[движок уже списал …]» |
| `effect_ids` | Принятые движком эффекты этого хода | [EffectEngine.apply](../../game/core/rules/effect_engine.gd#L118) по порядку, остальные резервы сгорают; строки итога — в чат |
| `next_mode` + `npc_id` | `social` / `trade` — разговор или торговля с NPC сцены; `combat` — игрок нападает на NPC сцены; `exploration` — конец разговора | Разговор начинается только с хода по словам игрока; враждебный NPC не говорит; торговля у закрытой лавки — разговор; `combat` — бой с этим NPC по его шаблону SRD |
| `changes` | Что по тексту изменилось | Только проверка согласованности на бэкенде: изменения без эффектов — доработка |
| `missing_concept` | Замысел игрока, для которого у движка нет понятия | Заметка автору в трейсе (`tools/trace_report.py`), игрок не видит |

После эффектов клиент сам продолжает: переход в другую комнату — ход `enter`; бой с NPC (`next_mode: combat`) или встреча мира — ход `combat_start`; 0 HP вне боя — `downed`; NPC, чей час вышел (расписание), уходит из разговора — `resume`.

## Короткий мастер (роутер)

Ход по словам игрока бэкенд сначала спрашивает у роутера ([router.py](../../llm_server/src/llm_server/router.py)): хватит ли рассказа. Короткий мастер **не вызывает инструментов** и отвечает [`ShortOutput`](../../llm_server/src/llm_server/router.py): `narration`, `options`, `next_mode` (`social` / `exploration`), `npc_id` или `need_full: true` — тогда ход идёт заново с полным промптом и инструментами. Ходы, которые движок уже решил (`rest`, `deal`, `haggle`, `quest`, `theft`, `law`, `wait`, `trap`, `combat_start`, `combat_round`, `death`, `resume`), идут коротким путём без роутера; `enter` — коротким, если комнату не надо обставлять. Выключить: `LLM_SERVER_ROUTER=0`.

## Лимиты

| Лимит | Значение | Где |
|---|---|---|
| Проверок за ход | 1 | `rules.json` `turn_limits.max_checks` → снимок `limits` |
| Эффектов за ход | 3 | `rules.json` `turn_limits.max_effects` |
| Запросов к модели за ход | 10 | `TURN_USAGE_LIMITS` в [turns.py](../../llm_server/src/llm_server/turns.py#L45) |
| Повторов инструмента `propose_effect` | 4 | `EFFECT_RETRIES` в [agents.py](../../llm_server/src/llm_server/agents.py#L336) |
| Новых людей | 4 на локацию, 12 за игру | `rules.json` `world_gen` |
| Новых комнат | 4 на место, 12 за игру | `rules.json` `world_gen` |
| Созданных заданий | 3 открытых, 3 у одного заказчика или доски | `rules.json` `quest_gen` |
| Магических вещей | 1 до долгого отдыха | `rules.json` `reward_budget.magic_per_rest` |
| Вещей в обстановке | 10 | `rules.json` `props.max_per_room` |
| Время за ход | до 720 минут | `rules.json` `time.max_master_minutes` |

## Нападение на NPC (v0.7.22.16)

Мастер нападение не проводит — он только открывает бой (`next_mode: combat`), если игрок напал словами. Всё остальное делает движок без мастера:

- кнопка **«Напасть»** у NPC — бой сразу (`GameState.attack_npc`); кто не ждёт (не враждебен, отношение ≥ `combat.unaware_attitude`) — застигнут врасплох;
- вредное заклинание (атака, урон, удерживающее состояние — `CombatRules.hostile_spell`) или оружие, прикреплённое к словам с целью-NPC, — бой сразу, заклинание — первым ударом;
- после боя: оглушённый NPC пакета — существо комнаты (`CreatureRules`): «Обыскать», «Связать», «Вести», «Отпустить», «Добить»; очнувшись или отпущенный, он уходит к себе, помнит, а нападение становится известно — преступление вида `assault` (`CrimeRules`, `rules.crime.kinds`); добитый — убийство;
- существо, на которое напали снова, дерётся со своими ранами и опыта второй раз не даёт.

Мастер видит оглушённых и связанных в `scene.creatures`, а не среди NPC: за них он отвечает в рассказе.

## Чего у мастера нет

- **Опыт.** Только бой и задания (`XpRules`); эффекта опыта нет.
- **Начать бой вне боя.** `start_combat` вне боя отклоняется; бой — по `next_mode: combat` с NPC сцены или встречей мира.
- **Сделки в торговле.** Покупка и продажа — панелью игрока; мастер отыгрывает ход `deal` и торг (`request_check` в торговле).
- **Быстрый переход, ожидание, отдых, кражи в окне карманов, ловушки, уровни.** Это кнопки движка; мастеру приходит готовый итог (ход своего `kind`).
- **Скрытое.** Тайны комнат и NPC в снимок не попадают: мастер видит зацепки и то, что движок уже открыл.

## Как добавить инструмент или эффект

1. Модель в [protocol.py](../../llm_server/src/llm_server/protocol.py): новый `*Effect` в объединение `Effect` (или `Engine*Params` / `Engine*Result` и новый метод в `CONTRACT_MODELS`).
2. `PROTOCOL_VERSION` на обеих сторонах, `uv run --project llm_server python -m llm_server.contract`, раздел «Протокол X.Y» в [ADR-0009](adr/0009-godot-backend-protocol.md).
3. Движок: ветка в [EffectEngine._plan](../../game/core/rules/effect_engine.gd#L139) (проверка → `{plan, summary}` или `{reason}`) и в `_apply_one`; правила — в своём классе `game/core/`, числа — в `rules.json`; тест gdUnit.
4. Новый метод `engine.*` — обработчик в `GameState` и `register_handler` в [backend.gd](../../game/autoload/backend.gd#L48).
5. Мастер: строка в docstring `propose_effect` или новый инструмент в `build_turn_agent`; тема правил (`TOPICS`, `topics/<тема>.md.j2`), если эффекту нужны правила.
6. Golden-сценарий ([golden-scenarios.md](golden-scenarios.md)); новые поля снимка — и в `golden.py`.
7. Строка здесь и сценарий в [master-scenarios.md](master-scenarios.md); понятие — в [concepts.md](../design/concepts.md).
