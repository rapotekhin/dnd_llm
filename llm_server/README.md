# llm_server/ — Python LLM-бэкенд

**Статус:** транспорт и протокол из [спайка связи](../docs/tech/connectivity-spike.md) (v0.3.4); ход — заглушка без ЛЛМ. Агенты — v0.4.1 ([roadmap](../docs/production/roadmap.md)).

«Мозг мастера» без состояния игры: принимает снимок хода от Godot, гоняет агентов Pydantic AI через OpenRouter и возвращает текст, варианты и предложенные эффекты ([ADR-0007](../docs/tech/adr/0007-godot-client-python-llm-backend.md)). Правил 5e здесь нет: проверки и эффекты идут обратными вызовами `engine.*` в Godot ([ADR-0008](../docs/tech/adr/0008-engine-decides-llm-narrates.md), [ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)).

## Стек

- Python 3.13, `uv`, FastAPI + uvicorn (WebSocket + JSON-RPC 2.0), Pydantic AI, pytest, ruff, pyright.
- Провайдер — OpenRouter; ключ и модель только в конфиге/env сервера. vLLM — в бэклоге.
- Логи + Langfuse (opt-in), учёт расходов и дневной лимит в конфиге.
- Запуск вручную (`uv run llm_server`), на сервере — за Caddy/nginx с `wss://`.

## Запуск

```bash
uv sync                                  # своё окружение llm_server/.venv
uv run pytest                            # протокол и контракт
uv run llm_server                        # ws://127.0.0.1:8765/ws, нужен LLM_SERVER_TOKEN (env или корневой .env)
uv run python -m llm_server.contract     # перевыгрузить contract/schema/ после правки моделей
```

Конфиг — переменные `LLM_SERVER_*` (`TOKEN`, `HOST`, `PORT`, `TURN_TIMEOUT`, `ENGINE_TIMEOUT`, `HELLO_TIMEOUT`, `MAX_TURNS`), см. `src/llm_server/config.py`. Токен не пишется в логи.

| Модуль | Что |
|---|---|
| `protocol.py` | Pydantic-модели сообщений, `PROTOCOL_VERSION`, коды ошибок — источник `contract/` |
| `session.py` | одно соединение: JSON-RPC в обе стороны, hello, ход, `engine.*`, таймауты |
| `app.py` | FastAPI: `/healthz`, `/ws` с проверкой токена (HTTP 401) |
| `turns.py` | обработчики хода; пока заглушка с `engine.check` |
| `contract.py` | выгрузка схем |

## Что сюда переедет из прототипа

Промпты (как файлы-шаблоны), Pydantic-схемы вывода, проверка ключа и баланса из `APIManager`, тесты циклов на фейковых агентах как спецификация. Раннер [«золотых» сценариев](../docs/tech/golden-scenarios.md) — в `llm_server/evals/` (v0.4.2).
