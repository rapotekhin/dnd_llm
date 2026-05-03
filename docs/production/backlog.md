# Backlog и техдолг

Список того, что нужно сделать, отсортированный по приоритету и категории.  
Это **рабочий список**, обновляется по мере работы.

---

## 🔥 Критический техдолг

Сейчас **нет открытых блокирующих пунктов** в этой категории.

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
**Действие:** прогнать pyright, починить, добавить в CI (когда будет).

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

Сейчас тестов нет. Хотя бы:
- Unit тесты для `coin_converter`, `level_up_utils`
- Integration тест exploration-loop с моком LLM
- Pre-commit с pyright + black/ruff
- Тесты для UI элементов (если возможно)
- Тесты на ENG\RU тесты, что вся локализация везде на одном языке
- Максимально увеличить покрытие тестами

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
- ~~Перевод архитектуры с «ЛЛМ-движок» на «ЛЛМ-ГМ»~~ → done, см. [adr/0001](../tech/adr/0001-llm-as-gm-not-engine.md)
