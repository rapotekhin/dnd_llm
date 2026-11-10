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

Пока файла по id нет, показывается заготовка вида `_blank/<вид>.png` (`_blank/default.png` — для неизвестного вида). Заменить иконку — положить свой PNG с тем же именем.

Иконки рисует Anima на своём Forge: [tools/anima/](../../../tools/anima/README.md). Заготовки — `python tools/anima/make_blanks.py`.
