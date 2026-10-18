# Backlog и техдолг

Список того, что нужно сделать, отсортированный по приоритету и категории.  
Это **рабочий список**, обновляется по мере работы.

---

## 🛠️ Технический долг (плановый)

### Side-session summary для trade

**Контекст:** [adr/0006](../tech/adr/0006-exploration-side-session-summary.md) закрыл цепочку `exploration → social → exploration`, но trade-loop пока не формирует собственный отчёт. В сценарии `social → trade → social → exploration` факты торговли не попадают в summary, который потом видит exploration.

**Действие:** на выходе из trade класть в transition детерминированный (без LLM) summary вида «куплено X за Y, продано Z», который social-loop агрегирует в свою историю до своего собственного выхода. Контракт уже учитывает `summary` в transition-сообщении — добавить только генерацию на стороне trade.

### Миграция сейвов с Pickle

**Что:** Pickle хрупок к рефакторингу классов.  
**Когда:** перед расшариванием сейвов или после стабилизации классов.  
**См.:** [tech/adr/0002-pickle-saves.md](../tech/adr/0002-pickle-saves.md)

### Стандартизация формата ID

**Что:** ID-шники сейчас разные — `tawern-001`, UUID, `mkt-npc-001`.  
**Действие:** определить convention (например: всё UUID, или всё `<type>-<random>`).

### Pyright на чистый прогон

**Что:** `pyrightconfig.json` существует, но текущий код может давать ошибки типов.  
**Действие:** прогнать pyright, починить, добавить отдельный job в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) (или второй workflow).

---

## 🎮 Фичи геймплея

### Combat (минимальная версия)

См. [design/systems/combat.md](../design/systems/combat.md). M1.

### Tools для ЛЛМ — автогенерация мира

См. [roadmap.md](roadmap.md) M2. Главная фича.

- [ ] `create_npc(name, role, location_id, ...)`
- [ ] `create_location(name, type, region, connected_to, ...)`
- [ ] `create_room(name, description, location_id, level, connections, ...)`
- [ ] `create_quest(name, description, status, ...)`
- [ ] `create_treasure(name, items, ...)`

### Память NPC

Сейчас NPC не помнит прошлых разговоров. Нужно `npc_memory_summary` по аналогии с `location_history_summary`.

### Стиль ГМ как настройка

Решено в [ADR-0010](../tech/adr/0010-game-decisions-worlds-tone-combat-death.md): выбор в новой игре + настройки. Делается в v0.5.0 (экран новой игры).

### Динамические цены в trade

Сейчас цены статичны. Должны учитывать репутацию / харизму.

### Экран смерти и рестарт

Часть M4: режимы «Одна жизнь» / «История» ([ADR-0010](../tech/adr/0010-game-decisions-worlds-tone-combat-death.md)).

### Спутники в партии

После 1.0: нанимаемые NPC со статблоками в бою ([ADR-0010](../tech/adr/0010-game-decisions-worlds-tone-combat-death.md) §4).

---

## 🎨 Контент и дизайн

### Арт-направление

См. [design/art-style.md](../design/art-style.md). Не определено.

- Шрифт основной + акцентный (с кириллицей)
- Палитра
- Иконки (предметы, школы магии, статусы)
- Аватарки NPC — ИИ-генерация / иллюстрации / заглушки?

### Стартовый контент

- Расширить стартовые локации (сейчас только таверна / рынок / пещеры)
- Добавить квестов в стартовые локации
- Расширить рекрутёр-NPC (есть ли пати-система?)

### Стартовая вселенная

Написать свой регион пакетом вселенной (городок + 3–4 места, тёмное фэнтези с надеждой) вместо Невервинтера — [ADR-0010](../tech/adr/0010-game-decisions-worlds-tone-combat-death.md), v0.5.0.

---

## 🚀 Платформа и инфра

### Локальная модель (vLLM)

Сейчас только OpenRouter. Поддержка vLLM в Python-бэкенде (OpenAI-совместимый `base_url`, structured output через guided decoding) — для приватности и независимости от провайдера. **Не в M1**, сильно позже ([ADR-0007](../tech/adr/0007-godot-client-python-llm-backend.md) §6).

### Раздача бэкенда игрокам без Python

В M1 бэкенд запускается вручную через `uv run`. Для раздачи на машины игроков — встроенный (embeddable) Python с зависимостями в папке; отдельное решение, когда понадобится ([ADR-0007](../tech/adr/0007-godot-client-python-llm-backend.md) §4).

### EN-локализация (полная)

Сейчас только RU полный. Когда RU стабилизируется — синк + дозаполнение EN.

### CI / тесты

