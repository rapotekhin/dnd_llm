# Between the Rolls

Одиночная D&D 5e RPG в открытом мире, где Мастером Подземелий выступает ЛЛМ.

Игрок создаёт персонажа по правилам D&D 5e и попадает в мир, который ЛЛМ ведёт как настольный мастер: описывает сцены, играет за NPC, назначает броски и реагирует на любые действия. Мир, NPC и квесты генерируются на ходу — это бесконечная песочница с роглайк-логикой.

> 🎯 **Главный принцип:** ЛЛМ исполняет роль ГМ, но **не является движком**. Все изменения мира — через Python-функции (tools): броски, инвентарь, создание сущностей. Это даёт воспроизводимость и экономит токены.

## Возможности

- ✅ Полное создание персонажа D&D 5e (расы, классы, заклинания, предыстория)
- ✅ Поднятие уровня (features, ASI, новые заклинания, subfeatures)
- ✅ Exploration с ЛЛМ-ГМ — описание сцен, броски, проверки навыков
- ✅ Социальные взаимодействия с NPC
- ✅ Торговля
- ✅ Перемещение по комнатам и локациям
- ✅ Сохранение/загрузка (10 слотов)
- ✅ Локализация на русском (английский — частично)
- 🚧 Combat (в разработке)
- 🚧 Автогенерация мира при выходе за известные локации (в разработке)

## Стек

- **UI:** Pygame
- **LLM-агенты:** Pydantic AI с typed-выводом и инструментами
- **Провайдер:** OpenRouter (по умолчанию `google/gemini-3.1-flash-lite-preview`)
- **D&D правила:** внешние пакеты [`dnd-5e-core`](https://github.com/rapotekhin/dnd-5e-core) и [`DnD-5th-Edition-API`](https://github.com/rapotekhin/DnD-5th-Edition-API)
- **Трейсинг:** Logfire (опционально)

## Установка

### 1. Клонировать проект и зависимости

```bash
git clone https://github.com/rapotekhin/dnd_llm.git
cd dnd_llm

# Внешние пакеты — рядом с этим репозиторием
git clone https://github.com/rapotekhin/dnd-5e-core ../dnd-5e-core
git clone https://github.com/rapotekhin/DnD-5th-Edition-API ../DnD-5th-Edition-API
```

### 2. Установить Python-зависимости

```bash
pip install -r requirements.txt

cd ../dnd-5e-core && pip install -e .
cd ../DnD-5th-Edition-API && ./install.bat   # на Windows
# на Linux/macOS — следуйте инструкциям в репозитории
cd ../dnd_llm
```

### 3. Настроить API-ключ

```bash
cp .env.example .env
```

Откройте `.env` и добавьте ключ OpenRouter:

```
OPENROUTER_API_KEY=ваш_ключ
```

Получить ключ: https://openrouter.ai/

### 4. Запустить игру

```bash
python game/main.py
```

## Тесты

Юнит- и интеграционные тесты на [pytest](https://pytest.org/) находятся в каталоге `tests/`. Для импортов нужны репозитории **`dnd-5e-core`** и **`DnD-5th-Edition-API`** рядом с проектом (как в разделе установки), каталог **`game/dnd_5e_data/`** с JSON правил; часть тестов загрузчиков опирается на **`game/assets/ru/*.jsonl`**.

```bash
pip install -r requirements-dev.txt
python -m pytest
```

Покрытие по `game/core` (плагин **`pytest-cov`** ставится вместе с `requirements-dev.txt`):

```bash
python -m pytest --cov=game/core --cov-report=term-missing
```

Если pytest пишет **`unrecognized arguments: --cov=...`**, в активированном venv выполните **`pip install -r requirements-dev.txt`** (или отдельно **`pip install pytest-cov`**).

Конфигурация: `pytest.ini`. Для агентов без реальных вызовов ЛЛМ тесты подставляют фейковые агенты; ключ OpenRouter для прогона тестов не обязателен.

## Переменные окружения

| Переменная | Обязательно | Назначение |
|---|---|---|
| `OPENROUTER_API_KEY` | ✅ | LLM-провайдер |
| `LOGFIRE_TOKEN` | ❌ | Трейсинг ЛЛМ-вызовов через Logfire |
| `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` / `LANGFUSE_HOST` | ❌ | Альтернативный трейсинг через Langfuse |

## Структура проекта

```
dnd_llm/
├── game/             ← основной код игры
│   ├── main.py       ← entry point
│   ├── core/         ← gameplay, ЛЛМ, состояние, сущности
│   ├── ui/           ← Pygame экраны
│   ├── assets/       ← стартовые локации и NPC (JSONL)
│   └── localization/ ← переводы RU/EN
├── docs/             ← документация (см. ниже)
├── scripts/          ← вспомогательные скрипты (например `check_localization.py` — паритет ключей RU/EN)
├── notebooks/        ← Jupyter ноутбуки для отладки
├── tests/            ← pytest: утилиты, загрузчики, торговля, сохранения, моки LLM-циклов
├── pytest.ini
├── requirements.txt
├── requirements-dev.txt  ← pytest, pydantic-ai для импорта агентов в тестах, pytest-cov
└── settings.json     ← пользовательские настройки игры
```

Подробнее об архитектуре — в [docs/tech/architecture.md](docs/tech/architecture.md).

## Документация

В папке [`docs/`](docs/) собрана полная техническая и геймдизайн-документация:

| Раздел | Что внутри |
|---|---|
| [vision/](docs/vision/) | Концепция, столпы проекта |
| [design/](docs/design/) | Геймдизайн, описание систем (exploration, social, trade, combat), UX |
| [narrative/](docs/narrative/) | Мир, NPC, квесты, стиль ГМ |
| [tech/](docs/tech/) | Архитектура, LLM-интеграция, ADR (архитектурные решения) |
| [production/](docs/production/) | Роадмап, техдолг |

Старт — с [docs/README.md](docs/README.md).

## Сохранения

Сохраняются в:
- **Windows:** `%LOCALAPPDATA%\DnD_LLM_Game\saves\save_{1..10}.pkl`
- **Linux/macOS:** `~/.local/share/DnD_LLM_Game/saves/save_{1..10}.pkl`

## Лицензия

MIT
