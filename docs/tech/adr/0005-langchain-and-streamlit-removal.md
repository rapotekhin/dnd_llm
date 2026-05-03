# ADR-0005: Удаление LangChain из APIManager и legacy Streamlit (`app/`)

**Дата:** 2026-05-03  
**Статус:** Accepted

## Контекст

[ADR-0003](0003-pydantic-ai-over-langchain.md) зафиксировал перевод агентов на Pydantic AI и оставил **остаточное** использование LangChain в `APIManager.generate_with_format()` как техдолг. В зависимостях при этом числился неиспользуемый в коде **LangGraph**. Отдельно в репозитории оставался каталог **`app/`** — Streamlit-прототип до UI на Pygame (см. альтернативы в [ADR-0004](0004-pygame-prototype.md)).

Фактическое состояние кода на момент решения: вызовов `generate_with_format` из игры не было; LangChain тянул лишние транзитивные пакеты и дублировал уже используемый путь через Pydantic AI и OpenRouter.

## Решение

- Убрать LangChain из игрового кода: `APIManager` отвечает за ключ OpenRouter, проверку баланса и фабрику `get_pydantic_ai_model()` без `ChatOpenAI`, цепочек и `generate_with_format`.
- Удалить вспомогательный код, завязанный только на LangChain (в т.ч. неиспользуемые обёртки инструментов).
- Удалить каталог **`app/`** (Streamlit-прототип).
- Убрать из `requirements.txt` неиспользуемый **`langgraph`**.

Идентификатор модели OpenRouter задаётся в `APIManager` (константа по умолчанию), без отдельного LangChain-клиента.

## Альтернативы

1. **Оставить LangChain только в APIManager «на будущее»** — отвергнуто: нет потребителей, лишняя связность и зависимости.
2. **Сохранить `app/` как архив** — отвергнуто: путает новых участников и дублирует устаревший путь запуска.

## Последствия

**Плюсы:** один предсказуемый путь LLM-вызовов, меньше зависимостей, проще онбординг.

**Минусы:** если понадобится разовый structured-вызов вне агента, его нужно строить через Pydantic AI или провайдерский SDK, а не через старый метод APIManager.

## Связанные

- [ADR-0003](0003-pydantic-ai-over-langchain.md) — исходный выбор Pydantic AI и описание хвоста LangChain (на момент записи 0003)
- [ADR-0004](0004-pygame-prototype.md) — отказ от Streamlit в пользу Pygame; данный ADR фиксирует удаление остатка прототипа из дерева репозитория
- [tech/llm-integration.md](../llm-integration.md)
- [production/backlog.md](../../production/backlog.md)
