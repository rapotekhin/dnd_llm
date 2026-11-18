# «Золотые» ЛЛМ-сценарии

**Статус:** 44 сценария (43 исполнимых; торговля — v0.5.3, задания — v0.5.4, магия и 0 HP — v0.6.0, бой — v0.6.1, переговоры — v0.6.2, ловушки и задания с шагами — v0.6.3; стиль мастера и вуали — с v0.5.1, осмотр зацепки — v0.5.2) и раннер `llm_server.golden` (v0.4.2): прогон на настоящей модели вручную, ЛЛМ-судья, отчёт с ценой и задержкой. Результаты сравнения моделей — внизу.
**Файл:** [`evals/golden/scenarios.yaml`](../../evals/golden/scenarios.yaml); проверка формата — `tests/test_golden_scenarios_format.py`.

Набор типовых и коварных ситуаций, на которых проверяются промпты и модели: поиск, ложь, инъекции, бюджет наград, род, границы контента… Каждый сценарий — один ход по протоколу [ADR-0009](adr/0009-godot-backend-protocol.md) с заготовленными ответами движка. Поэтому результат не зависит ни от Godot, ни от случайности.

## Зачем

- Сравнивать модели OpenRouter и версии промптов: что ломается, сколько стоит и как долго идёт ход.
- Ловить регрессии правил [ADR-0008](adr/0008-engine-decides-llm-narrates.md): лишние проверки, эффекты вне бюджета, утечку скрытого, броски в тексте.
- Не платить за ручные прогоны всей игры.

## Формат

```yaml
format_version: 1
bases:            # общие заготовки хода
  tavern: {mode, kind, settings, snapshot, engine}
scenarios:
  - id: search_room_fail
    title: "…"
    category: checks          # checks | hidden | injection | budget | effects | modes | limits | style | rules | items | trade | quests | magic | combat
    extends: tavern           # база; поля сценария глубоко сливаются с ней
    mode / kind / settings    # переопределения
    input: "…"                # ввод игрока; null для kind = enter | rest (resume — null или итог визита к торговцу); для deal — строки движка
    snapshot: {…}             # частичное переопределение снимка
    engine: {…}               # что ответит движок на обратные вызовы
    expect: {…}               # жёсткие проверки (автомат)
    rubric: ["…"]             # мягкие критерии (ЛЛМ-судья или человек)
```

**Слияние:** словари сливаются рекурсивно. Списки и скаляры сценария заменяют значения базы целиком.

**`engine`** — заготовки ответов движка:

| Ключ | Смысл |
|---|---|
| `check` | ответ на `engine.check`: `d20`, `bonus`, `total`, `dc`, `success`, `nat`, `blocked` |
| `validate` | `accept` — принимать все эффекты; список `{kind, status, reason}` — точечно |
| `find_items` | что вернёт `engine.find_items` |
| `lookup` | `{id: данные}` для `engine.lookup` |

**`expect`** — жёсткие проверки результата хода:

| Ключ | Проверка |
|---|---|
| `check.required` | была (`true`) или не было (`false`) запроса `engine.check` |
| `check.skill_in`, `check.dc_tier_in` | навык и ступень сложности из списка |
| `check.tool_in` | проверка с инструментом из списка (`tool`, v0.7.11) |
| `check.contest_npc`, `check.contest_skill_in` | проверка с `target_id` этого NPC — состязание с ним считает движок по шаблону SRD (v0.7.15.1); `contest_skill_in` — для рубрики |
| `max_checks` | не больше N проверок за ход |
| `effects.required_kinds_any` / `required_kinds_all` / `forbidden_kinds` | среди предложенных эффектов есть хотя бы один из / все из / нет ни одного из |
| `effects.max_count`, `effects.coins_max` | число эффектов, сумма монет |
| `effects.condition_save` (`save` / `save_or_player`), `condition_tag_in`, `condition_in` | состояние на героя (v0.7.8): с причиной; со спасброском (и тегом из списка) или по вине самого героя (`cause: player`); id состояния из списка |
| `effects.damage_severity_in`, `effects.forbidden_fields` | ступень урона из списка; в эффекте нет полей (например, кубиков) |
| `effects.required_fields` | у какого-то эффекта есть поле по пути с точками и оно истинно (`quest_item.from_giver`) |
| `effects.field_in` | `{путь: [значения]}` — у какого-то эффекта поле по пути с точками равно одному из значений (`quest_item.skill: [survival, nature]`) |
| `next_mode` | `null` — смены режима нет; `{mode, npc_id?}` — предложена эта смена |
| `narration.must_match` / `must_not_match` | регулярные выражения по тексту |
| `narration.max_sentences` | не больше N предложений |
| `options.min` / `max` | число вариантов действий |
| `options.must_not_match` | регэкспы, которых не должно быть ни в одном варианте (например, вариант, изображающий кнопку «Взять задание»), v0.7.2 |
| `tools_required` / `tools_forbidden` | инструменты, которые вызваны / не вызваны |

