# contract/ — протокол Godot ↔ LLM-бэкенд

**Статус:** `schema/` — все методы протокола 0.2.0: `session.*`, `turn.*`, `summary.*`, `engine.*` (v0.4.1).

Источник истины для полей сообщений обеих сторон ([ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)):

- JSON Schema всех методов (`session.*`, `turn.*`, `summary.*`, `engine.*`) и тел эффектов;
- `PROTOCOL_VERSION` (semver, при рукопожатии сверяется major).

## Правила

- **Схемы не пишутся руками.** Их выгружает `uv run python -m llm_server.contract` из Pydantic-моделей `llm_server/` (`model_json_schema()`). Тест в CI проверяет, что файлы здесь совпадают с моделями.
- Godot проверяет входящие сообщения по этим схемам в отладке и тестах.
- Несовместимое изменение — новый major `PROTOCOL_VERSION`; добавление необязательного поля — minor.
