# Backlog и техдолг

Список того, что нужно сделать, отсортированный по приоритету и категории.  
Это **рабочий список**, обновляется по мере работы.

---

## 🔥 Критический техдолг

### Сломанная механика перехода exploration → social → exploration (и через trade)

**Симптом:** при возврате в exploration после side-сессии (social или social → trade → social) ЛЛМ-агент ведёт себя так, словно диалог не закончился: продолжает отвечать на последнюю реплику игрока, либо предлагает действия без учёта произошедшего, либо «не помнит» исхода диалога/торговли.

**Когда воспроизводится:**
- `exploration → social → exploration` (выход из social — что через действие LLM, что по кнопке «Уйти»)
- `exploration → social → trade → social → exploration` — особенно ярко, потому что у trade нет своего summary

**Корневые причины (по результатам разбора кода):**

1. **`exploration` thread не завершается на side-transition, а паузится** ([`game/core/gameplay/exploration.py`](../../game/core/gameplay/exploration.py) `_exploration_loop`, ветка `next_act in ("social", "trade")`). На возврате он будится сигналом `resume` и сразу идёт к `generate_actions`. При этом:
   - `state["scene"]` **остаётся той, что была до ухода** в social/trade — никто её не пересобирает; LLM получает в промпте `prompt_generate_actions(history, scene)` старое описание мира.
   - `state["history"]` обнуляется в `[]`, но **в него не добавляется отчёт** о том, что случилось в side-сессии. Контекст возврата для LLM пуст.

2. **Канал передачи итога side-сессии в exploration отсутствует.** Сейчас единственный «мост» — поле `location.location_history_summary`, которое читается заново только при пересборке агентов exploration через системный промпт. Этого недостаточно: в самом промпте действий и резолюции его нет, и LLM не получает сигнала «диалог закончился».

3. **Race condition при выходе из social кнопкой «Уйти»** ([`game/ui/screens/social_screen.py`](../../game/ui/screens/social_screen.py) `_trigger_summary_on_leave` → `generate_social_summary_async`). Summary стартует в **отдельном фоновом потоке**, exploration же в этот момент уже получает `resume` и пересобирает агентов. LLM-вызов саммари занимает секунды — к моменту пересборки `location_history_summary` обычно ещё **не обновлён**, и системный промпт exploration агентов не содержит свежей информации о только что закончившемся диалоге.

4. **Trade не пишет собственного summary вообще.** Цепочка `social → trade → social` теряет информацию о торговле: в `state["history"]` social-loop про trade не появляется ничего, а `_generate_social_summary` суммирует только реплики диалога. На возврат в exploration факт торговли может «пропасть» либо просочиться искажённо.

5. **Несовпадение жизненных циклов social-thread и UI чата.** При возврате `exploration → social → trade → social` `MainScreen._enter_social → set_npc()` чистит `_chat_entries` в UI, тогда как `state["history"]` social-loop сохраняется. Это рассинхронизирует то, что видит игрок, и то, что видит LLM.

**Ожидаемое поведение:** перед возвратом в exploration формируется явная **суммаризация side-сессии** (social + всё, что было внутри: trade, в будущем — combat и др.). Эта суммаризация попадает в контекст exploration-агента **синхронно и гарантированно**, и стартовый шаг exploration на возврате (новый scene + actions) строится с её учётом. ЛЛМ exploration видит, что произошёл диалог/торговля, и предлагает игроку выбор действий с учётом нового положения.

**Архитектурное решение:** оформляется отдельным ADR — см. [adr/0006-exploration-side-session-summary.md](../tech/adr/0006-exploration-side-session-summary.md).

---

## 🛠️ Технический долг (плановый)

### Миграция сейвов с Pickle

**Что:** Pickle хрупок к рефакторингу классов.  
**Когда:** перед расшариванием сейвов или после стабилизации классов.  
**См.:** [tech/adr/0002-pickle-saves.md](../tech/adr/0002-pickle-saves.md)

### Возврат на Langfuse?

**Что:** сейчас Logfire, раньше был Langfuse. Не уверены, что Logfire лучше.  
**Действие:** обсудить и решить — оставить Logfire или вернуться на Langfuse.  
**См.:** [tech/llm-integration.md](../tech/llm-integration.md) → раздел Трейсинг

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

См. [narrative/dm-style.md](../narrative/dm-style.md). Выбор стиля при старте/в настройках.

### Динамические цены в trade

Сейчас цены статичны. Должны учитывать репутацию / харизму.

### Экран смерти и рестарт

Часть рогалик-цикла (M4).

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

### Сеттинг — закрепить Forgotten Realms?

См. [narrative/world.md](../narrative/world.md). Сейчас Невервинтер заглушка. Оставить FR или переехать на свой сеттинг — открытый вопрос.

---

## 🚀 Платформа и инфра

### Локальная модель (vllm)

Сейчас только OpenRouter. Запуск vllm локально или на своём сервере — для приватности и независимости от провайдера.

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
| Multiclassing — поддерживаем? | [systems/leveling.md](../design/systems/leveling.md) |
| Сетка в combat — нужна? | [systems/combat.md](../design/systems/combat.md) |
| Меняем ли Невервинтер на своё? | [narrative/world.md](../narrative/world.md) |
| Logfire или Langfuse? | [tech/llm-integration.md](../tech/llm-integration.md) |

---

## ✅ Закрытые

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