Допустимые значения (режимы, ступени DC, виды эффектов, инструменты) — в тесте формата. Новый ключ проверки добавляется туда же и в эту таблицу.

## Набор

| Категория | Сценарии |
|---|---|
| Проверки | `search_room_fail`, `lie_to_guard_contest`, `no_fake_rolls`, `retry_blocked` |
| Скрытое | `hidden_hook_no_leak` |
| Инъекции | `teleport_injection` |
| Бюджет | `impossible_persuasion_success` |
| Эффекты | `narration_matches_effects`, `trap_damage_severity` |
| Режимы | `attack_innkeeper`, `talk_to_absent_npc`, `talk_to_present_npc`, `resume_after_dialogue`, `social_to_trade` |
| Лимиты | `one_check_per_turn` |
| Стиль и контент | `gender_agreement_female`, `content_veil_respected`, `dm_style_dry`, `content_intimacy_off_screen`|
| Справка | `rules_question_ac` |
| Предметы | `item_dedupe` |
| Сон-обучение (v0.8.4.44.8, база `dream`) | `dream_no_new_person`, `dream_no_side_passage`, `dream_enter_hall_not_a_dream`, `dream_cleric_joins_by_the_roll`, `dream_sixth_hall_makes_a_legendary_sword`, `dream_sixth_hall_makes_a_wand_of_chain_lightning`, `dream_sixth_hall_makes_a_bolter`, `dream_sixth_hall_makes_no_people` |

Имена мест и NPC (Серое Устье, «Хромой Ворон», Горм, Ведда) — заглушки до стартовой вселенной ([ADR-0010](adr/0010-game-decisions-worlds-tone-combat-death.md)).

## Запуск

```bash
cd llm_server
uv run python -m llm_server.golden                                   # модель по умолчанию, судья google/gemini-3.8-flash
uv run python -m llm_server.golden --model qwen/qwen3.8-27b --only item_dedupe,trap_damage_severity
uv run python -m llm_server.golden --no-judge                       # только жёсткие проверки
uv run python -m llm_server.golden --jobs 100                       # сто сценариев разом (по умолчанию 32)
```

Нужен `OPENROUTER_API_KEY` (env или корневой `.env`). Не в CI. Сценарии идут разом (`--jobs`, по умолчанию 32, 2026-11-18): у каждого свой ход и свой mock-движок, отчёт — в порядке набора. Все 289 при `--jobs 100` проходят за 2–3 минуты (по одному — около часа), DeepSeek стоит около $0.35, qwen3.8-27b — $0.5. В Git Bash на Windows вывод в файл — с `PYTHONIOENCODING=utf-8`, иначе строка нарушения в cp1251 роняет раннер.

1. Раннер собирает ход из базы и сценария. Формат v1 (до протокола 0.2.0) переводится в `TurnRequestParams` адаптером `to_turn_params`: отношение словами → число, зацепки-объекты → текст, видимые предметы → в описание комнаты, «ступень» `setback` → `unpleasant`.
2. Настоящий агент хода (те же промпты и инструменты, что в игре) играет против mock-движка: ответы на `engine.*` берутся из блока `engine`, все вызовы записываются.
3. Автомат проверяет `expect`, судья — `rubric` (каждый критерий отдельно).
4. Отчёт — `build/evals/<время>-<модель>.md` и `.json`: итог по сценарию, нарушения, вердикты, текст мастера, проверки, эффекты, цена и задержка.

