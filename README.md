# Between the Rolls

Одиночная D&D 5e RPG, где Мастером Подземелий выступает ЛЛМ.

Игрок создаёт персонажа по правилам D&D 5e и попадает в мир, который ЛЛМ ведёт как настольный мастер: описывает сцены, играет за NPC, назначает броски и реагирует на любые действия.

> 🎯 **Главный принцип:** ЛЛМ исполняет роль мастера, но **не является движком**. Броски, предметы, деньги, опыт и переходы решает игровой движок; мастер просит проверку или предлагает эффект, а движок проверяет и применяет ([ADR-0008](docs/tech/adr/0008-engine-decides-llm-narrates.md)).

## Возможности

- ✅ Создание персонажа D&D 5e по SRD: расы, классы, подклассы, point buy, навыки, заклинания, снаряжение; готовые герои мира
- ✅ Пакеты миров (моды) и стартовый мир «Сумеречная Марка»; стиль мастера и границы контента
- ✅ Исследование: проверки навыков с картой броска, скрытое в комнатах, долгий отдых, карта и журнал
- ✅ Разговоры с NPC и торговля через панель сделки, с торгом и запасами торговцев
- ✅ Опыт за задания (и бой — с его появлением), повышение уровня 1–5
- ✅ Сохранения в JSON со слотами и автосейвом
- 🚧 Бой (M3), меняющийся мир и генерация мира (M2+) — [роадмап](docs/production/roadmap.md)

## Структура репозитория

| Папка | Что |
|---|---|
| `game/` | Godot-клиент (GDScript): UI, состояние, правила, сейвы — [godot-client.md](docs/tech/godot-client.md) |
| `llm_server/` | Python LLM-бэкенд: FastAPI + WebSocket, Pydantic AI, OpenRouter — [README](llm_server/README.md) |
| `contract/` | JSON Schema протокола Godot ↔ бэкенд |
| `tools/` | импорт SRD, проверка пакетов миров, живые плейтесты |
| `evals/` | «золотые» ЛЛМ-сценарии |
| `infra/` | локальный `wss://` через Caddy |
| `docs/` | документация и ADR |

Версия проекта — в файле `VERSION`. Pygame-прототип (v0.3.x) удалён в v0.5.4 после [проверки паритета](docs/production/parity-v031.md); он остался в истории git.

## Запуск

1. Ключ OpenRouter и токен сервера — в корневой `.env`:

   ```
   OPENROUTER_API_KEY=ваш_ключ
   LLM_SERVER_TOKEN=любая_строка
   ```

2. Бэкенд (нужен [uv](https://docs.astral.sh/uv/)):

   ```bash
   uv run --project llm_server python -m llm_server
   ```

3. Игра — Godot 4.7: открыть папку `game/` в редакторе или

   ```bash
   godot --path game
   ```

   Адрес и токен сервера — в «Настройки → Мастер». Развёртывание на сервер — [deploy.md](docs/tech/deploy.md).

## Тесты

- Godot: gdUnit4 (`game/test/`), команда — в [AGENTS.md](AGENTS.md#commands).
- Бэкенд: `cd llm_server && uv run pytest` (протокол, контракт, промпты, проверка пакетов миров).
- Формат «золотых» сценариев: `pip install -r requirements-dev.txt && python -m pytest`.
- Живой плейтест: `python tools/godot_playtest.py` (сценарии и правила — скилл [playtest](.claude/skills/playtest/SKILL.md)).

**CI на GitHub:** на pull request в `main` запускаются тесты бэкенда, формат сценариев и проверка, что изменены `VERSION` и `RELEASE_NOTES.md`.

## Документация

| Раздел | Что внутри |
|---|---|
| [vision/](docs/vision/) | Концепция, столпы проекта |
| [design/](docs/design/) | Геймдизайн, системы, UX |
| [narrative/](docs/narrative/) | Мир, NPC, квесты, стиль мастера |
| [tech/](docs/tech/) | Godot-клиент, протокол, бэкенд, ADR |
| [production/](docs/production/) | Роадмап, бэклог |

Старт — с [docs/README.md](docs/README.md).

## Лицензия

MIT. Данные правил — SRD 5.1 (CC BY 4.0), см. [tools/srd/source](tools/srd/source/README.md).
