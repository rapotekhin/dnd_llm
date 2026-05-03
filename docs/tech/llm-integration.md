# LLM Integration

Самая важная техническая часть проекта. Здесь описано, как ЛЛМ встроен в игру.

## Главный принцип

> **ЛЛМ — Мастер Подземелий, не движок.**  
> См. [vision/pillars.md](../vision/pillars.md) принцип №1 и [adr/0001-llm-as-gm-not-engine.md](adr/0001-llm-as-gm-not-engine.md).

ЛЛМ не хранит состояние мира. Все изменения — через **инструменты (tools)** — Python-функции, которые ЛЛМ вызывает.

## Стек

| Компонент | Что делает |
|---|---|
| **Pydantic AI** | Основной фреймворк для LLM-агентов с typed-выводом и tools |
| **OpenRouter** | Провайдер моделей (дефолт: `google/gemini-3.1-flash-lite-preview`) |
| **Pydantic** | Схемы структурированного вывода |
| **Logfire** | Трейсинг (опционально, по `LOGFIRE_TOKEN`) |
| **LangChain** | Легаси, остался в `APIManager.generate_with_format`. Выпиливается. |

## APIManager

`game/core/llm_engine/api_manager.py` — единая точка входа к ЛЛМ.

Главные методы:
- `get_pydantic_ai_model()` — даёт модель для Pydantic AI агентов
- `validate_key()` — проверяет ключ OpenRouter, читает баланс
- `generate_with_format(prompt, schema)` — **легаси через LangChain**, используется кое-где, постепенно мигрируется

Дефолтная модель — в коде (хардкод). См. список закомментированных альтернатив в файле.

## Pydantic AI агенты

Каждый режим игры строит **несколько агентов**, каждый с своей output-схемой. Пример из `exploration.py`:

```python
def _build_resolution_agent(api_manager, game_state):
    model = api_manager.get_pydantic_ai_model()
    agent = Agent(
        model,
        deps_type=MainGameState,
        output_type=AgentResolutionOutput,
        instructions=(
            get_exploration_system_prompt(game_state)
            + "\n\n"
            + AGENT_RESOLUTION_INSTRUCTIONS
        ),
    )
    @agent.tool_plain
    def roll_dice(...) -> dict: ...
    
    @agent.tool_plain
    def rule_db_lookup(...) -> str: ...
    
    return agent
```

### Агенты по режимам

**Exploration** (3 агента):
- `describe_agent` → `SceneDescription` — описание сцены при входе
- `generate_actions_agent` → `ActionList` — варианты действий
- `resolution_agent` → `AgentResolutionOutput` — разрешение выбора

Дополнительно: `summary_agent` → `LocationSummary` — обновление `location_history_summary` при выходе из локации.

**Social** — аналогично, агенты для greeting / response options / resolution / summary.

**Trade** — преимущественно механический режим, ЛЛМ только для реплик NPC.

## Инструменты (Tools)

Сейчас два:

### `RollDiceTool` (`game/core/tools/roll.py`)

```python
roll_dice(
    expression: str,             # "1d20+3", "2d6+2"
    has_advantage: bool = False,
    has_disadvantage: bool = False,
    difficulty_class: Optional[int] = None,
)
```

**Важно:** ЛЛМ обязан передавать `expression` в нотации кубиков, не «wisdom check». Это явно прописано в промпте — ЛЛМы путаются регулярно.

### `RuleDbLookupTool` (`game/core/tools/db_lookup.py`)

Обращение к базе правил D&D 5e (через `dnd-5e-core`).

### Что нужно (план)

Для столпа №1 (ЛЛМ как ГМ) нужно расширить набор инструментов:

- `create_npc(...)` — для автогенерации NPC при встрече нового персонажа
- `create_location(...)` — для расширения мира
- `create_quest(...)` — для динамических квестов
- `apply_damage(target_id, amount, damage_type)` — для боя
- `add_item_to_inventory(actor_id, item_id, count)`
- `set_condition(actor_id, condition, duration)` — отравлен, оглушён и т.п.

Сейчас ничего из этого нет. Главный пункт техдолга.

## Промпты

Все системные промпты — в `game/core/prompts/`:

- `exploration_prompts.py` — самый большой
- `social_prompts.py`
- `npc_creation_prompts.py` — для будущей автогенерации
- `location_creation_prompts.py` — то же
- `qwest_creation_prompts.py` — для квестов (опечатка в имени → техдолг)

### Структура системного промпта (exploration)

```
[Роль и задача]
[Правила использования tools]
[Контекст персонажа]      ← из game_state.player
[Контекст локации]         ← из current_location
[Контекст комнаты]         ← из current_room
[Связанные комнаты с ID]   ← важно для переходов
[NPC в комнате с ID]       ← важно для social/trade
[Сокровища]
[Открытые/скрытые квесты]
[location_history_summary] ← главный механизм экономии токенов
[Правила поведения]
```

### Контекст-пейлоад

ЛЛМ всегда получает **полный** профиль персонажа и локации в системном промпте. Это много токенов, но необходимо: ЛЛМ должен знать, на что игрок способен.

**Что НЕ передаём:**
- Полную историю всех действий — заменена `location_history_summary`
- Содержимое других локаций — только текущая
- Детали других NPC — только из текущей комнаты

## Структурированный вывод

**Все LLM-ответы строго типизированы.** Свободного текста с парсингом стараемся избегать.

Pydantic-схемы — в `game/core/gameplay/schemas/`. Главные:

- `SceneDescription`, `ActionList`, `ActionOption` — простые
- `AgentResolutionOutput` — главный вывод exploration с `narration`, `action`, `question_to_player`, `metadata`
- `ActionMetadata` — `npc_id` или `room_id` для переходов

**Fallback:** `_parse_agent_resolution_output()` в `exploration.py` — парсер на случай, если Pydantic AI вернул невалидный JSON. Поддерживает текстовый формат с маркерами `НАРРАЦИЯ:`, `ДЕЙСТВИЕ:`, `ВОПРОС_ИГРОКУ:`.

## Экономия токенов (важно)

Способы снизить расход:

1. **`location_history_summary`** — вместо накопления полной истории
2. **Очистка `state["history"]`** при возврате из social/trade — события до side-session уже в саммари
3. **Дешёвая модель по умолчанию** (Gemini Flash Lite)
4. **`temperature=0.35`** — детерминистичнее, меньше «ретраев»
5. **Структурированный вывод** — нет токенов на свободный текст-обёртку

## Трейсинг

- **Logfire** — текущая система. Включается при наличии `LOGFIRE_TOKEN` в `.env`. Используется через `logfire.span()` для exploration / social / trade.
- **Langfuse** — был раньше, частично остался в `APIManager`. Возможно вернуться (см. [production/backlog.md](../production/backlog.md)).

## Тестирование без UI

В конце `exploration.py` есть консольный режим (`if __name__ == "__main__"`):

```bash
python game/core/gameplay/exploration.py
```

Это запустит exploration с консольным «UI», читая save_1.pkl. Полезно для отладки промптов.

## Известные проблемы

- **Галлюцинации NPC** — ЛЛМ может упомянуть NPC, которого нет в комнате, как будто он есть
- **Игнорирование metadata** — иногда ЛЛМ возвращает `action: "social"` без `npc_id`
- **Длина наррации** — ЛЛМ склонен к многословию; правила в промпте не всегда срабатывают
- **Несоблюдение нотации кубиков** — несмотря на явное указание, ЛЛМ изредка передаёт «Perception check» вместо `1d20+X`