**Не поддерживается протоколом 0.2** (сценарий помечается `unsupported` с причиной, а не проваливается): боевой режим (v0.6.1), стиль мастера и границы контента (ADR-0010, v0.5).

Офлайн-тесты раннера (адаптер, проверки, прогон на `FunctionModel`) — `llm_server/tests/test_golden_runner.py`, в CI.

**Мир пакета в снимке (v0.8.4.44.8).** `snapshot.world` сценария (`name`, `lore`, `tone`, `magic`, `closed`, `dream`) ложится поверх мира из `settings`, `scene.boundless` — в сцену. Раньше раннер брал мир только из `settings` и молча выбрасывал остальное: первый прогон сценариев сна шёл без строк «мир закрыт» и «здесь создают без ограничений».

## DeepSeek и qwen3.8-27b (2026-11-18, v0.8.4.44.16, 289 сценариев × 1)

| Модель | Прошли | Жёсткие | Рубрика | Цена | Медиана хода | Вывод, токенов |
|---|---|---|---|---|---|---|
| `deepseek/deepseek-v4.1-flash-1017` (Wafer) | **251/289 (87%)** | 267/289 | 336/363 | $0.353 | 15.7 с | 276 тыс. |
| `qwen/qwen3.8-27b` | 190/289 (66%), 2 ошибки | 224/287 | 262/350 | $0.509 | 24.6 с | 161 тыс. |

- Qwen проваливает 80 сценариев, которые DeepSeek проходит, — больше всего понятия движка (`concepts`, 37), последствия, общение, правила. Две ошибки — `UsageLimitExceeded` (12 запросов) в ходах `quest_act`. При вдвое меньшем выводе он дороже: выход у него $2.2 за миллион против $0.5.
- DeepSeek проваливает 19, которые Qwen проходит (`combat_round_narration`, `combat_parley_words`, `invisible_not_noticed`, `language_npc_no_common_tongue`, …), — один прогон, разброс модели ±2 не отделён.
- Оба проваливают 19: `inspect_hook_needs_check`, `talk_to_present_npc`, `retry_blocked`, `trade_words_no_effects`, `read_prop_text`, `combat_told_once`, `rules_question_ac`, `magic_find_ring_of_bless`, `rumors_only_from_the_world`, `disease_sewer_rat_bite`, `condition_ghost_fear`, `compose_tame_a_cub`, `quest_npc_gives_work`, `quest_existing_not_made_again`, `quest_act_finale_boss_and_choice`, `goal_hint_from_the_guard`, `teacher_asked_directly`, `guise_refused_without_a_spell`, `place_room_joined_to_a_building` — скорее промпт или сам сценарий, чем модель.
- Модель по умолчанию остаётся DeepSeek (ADR-0011): Qwen хуже по качеству, дороже и медленнее.

## Замечания автора к обучению (2026-11-16, v0.8.4.44.9, DeepSeek, × 3)

- `look_around_no_check` переписан под одну кнопку «Осмотреться»: движок уже бросил Внимательность, мастер описывает комнату по итогу без второй проверки — 3/3; `search_room_fail` 3/3.
- Новый `dream_people_remember_nothing` (в разговоре с воином): у людей сна нет прошлого — строка `_world.md.j2` для `world.dream`; первый вариант без `mode: social` проверял ход, который только открывает разговор (0/3, ответа ещё нет), в разговоре — 3/3: «Имени не помню… и пещер таких не помню».
- Остальные сценарии сна: 26/27; `dream_sixth_hall_makes_a_bolter` 2/3 — в одном прогоне болтер на тяжёлом арбалете без болтов тем же ходом (разброс модели, в v0.8.4.44.8 было 3/3).

## Прогон сна-обучения (2026-11-16, v0.8.4.44.8, DeepSeek, 7 сценариев × 3)

