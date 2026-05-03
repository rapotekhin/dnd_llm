# Документация Between the Rolls

Карта документации проекта.

## Структура

```
/docs
├── /vision        — Why: концепция и принципы
├── /design        — What: геймдизайн и UX
├── /narrative     — World: лор, тон, контент
├── /tech          — How: архитектура и решения
└── /production    — When: роадмап и техдолг
```

## С чего начать

| Если ты... | Открой |
|---|---|
| **Впервые видишь проект** | [vision/pitch.md](vision/pitch.md) |
| **Хочешь понять, во что играть** | [design/overview.md](design/overview.md) |
| **Программист, лезешь в код** | [tech/architecture.md](tech/architecture.md) |
| **Работаешь с ЛЛМ-частью** | [tech/llm-integration.md](tech/llm-integration.md) |
| **Хочешь добавить контент (NPC/локацию)** | [narrative/world.md](narrative/world.md) |
| **Планируешь, что делать дальше** | [production/roadmap.md](production/roadmap.md) |
| **Запускаешь автотесты разработчика** | [README.md](../README.md) («Тесты»), [tech/architecture.md](tech/architecture.md) §«Автотесты» |
| **Видишь странное архитектурное решение** | [tech/adr/](tech/adr/) |

## Принципы документации

- **Живая, а не идеальная** — лучше короткая актуальная страница, чем длинная устаревшая
- **Решения важнее результатов** — *почему* так, а не *что* так (см. ADR)
- **Код — источник истины для механики** — дока описывает намерения и контекст, а не повторяет код
- **RU primary** — пишем по-русски, английский для технических терминов

## Не дублируем здесь

- Установку и запуск — это в [README.md](../README.md) и [CLAUDE.md](../CLAUDE.md)
- Историю изменений — это в `git log` и `RELEASE_NOTES.md`
- API внешних библиотек D&D — это в репозиториях `dnd-5e-core` и `DnD-5th-Edition-API`
