# Документация Between the Rolls

Карта документации проекта.

## Структура

```
/docs
├── /vision        — Why: концепция и принципы
├── /design        — What: геймдизайн и UX
├── /narrative     — World: лор, тон, контент
├── /tech          — How: архитектура и решения
└── /production    — When: роадмап и бэклог
```

## С чего начать

| Если ты... | Открой |
|---|---|
| **Впервые видишь проект** | [vision/pitch.md](vision/pitch.md), [vision/pillars.md](vision/pillars.md) |
| **Хочешь понять, во что играть** | [design/overview.md](design/overview.md) |
| **Программист, лезешь в Godot-клиент** | [tech/godot-client.md](tech/godot-client.md) |
| **Работаешь с мастером (бэкенд, промпты)** | [tech/master-tools.md](tech/master-tools.md) — все инструменты и эффекты мастера, [tech/master-scenarios.md](tech/master-scenarios.md) — что мастер умеет по сценариям, [tech/llm-integration.md](tech/llm-integration.md), [../llm_server/README.md](../llm_server/README.md), [ADR-0009 — протокол](tech/adr/0009-godot-backend-protocol.md), [tech/golden-scenarios.md](tech/golden-scenarios.md) |
| **Хочешь добавить контент (мир, NPC, задания)** | [tech/godot-client.md → «Пакеты миров»](tech/godot-client.md#пакеты-миров), пакет `game/data/worlds/frontier/` |
| **Планируешь, что делать дальше** | [production/roadmap.md](production/roadmap.md), [production/backlog.md](production/backlog.md) |
| **Разворачиваешь сервер мастера** | [tech/deploy.md](tech/deploy.md) |
| **Видишь странное архитектурное решение** | [tech/adr/](tech/adr/) |

Ключевые решения: [ADR-0007](tech/adr/0007-godot-client-python-llm-backend.md) (Godot + Python-бэкенд), [ADR-0008](tech/adr/0008-engine-decides-llm-narrates.md) (движок решает, ЛЛМ рассказывает), [ADR-0009](tech/adr/0009-godot-backend-protocol.md) (протокол), [ADR-0010](tech/adr/0010-game-decisions-worlds-tone-combat-death.md) (миры, тон, бой, смерть), [ADR-0011](tech/adr/0011-default-master-model.md) (модель мастера).

## Исторические документы

Описывают pygame-прототип (удалён в v0.5.4, [паритет](production/parity-v031.md)): [tech/architecture.md](tech/architecture.md), [production/review-2026-10.md](production/review-2026-10.md). Решения в них и в ADR-0001…0006 по-прежнему объясняют, откуда пришли нынешние правила. Остальные страницы переписаны под Godot-версию: мастер — [tech/llm-integration.md](tech/llm-integration.md), данные и сейвы — [tech/data-models.md](tech/data-models.md), мир Марки — [narrative/world.md](narrative/world.md), [narrative/npcs.md](narrative/npcs.md), [narrative/quests.md](narrative/quests.md).

## Принципы документации

- **Живая, а не идеальная** — лучше короткая актуальная страница, чем длинная устаревшая
- **Решения важнее результатов** — *почему* так, а не *что* так (см. ADR)
- **Код — источник истины для механики** — дока описывает намерения и контекст, а не повторяет код
- **RU primary** — пишем по-русски, английский для технических терминов

## Не дублируем здесь

- Установку и запуск — это в [README.md](../README.md) и [AGENTS.md](../AGENTS.md)
- Историю изменений — это в `git log` и `RELEASE_NOTES.md`