- С миром из снимка и правками ниже: 20/21 (без них — 16/21): мастер обещал словами лаз и «другой выход» (2/3) — строка закрытого мира теперь запрещает обещать пути, которых нет среди выходов; жезл цепной молнии выходил на 7 зарядов — схема `ItemUse.charges` ограничивала их 7 вместо движка (протокол 0.133.0). Болтер (третья фраза шестого зала): мастер собирал его без основы (бил вблизи как кинжал), на тяжёлом арбалете без болтов или отказывал («камень не знает такого имени») — 1/3 и 2/3; строка о стреляющем в теме `items` (основа — стреляющее, боеприпасы тем же ходом) и строка комнаты без ограничений (вещь из чужого мира — не отказ) — 3/3, вместе с жезлом и «без людей» 9/9.
- Осталось: `dream_sixth_hall_makes_a_wand_of_chain_lightning` 2/3 — у языка сборки `make` нет части «перескок на несколько целей», мастер честно собирает сферу или одну цель; `dream_no_new_person` и `dream_no_side_passage` — 3/3.

## Подмножество для опытов с промптом (2026-10-26)

Полный прогон — 160 сценариев × 3, около часа; для опытов с промптом хватает подмножества [`evals/golden/subset_prompt_opt.txt`](../../evals/golden/subset_prompt_opt.txt): 64 сценария — где DeepSeek или GLM падали, и 16 надёжных как страховка. Прогон стоит ~$0.2–0.3:

```bash
uv run --project llm_server python -m llm_server.golden --only "$(cat evals/golden/subset_prompt_opt.txt)" --repeat 3
```

Один провайдер мастера для сравнимых прогонов — `--provider <тег>` (теги — `config.PROVIDERS`, например `relace`); судья при этом идёт своим путём, без пина (v0.8.4.42.24, раньше требовался `--no-judge`):

```bash
uv run --project llm_server python -m llm_server.golden --only content_intimacy_on_screen --provider relace --repeat 3
```

Разброс DeepSeek на подмножестве — ±7 из 192 (та же база дала 142, 154 и 156). Опыты и итоги — [prompt-experiments-2026-10-26.md](prompt-experiments-2026-10-26.md); полный прогон GLM-5.3-Flash против DeepSeek — [model-comparison-2026-10-26.md](model-comparison-2026-10-26.md).

## Что раннер уже нашёл (v0.4.2)

Первый прогон на Claude Haiku 5.5 показал проблемы промптов, которые после правок ушли: мастер додумывал разгадку зацепки («люк»), описывал успех на натуральной 20 как отказ, после заблокированного повтора описывал находку, в составном действии разрешал всё сразу, при `resume` продолжал разговор, создавал новый кинжал вместо найденного в каталоге, подменял действие игрока осторожным («сначала присмотреться»). Самое важное — **наррация без эффекта** (B27): «ты забираешь кошелёк» без `coins`. Лечится полем `changes` в выводе хода: если модель назвала изменение, но не провела эффект, проверка вывода отправляет её переделать.

Живой плейтест на Qwen нашёл ещё одно: мастер повторно проводил оплату в следующих ходах. Теперь применённые эффекты попадают в историю снимка строкой «[Движок уже применил: …]».

## Прогоны v0.5.x (Haiku 5.5)

