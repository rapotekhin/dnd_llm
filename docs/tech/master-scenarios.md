# Что умеет мастер: сценарии

Всё, что мастер уже может сделать в игре, — по сценариям: когда это происходит, какими инструментами, что проверяет движок и чем кончается. Сверено с кодом протокола 0.49.0 (v0.7.22.22). Поля инструментов и эффектов, ссылки на код каждого — в [master-tools.md](master-tools.md); здесь — как из них складывается действие. Взгляд со стороны игрока — что он может захотеть, каким каналом это доходит до мира и где пробелы — в [player-scenarios.md](player-scenarios.md).

Обозначения в пайплайнах: `request_check` / `propose_effect(...)` / `find_*` / `rules(...)` / `lookup` — инструменты мастера; **кнопка** — действие движка без мастера; `kind` — вид хода, который клиент шлёт мастеру; «golden» — сценарии в [evals/golden/scenarios.yaml](../../evals/golden/scenarios.yaml), которые проверяют это поведение на настоящей модели.

## Общий пайплайн хода

1. **Клиент собирает ход** ([GameState._request](../../game/autoload/game_state.gd#L1970)): `mode` (`exploration` / `social` / `trade` / `combat`), `kind`, ввод игрока, `npc_id` собеседника, снимок мира ([TurnSnapshot.build](../../game/core/session/turn_snapshot.gd#L7)) → `turn.request`.
2. **Бэкенд выбирает путь** ([turns.py](../../llm_server/src/llm_server/turns.py#L162)): ходы, которые движок уже решил, и вход в обставленную комнату идут коротким промптом; слова игрока сначала оценивает роутер. Короткий мастер отвечает только текстом или просит полный (`need_full`) ([router.py](../../llm_server/src/llm_server/router.py)).
3. **Полный мастер** ([build_turn_agent](../../llm_server/src/llm_server/agents.py#L422)) читает системный промпт режима (правила, мир, сцена, темы сцены) и зовёт инструменты. Каждый вызов идёт в Godot как `engine.*`. Проверка бросается сразу, эффект только резервируется.
4. **Итог хода** — текст, варианты, их цена, `effect_ids`, `next_mode` ([master-tools → Итог хода](master-tools.md#итог-хода)).
5. **Клиент применяет итог** ([GameState._apply_result](../../game/autoload/game_state.gd#L2037)): названные резервы применяются, остальные сгорают. Потом клиент сам продолжает: новая комната — ход `enter`, бой — `combat_start`, 0 HP — `downed`, конец разговора — `resume`.

Ход по одному правилу: **сначала проверка, потом описание**, и всё, что изменилось, — только принятыми эффектами ([ADR-0008](adr/0008-engine-decides-llm-narrates.md)).

---

## Место и перемещение

### Описать новую комнату и обставить её

- **Когда:** герой впервые вошёл в комнату (`kind: enter`, в сцене `furnish: true`).
- **Пайплайн:** `find_items` (если вещи переносные) → `propose_effect(furnish {props: […]})` → описание только этих вещей.
- **Движок:** комната ещё не обставлена; до 10 вещей; цена переносных по уровню; хозяин — NPC комнаты; контейнеры с содержимым и замком; ничейное в контейнерах — в бюджете наград ([PropRules.plan_furnish](../../game/core/rules/prop_rules.gd#L85)).
- **Итог:** вещи комнаты закреплены навсегда (`session.props`); дальше мастер описывает только список «Вокруг» из снимка.
- **Golden:** `furnish_on_first_visit`, `describe_only_props`.

### Переместить героя

- **Когда:** игрок словами идёт туда, куда есть выход («иду в погреб»), или мастер ведёт его по сюжету (стража уводит).
- **Пайплайн:** `propose_effect(move {room_id, npcs?})` → итог с `effect_ids`.
- **Движок:** один переход за ход; не перегружен; выход открыт ([ExplorationRules.open_exits](../../game/core/rules/exploration_rules.gd#L138)) и не стережётся найденной ловушкой; в плену — нельзя; под стражей — в любую комнату той же локации, задержание идёт с героем; `npcs` — спутники по правилу `npc_follow` ([_plan](../../game/core/rules/effect_engine.gd#L163)).
- **Итог:** клиент ведёт героя тем же путём, что кнопка выхода (v0.7.22.16): ловушка на выходе срабатывает, время в пути, пассивная Внимательность, тайники, шаги заданий, существа после боя идут за ним; встреча комнаты — враги затаились (герой крался) или бой; иначе ход `enter` — мастер описывает новую комнату.
- **Без мастера:** кнопки выходов ([GameState.go](../../game/autoload/game_state.gd#L1324)) и быстрый переход по карте (`travel`) — движок сам ведёт героя, проверяет перевес, ловушки и встречи, мастер получает `enter`.
- **Golden:** `teleport_injection` (в несуществующий выход — нельзя), `npc_goes_along_on_move`, `crime_escort_to_captain`.

### Сделать новое место на краю мира или объект в локации

- **Когда:** игрок идёт туда, чего в пакете нет («сворачиваю с тропы в чащу»), а в сцене есть открытый край (`scene.open_edges`); или трактирщик назвал баню, которой нет. С v0.7.22.21.1 — и не здесь: «пекарня за городом» в таверне строится у Северных ворот. С v0.7.22.24 — и внутри известного: баня у площади — `inside: true` с `room_id` площади, край не нужен.
- **Пайплайн:** `find_places(query)` (похожие места и открытые края известного мира) → (нет похожего) → `propose_effect(create_place {room_id?, edge, rooms[1–4], new_location?, name, description, terrain})` → у этой комнаты часто в том же ходе `move` в новую; у другой комнаты герой остаётся на месте, мастер говорит, как дойти.
- **Движок:** после `find_places`; только открытый край комнаты; одно место за ход; до 4 комнат на место и 12 за игру; новые имена; выходы — внутри места, к миру ведёт первая комната; новая локация — только где край разрешает, местность из списка края; встреча в бюджете опыта уровня ([WorldGen.plan_place](../../game/core/world/world_gen.gd#L193)).
- **Объект (v0.7.22.24):** комнаты одного `create_place` — один объект (`site`: имя, теги вида, `public`, хозяин `owner_id`); частная комната — `public: false` у комнаты; войти без спроса — сначала предупреждение, потом вторжение ([SiteRules](../../game/core/rules/site_rules.gd)).
- **Итог:** место живёт как место пакета (выход из этой комнаты, объект на карте); автор может перенести его в пакет вместе с объектом (`tools/promote_world.py`).
- **Правила:** тема `places` (сама в промпте, когда есть открытый край).
- **Golden:** `place_off_the_trail`, `place_made_at_mention`, `no_edge_no_place`, `bakery_past_the_north_gate`, `site_inside_bathhouse`.

### Провести время

- **Когда:** игрок ждёт, работает, спит под открытым небом словами.
- **Пайплайн:** `propose_effect(advance_time {minutes, reason})`.
- **Движок:** не в бою; раз за ход; до 720 минут ([_plan](../../game/core/rules/effect_engine.gd#L330)); время двигает [TimeRules](../../game/core/rules/time_rules.gd) — эффекты кончаются, лавки закрываются, ищут тела.
- **Без мастера:** кнопка «Ждать» (`kind: wait`) и отдых (`kind: rest`) — движок двигает часы сам, мастер рассказывает.
- **Golden:** `wait_until_evening`.

---

## Проверки

### Проверка навыка или спасбросок

- **Когда:** исход действия не очевиден: убедить, найти, подкрасться, удержаться, вскрыть.
- **Пайплайн:** `request_check {skill | save, dc_tier, reason, target_id?, sense?, tool?, argument?}` → описание по итогу (успех — удача, провал — неудача и её цена).
- **Движок:** DC по ступени (в разговоре — по шаблону SRD собеседника), бонус героя, состояния, темнота, язык, инструмент, вещи и заклинания ([_engine_check](../../game/autoload/game_state.gd#L2224)); одна проверка за ход.
- **Повтор:** та же проверка без перемен не бросается — прежний итог (`blocked`); новый довод (`argument`), заклинание, отношение, инструмент — перемена ([ExplorationRules.locked](../../game/core/rules/exploration_rules.gd#L51)).
- **Golden:** `no_fake_rolls`, `one_check_per_turn`, `retry_blocked`, `social_repeat_same_words`, `impossible_persuasion_success`, `lie_to_guard_contest`, `tool_pick_lock`.

### Найти скрытое

- **Когда:** игрок ищет, осматривает зацепку (`scene.hooks`).
- **Пайплайн:** `request_check {skill: perception | investigation}` → описать **ровно** открытое движком (`revealed`).
- **Движок:** скрытое комнаты по итогу броска ([ExplorationRules.active_reveal](../../game/core/rules/exploration_rules.gd#L125)), тайники выдаются сразу, шаги заданий продвигаются; ловушка найдена — её обезвреживают кнопкой (`kind: trap`).
- **Golden:** `search_room_fail`, `inspect_hook_needs_check`, `hidden_hook_no_leak`, `magic_find_in_a_cache`.

---

## Люди

### Начать и закончить разговор

- **Когда:** игрок обращается к NPC сцены своими словами.
- **Пайплайн:** реплика + `next_mode: social`, `npc_id` (короткий мастер тоже может). Закончить — `next_mode: exploration`.
- **Движок / клиент:** разговор начинается только с хода по словам игрока (не на `resume`); враждебный NPC не говорит ([SocialRules.refuses](../../game/core/rules/social_rules.gd)); кого нет в сцене — не отвечает, мастер говорит, где его найти.
- **Итог:** в разговоре мастер говорит за NPC (`social.md.j2`); конец разговора — сводка в память (`summary.request`).
- **Golden:** `talk_to_present_npc`, `talk_to_absent_npc`, `absent_npc_does_not_answer`, `listen_does_not_start_talk`, `resume_after_dialogue`, `hostile_refuses_to_talk`.

### Что NPC даёт словами

| Просьба | Пайплайн | Движок пускает, если |
|---|---|---|
| Отношение меняется | `npc_attitude {npc_id, delta ±1…2}` | NPC в комнате |
| Скидка | `request_check {persuasion…, target_id}` (если нужно) → `npc_discount {percent}` | торговец; отношение ≥ +1 или склонён проверкой в этом ходе |
| Услуга даром | (проверка) → `npc_favor {service}` | услуга из `services`; отношение ≥ +2 или склонён; раз в неделю |
| Тайна | по проверке — сама в `revealed`; по доброй воле — `reveal_secret {secret_id}` | отношение, которое нужно тайне |
| Запомнит обещание | `note {text, npc_id}` | NPC в комнате; вернётся в `scene.npcs[].memory` |
| Слава в поселении | `reputation {delta ±1…3, reason}` | локация — поселение; раз за ход |

- **Правила:** тема `social` (сама в промпте в разговоре); код — [SocialRules](../../game/core/rules/social_rules.gd), [ReputationRules](../../game/core/rules/reputation_rules.gd).
- **Golden:** `discount_after_persuasion`, `favor_from_a_friend`, `secret_hint_not_invented`, `secret_by_check`, `npc_memory_promise`, `npc_memory_recall`, `reputation_public_deed`, `reputation_not_for_small_talk`, `charmed_npc_is_friendly`.

### NPC идёт с героем

- **Пайплайн:** (проверка) → `npc_follow {npc_id}`; в переходе — `move {room_id, npcs: [id]}`; оставить — `npc_follow {follow: false}`, отпустить домой — `{follow: false, home: true}`.
- **Движок:** отношение от +2 или склонён проверкой; не враждебен; до 3 спутников ([FollowRules.plan](../../game/core/rules/follow_rules.gd#L19)).
- **Кнопки игрока** (v0.7.22.22): «Ждать здесь», «Вести с собой», «Отпустить» — без мастера.
- **В бою** (v0.7.22.22): спутник сам встаёт на сторону героя — не против стражи закона и не против людей своей локации ([AllyRules.joining](../../game/core/rules/ally_rules.gd)); мастер его в бой не зовёт.
- **Golden:** `npc_follows_the_hero`, `npc_goes_along_on_move`.

### Создать человека

- **Когда:** игрок ищет того, кого в мире нет (пекаря, сапожника), или собеседник назвал человека, которого нет.
- **Пайплайн:** `find_npcs(query)` → (нет) → `propose_effect(create_npc {npc: {name, role, race?, gender, age?, build?, height?, description, personality, monster, room_id?, trader?, stock?, links?}})`.
- **Движок:** после `find_npcs`; один за ход; новое имя; комната этой локации; до 4 новых на локацию и 12 за игру; шаблон людей SRD с CR ≤ 3; облик — id из списков `rules.body` или выберет движок; торговец — товар из каталога ([WorldGen.plan_npc](../../game/core/world/world_gen.gd#L65)).
- **Итог:** человек живёт как NPC пакета; с ним говорят и торгуют; автор может перенести его в пакет (`tools/promote_world.py`).
- **Правила:** тема `people`.
- **Golden:** `npc_missing_is_made`, `npc_existing_not_made_again`, `trader_made_as_trader`, `rumors_only_from_the_world`.

---

## Вещи и награды

### Дать награду: монеты или вещь

- **Пайплайн:** `coins {delta_cp > 0, reason}` или `give_item {item_id, qty}` (вещь каталога — после `find_items`, если id неизвестен).
- **Движок:** предел награды уровня и бюджет до долгого отдыха (`reward_left_cp` в листе); после «почти невозможного» успеха — четверть; магическая вещь не стоит монет бюджета, но одна до долгого отдыха и только в ходе с пройденной проверкой; вещь задания — только с заданием ([_plan](../../game/core/rules/effect_engine.gd#L223)).
- **Golden:** `reward_budget_spent`, `magic_find_in_a_cache`, `quest_agree_gives_the_thing`.

### Создать новый предмет

- **Когда:** нужной вещи нет в каталоге: записка с текстом, жезл, зелье, необычный клинок.
- **Пайплайн:** `find_items(query, base?, properties?)` → (нет похожего) → `give_item {item: {name, item_type, base?, rarity, value_cp, properties[], description, use?, text?}}`.
- **Движок:** после `find_items`; свойства — только из словаря движка; действие (`use`) — заклинание книги движка, лечение, сопротивление, преимущество; редкость по уровню; цена по свойствам ([ItemRules.check_generated](../../game/core/items/item_rules.gd#L350)).
- **Итог:** вещь в листе героя и в библиотеке бэкенда ([library.py](../../llm_server/src/llm_server/llm/library.py)) — в следующий раз `find_items` её найдёт; автор переносит в каталог `tools/promote_items.py`.
- **Правила:** тема `items`.
- **Golden:** `item_dedupe`, `item_letter_with_text`, `item_wand_with_charges`, `master_item_by_description`, `item_unknown_not_revealed`.

### Плата и платный вариант

- **Пайплайн:** игрок платит словами — `coins {delta_cp < 0}`; мастер предлагает платный выбор — `options` + `option_costs` («Заплатить пять серебряных и выслушать» — 50).
- **Движок:** хватает ли монет; платный вариант списывает **клиент** при нажатии ([choose_option](../../game/autoload/game_state.gd#L1231)), мастер получает «[движок уже списал …]».
- **Правила:** тема `pay`.
- **Golden:** `pay_for_rumours`, `rent_room_words`.

### Взять, отдать, выбросить вещь

| Действие | Эффект | Движок |
|---|---|---|
| Взять вещь комнаты | `take_prop {prop_id}` | переносная; хозяин видит — реагирует ([PropRules.plan_take](../../game/core/rules/prop_rules.gd#L150)) |
| Изменить вещь комнаты | `prop_state {prop_id, state}` | открыта, закрыта, сломана, сожжена, сдвинута |
| Отдать свою вещь | `take_item {item_id, qty}` | есть у героя; проклятую не отдать; вещь шага задания — только адресату (закрывает шаг) |
| Оставить в комнате | `drop_item {item_id, qty}` | вещь или сумка с содержимым становится вещью комнаты |

- **Без мастера:** «Взять», «Выбросить» в окне места и листе — кнопки движка.
- **Golden:** `take_prop_words`, `read_prop_text`, `quest_claim_by_words`.

### Сундуки и сумки

- **Пайплайн:** взять — `take_from {prop_id, item_id}`; положить — `put_in`; запертый — `request_check {sleight_of_hand, tool: thieves_tools}` (или `athletics`) → `unlock {how: pick | force}`, ключом — `unlock {how: key}`.
- **Движок:** контейнер не заперт, в нём есть, ёмкость; вскрыть — только после пройденной в этом ходе проверки с итогом не ниже DC замка ([ContainerRules](../../game/core/rules/container_rules.gd), [_plan_unlock](../../game/core/rules/effect_engine.gd#L565)).
- **Правила:** тема `containers` (сама в промпте, когда в комнате контейнер).
- **Golden:** `container_take_from`, `container_locked_pick`, `bag_take_out`, `dead_traders_wares`.

### Торговля

- **Открыть:** слова игрока → `next_mode: trade`, `npc_id` (только торговцу, лавка открыта, не закрыта за кражу).
- **Сделки:** панель игрока, без мастера; мастер отыгрывает готовое (`kind: deal`). `coins` / `give_item` / `take_item` в торговле движок отклоняет.
- **Торг:** кнопка или `request_check` социальным навыком в торговле → бросок торга движка, итог — в `note` ([TradeRules.is_haggle](../../game/core/rules/trade_rules.gd#L331)); `kind: haggle`.
- **Товар торговца в разговоре:** `give_item` его товара — отказ, нужна торговля.
- **Golden:** `social_to_trade`, `trade_words_no_effects`, `trade_haggle_words`, `trade_deal_narration`, `social_buy_from_trader`, `trader_news_explains_prices`.

---

## Герой

### Урон и лечение

- **Пайплайн:** `damage {severity: unpleasant | dangerous | deadly, damage_type, reason}`; `heal {tier: minor | moderate | major, reason}`.
- **Движок:** кубы по ступени и уровню, сопротивления героя; 0 HP вне боя — герой без сознания, ход `downed` ([_plan](../../game/core/rules/effect_engine.gd#L193)).
- **Golden:** `trap_damage_severity`, `downed_comes_to`.

### Наложить или снять состояние

- **Пайплайн:** `rules("conditions")` (в сцене — уже в промпте) → `condition {condition, reason, save {ability, dc_tier}, tag?, duration, by?, repeat_save?, ends_on_damage?}`; снять — `{on: false}`.
- **Движок:** спасбросок героя с чертами расы по `tag`; без спасброска — только когда герой сам навлёк это в своём ходе (`cause: player`: выпил, лёг спать); выводящее из строя вне боя — со сроком ([_plan_condition](../../game/core/rules/effect_engine.gd#L405)).
- **Golden:** `condition_vial_of_poison`, `condition_ghost_fear`, `condition_let_them_bind`, `condition_doze_by_the_fire`.

### Колдовство, умения, вещи

| Как | Пайплайн |
|---|---|
| Заклинание словами | `cast {spell, slot_level?, on_self?}` → что оно сделало в мире — по теме `spells` (`rules("spells")`), исход — проверкой или эффектами |
| Заклинание или умение кнопкой листа | движок тратит ячейку или использование сам; мастеру — `kind: ability` с фактами |
| Заклинание, прикреплённое к словам | движок тратит при отправке; мастер получает «[Вместе с этим, до слов игрока: …]» |
| Умение с использованиями | `use_feature {feature, amount}` (лечение умения считает движок) |
| Зелье, свиток, жезл | `use_item {item_id}` |
| Надеть, снять, раздеться | `rules("equip")` → `equip {slot, item_id?}`; переодевание тратит минуты |

- **Движок:** [SpellRules.check](../../game/core/rules/spell_rules.gd#L51), [FeatureUses.can_use](../../game/core/character/feature_uses.gd#L73), [ItemRules.can_use](../../game/core/items/item_rules.gd#L473), [_plan_equip](../../game/core/rules/effect_engine.gd#L524).
- **Golden:** `cast_spell_words`, `use_feature_words`, `spell_zone_of_truth`, `spell_minor_illusion`, `spell_speak_with_animals`, `strip_by_words`, `put_on_a_ring_by_words`, `throw_flask_out_of_combat`.

---

## Задания и цель

### Взять задание словами

- **Пайплайн:** `accept_quest {quest_id}` — как кнопка «Взять задание»; вещь, которую заказчик даёт с заданием, — `give_item` её id берёт задание целиком.
- **Движок:** задание есть, не взято, его даёт собеседник; лимит созданных ([QuestRules.can_accept](../../game/core/rules/quest_rules.gd#L79)).
- **Golden:** `quest_take_by_words`, `accept_quest_by_words`, `quest_offer_when_asked`.

### Создать задание

- **Когда:** NPC сцены просит о помощи, игрок ищет работу, читает доску, задумывает своё дело.
- **Пайплайн:** `rules("quests")` (у доски — уже в промпте) → `find_quests(query)` → (нет похожего) → `create_quest {giver | board_prop_id | own, title, offer_text, scale, steps[1–4], new_npcs?, new_place?, quest_item?, reward_item_id?}`.
- **Шаги:** `talk` (NPC, `item_id` — что отдать), `visit` (комната, где герой не был), `find` (тайна мира или вещь задания), `fight` (встреча); то, что приносит задание, — `new:<key>`.
- **Движок:** после `find_quests`; одно за ход; заказчик — NPC сцены, для доски — живой человек мира или новый; своё дело — без заказчика, берётся сразу; не в розыске; до 3 открытых созданных; награду ставит движок по `scale` и уровню, опыт класса — только за опасное ([QuestGen.plan_quest](../../game/core/world/quest_gen.gd#L97)).
- **Итог:** задание предложено (кнопка «Взять задание» у заказчика), шаги — в журнале; возвращение к заказчику движок добавит сам.
- **Golden:** `quest_npc_gives_work`, `quest_existing_not_made_again`, `quest_brings_its_thing`, `quest_board_order`, `quest_own_deed`.

### Жизненная цель героя

- **Оценка:** игрок пишет цель в листе → `kind: goal` → `goal_assess {scale, direction, concepts[]}`; порог ставит движок ([GoalRules.plan_assess](../../game/core/character/goal_rules.gd#L33)).
- **До порога:** мир не ведёт к цели (ответы по логике мира: новичку о драконе — смех и совет подрасти).
- **За порогом, на вопрос игрока:** `goal_hint` (один за ход) → после достаточных намёков `create_quest {for_goal: true}`.
- **Правила:** тема `goals`.
- **Golden:** `goal_assessed`, `goal_novice_and_the_dragon`, `goal_not_brought_up`, `goal_hint_after_the_threshold`, `goal_quest_after_hints`, `goal_no_hint_in_the_wrong_place`, `high_goal_is_a_path`.

---

## Бой

### Начать бой

- **Игрок нападает на NPC сцены словами:** итог с `next_mode: combat`, `npc_id` → клиент начинает бой с этим NPC по его шаблону SRD (`kind: combat_start`). Урон NPC эффектом вне боя движок не примет.
- **Кнопка «Напасть» у NPC** (v0.7.22.16): бой сразу, без мастера; герой ходит первым, NPC, который не ждёт (не враждебен, отношение ≥ −1), застигнут врасплох.
- **Оружие или вредное заклинание, прикреплённое к словам, с целью-NPC** (v0.7.22.16): бой начинает движок, заклинание — первый удар; очарование, лечение и слова остаются ходом мастера.
- **Кто здесь:** NPC из списка сцены — здесь, даже если раньше рассказ его «увёл»; мастер строит рассказ по списку.
- **Встреча мира:** движок при входе в комнату со встречей: заметили — бой, не заметили — существа затаились, мастер описывает их и бой сам не начинает ([EncounterRules](../../game/core/rules/encounter_rules.gd)).
- **Нельзя:** `start_combat` вне боя — отказ («драка начинается, когда игрок нападает на NPC сцены, или встречей мира»).
- **Golden:** `attack_innkeeper`, `attack_npc_the_story_lost`, `lurking_foes_no_fight`; плейтест `attack`.

### В бою

| Что | Как |
|---|---|
| Раунд | Движок играет раунд, мастер рассказывает (`kind: combat_round`) |
| Импровизация игрока | `request_check` → `damage` / `condition` с `target_id` врага ([_plan_on_foe](../../game/core/rules/effect_engine.gd#L469)) |
| Подкрепление | `start_combat {enemies, side}` — в бюджете опыта уровня, у края поля через раунд ([_plan_fight](../../game/core/rules/effect_engine.gd#L494)) |
| Переговоры | `request_check {persuasion | intimidation}` — бросок против DC переговоров боя |
| Смерть героя | `kind: death` — эпитафия |
| Союзники (v0.7.22.22) | Спутники, союзники встречи пакета (`allies`), призванные заклинанием — в `combat.allies`; ходят сами ([CombatRules._ally_turn](../../game/core/rules/combat_rules.gd), [AllyRules](../../game/core/rules/ally_rules.gd)); мастер рассказывает их удары только по строкам раунда, эффектов за них не даёт. Golden `allies_in_the_round`; плейтест `allies` |

- **Нельзя в бою:** `move`, `coins`, `give_item`, `take_item`, `npc_attitude`, `advance_time`, `furnish`, `take_prop`; доспех и носимое не меняют.
- **После боя:** сдавшиеся, оглушённые и перемирие — существа комнаты (`scene.creatures`); за них мастер отвечает в рассказе, `next_mode: social` к ним не открывает разговор ([CreatureRules](../../game/core/rules/creature_rules.gd)). С v0.7.22.16 существо помнит свои раны, а опыт за него даётся один раз. Беспомощного (без сознания, связан) — «Добить» без боя, остальных — «Напасть». Оглушённый NPC пакета — тоже существо: «Обыскать», «Добить»; очнувшись, он уходит к себе, помнит, а нападение — преступление по закону.
- **Плен:** проигранный бой с разумными или кнопка «Сдаться» (v0.7.22.17) — плен; пленители отбирают вещи в сундук комнаты; сбежал — пленители затаились в комнате, даже если бой был без встречи пакета (v0.7.22.16). Бой со стражей проигран или сдался ей — не плен, а снова задержание.
- **Golden:** `combat_round_narration`, `combat_parley_words`, `combat_improvisation`, `monster_round_prone_and_grappled`, `death_epitaph`, `creature_bound_questioned`.

### Пленники и перемирие

Ветка целиком — таблица [«Пленник»](../design/concepts.md#пленник) (v0.7.22.17).

| Что | Пайплайн | Движок |
|---|---|---|
| Допрос пленника | игрок «Заговорить» → ход мастера; правда под давлением — `request_check` с `target_id` существа | пленник отвечает по своему нраву и страху; память — `note` |
| Разговор с существом перемирия | то же | в снимке: «не пленник: свободен, не связан» — говорят на равных |
| Продать зверя NPC сцены | `owner {creature_id, owner_id, price_cp}` | цена не выше потолка и кошелька; разумного не продают (рабства нет); существо уходит к покупателю, `coins` не нужен ([OwnerRules.plan](../../game/core/rules/owner_rules.gd#L87)) |
| Отдать даром, отпустить словами | `owner {creature_id, owner_id}` / `owner {creature_id, owner_id: ""}` | как выше, без цены |
| Хозяин уступает свою вещь | `owner {item_id, owner_id: "hero"}` | вещь помечена чужой («чужое: …» в листе), хозяин здесь |
| Связать, вести, отдать страже, отпустить, добить | кнопки игрока, без мастера | [CreatureRules.act](../../game/core/rules/creature_rules.gd#L120) |

- **Правила:** тема `captives` (сама в промпте, когда в сцене есть существа после боя).
- **Golden:** `creature_bound_questioned`, `captive_beast_sold`, `truce_not_a_prisoner`; плейтест `captives`.

---

## Закон

| Сценарий | Пайплайн | Движок |
|---|---|---|
| Нападение на NPC, который выжил | — (движок после боя) | преступление вида `assault`: видели или жертва в сознании — известно сразу, иначе когда очнётся; приговор легче (колодки, вергельд 10 зм) |
| Герой признался или его разоблачили | `crime_known {victim_id}` | тайное убийство (или нападение) из хроники; молва, отношение, розыск ([CrimeRules.plan_reveal](../../game/core/rules/crime_rules.gd#L206)) |
| Стража уводит к капитану | `move {room_id}` под стражей | любая комната той же локации; задержание идёт с героем |
| Отпустить словами | `request_check {persuasion | deception | intimidation}` → `crime_release` | проверка пройдена на ступени движка за преступления; розыск остаётся ([CrimeRules.plan_release](../../game/core/rules/crime_rules.gd#L383)) |
| Задержание кнопками | вергельд или срок, сопротивление (бой), убедить, обмануть, запугать, подкупить — движок бросает и применяет сам ([GameState.crime_answer](../../game/autoload/game_state.gd#L1619)); мастер рассказывает (`kind: law`) | рассказ — только по итогу движка: в конце строк — «Исход» (держат / отпустили, розыск остаётся / искуплено), наказаний сверх названных нет (v0.7.22.18) |
| Ожидание в розыске | «Ждать» или `advance_time` | в округе с законом время идёт шагами `crime.wait_step`, после каждого — патруль; задержали — ожидание прервано (v0.7.22.18, [CrimeRules.wait](../../game/core/rules/crime_rules.gd)) |
| Нападение на NPC при людях | кнопка «Напасть», `next_mode: combat`, вредное заклинание | стража закона и NPC с боевыми тегами (`crime.defend.tags`) вступают в бой, кроме друзей героя (отношение от +2) и спутников; бой проигран страже — задержание, нападение — преступление (v0.7.22.18, [CrimeRules.defenders](../../game/core/rules/crime_rules.gd)) |
| Ночлег и услуги в розыске | — | услуги торговцев (и даром, `npc_favor`) и платная комната закрыты, как торговля; бесплатный ночлег (храм для прислужника, лагерь) остаётся (v0.7.22.18) |

- **Правила:** тема `crime` (сама в промпте, когда у героя есть преступления).
- **Golden:** `crime_confession`, `crime_wanted_no_work`, `crime_stocks_narration`, `crime_escort_to_captain`, `crime_release_after_check`, `crime_hide_body_no_promise`, `crime_threat_let_go`, `crime_wanted_no_room`; плейтест `consequences`.

---

## Память и замысел

### Память мастера и флаги мира

- **Заметка:** `note {text}` — короткая фраза по-русски в журнал («Айра поклялась служить человеку в капюшоне»); вернётся в `scene.notes`.
- **Флаг:** `flag {flag}` — только флаг, который знает пакет (выборы заданий, тайны); свой — нельзя, для памяти — `note`.
- **Golden:** `memory_is_a_note`.

### Замысел, которого нет в движке

- **Пайплайн:** собрать из понятий движка (проверки, эффекты, вещи, отношение, память, задания, тайны); высокая цель — путь из шагов; нечего собрать — отказ в мире и `missing_concept` («стать матерью драконов») — заметка автору.
- **Правила:** тема `goals`; реестр понятий — [concepts.md](../design/concepts.md).
- **Golden:** `compose_tame_a_cub`, `missing_concept_dragons`, `high_goal_is_a_path`.

---

## Ходы, которые решил движок

Мастер только рассказывает готовый итог; эффектов не добавляет (короткий путь, [router.SHORT_KINDS](../../llm_server/src/llm_server/router.py)).

| `kind` | Откуда | Что в `input` |
|---|---|---|
| `enter` | переход, начало игры, загрузка | строки пути; новая комната — с обстановкой (полный путь). Повторный вход в комнату, описанную сегодня, без событий по пути — строка движка «Снова …» без хода мастера (v0.7.22.20) |
| `resume` | конец разговора, уход NPC | — |
| `rest` | кнопки отдыха | восстановлено и прошедшее время |
| `wait` | «Ждать» | время и что случилось |
| `deal`, `haggle` | панель сделки, кнопка торга | факты сделки или торга |
| `quest` | шаг или конец задания кнопкой | что произошло и награда |
| `ability` | заклинание, умение, вещь из листа | что движок применил |
| `trap` | обезвредить, обойти ловушку | итог |
| `theft` | окно карманов | украдено или замечено |
| `law` | кнопки задержания | итог |
| `goal` | цель в листе | текст цели — мастер оценивает её `goal_assess` (полный путь) |
| `combat_start`, `combat_round`, `death` | бой движка | строки раунда |
| `downed` | 0 HP вне боя | цена: что потеряно, сколько прошло |

Тексты этих ходов — [turn.md.j2](../../llm_server/src/llm_server/prompts/turn.md.j2).
