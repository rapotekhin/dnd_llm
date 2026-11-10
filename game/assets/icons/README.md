# Иконки

Иконка чего-то в игре (вещи, заклинания, умения класса, черты расы, состояния, действия боя, группы инвентаря) — файл `<вид>/<id>.png`, 128×128, прозрачный фон:

| Вид | Папка | id из |
|---|---|---|
| вещи | `items/` | `data/items.json` → `catalog` |
| заклинания | `spells/` | `data/srd/spells.json` |
| умения классов | `features/` | `data/srd/classes.json` → `features` |
| черты рас | `traits/` | `data/srd/races.json` → `traits` |
| состояния | `conditions/` | `data/rules.json` → `condition_effects` |
| действия боя | `acts/` | `core/acts/<id>.gd` |
| группы инвентаря | `groups/` | `data/rules.json` → `item_rules.groups.rows` |
| интерфейс: кнопки окон, нужды, дела места, отбор панели действий | `ui/` | `data/icons.json` → `ui` (значение — что нарисовать) |
| знаки поверх иконки: стихия, материал, форма заклинания | `marks/<elements, materials, shapes>/` | `data/icons.json`; без файла знак — цветная точка |

Иконку выбирает одно место — `IconRules.of` (`game/core/rules/icon_rules.gd`); `data/icons.json → shared` даёт один файл нескольким id. Пока файла по id нет, сделанная или магическая вещь берёт иконку своей простой основы (`ItemRules.plain_of`: грозовой длинный меч — длинный меч) со знаками стихии и материала и рамкой редкости, потом иконку своей группы; заклинание — заготовку в цвете своей школы со знаками урона и формы; остальное — `_blank/<вид>.png` (`_blank/default.png` — для неизвестного вида). Заменить иконку — положить свой PNG с тем же именем.

Иконки рисует Anima на своём Forge: [tools/anima/](../../../tools/anima/README.md). Заготовки — `python tools/anima/make_blanks.py`.
