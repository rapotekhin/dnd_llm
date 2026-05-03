---
name: docs_lookup
description: Use this skill when the user asks conceptual questions about the Between the Rolls project — architecture, design decisions, how a system works, why something is built a certain way, where to find information about a feature, what's planned vs. done. Trigger phrases include "как устроено", "почему так", "где описано", "что про", "как работает", "архитектура", "дизайн", "столпы", "роадмап", "техдолг", "ADR", or any question whose answer likely lives in /docs. Also trigger before answering questions about gameplay systems (exploration, social, trade, combat, character creation, leveling), narrative content, or LLM integration — these have dedicated docs that should be consulted first instead of guessing from code.
---

# Documentation Lookup — Between the Rolls

Цель: давать ответы на вопросы о проекте, **сначала проверив документацию**, а не код.

## Когда срабатывать

Срабатывай **до** того, как лезть в код, если вопрос про:

- Концепцию проекта, vision, цели, ЦА
- Архитектурные решения (почему так, не иначе)
- Игровые системы (как работает exploration / social / trade / combat / создание персонажа / level up)
- Геймплейный поток, навигацию между экранами
- Лор, мир, NPC, квесты, стиль ГМ
- LLM-интеграцию, промпты, инструменты, агенты
- Модели данных, классы, связи
- Что в роадмапе, что в техдолге, что не сделано

## Карта документации

```
docs/
├── README.md                                 ← точка входа, навигация
│
├── vision/                                   ← Why
│   ├── pitch.md                              — концепция, USP, ЦА
│   └── pillars.md                            — 5 нерушимых принципов
│
├── design/                                   ← What
│   ├── overview.md                           — игровая петля
│   ├── art-style.md                          — арт (черновик)
│   ├── systems/
│   │   ├── exploration.md                    — главный режим
│   │   ├── social.md                         — диалоги
│   │   ├── trade.md                          — торговля
│   │   ├── combat.md                         — план (не реализован)
│   │   ├── character-creation.md             — создание персонажа
│   │   └── leveling.md                       — поднятие уровня
│   └── ux/
│       ├── screens-flow.md                   — граф переходов между экранами
│       └── navigation.md                     — UI-конвенции
│
├── narrative/                                ← World
│   ├── world.md                              — сеттинг, локации
│   ├── npcs.md                               — NPC, архетипы
│   ├── quests.md                             — квестовая система
│   └── dm-style.md                           — стиль ГМ
│
├── tech/                                     ← How
│   ├── architecture.md                       — общая схема, слои
│   ├── llm-integration.md                    — агенты, tools, промпты, экономия токенов
│   ├── data-models.md                        — классы, MainGameState
│   └── adr/                                  — Architecture Decision Records
│       ├── 0001-llm-as-gm-not-engine.md      — главный принцип
│       ├── 0002-pickle-saves.md              — почему Pickle
│       ├── 0003-pydantic-ai-over-langchain.md
│       ├── 0004-pygame-prototype.md
│       └── 0005-langchain-and-streamlit-removal.md
│
└── production/                               ← When
    ├── roadmap.md                            — этапы M1–M6
    └── backlog.md                            — техдолг + открытые вопросы
```

## Алгоритм работы

1. **Распознай тему вопроса** и сопоставь с разделом:

   | Вопрос | Раздел |
   |---|---|
   | «Зачем эта игра?» / «Что за USP?» | `vision/pitch.md` |
   | «Какие принципы нельзя нарушать?» | `vision/pillars.md` |
   | «Как работает exploration / social / trade / combat?» | `design/systems/<тема>.md` |
   | «Какие экраны и как они связаны?» | `design/ux/screens-flow.md` |
   | «Какой сеттинг / лор / тон?» | `narrative/world.md`, `dm-style.md` |
   | «Как устроена архитектура?» | `tech/architecture.md` |
   | «Как ЛЛМ интегрирован? Какие tools?» | `tech/llm-integration.md` |
   | «Почему Pickle / LangChain / Pygame?» | `tech/adr/<NNNN>-*.md` |
   | «Что в планах / что в работе?» | `production/roadmap.md`, `backlog.md` |

2. **Прочитай нужный файл** через Read tool. Если несколько — читай параллельно.

3. **Ответь по содержимому документа** + укажи путь к источнику в виде кликабельной ссылки markdown.

4. **Если темы нет в доках:**
   - Скажи это явно
   - Перейди к коду как fallback
   - Предложи добавить раздел в доку (через скилл `docs_updater`)

## Принципы ответов

- **Дока — источник истины для намерений и решений.** Код — для текущей реализации. Если они расходятся — упомяни оба.
- **Не пересказывай дословно** — отвечай на конкретный вопрос пользователя, ссылаясь на документ.
- **Указывай путь к источнику** как `[design/systems/exploration.md](docs/design/systems/exploration.md)`.
- **Замечай устаревание** — если документ говорит о состоянии, которое не совпадает с текущим кодом, упомяни и предложи `docs_updater`.

## Якоря-подсказки (быстрая навигация)

- **«Главный принцип ЛЛМ ≠ движок»** → [tech/adr/0001](docs/tech/adr/0001-llm-as-gm-not-engine.md) и [vision/pillars.md](docs/vision/pillars.md) §1
- **Поток фоновых тредов** → [tech/architecture.md](docs/tech/architecture.md) §«Фоновые потоки»
- **Контракт UI ↔ gameplay-thread** → [design/systems/exploration.md](docs/design/systems/exploration.md), сообщения `scene/actions/narration/transition`
- **Что делать с галлюцинациями ЛЛМ** → [tech/llm-integration.md](docs/tech/llm-integration.md) §«Известные проблемы»
- **Открытые вопросы** → [production/backlog.md](docs/production/backlog.md) §«Открытые вопросы»

## Что НЕ делать

- ❌ Не читай весь `/docs` целиком при каждом вопросе — это бессмысленно дорого
- ❌ Не цитируй большие куски документов — отвечай по содержимому, ссылайся
- ❌ Не угадывай ответ из кода, если есть документ на эту тему — сначала дока
- ❌ Не путай `vision/` (намерения) и текущее состояние из кода
