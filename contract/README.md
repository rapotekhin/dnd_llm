# contract/ — протокол Godot ↔ LLM-бэкенд

**Статус:** схемы появятся в v0.4.1 ([roadmap](../docs/production/roadmap.md)).

Источник истины для полей сообщений обеих сторон ([ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)):

- JSON Schema всех методов (`session.*`, `turn.*`, `summary.*`, `engine.*`) и тел эффектов;
- `PROTOCOL_VERSION` (semver, при рукопожатии сверяется major).

## Правила

- **Схемы не пишутся руками.** Их выгружает скрипт из Pydantic-моделей `llm_server/` (`model_json_schema()`). CI проверяет, что файлы здесь совпадают с моделями.
- Godot проверяет входящие сообщения по этим схемам в отладке и тестах.
- Несовместимое изменение — новый major `PROTOCOL_VERSION`; добавление необязательного поля — minor.