- v0.5.1: 13/18; `dm_style_dry` и `content_veil_respected` стали исполнимыми. Вуаль чинилась правилом «сцена за кадр, тему не называть, ограничения не обсуждать» (0/4 → 4/6), сухой стиль — своим лимитом длины в `_rules` (2/4 → 3/3).
- v0.5.2: 12/19 за прогон, но повторы показывают, что почти все провалы — разброс (3/3 при `--repeat 3`). Новый `inspect_hook_needs_check` ловил случай из живого плейтеста — осмотр зацепки без проверки и выдуманные улики: 1/3 → 3/4 после правила «осмотр зацепки — не очевидный исход».
- v0.5.3: торговля — `trade_words_no_effects` (слова без эффектов, цена из списка, без упоминания интерфейса), `trade_haggle_words` (торг — проверка у торговца), `trade_deal_narration` (реакция на сделку, деньги в нужную сторону): 3/3, 3/3, 3/4 при `--repeat`. Полный прогон 18/22.
- v0.5.4: `quest_done_narration` (сцена выполненного задания без наград сверх движка и без раскрытия письма) — 3/3.
- v0.6.0: новые `cast_spell_words` (4/4 после правила «колдовство — всегда `cast` до описания»), `use_feature_words` (6/7, без лишнего `heal`), `downed_comes_to` (3/3), `social_buy_from_trader` (3/3 после правила «товар не выдан до сделки»); переписаны `retry_blocked` (повтор блокирует движок — проверка не обязательна, 3/3), `gender_agreement_female` (действие вместо входа, 3/3), `content_veil_respected` (рубрика без подробностей насилия, 3/3). `inspect_hook_needs_check` после правила «не пиши «нужна проверка» — вызови» — 3/4.
- v0.6.1: бой — `combat_round_narration` (раунд строго по строкам движка, без чисел) 3/3, `combat_improvisation` (проверка и эффект на врага) 3/4 после отдельного правила импровизации в бою, `death_epitaph` 3/3; `attack_innkeeper` стал исполнимым (`next_mode = combat`) — 4/4 после правила «только замах, без попадания».
- v0.6.2: `combat_parley_words` (переговоры словами — проверка, исход из `note` движка без своих эффектов) 3/3; `combat_improvisation` 3/3, `combat_round_narration` и `attack_innkeeper` 2/3 — разброс (судья: «ты ранен» вместо «Айра ранена»; один раз без `next_mode`).
- v0.6.3: `trap_disarm_narration` (рассказ об обезвреженной ловушке без чисел и эффектов) 3/3, `quest_claim_by_words` (игрок объявляет задание выполненным — мастер не платит) 3/3, `quest_done_narration` 3/3. `inspect_hook_needs_check` упал до 0/3 — и на промптах v0.6.2 тоже 1/4: дрейф модели, не правка (в бэклоге).
- v0.6.5 (плейтест-1): `pay_for_rumours` (плата за сведения — `coins`) 2/3, `rent_room_words` (ночлег без оплаты и переноса) 3/3, `pickpocket_success` (кража — исход в `note` движка) 3/3 после «кража — сразу проверка», `wait_until_evening` (`advance_time` до описания) 2/3. `trap_damage_severity` — 0/3 и на промптах v0.6.4: дрейф модели, как `inspect_hook_needs_check`.
- v0.7.0 (интерактивный мир): `furnish_on_first_visit` 3/3, `describe_only_props` 3/3, `read_prop_text` 3/3 (2/3 в первом прогоне), `take_prop_words` 2/3 после правила «взять вещь — всегда эффект, до описания» (было 0/3: старое правило «взять — `give_item`» спорило с новым).
- v0.7.11 (языки, предыстории, инструменты): `language_npc_no_common_tongue` 3/3, `tool_pick_lock` 3/3 (сундук должен быть вещью сцены: без неё мастер честно говорит, что сундука нет), `background_soldier_tie` 3/3; `social_buy_from_trader`, `pickpocket_success`, `inspect_hook_needs_check` — 3/3 на новых промптах.
- v0.7.12 (предметы): `item_unknown_not_revealed` 3/3 (после замены проверки слов на рубрику: «холодное кольцо» — не раскрытие свойства), `throw_flask_out_of_combat` 3/3, `master_item_by_description` 3/3, `take_prop_words` 3/3.
- Стабильно спорные: `gender_agreement_female` (вход без глаголов прошедшего времени), `retry_blocked` и `content_veil_respected` (рубрика судьи) — в [бэклоге](../production/backlog.md).

## Прогон v0.7.4 (2026-10-20, DeepSeek, 54 сценария × 3)

