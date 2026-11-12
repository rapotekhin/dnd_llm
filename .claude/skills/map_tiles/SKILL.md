---
name: map_tiles
description: Use this skill when making or changing the map's tileset — grounds (textures under the dual grid) and props (things on a square) drawn by FLUX over OpenRouter with tools/tiles/gen_tiles.py, wired into `grounds` of game/data/layouts.json, and when the map generator must lay a ground so the dual grid draws it well. Trigger on "тайлсет", "тайлы", "нарисуй землю", "текстура карты", "песок / снег / пещера на карте", "дуал-грид", "dual grid", "предмет на клетке", "крыша", "tileset", "tiles", and on edits under tools/tiles/**, game/assets/tiles/**, game/ui/components/map_ground.*, `grounds` of layouts.json. Do NOT use for icons and portraits (that is `anima_art`), for the fight's surfaces of anims.json, or for the master's event images.
---

# map_tiles

Тайлсет карты: земля и предметы, которые рисует FLUX, их место в данных `grounds` и в генераторе карты. Цель — чтобы новая земля появилась в игре, а не осталась картинкой.

Полная картина — [docs/design/tileset.md](../../../docs/design/tileset.md): что нарисовано, что рисуется чужой картинкой, чего нет и что делать дальше. Читай его первым и обновляй последним.

## Когда срабатывать

- «нарисуй песок / снег / скалу», «пещера рисуется кирпичом», «добавь мост на карту»
- новая земля или предмет на клетке, перерисовать неудачный вариант
- карта выглядит пятнистой: одиночные клетки, шов текстуры, повтор
- правки `tools/tiles/**`, `game/assets/tiles/**`, `map_ground.gd` / `.gdshader`, `grounds` в `layouts.json`

**НЕ срабатывает на:**
- иконки, портреты, элементы интерфейса — это `anima_art`
- поверхности боя (масло, огонь, паутина) — `surfaces` в `data/anims.json`
- картинки событий мастера — `llm_server/images.py`

## Как устроено (коротко)

- **Слои.** Символ клетки (`cells`) решает правила. Земля и предмет — только вид, их выбирает `grounds`:
  - `cells` — земля по символу и ключам места: вид (`temple`, `dunes`…), его семья, форма (`open` / `building` / `tunnels`), `*` — самый точный первым (`LayoutGen.ground_keys`);
  - `order` — земли снизу вверх;
  - `sharp` — земли, которые держат клетку (стена, крыша);
  - `props` и `size` — предмет на клетке и его размер;
  - `patches` — пятна другой земли по сиду карты или кайма `near` вокруг символа (пляж), по тем же ключам;
  - `repeat` и `colour` — охват текстуры и цвет земли без картинки.
- **Двойная сетка.** `MapGround` → `map_ground.gdshader`: цвет точки решают 4 клетки вокруг неё, края — маска с шумом. Угловых плиток не рисуем: у земли **одна** бесшовная текстура.
- **Генератор** (`LayoutGen`):
  - земля пятнами — строка `scatter` с `blob: true` (`blobs`, `_despeckle`, `_tidy`);
  - предметы ставятся по одному;
  - здание на открытой карте — стена `#` по краю и крыша `r` внутри. Там, где генератор обходит стену, он обходит и крышу (`_built`).

## Алгоритм: нарисованный край пары земель

1. Пара — строка `grounds.edges` (`low` ниже `high` в `order`, не `sharp`), фраза стыка — `tiles.json` → `edges.<low>__<high>`.
2. `gen_tiles.py draw --only <low>__<high> --variants 2` → `sheet --only …` (лист с сеткой плиток): берег непрерывен через все стыки, тон ровный.
3. `picks.json` → `install --only …` → импорт → `walk` (снимок `shore` вблизи берега).

## Алгоритм: новая земля или предмет

1. **Проверь, нет ли уже.** Смотри таблицы «Что нарисовано» и «Есть в генерации, но рисуется чужой картинкой» в `tileset.md`. Часто нужна не картинка, а строка данных.
2. **Промт** — строка в `tools/tiles/tiles.json`: `ground.<id>` или `props.<id>`. Пиши только то, что в кадре: общий стиль уже лежит в `style`. Для предмета добавь «seen exactly from straight above … no sides, no perspective», иначе FLUX рисует в три четверти.
3. **Нарисовать.** OpenRouter, около $0.009 за кадр. Ключ `OPENROUTER_API_KEY` берётся из `.env` — не печатать.
   ```bash
   python tools/tiles/gen_tiles.py draw --only sand,snow            # 3 варианта; --force — заново
   tools/anima/.venv-matte/Scripts/python.exe tools/tiles/gen_tiles.py matte --only <props>   # предметы
   python tools/tiles/gen_tiles.py sheet --only sand,snow           # build/tiles/sheet_*.png
   ```
   Посмотри листы (Read):
   - земля показана 2×2 — не должно быть ни шва, ни заметного повтора пятна;
   - предмет показан на шахматке — без фона и без обрезков.