**Уже есть:**

- pytest в `tests/` (`requirements-dev.txt`, `pytest.ini`) — утилиты и билдеры, загрузка стартовых JSONL, торговля, сохранения/загрузка состояния, моки циклов exploration и social без ключей API; парсер ответа DM вынесен в `agent_resolution_parse.py` и покрыт отдельно.
- **GitHub Actions:** [.github/workflows/ci.yml](../../.github/workflows/ci.yml) — на pull request в `main` или `master` на Ubuntu (Python 3.11) ставятся `requirements.txt` + `requirements-dev.txt`, запускается `pytest`; отдельный job вызывает [.github/scripts/check_pr.py](../../.github/scripts/check_pr.py) и требует, чтобы в диффе PR были изменения `__version__` в `game/__init__.py` и файла `RELEASE_NOTES.md` в корне.

**Хотелось бы дальше:**

- Pre-commit: pyright + black/ruff
- Тесты UI (если получится без хрупкости)
- Автопроверка паритета ключей локализации RU/EN (отдельно от скрипта `scripts/check_localization.py`)
- Порог покрытия (`pytest-cov --cov-fail-under=…`) по договорённости

---

## ❓ Открытые вопросы (нужно решить)

| Вопрос | Где обсуждается |
|---|---|
| Цены в trade — статика или динамика? | [systems/trade.md](../design/systems/trade.md) |
| Память NPC — нужна и как реализовать? | [systems/social.md](../design/systems/social.md) |

---

## ✅ Закрытые

- ~~Сеттинг, тон ГМ, сетка в бою, мультикласс, мета-прогресс~~ → [ADR-0010](../tech/adr/0010-game-decisions-worlds-tone-combat-death.md): вселенные-пакеты и свой регион, выбор стиля, зоны, мультикласс после боя, без мета-прогресса
- ~~Logfire или Langfuse?~~ → Langfuse в Python-бэкенде, Logfire убирается ([ADR-0007](../tech/adr/0007-godot-client-python-llm-backend.md) §6)
- ~~Переезд с Pygame~~ → Godot-клиент + Python LLM-бэкенд ([ADR-0007](../tech/adr/0007-godot-client-python-llm-backend.md))
- ~~Сломанная механика перехода `exploration → social → exploration` (и через trade)~~ → реализован [adr/0006](../tech/adr/0006-exploration-side-session-summary.md): синхронный `summary` в transition, передача его в exploration через `resume`-сообщение, повторный `describe_scene` на resume по отдельному промпту, видимый игроку маркер «Возвращение к исследованию» + DM-нарратив. Async-путь `generate_social_summary_async` удалён, кнопка «Уйти» в social шлёт `{"type": "leave"}` в очередь loop'а. Trade пока не пишет своего summary — оставлено в техдолге.
- ~~Зацикливание `question_to_player` в social~~ → поле удалено из `SocialResolutionOutput`; loop теперь один проход на ход; NPC сам переспрашивает в характере, если ввод неоднозначный.
- ~~Legacy `app/` (Streamlit)~~ → удалена из репозитория
- ~~LangChain в `APIManager`~~ → выпилен; см. [adr/0005](../tech/adr/0005-langchain-and-streamlit-removal.md) (исходное решение о Pydantic AI — [adr/0003](../tech/adr/0003-pydantic-ai-over-langchain.md))
- ~~Проверка паритета ключей RU ↔ EN~~ → скрипт `scripts/check_localization.py`; текущие `ru.xml` / `en.xml` совпадают по наборам id
- ~~Имя `qwest_creation_prompts.py`~~ → файла в кодовой базе не было; при добавлении промптов квестов использовать **`quest_creation_prompts.py`**
- ~~Перенос UI с Streamlit на Pygame~~ → done
- ~~Z-order и перекрытия в UI~~ → done в v0.2.0
- ~~Декомпозиция мегаэкранов (character creation / level up / trade)~~ → первый этап: подпакеты и реэкспорт из `*_screen.py`; см. [architecture](../tech/architecture.md)
- ~~Базовый набор автотестов (pytest) для ядра игры~~ → каталог `tests/`; см. [README](../../README.md) («Тесты»), [architecture](../tech/architecture.md)
- ~~CI на GitHub: pytest на PR~~ → [.github/workflows/ci.yml](../../.github/workflows/ci.yml); см. [README](../../README.md) («Тесты»), [architecture](../tech/architecture.md)
- ~~Перевод архитектуры с «ЛЛМ-движок» на «ЛЛМ-ГМ»~~ → done, см. [adr/0001](../tech/adr/0001-llm-as-gm-not-engine.md)
