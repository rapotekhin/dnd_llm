# Architecture Decision Records

ADR — это короткая запись о **значимом архитектурном решении**: что было решено, почему, какие альтернативы рассматривались.

## Зачем

Через год никто (включая автора) не помнит, **почему** выбран Pickle, а не SQLite. ADR отвечает на этот вопрос.

## Формат

```markdown
# ADR-NNNN: Заголовок

**Дата:** YYYY-MM-DD  
**Статус:** Accepted | Superseded by ADR-XXXX | Deprecated

## Контекст
Что мы решали и почему это вообще проблема.

## Решение
Что решили сделать.

## Альтернативы
Что ещё рассматривали и почему отвергли.

## Последствия
Хорошие и плохие. Что станет проблемой потом.
```

## Текущие ADR

- [0001-llm-as-gm-not-engine.md](0001-llm-as-gm-not-engine.md) — ЛЛМ играет ГМ, состояние мира — в коде
- [0002-pickle-saves.md](0002-pickle-saves.md) — Pickle для сохранений (с оговорками)
- [0003-pydantic-ai-over-langchain.md](0003-pydantic-ai-over-langchain.md) — Pydantic AI основной; LangChain оставлен в APIManager как техдолг (на момент записи)
- [0004-pygame-prototype.md](0004-pygame-prototype.md) — Pygame для прототипа, возможен переезд на Godot
- [0005-langchain-and-streamlit-removal.md](0005-langchain-and-streamlit-removal.md) — удаление LangChain из APIManager, каталога `app/`, зависимости LangGraph
- [0006-exploration-side-session-summary.md](0006-exploration-side-session-summary.md) — возврат из side-сессии (social/trade/combat) в exploration через явную синхронную суммаризацию (Proposed)
