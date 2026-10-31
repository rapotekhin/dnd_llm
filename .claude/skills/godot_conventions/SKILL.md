---
name: godot_conventions
description: Use this skill when writing or modifying GDScript (.gd), scenes (.tscn), autoloads, game/data/*.json or game/localization/strings.csv in the Between the Rolls Godot client (game/). Trigger on tasks like "добавь экран", "сделай окно", "реализуй механику в Godot", "напиши тест gdUnit", "add a screen", "implement X in Godot", or any edit under game/. Ensures pure core/ without nodes, data-driven JSON, tr() keys for player text, EventBus navigation, static typing, save migrations and tests. Do NOT use for llm_server/ (Python) or docs-only changes.
---

# Godot Conventions — Between the Rolls

Держит код `game/` единообразным: архитектура и правила — в [docs/tech/godot-client.md](../../../docs/tech/godot-client.md), образец — `C:\Code\hive_world_shop`.

## Когда срабатывать

- Любая правка `game/**/*.gd`, `*.tscn`, `project.godot`
- Новые данные в `game/data/*.json`, строки в `game/localization/strings.csv`

**НЕ срабатывает на:** `llm_server/`, `contract/`, только `docs/`.

## Алгоритм работы

1. **Прочитай** [godot-client.md](../../../docs/tech/godot-client.md) и дизайн системы в `docs/design/systems/` (через `docs_lookup`). Для правил 5e — [ADR-0008](../../../docs/tech/adr/0008-engine-decides-llm-narrates.md): движок решает, ЛЛМ описывает.
2. **Выбери слой:**
   - правило, формула, состояние → `game/core/<домен>/` (`RefCounted`, без нод)
   - отображение и ввод → `game/ui/` (экраны и окна — сцены `.tscn`, скрипт только заполняет их; строки списков — кодом; [ADR-0013](../../../docs/tech/adr/0013-ui-in-scenes.md))
   - глобальное → `game/autoload/`
   - числа и контент → `game/data/*.json` или SRD-данные, не код
3. **Напиши код**, пройди чеклист.
4. **Проверь:** импорт без ошибок, gdUnit4 зелёный, живой сценарий (`python tools/godot_playtest.py`) — команды в [godot-client.md](../../../docs/tech/godot-client.md#тесты-и-живая-проверка). Подробности живой проверки — скилл `playtest`.
5. **Вызови `docs_updater`**, если поменялось документированное поведение.

## Чеклист

- [ ] Статическая типизация: `var x: int`, `func f(a: GameSession) -> void`, `Array[String]`, `Dictionary[String, int]`
- [ ] Файлы `snake_case.gd`, `class_name PascalCase`, сигналы в прошедшем времени (`turn_finished`)
- [ ] `core/` не трогает `Node`, `get_tree()`, autoload-ы и `tr()`: возвращает ключи, UI переводит
- [ ] Случайность — только через переданный `RandomNumberGenerator` (RNG сессии), никаких `randi()` в `core/`
- [ ] Состояние `core/` — `to_dict()` / `static func from_dict()`; целые из JSON приводятся `int()`
- [ ] Формат сейва изменился → `SaveFormat.SAVE_VERSION` + шаг в `MIGRATIONS` + фикстура `test/fixtures/saves/save_v<N>.json`
- [ ] Текст игрока — ключ в `text` или `tr("KEY")`, ключ добавлен в `strings.csv`; текст модели и игрока — с `auto_translate_mode = DISABLED`
- [ ] Экраны не знают друг о друге: переходы через `EventBus.navigate`, вход в игру через `GameEntry`
- [ ] Подписки экранов на `EventBus` — методами, не лямбдами (экраны пересоздаются, шина живёт всегда)
- [ ] Цвета и шрифты — варианты темы `ui/theme/game_theme.tres`, в коде — имена и цвета из `UiTheme`, не по месту
- [ ] Новая сцена: `required()` со всеми нужными узлами, узлы через `UiScenes.need`, открытие через `UiScenes.open`, примерные строки в группе `editor_sample`, имена узлов для плейтестов сохранены; окно наследует `modal_frame.tscn`, его `_ready` начинается с `super()`
- [ ] d20 — `Roll`, значение → ступень — `Scale`, монеты и долги — `Ledger`, цена — `Price`, действие со временем — строка в `TimeRules.registry()`; `until` — абсолютная минута
- [ ] Реакция на поступок героя — строка в `WorldEvent.registry()`, изменение записи пакета — `Overlay.put`, «где» — `Where`; ссылки — `EntityRef`
- [ ] Новое правило в `core/` — тест в `game/test/`; все наборы gdUnit4 зелёные
- [ ] Никакого токена в логах, снимках, `describe()` и аргументах командной строки
- [ ] Комментарии короткие, только «почему»

## Что НЕ делать

- ❌ Не класть игровую логику в экран — только отображение и команды `GameState`
- ❌ Не применять эффекты из ответа модели напрямую — только через резервы хода ([ADR-0009 §5](../../../docs/tech/adr/0009-godot-backend-protocol.md))
- ❌ Не хардкодить русские строки в UI и числа баланса в коде
- ❌ Не упоминать классы UI в сценариях `game/tools/playtest/` — сравнивать через `screen_is()`
- ❌ Не запускать сценарии без `--profile=agent` — они чистят сейвы профиля
- ❌ Не править `game/addons/gdUnit4/` и не коммитить `*.translation`, `game/.godot/`, `build/`

## Связанные

- [docs/tech/godot-client.md](../../../docs/tech/godot-client.md), [connectivity-spike.md](../../../docs/tech/connectivity-spike.md)
- ADR: [0007](../../../docs/tech/adr/0007-godot-client-python-llm-backend.md), [0008](../../../docs/tech/adr/0008-engine-decides-llm-narrates.md), [0009](../../../docs/tech/adr/0009-godot-backend-protocol.md), [0010](../../../docs/tech/adr/0010-game-decisions-worlds-tone-combat-death.md)
- Скиллы: `playtest`, `docs_updater`, `release_notes_updater`
