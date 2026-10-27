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
| `LLM_SERVER_MODEL` | `deepseek/deepseek-v4.1-flash-1017` | модель по умолчанию (ADR-0011, с v0.7.3) |
| `LLM_SERVER_MODELS` | deepseek-v4.1-flash-1017, haiku-5.5, qwen3.8-27b, gemini-3.8-flash; бесплатные (v0.7.20.1): openrouter/free, nemotron-3.5-super-vl:free, gemma-4-31b-it:free, nemotron-3-ultra-550b-a55b:free | белый список для выбора в игре; у бесплатных — лимит запросов в день, у Nemotron рассуждения выключены (иначе съедают весь ответ) |
| `LLM_SERVER_PROVIDER_SORT` | `price` | провайдер модели на OpenRouter: `price` — самый дешёвый из поддерживающих все параметры запроса, `throughput`, `latency`, `off` — маршрутизация OpenRouter (v0.7.4) |
| `LLM_SERVER_PROVIDER_TOP` | `3` | при `price` (v0.7.14.5): запрос идёт только к N самым дешёвым провайдерам на типичный ход (20k токенов на входе, 1k на выходе), умеющим `tools` и живым последние 30 минут, по одной метке на провайдера; список обновляется раз в 15 минут (`llm/providers.py`). С v0.7.34.1 цена хода считает кэш (`LLM_SERVER_CACHE_SHARE`) и наши счета: каждый запрос сверяется с прайсом провайдера, и цена провайдера умножается на «выставлено ÷ прайс» за последние 7 дней (от 3 запросов; `var/provider_bills.json`, переживает перезапуск). Старые счета забываются — подорожавший или подешевевший провайдер пробуется снова. Отчёт и засев счетов из трейсов — `tools/provider_cost.py` |
| `LLM_SERVER_MIN_TPS` | `30` | порог скорости из этих N (p50, токенов в секунду, статистика OpenRouter за 5 минут): кто медленнее, идёт в конец очереди; `0` — без порога. Кто ответил — `provider` в трейсе хода |
| `LLM_SERVER_CACHE_SHARE` | `0.7` | доля входа хода из кэша провайдера при сравнении цен (трейсы 2026-10: 69% у Relace); у провайдера без цены кэша весь вход — по полной. Закреплённого первым провайдера больше нет (с 2026-10-24 был Relace): OpenInference выставлял в 3.5–4.8 раза больше прайса — теперь это видят счета, а не ручная настройка |
| `LLM_SERVER_MIN_TURN_TPS` | `20` | наш собственный замер: каждый запрос к OpenRouter (токены ответа / секунды, вместе с чтением длинного промпта); провайдер, медленнее порога за последние 30 минут, выбывает из N — отвечает самый дешёвый из шустрых, а если медленны все — все остаются; `0` — не замерять. Статистика OpenRouter строится на коротких запросах и не видела, что OpenInference тянул наши 40-тысячные ходы по 14 ток/с |
| `LLM_SERVER_DAILY_BUDGET_USD` | `1.0` | дневной лимит, `off` — без лимита; считается по тому, что OpenRouter выставил за каждый запрос (поле `cost` ответа: цена провайдера, который ответил, вместе с повторами и упавшими ходами), без него — по цене модели из каталога (v0.7.14.5) |
| `LLM_SERVER_DATA_DIR` | `llm_server/var` | счётчик бюджета, библиотека предметов, счета провайдеров |
| `LLM_SERVER_HOST` / `PORT` | `127.0.0.1` / `8765` | |
| `LLM_SERVER_TURN_TIMEOUT` / `ENGINE_TIMEOUT` / `HELLO_TIMEOUT` | 180 / 10 / 10 с | ход ждёт медленного провайдера до 3 минут (v0.7.14.5, было 90); клиент ждёт на 5 с дольше (`game.json` `turn.client_timeout_s`) |
| `LLM_SERVER_MAX_TURNS` | 1 | одновременных ходов на сервер |
| `LLM_SERVER_IMAGES` | `1` | картинки событий (v0.7.35): `0` — сервер не рисует, кисточки в игре нет. Модели — `config.IMAGE_MODELS`: Recraft V4.1 Flash (по умолчанию, ~$0.007), Recraft V4.1, FLUX 3 Klein (~$0.009), FLUX.2 Pro (~$0.045); цена в настройках — по нашим счетам (`var/image_prices.json`) |
| `LLM_SERVER_IMAGE_MODEL` | `recraft/recraft-v4.1-flash` | модель картинок по умолчанию |
| `LLM_SERVER_A1111_URL` | — | свой AUTOMATIC1111 (`http://host:7860`): добавляет модель `a1111` с шаблоном `sd` (теги и negative prompt) |
| `LANGFUSE_ENABLED` | — | `1` + ключи `LANGFUSE_*` — трейсы всех запусков агента |

## Устройство

| Модуль | Что |
|---|---|
| `protocol.py` | Pydantic-модели: снимок, эффекты, `engine.*`, `summary.*`, `PROTOCOL_VERSION`, коды ошибок — источник `contract/` |
| `session.py` | одно соединение: JSON-RPC в обе стороны, hello, ход, `session.status`, `summary.request`, таймауты |
| `agents.py` | агент хода: инструменты `request_check`, `propose_effect`, `lookup`, `find_items` → `engine.*`; проверка вывода |
| `turns.py` | обработчики хода и сводки: модель из белого списка, бюджет, повторы OpenRouter (не после обращения к движку), учёт расходов |
| `prompts/*.md.j2` | промпты Jinja2 (строгий режим): правила, сцена, режимы `exploration` / `social` / `trade`, ход, сводка |
| `images.py` | картинка события (v0.7.35): агент пишет промпт по шаблону семейства (`prompts/images/<template>.md.j2`: блок `instructions` — как писать, блок `prompt` — где стиль), бэкенд рисует — OpenRouter `/api/v1/images` или свой AUTOMATIC1111; цены по счетам. Новая модель — строка `ImageModel` в `config.py`; новое семейство — шаблон; новый сервер — `backend` и функция в `draw` |
| `llm/` | каталог моделей с ценами OpenRouter, фабрика моделей, дневной бюджет, библиотека созданных предметов |
| `app.py`, `__main__.py` | FastAPI, проверка токена, запуск, проверка ключа, Langfuse |

## Тесты

`tests/test_agent.py` — агент целиком через настоящий WebSocket: `FunctionModel` играет модель, тест играет Godot и отвечает на `engine.*`. Проверяются лимиты хода, отклонённые эффекты, повторы, бюджет, выбор модели, смена режима, библиотека предметов. Живая проверка с настоящей моделью — `python tools/godot_playtest.py --scenario live --real` (скилл `playtest`).
