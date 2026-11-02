# contract/ — протокол Godot ↔ LLM-бэкенд

**Статус:** `schema/` — все методы протокола 0.105.0: `session.*`, `turn.*`, `summary.*`, `engine.*`, `image.*` (v0.7.63).

Источник истины для полей сообщений обеих сторон ([ADR-0009](../docs/tech/adr/0009-godot-backend-protocol.md)):

- JSON Schema всех методов (`session.*`, `turn.*`, `summary.*`, `engine.*`, `image.*`) и тел эффектов;
- `PROTOCOL_VERSION` (semver, при рукопожатии сверяется major).

## Правила

- **Схемы не пишутся руками.** Их выгружает `uv run python -m llm_server.contract` из Pydantic-моделей `llm_server/` (`model_json_schema()`). Тест в CI проверяет, что файлы здесь совпадают с моделями.
- Godot по этим схемам не проверяет. Его версия протокола (`backend_client.gd`) сверяется с бэкендом тестом `test_godot_client_speaks_the_same_protocol_version`, а каждое сообщение настоящего хода в обе стороны проверяет по схемам `test_contract_messages.py`.
- Несовместимое изменение — новый major `PROTOCOL_VERSION`; добавление необязательного поля — minor.
