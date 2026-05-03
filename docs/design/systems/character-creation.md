# Character Creation

Создание персонажа D&D 5e — самый объёмный сценарий в UI: класс `CharacterCreationScreen` и связанные виджеты живут в подпакете [`game/ui/screens/character_creation/`](../../../game/ui/screens/character_creation/); для стабильных импортов класс по-прежнему доступен как `game.ui.screens.character_creation_screen`.

## Этапы

Пошаговый wizard:

1. **Базовое** — имя, пол, мировоззрение
2. **Раса** — выбор расы и подрасы (если есть)
3. **Класс** — выбор класса
4. **Характеристики** — 6 D&D ability scores (раздача очков / стандартный массив / случайные)
5. **Навыки и владения** — выбор из доступных по классу/расе
6. **Предыстория (Background)** — биография, идеалы, привязанности, изъяны
7. **Заклинания** (если класс заклинатель) — выбор фокусов и заклинаний 1-го уровня
8. **Снаряжение** — стартовый инвентарь по классу
9. **Подтверждение** — итоговая карточка и кнопка «Начать игру»

После подтверждения экран возвращает объект `Character` в `Game._handle_screen_result()`, который становится `game_state.player`.

## Источник правил

Раса/класс/заклинания/предметы — из внешнего пакета **`dnd-5e-core`** (отдельный репозиторий).  
Локальный код только собирает выбор пользователя в финальный `Character`.

Сборка идёт через `core/builders/character_builder.py`.

## Случайная генерация

Есть быстрая опция «случайный персонаж» — `Character.create_random_character()` использует `simple_character_generator` из `dnd_5e_core`.

## Что хранится в `Character` сверх `dnd_5e_core.Character`

Основные дополнения (`game/core/entities/character.py`):
- `alignment` — мировоззрение
- `background` — предыстория
- `coins` — монеты (в copper, см. trade)
- `damage_vulnerabilities/resistances/immunities`
- `condition_advantages/immunities`
- `senses` — darkvision и т.п.
- `features` — список индексов выбранных способностей (включая subfeatures)
- `class_specific` — счётчики типа `action_surges`, `sorcery_points`

## Известные проблемы

- **Локализация EN** — данные классов/рас на английском, перевод неполный. Техдолг.
