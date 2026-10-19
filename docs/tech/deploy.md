# Развёртывание llm_server на сервере

> ⚠️ **Не проверено на живом сервере.** Инструкция собрана по [ADR-0007](adr/0007-godot-client-python-llm-backend.md) и [спайку связи](connectivity-spike.md), где цепочка Godot ↔ Caddy (`wss://`) ↔ uvicorn проверена локально в Docker. Первое развёртывание — повод исправить этот документ.

Бэкенд — обычный Python-процесс без состояния игры. Он слушает только `127.0.0.1`, а наружу его выставляет Caddy с сертификатом Let's Encrypt. Запуск ручной, через systemd. Встроенный Python для игроков — в бэклоге.

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
