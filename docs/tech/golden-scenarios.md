# «Золотые» ЛЛМ-сценарии

**Статус:** формат и 20 сценариев готовы (M0). Прогон на модели — `llm_server/evals` в v0.4.2 ([roadmap](../production/roadmap.md)).
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
    category: checks          # checks | hidden | injection | budget | effects | modes | limits | style | rules | items
    extends: tavern           # база; поля сценария глубоко сливаются с ней
    mode / kind / settings    # переопределения
    input: "…"                # ввод игрока; null для kind = enter | resume
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
| `check.contest_npc`, `check.contest_skill_in` | состязание с этим NPC и навыком |
| `max_checks` | не больше N проверок за ход |
| `effects.required_kinds_any` / `forbidden_kinds` | среди предложенных эффектов есть хотя бы один из / нет ни одного из |
| `effects.max_count`, `effects.coins_max` | число эффектов, сумма монет |
| `effects.damage_severity_in`, `effects.forbidden_fields` | ступень урона из списка; в эффекте нет полей (например, кубиков) |
| `next_mode` | `null` — смены режима нет; `{mode, npc_id?}` — предложена эта смена |
| `narration.must_match` / `must_not_match` | регулярные выражения по тексту |
| `narration.max_sentences` | не больше N предложений |
| `options.min` / `max` | число вариантов действий |
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
| Стиль и контент | `gender_agreement_female`, `content_veil_respected`, `dm_style_dry` |
| Справка | `rules_question_ac` |
| Предметы | `item_dedupe` |

Имена мест и NPC (Серое Устье, «Хромой Ворон», Горм, Ведда) — заглушки до стартовой вселенной ([ADR-0010](adr/0010-game-decisions-worlds-tone-combat-death.md)).

## Как будет запускаться (v0.4.2)

1. Раннер в `llm_server/evals` собирает `turn.request` из базы и сценария и подставляет mock-движок с ответами из `engine`.
2. Прогоняет реальную модель (вручную, не в CI). Записывает результат, `usage` и время.
3. Автомат проверяет `expect`, ЛЛМ-судья (или автор) оценивает `rubric`.
4. Отчёт: таблица «сценарий × модель/промпт» — пройдено, цена, задержка.

Файл переедет в `llm_server/evals/` вместе с раннером, формат не меняется.
