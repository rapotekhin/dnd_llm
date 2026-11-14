# Развёртывание llm_server на сервере

> ⚠️ **Не проверено на живом сервере.** Инструкция собрана по [ADR-0007](adr/0007-godot-client-python-llm-backend.md) и [спайку связи](connectivity-spike.md), где цепочка Godot ↔ Caddy (`wss://`) ↔ uvicorn проверена локально в Docker. Первое развёртывание — повод исправить этот документ.

Бэкенд — обычный Python-процесс без состояния игры. Он слушает только `127.0.0.1`, а наружу его выставляет Caddy с сертификатом Let's Encrypt. Запуск ручной, через systemd.

Обычному игроку сервер не нужен: билд игры запускает мастера сам (см. [«Встроенный сервер»](#встроенный-сервер) в конце страницы). Эта инструкция — для своего сервера на несколько игроков, где ключ OpenRouter и расходы лежат на его владельце.

## Что нужно

- Linux-сервер (Ubuntu 24.04 или похожий), открытые порты 80 и 443.
- Домен с A-записью на сервер, например `master.example.org`.
- Ключ OpenRouter и общий токен доступа для игроков (не короче 16 символов): `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`.

## 1. Код и окружение

```bash
sudo useradd --system --create-home --home-dir /opt/btr btr
sudo -iu btr
git clone https://github.com/rapotekhin/dnd_llm.git app && cd app
curl -LsSf https://astral.sh/uv/install.sh | sh      # uv в ~/.local/bin
~/.local/bin/uv sync --project llm_server --no-dev   # Python 3.13 uv скачает сам
```

## 2. Конфиг

`/opt/btr/app/.env` (права `600`, владелец `btr`). Корневой `.env` читается сервером и не попадает в git:

```bash
LLM_SERVER_TOKEN=<общий токен для игроков>
OPENROUTER_API_KEY=<ключ OpenRouter>
LLM_SERVER_MODEL=deepseek/deepseek-v4.1-flash-1017
LLM_SERVER_MODELS=deepseek/deepseek-v4.1-flash-1017,anthropic/claude-haiku-5.5,qwen/qwen3.8-omni-flash,qwen/qwen3.8-27b,google/gemini-3.8-flash
LLM_SERVER_PROVIDER=wafer        # провайдер мастера по умолчанию, без выбора (v0.8.4.42.26); auto — выбор ниже
LLM_SERVER_PROVIDER_SORT=price   # самый дешёвый провайдер модели на OpenRouter; off — как решит OpenRouter
LLM_SERVER_PROVIDER_TOP=3        # из трёх самых дешёвых…
LLM_SERVER_MIN_TPS=30            # …первый, кто шустрее 30 токенов/с (медленные — в запасе)
LLM_SERVER_DAILY_BUDGET_USD=1.0
# LANGFUSE_ENABLED=1, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST — по желанию (uv sync --group observability)
```

Остальные переменные (`LLM_SERVER_HOST`, `PORT`, таймауты, `LLM_SERVER_DATA_DIR`) — в [llm_server/README.md](../../llm_server/README.md). `HOST` оставьте `127.0.0.1`.

## 3. systemd

`/etc/systemd/system/btr-llm.service`:

```ini
[Unit]
Description=Between the Rolls LLM backend
After=network-online.target

[Service]
User=btr
WorkingDirectory=/opt/btr/app
ExecStart=/opt/btr/.local/bin/uv run --project llm_server --no-dev llm_server
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/btr/app/llm_server/var /opt/btr/.cache

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now btr-llm
journalctl -u btr-llm -f        # «OpenRouter key ok, credits left …», ключ и токен в лог не пишутся
```

## 4. Caddy

Нативно, а не в Docker: на Linux контейнер не достанет `127.0.0.1` хоста ([находка 7 спайка](connectivity-spike.md#находки)).

```bash
sudo apt install caddy
```

`/etc/caddy/Caddyfile`:

```
master.example.org {
	reverse_proxy 127.0.0.1:8765
}
```

```bash
sudo systemctl reload caddy
curl https://master.example.org/healthz      # {"status":"ok","version":"…"}
```

Caddy сам получает и продлевает сертификат Let's Encrypt. WebSocket и заголовок `Authorization` проходят без настроек, журнал доступа по умолчанию выключен, так что токен не оседает в логах.

## 5. Игра

«Настройки → Мастер»: адрес `wss://master.example.org/ws`, токен из `.env`. Сертификат указывать не нужно: Let's Encrypt проверяется системными корнями. Нажмите «Сохранить и проверить». В той же вкладке выбирается модель из списка сервера.

## Обновление и бюджет

```bash
sudo -iu btr bash -c 'cd app && git pull && ~/.local/bin/uv sync --project llm_server --no-dev'
sudo systemctl restart btr-llm
```

Дневной расход хранится в `llm_server/var/budget.json` и сбрасывается в полночь UTC. Исчерпанный лимит — ошибка `budget_exceeded`, игра пишет об этом игроку. Библиотека созданных мастером предметов — `llm_server/var/items/library.jsonl`.

## Встроенный сервер

Билд `python tools/build_game.py` лежит в `build/release/<версия>/`: `BetweenTheRolls.exe`, `server.exe` и его библиотеки `server_lib/`. Переносить папку надо целиком. Игрок запускает только игру. Как это устроено и почему так — [ADR-0014](adr/0014-embedded-master-server.md).

| Что | Как |
|---|---|
| Включается | адрес мастера в настройках пуст и рядом с игрой есть `server.exe` |
| Внешний сервер | задайте адрес и токен, как в шаге 5: встроенный не запускается |
| Ключ OpenRouter | окно при первом запуске или «Настройки → Мастер»; хранится в `backend.cfg` |
| Адрес и токен | только `127.0.0.1`, порт и токен новые при каждом запуске |
| Выход из игры | игра завершает `server.exe`; если игра упала, он завершается сам |
| Падение сервера | до 3 перезапусков подряд, затем окно с причиной |
| Данные | `%APPDATA%/Godot/app_userdata/Between the Rolls/master/`: журнал `server.log`, бюджет, библиотека предметов, трассы модели |

`backend.cfg` с заполненным адресом остаётся внешним сервером: чтобы перейти на встроенный, очистите поле адреса в «Настройки → Мастер».

Проверка: `build_game.py` запускает сервер и игру на заглушке мастера, смотрит, что слушается только `127.0.0.1`, что сервер кончается вместе с игрой и что значений из `.env` нет в файлах билда.

### Билд для Linux

`python tools/build_game.py --linux` кладёт в `build/release/<версия>/linux/` игру `BetweenTheRolls.x86_64`, сервер `server`, `server_lib/` и `README.md` о том, как запускать, а рядом архив `BetweenTheRolls-<версия>-linux-x86_64.tar.gz` с битами запуска. Игрок распаковывает архив и запускает `BetweenTheRolls/BetweenTheRolls.x86_64`; данные игры — в `~/.local/share/godot/app_userdata/Between the Rolls/`.

| Что | Как |
|---|---|
| Игра | экспорт Godot по пресету «Linux» на Windows; нужны `linux_*.x86_64` из официальных шаблонов той же версии в `%APPDATA%/Godot/export_templates/<версия>.stable/` |
| Сервер | PyInstaller замораживает только под свою систему, поэтому этот шаг идёт в WSL (`--wsl`, по умолчанию `Ubuntu`) тем же скриптом: uv в `~/.local/bin`, Python от uv (не системный), окружение `~/.cache/btr/server-venv` на диске Linux, а не `llm_server/.venv` Windows |
| glibc | билд не должен просить glibc новее 2.35 (Ubuntu 22.04, Debian 12): проверяется по всем ELF-файлам билда |
| Проверка | та же, что у Windows, но в WSL: сервер на заглушке, игра без ключа и с сервером, слушает только `127.0.0.1`, сервер кончается с игрой |
| Имя сервера | игра ищет рядом с собой `server.exe` на Windows и `server` на Linux (`EmbeddedServer.find_exe`) |
