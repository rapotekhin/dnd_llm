# ADR-0003: Pydantic AI вместо LangChain (для агентов)

**Дата:** 2026-05-03 (зафиксировано задним числом)  
**Статус:** Accepted, LangChain в процессе выпиливания

## Контекст

Изначально проект использовал **LangChain** для всех LLM-вызовов: `ChatOpenAI`, `PydanticOutputParser`, `ChatPromptTemplate`.

Когда понадобились агенты с инструментами и строгим типизированным выводом, обнаружились проблемы:

- LangChain Tools API громоздкий
- Структурированный вывод через `PydanticOutputParser` нестабильный
- Документация LangChain меняется быстро, версии часто несовместимы

Появился **Pydantic AI** — фреймворк для агентов с типизированными tools и output_type.

## Решение

**Pydantic AI** — основной инструмент для всех LLM-агентов.

Все agentic-вызовы в `game/core/gameplay/` используют `pydantic_ai.Agent` с:
- `output_type=<Pydantic Model>` — гарантирует типизированный вывод
- `@agent.tool_plain` — простая регистрация инструментов
- `instructions=` — системный промпт

LangChain остаётся в `APIManager.generate_with_format()` — это **техдолг**, в процессе выпиливания.

## Альтернативы

1. **LangChain** — отвергнут (см. контекст)
2. **OpenAI SDK напрямую с function calling** — слишком низкоуровнево, повторяющийся boilerplate для structured output
3. **LangGraph** — для сложных state machine'ов; пока избыточно для текущих задач (но `langgraph` есть в requirements — задел)
4. **Свой минимальный фреймворк** — overengineering

## Последствия

**Плюсы:**
- Чистый код агентов
- Типизированный вывод «из коробки»
- Простая регистрация инструментов
- Один и тот же подход во всех режимах (exploration / social / trade)

**Минусы:**
- Молодой фреймворк, API может меняться
- Завязка на конкретную библиотеку
- LangChain нужно постепенно убрать из `APIManager` (см. техдолг)

## Связанные

- [tech/llm-integration.md](../llm-integration.md)
- [production/backlog.md](../../production/backlog.md) — пункт «выпилить LangChain»