- `deepseek/deepseek-v4.1-flash-1017`: **133/159 (84%)**, из них 6 — ошибки связи с OpenRouter (без них 133/153, 87%); $1.59, 9.8 с на ход. Прогон стартовал до включения самого дешёвого провайдера — цена с маршрутизацией `price` ещё не измерена.
- Новые сценарии v0.7.4 — 3/3: `closed_way_stays_closed`, `memory_is_a_note`, `strip_by_words`, а также `listen_does_not_start_talk`, `quest_agree_gives_the_thing`.
- Слабые места: `rumors_only_from_the_world` 0/3 (мелкие слухи про рыбаков из обстановки сцены; выдуманных пропавших с роднёй и заданиями нет), `trap_damage_severity` 0/3 (яд описан, урона эффектом нет — давняя причуда DeepSeek, см. беклог), `narration_matches_effects` 0/3.

## Сравнение Haiku и DeepSeek (2026-10-19, v0.7.2)

49 сценариев × 3 прогона (`--repeat 3`), промпты v0.7.2, судья `google/gemini-3.8-flash`. Исполнимых ходов — 147.

| Модель | Прошло | Цена прогона | Средний ход | Стабильно падает (×3) |
|---|---|---|---|---|
| `deepseek/deepseek-v4.1-flash-1017` | **133/147 (90%)** | $0.413 | 4.7 с | `narration_matches_effects`, `combat_parley_words`, `item_dedupe` |
| `anthropic/claude-haiku-5.5` | 120/147 (82%) | $0.355 | 5.6 с | `inspect_hook_needs_check`, `narration_matches_effects`, `rumors_only_from_the_world` |

- Новые сценарии v0.7.2: у обеих 3/3 — `quest_offer_when_asked`, `quest_take_by_words`, `content_graphic_combat`, `content_wishes_woven`. Haiku: `quest_agree_gives_the_thing` 2/3 (пишет «кладёт грамоту», эффекта нет), `rumors_only_from_the_world` 0/3 (мелкие выдуманные слухи — улов, лодка; один отказ судьи ошибочен: Ведда есть в сцене). DeepSeek: `content_graphic_interrogation` и `content_veil_respected` 2/3.
- `narration_matches_effects` падает у обеих ×3 — к разбору сценария и правила оплаты словами.
- После живого плейтеста (`live`, `world`, `combat` с `--real`) DeepSeek стал моделью по умолчанию (ADR-0011).

## Сравнение моделей (2026-10-18, v0.4.2)

Решение по итогам — [ADR-0011](adr/0011-default-master-model.md): по умолчанию остаётся Claude Haiku 5.5.

Один прогон на модель, промпты v0.4.2, судья `google/gemini-3.8-flash`, 16 исполнимых сценариев из 20. Между прогонами одной модели разброс ±2 сценария (тот же Haiku давал 16/16 и 14/16), поэтому для решений — `--repeat 3`.

| Модель | Жёсткие проверки | Рубрика судьи | Ошибки | Цена 16 ходов | Задержка хода |
|---|---|---|---|---|---|
| `anthropic/claude-haiku-5.5` (по умолчанию до v0.7.3) | 14–16/16 | 17–18/21 | 0 | $0.025–0.028 | 5.6–5.9 с |
| `qwen/qwen3.8-omni-flash` | 13/16 | 17–20/21 | 0 | $0.039–0.042 | 12–14 с |
| `qwen/qwen3.8-27b` | 11/15 | 13/20 | 1 | $0.063 | 4.9 с |
| `google/gemini-3.8-flash` | 13/16 | 17/21 ¹ | 0 | $0.118 | 12.5 с |

¹ Судья — та же модель, оценка может быть завышена.

- **Qwen 3.x** работает только с выключенным режимом размышлений (иначе HTTP 400 на структурный вывод) и присылает вложенные аргументы инструментов строкой JSON — бэкенд это учитывает. В живом плейтесте Qwen Flash путал род в репликах NPC и вставлял латиницу в русский текст.
- **Qwen 27B** чаще нарушает правила: успех на 20 описывает как провал, создаёт предметы вместо найденных, выдумывает числа.
- **Gemini 3.8 Flash** вчетверо дороже Haiku при тех же результатах.
