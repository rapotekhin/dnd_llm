# llm_server/ — Python LLM-бэкенд

**Статус:** v0.4.1 — агенты Pydantic AI через OpenRouter, все методы протокола 0.2.0 ([ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)), выбор модели из белого списка, дневной бюджет, Langfuse по желанию.

«Мозг мастера» без состояния игры: принимает снимок хода от Godot, гоняет агента и возвращает текст, варианты, проверки и id принятых движком эффектов ([ADR-0007](../docs/tech/adr/0007-godot-client-python-llm-backend.md)). Правил 5e здесь нет: проверки, эффекты, справка и поиск предметов идут обратными вызовами `engine.*` в Godot ([ADR-0008](../docs/tech/adr/0008-engine-decides-llm-narrates.md)).

## Стек

Python 3.13, `uv`, FastAPI + uvicorn (WebSocket + JSON-RPC 2.0), Pydantic AI (OpenRouter), Jinja2, pytest. Langfuse — группа `observability`.

## Запуск

```bash
uv sync                                  # своё окружение llm_server/.venv
uv run pytest                            # протокол, агент на FunctionModel, промпты, контракт — без сети и денег
uv run llm_server                        # ws://127.0.0.1:8765/ws
LLM_SERVER_TURN_HANDLER=stub uv run llm_server   # без ЛЛМ: заглушка хода для UI и протокольных тестов
uv run python -m llm_server.contract     # перевыгрузить contract/schema/ после правки моделей
```

На сервер — [docs/tech/deploy.md](../docs/tech/deploy.md).

## Конфиг (env или корневой `.env`)

| Переменная | По умолчанию | Что |
|---|---|---|
| `LLM_SERVER_TOKEN` | — | общий токен игроков, ≥ 16 символов |
| `OPENROUTER_API_KEY` | — | обязателен для `agent`; при старте проверяется, в логи не пишется |
| `LLM_SERVER_TURN_HANDLER` | `agent` | `agent` (ЛЛМ) или `stub` |
| `LLM_SERVER_MODEL` | `anthropic/claude-haiku-5.5` | модель по умолчанию |
| `LLM_SERVER_MODELS` | haiku-5.5, qwen3.8-omni-flash, qwen3.8-27b, gemini-3.8-flash, deepseek-v4.1-flash-1017 | белый список для выбора в игре |
| `LLM_SERVER_DAILY_BUDGET_USD` | `1.0` | дневной лимит, `off` — без лимита |
| `LLM_SERVER_DATA_DIR` | `llm_server/var` | счётчик бюджета, библиотека предметов |
| `LLM_SERVER_HOST` / `PORT` | `127.0.0.1` / `8765` | |
| `LLM_SERVER_TURN_TIMEOUT` / `ENGINE_TIMEOUT` / `HELLO_TIMEOUT` | 90 / 10 / 10 с | |
| `LLM_SERVER_MAX_TURNS` | 1 | одновременных ходов на сервер |
| `LANGFUSE_ENABLED` | — | `1` + ключи `LANGFUSE_*` — трейсы всех запусков агента |

## Устройство

| Модуль | Что |
|---|---|
| `protocol.py` | Pydantic-модели: снимок, эффекты, `engine.*`, `summary.*`, `PROTOCOL_VERSION`, коды ошибок — источник `contract/` |
| `session.py` | одно соединение: JSON-RPC в обе стороны, hello, ход, `session.status`, `summary.request`, таймауты |
| `agents.py` | агент хода: инструменты `request_check`, `propose_effect`, `lookup`, `find_items` → `engine.*`; проверка вывода |
| `turns.py` | обработчики хода и сводки: модель из белого списка, бюджет, повторы OpenRouter (не после обращения к движку), учёт расходов |
| `prompts/*.md.j2` | промпты Jinja2 (строгий режим): правила, сцена, режимы `exploration` / `social` / `trade`, ход, сводка |
| `llm/` | каталог моделей с ценами OpenRouter, фабрика моделей, дневной бюджет, библиотека созданных предметов |
| `app.py`, `__main__.py` | FastAPI, проверка токена, запуск, проверка ключа, Langfuse |

## Тесты

`tests/test_agent.py` — агент целиком через настоящий WebSocket: `FunctionModel` играет модель, тест играет Godot и отвечает на `engine.*`. Проверяются лимиты хода, отклонённые эффекты, повторы, бюджет, выбор модели, смена режима, библиотека предметов. Живая проверка с настоящей моделью — `python tools/godot_playtest.py --scenario live --real` (скилл `playtest`).
