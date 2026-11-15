# Рисованные карты по маске — эксперимент

Эксперимент 2026-11-14 к [ADR-0018](../../docs/tech/adr/0018-painted-maps-by-mask.md): карта генератора → маска по 32 px на клетку → FLUX и другие модели рисуют готовую карту, клетки и правила остаются за движком. Кадры, маски и листы сравнения лежат локально в `build/mask_maps/` (арт не идёт на GitHub).

```bash
python tools/godot_playtest.py --scenario map_compare
```
Выгружает карты и наш рендер в `build/playtest/map_compare/` (`maps.json`, `ours_<комната>.png`). Комнаты — из `MAP_ROOMS` через запятую, по умолчанию таверна, площадь и опушка. Первую тройку скрипт ждёт в `build/mask_maps/maps_v1.json` (копия `maps.json` того прогона).

```bash
MASK_PALETTE=nat MASK_LOOSE=1 MASK_SMOOTH=1 tools/anima/.venv-matte/Scripts/python.exe tools/mask_maps/mask_maps.py masks
MASK_PALETTE=nat MASK_LOOSE=1 MASK_SMOOTH=1 MASK_SEEDS=7,21 tools/anima/.venv-matte/Scripts/python.exe tools/mask_maps/mask_maps.py draw flux-klein,brod-smithy
```
`masks` строит маски и промпты, `draw` рисует (модели и комнаты через запятую; пусто — все). Цена и время каждого кадра дописываются в `build/mask_maps/costs.jsonl`. Нужен Python с numpy и Pillow (`tools/anima/.venv-matte`) и ключ OpenRouter, как у `tools/anima`.

| Переменная | Что |
|---|---|
| `MASK_PALETTE=nat` | естественные цвета и обводка вещей; без неё — яркие условные цвета первого прогона |
| `MASK_LOOSE=1` | свободный промпт по форме места (`open`, `building`, `tunnels`) |
| `MASK_SMOOTH=1` | края природы искривлены шумом двух масштабов, дороги — только крупным, кроны шире клетки, стены, крыши, полы и грядки чёткие |
| `MASK_SEEDS` | сиды через запятую, по умолчанию 7 |

Сравнение: `overlay.py` (контуры маски поверх кадра, листы второго прогона), `sheet_v3.py` (листы третьего прогона с сеткой клеток), `loose_sheet.py` (строгий и свободный промпт по моделям), `agree.py` (грубая доля клеток, узнанных по цвету — поощряет буквальные цвета маски, позицию не мерит).
