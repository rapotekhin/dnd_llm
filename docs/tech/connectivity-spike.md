# Спайк связи Godot ↔ LLM-бэкенд

**Дата:** 2026-10-18 · **Версия:** 0.3.4 · **Итог:** транспорт из [ADR-0007](adr/0007-godot-client-python-llm-backend.md) и [ADR-0009](adr/0009-godot-backend-protocol.md) работает, блокеров для v0.4.0 нет.

Последний пункт M0. Проверяли не ЛЛМ, а трубу: Godot `WebSocketPeer` ↔ Caddy (`wss://`, `tls internal`) ↔ FastAPI/uvicorn, токен в заголовке, `session.hello`, ping/pong и обратный вызов `engine.check` из бэкенда в Godot посреди хода.

## Что построено

Код спайка — фундамент, а не выброс: на нём строятся v0.4.0 и v0.4.1.

| Где | Что |
|---|---|
| `llm_server/` | uv-проект (Python 3.13): `Session` — JSON-RPC в обе стороны по одному сокету, токен при апгрейде (HTTP 401), `session.hello` с проверкой версии и таймаутом 10 с, один ход на соединение, лимит ходов на сервер, `turn.cancel`, таймауты хода и `engine.*`, коды ошибок ADR-0009 §7, лимит 1 МБ. Ход — заглушка без ЛЛМ: `action` вызывает `engine.check` |
| `contract/schema/` | JSON Schema из Pydantic-моделей, `protocol_version.json`; тест падает, если схемы устарели |
| `game/core/net/` | `BackendConfig` (`user://backend.cfg` → env `BTR_BACKEND_TOKEN` → аргументы), `JsonRpcPeer` (JSON-RPC поверх `WebSocketPeer`, белый список обработчиков), `RpcCall`, `BackendClient` (hello, переподключение 1→30 с, таймаут подключения) |
| `game/tools/connectivity_check.gd` | headless-сценарий: hello → ход `enter` → ход `action` с `engine.check` (seeded d20, nat 20/1) |
| `infra/dev/` | Caddy в Docker: `localhost:8443`, `tls internal`, прокси на `host.docker.internal:8765` |
| `tools/connectivity_e2e.py` | поднимает сервер с одноразовым токеном и Caddy, гоняет Godot по всем случаям, печатает таблицу |

## Как запустить

```bash
cd llm_server && uv sync && uv run pytest     # протокол, 23 теста
python tools/connectivity_e2e.py              # всё вместе, нужен Docker; --no-proxy без Caddy, --quick без простоя 45 с
```

## Результаты

Windows 10, Godot 4.7.2, Docker Desktop 29.2, Caddy 2.10, uvicorn `websockets-sansio`. Заглушка хода, без ЛЛМ.

| Случай | Итог | Подключение + hello | Ход `enter` | Ход `action` + `engine.check` |
|---|---|---|---|---|
| `ws://127.0.0.1` | ✅ | 16 мс | 6 мс | 14 мс |
| `ws://`, неверный токен | ✅ отказ (401) | — | — | — |
| `wss://localhost` через Caddy | ✅ | 36–43 мс | 6 мс | 14 мс |
| `wss://`, неверный токен | ✅ отказ (401 через Caddy) | — | — | — |
| `wss://`, корень Caddy не доверен | ✅ отказ (mbedTLS −9984) | — | — | — |
| `wss://`, простой 45 с, потом ход | ✅ ping/pong держит соединение через прокси | 42 мс | 7 мс | 14 мс |

Накладные расходы транспорта — десятки миллисекунд против секунд ответа модели. Токен ни разу не попал в логи сервера, Caddy и Godot.

## Находки

1. **Godot резолвит `localhost` в `::1` и не пробует `127.0.0.1`.** Порт, опубликованный только на IPv4, даёт вечный CONNECTING. В `compose.yaml` порт опубликован на обоих loopback.
2. **`WebSocketPeer` может висеть в CONNECTING без ошибки.** `BackendClient` сам сдаётся через 10 с и уходит в переподключение. Это нужно и игроку, не только в dev.
3. **Godot не отличает «сервер лежит» от 401 и ошибки TLS.** Все три — закрытие с кодом −1, причина видна только в логе движка. Экрану «бэкенд недоступен» (v0.4.0) нужна подсказка про все три. Предложение: перед сокетом делать `GET /healthz` через `HTTPRequest` — так «сервер не отвечает» отделяется от «токен или сертификат».
4. **Числа из JSON приходят в Godot как `float`** (`limits.max_message_bytes` = `1048576.0`). Лёгкая проверка в Godot (ADR-0009 §8) должна приводить целые поля через `int()`.
5. **`inbound_buffer_size` у `WebSocketPeer` по умолчанию 64 КБ.** Снимок или результат больше этого не доходит. `JsonRpcPeer` ставит буферы под лимит протокола (1 МБ, с 0.71.0 — 8 МБ).
6. **uvicorn:** реализация `websockets` устарела, используем `websockets-sansio`. HTTP 401 при апгрейде (расширение `websocket.http.response`) и ping/pong с ней работают.
7. **Docker Desktop:** Caddy в контейнере достаёт uvicorn на `127.0.0.1` хоста через `host.docker.internal`, бинд на `0.0.0.0` не нужен. **На Linux-сервере это не так:** `host-gateway` ведёт на мост Docker. Там Caddy ставится нативно или с `network_mode: host`. Не проверено, это часть инструкции развёртывания в v0.4.1.
8. **Windows:** `uv run` запускает Python дочерним процессом, и `terminate()` убивает только `uv` — сервер остаётся на порту. Скрипт гасит всё дерево (`taskkill /T`).
9. **TLS в Godot:** `TLSOptions.client(root)` с одним корнем Caddy работает. Системные CA корень `tls internal` не принимают — так и должно быть.

## Решения по итогам

Записаны в [ADR-0009 §9](adr/0009-godot-backend-protocol.md#9-уточнения-после-спайка-связи):

- `PROTOCOL_VERSION` начинается с `0.1.0`. Пока major = 0, несовместимо и изменение minor, поэтому сверяются major и minor.
- Клиентские коды ошибок Godot (по сети не ходят): −32090 `connection_lost`, −32091 `client_timeout`, −32092 `message_too_big`.
- Таймаут подключения на клиенте — 10 с.
- Python бэкенда — 3.13 (было 3.12 в ADR-0007).

## Связанные

- [ADR-0007](adr/0007-godot-client-python-llm-backend.md), [ADR-0009](adr/0009-godot-backend-protocol.md)
- [roadmap.md](../production/roadmap.md) — M0, v0.4.0 (`Backend`), v0.4.1, v0.4.2
