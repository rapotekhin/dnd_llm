# llm_server/ — Python LLM-бэкенд

**Статус:** каркас появится в v0.4.1 ([roadmap](../docs/production/roadmap.md)).

«Мозг мастера» без состояния игры: принимает снимок хода от Godot, гоняет агентов Pydantic AI через OpenRouter и возвращает текст, варианты и предложенные эффекты ([ADR-0007](../docs/tech/adr/0007-godot-client-python-llm-backend.md)). Правил 5e здесь нет: проверки и эффекты идут обратными вызовами `engine.*` в Godot ([ADR-0008](../docs/tech/adr/0008-engine-decides-llm-narrates.md), [ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)).

## Стек

- Python 3.12, `uv`, FastAPI + uvicorn (WebSocket + JSON-RPC 2.0), Pydantic AI, pytest, ruff, pyright.
- Провайдер — OpenRouter; ключ и модель только в конфиге/env сервера. vLLM — в бэклоге.
- Логи + Langfuse (opt-in), учёт расходов и дневной лимит в конфиге.
- Запуск вручную (`uv run llm_server`), на сервере — за Caddy/nginx с `wss://`.

## Что сюда переедет из прототипа

Промпты (как файлы-шаблоны), Pydantic-схемы вывода, проверка ключа и баланса из `APIManager`, тесты циклов на фейковых агентах как спецификация. Раннер [«золотых» сценариев](../docs/tech/golden-scenarios.md) — в `llm_server/evals/` (v0.4.2).
