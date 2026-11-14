# Architecture Decision Records

ADR — это короткая запись о **значимом архитектурном решении**: что было решено, почему, какие альтернативы рассматривались.

## Зачем

Через год никто (включая автора) не помнит, **почему** выбран Pickle, а не SQLite. ADR отвечает на этот вопрос.

## Формат

```markdown
# ADR-NNNN: Заголовок

**Дата:** YYYY-MM-DD  
**Статус:** Accepted | Superseded by ADR-XXXX | Deprecated

## Контекст
Что мы решали и почему это вообще проблема.

## Решение
Что решили сделать.

## Альтернативы
Что ещё рассматривали и почему отвергли.

## Последствия
Хорошие и плохие. Что станет проблемой потом.
```

## Текущие ADR

- [0001-llm-as-gm-not-engine.md](0001-llm-as-gm-not-engine.md) — ЛЛМ играет ГМ, состояние мира — в коде
- [0002-pickle-saves.md](0002-pickle-saves.md) — Pickle для сохранений (заменено, сейвы теперь JSON)
- [0003-pydantic-ai-over-langchain.md](0003-pydantic-ai-over-langchain.md) — Pydantic AI основной; LangChain оставлен в APIManager как техдолг (на момент записи)
- [0004-pygame-prototype.md](0004-pygame-prototype.md) — Pygame для прототипа, возможен переезд на Godot (заменён ADR-0007)
- [0005-langchain-and-streamlit-removal.md](0005-langchain-and-streamlit-removal.md) — удаление LangChain из APIManager, каталога `app/`, зависимости LangGraph
- [0006-exploration-side-session-summary.md](0006-exploration-side-session-summary.md) — возврат из side-сессии (social/trade/combat) в exploration через явную синхронную суммаризацию (заменено, относится к прототипу)
- [0007-godot-client-python-llm-backend.md](0007-godot-client-python-llm-backend.md) — игра на Godot, ЛЛМ-логика в Python-бэкенде (WebSocket + JSON-RPC, правила 5e только в движке)
- [0008-engine-decides-llm-narrates.md](0008-engine-decides-llm-narrates.md) — движок решает, ЛЛМ описывает: проверки, эффекты, бюджеты, генерация предметов
- [0009-godot-backend-protocol.md](0009-godot-backend-protocol.md) — протокол Godot ↔ бэкенд: подключение, методы, транзакция хода, ошибки, кассеты
- [0010-game-decisions-worlds-tone-combat-death.md](0010-game-decisions-worlds-tone-combat-death.md) — игровые решения: вселенные-пакеты, свой регион, стиль ГМ, зоны в бою, режимы смерти
- [0011-default-master-model.md](0011-default-master-model.md) — модель мастера по умолчанию Claude Haiku 5.5: сравнение с Qwen 3.8 Omni Flash, Qwen 3.8 27B и Gemini 3.8 Flash на «золотых» сценариях
- [0012-unified-models.md](0012-unified-models.md) — единые модели: одна запись с частями вместо хранилищ и классов, шаблоны в данных, сейвы этапа не переносим
- [0014-embedded-master-server.md](0014-embedded-master-server.md) — сервер мастера запускается вместе с игрой: `server.exe` на `127.0.0.1`, ключ игрока, порт и токен на один запуск
- [0015-faction-budgets-and-world-simulation.md](0015-faction-budgets-and-world-simulation.md) — бюджеты фракций ограничивают создание мира; после долгого отдыха фоновый день мира: агенты фракций, суммаризатор, исходы по функциям движка (M6)
- [0013-ui-in-scenes.md](0013-ui-in-scenes.md) — интерфейс в сценах Godot: экраны и окна правятся в редакторе, тема `.tres`, базовое окно
- [0016-one-road-for-every-character.md](0016-one-road-for-every-character.md) — одна дорога для любого персонажа: что может игрок, может любой NPC и монстр
- [0017-own-size-on-next-frame.md](0017-own-size-on-next-frame.md) — элемент, который сам подгоняет свой размер, ставит его на следующем кадре: падение Godot в конце боя (v0.8.4.43.53)