4. **Выбрать** вариант в `tools/tiles/picks.json`, затем `python tools/tiles/gen_tiles.py install --only <ids>` — он кладёт и чёткий набор для близкого зума (`ground_hi/`, `props_hi/`); для предмета перед этим нужен `matte`.
5. **Данные** в `game/data/layouts.json` → `grounds`:
   - земля: id в `order` на свою высоту (вода ниже травы, стены и крыши выше всех; не больше 32 земель), цвет в `colour`, где она лежит — в `cells` (по символу и виду места, его семье или форме);
   - ровный край — id в `sharp`;
   - предмет: `props.<символ>.<форма>` и `size`;
   - если земля нужна пятнами — новый символ в `cells` (без `solid`, если она проходима; с `cost`, если трудная) и строка `scatter` вида с `blob: true`, либо `patches` по форме.
6. **Импорт и тесты:**
   ```bash
   "$GODOT" --headless --path game --import
   "$GODOT" --path game --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test/core/test_layout_v080.gd --ignoreHeadlessMode
   ```
   - `test_every_square_has_a_ground_of_the_order_and_every_cell_one_of_its_own` ловит символ без земли и предмет без размера;
   - `test_an_open_maps_grounds_lie_in_patches_with_no_lone_square` ловит одиночные клетки.
7. **Посмотреть глазами:** `python tools/godot_playtest.py --scenario walk` (таверна, площадь, зум) → `build/playtest/walk/*.png`. Для пещеры, леса и других мест — открыть место этого вида (`--preview`, `--room=`).
8. **Обновить** `docs/design/tileset.md`: перенести строку из «рисуется чужим» или «нет» в «нарисовано», поправить «Что сделать дальше».

## Подводные камни

- **Буква клетки** не должна совпадать с буквой метки чанков (`marks`: `R` — кровать и ринг, `H`, `E`, `C`…). Метки читаются раньше клеток, но двусмысленная буква запутает чтение. Поэтому крыша — `r`.
- **Новый сплошной символ** (как крыша): найди места, где генератор сравнивает с `WALL`, и добавь его туда (`_built`). Иначе центр карты вычистится прямо внутри дома или дверь встанет на крышу.
- **После любой правки генератора** — тест «сарай во дворе» (`test_build_grow_v0844427`) и все тесты раскладки. Перед коммитом — полный gdUnit.
- **Изменение разброса меняет вид карт старых сохранений.** Выходы, места и дороги хранятся, а вид пересчитывается из сида. Это нормально, но напиши об этом в релиз-нотах.
- `MapField` не выбирает цвет или картинку по символу. Только данные `grounds` через `LayoutGen.grounds` / `prop_of` — одна дорога, как в AGENTS.md.

## Что НЕ делать

- ❌ Не рисовать края плитками по отдельности и не кадрами по одной плитке: тон поплывёт. Край пары — один лист 4×4 по маске `edge_layout` (`gen_tiles.py draw --only <low>__<high>`), и только там, где маски мало (`tileset.md`).
- ❌ Не брать чужие наборы (itch.io и т.п.) и не кормить их FLUX как образец. Стиль живописный и свой ([art-style.md](../../../docs/design/art-style.md)).
- ❌ Не писать текстуру или цвет земли в код окна — только `grounds`.
- ❌ Не коммитить картинки: `game/assets/tiles/` в `.gitignore`. В git — промты `tiles.json` и выбор `picks.json`, картинки ставит `install` локально.
- ❌ Не оставлять одиночные клетки земли: на двойной сетке это маленькое пятнышко. Пятна — через `blob`.
- ❌ Не гонять тайлы на Forge, не предупредив сессию, которая рисует иконки (`anima_art`).

## Связанные

- [docs/design/tileset.md](../../../docs/design/tileset.md), [art-style.md](../../../docs/design/art-style.md), [godot-client.md](../../../docs/tech/godot-client.md) («Земля карты»), [concepts.md](../../../docs/design/concepts.md) («Земля карты»)
- код: `tools/tiles/gen_tiles.py`, `tools/tiles/tiles.json`, `tools/tiles/picks.json`; `game/core/world/layout_gen.gd` (`grounds`, `prop_of`, `blobs`, `_despeckle`, `_tidy`, `_wall_box`, `_built`); `game/ui/components/map_ground.gd`, `map_ground.gdshader`
- скилл `anima_art`: предметы вырезает его `matte.py`, FLUX вызывается через `anima_gen.openrouter_frame`
