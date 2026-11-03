"""The author's test checklist: every item, monster, ability, spell and defense of the game with its dev console command.

One .xlsx with a sheet per kind (ordinary items, magic items, monsters, abilities, spells, resistances and immunities);
each row has the command to put it into the game (the dev console, `--dev` or «Режим разработчика»: docs/tech/godot-client.md
«Отладка») and the author's columns: проверено, есть баг, исправлено, комментарий. Run again after the data changes:
the marks and comments already in the file stay with their rows (by the sheet and the id).

    uv run --with openpyxl python tools/checklist.py            # → docs/checklist/test-checklist.xlsx
    uv run --with openpyxl python tools/checklist.py --out x.xlsx --world frontier
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "game" / "data"
OUT = ROOT / "docs" / "checklist" / "test-checklist.xlsx"

# The author's columns, the same on every sheet, at its end.
MARKS = ["Проверено", "Есть баг", "Исправлено", "Комментарий"]
FLAGS = MARKS[:3]
# Magic by its kind: what is not plain gear even when its rarity is common (a potion, a wand, a wondrous thing).
MAGIC_TYPES = {"wondrous"}
DICE = str.maketrans({"d": "к"})
# Words of the data in Russian for the sheet: an item's kind, a weapon's category and range, an armour's category.
WORDS = {"gear": "снаряжение", "weapon": "оружие", "armor": "доспех", "consumable": "расходник", "wondrous": "чудесный",
         "treasure": "сокровище", "quest": "квест", "simple": "простое", "martial": "воинское", "melee": "ближнее",
         "ranged": "дальнобойное", "light": "лёгкий", "medium": "средний", "heavy": "тяжёлый", "shield": "щит"}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def ru_dice(text: str) -> str:
    return str(text).translate(DICE)


def ru(word: object) -> str:
    return WORDS.get(str(word), str(word))


class Data:
    """What the game loads for a pack: the SRD, the item catalog with the pack's own things, the rules."""

    def __init__(self, world: str) -> None:
        srd = DATA / "srd"
        self.monsters = load(srd / "monsters.json")
        self.spells = load(srd / "spells.json")
        classes = load(srd / "classes.json")
        self.classes = classes["classes"]
        self.subclasses = classes["subclasses"]
        self.features = classes["features"]
        races = load(srd / "races.json")
        self.races = races["races"]
        self.traits = races["traits"]
        self.misc = load(srd / "misc.json")
        self.rules = load(DATA / "rules.json")
        pack = load(DATA / "worlds" / world / "pack.json")
        own = load(DATA / "worlds" / world / "world.json").get("items", {})
        catalog = load(DATA / "items.json")["catalog"]
        for gone in pack.get("rules", {}).get("items_exclude", []):
            catalog.pop(gone, None)
        self.items = {k: dict(v, source="SRD") for k, v in catalog.items()}
        self.items.update({k: dict(v, source="пакет " + world) for k, v in own.items()})  # WorldPack.apply_rules
        self.damage = self.misc["damage_types"]

    def item_name(self, item_id: str) -> str:
        return str(self.items.get(item_id, {}).get("name", item_id))

    def spell_name(self, spell_id: str) -> str:
        return str(self.spells[spell_id]["name"]) if spell_id in self.spells else f"{spell_id} (нет в игре)"

    def condition_name(self, cond: str) -> str:
        own = self.rules.get("condition_effects", {}).get(cond, {})
        return str(own.get("name", str(self.rules["conditions"].get(cond, cond)).split(":")[0]))

    def damage_name(self, dtype: str) -> str:
        return str(self.damage.get(dtype, dtype))


def is_magic(d: dict) -> bool:
    use = d.get("use")
    return (d.get("rarity", "common") != "common" or bool(d.get("attunement")) or bool(d.get("charges"))
            or bool(d.get("caster")) or d.get("item_type") in MAGIC_TYPES
            or (isinstance(use, dict) and bool(use.get("spell"))))


def item_text(d: dict, data: "Data") -> str:
    """Its description, or what its numbers say when it has none (a weapon, an armour)."""
    if d.get("description"):
        return str(d["description"])
    parts: list[str] = []
    w = d.get("weapon")
    if isinstance(w, dict):
        line = f"оружие {ru(w.get('category', ''))}, {ru(w.get('range', ''))}: {ru_dice(w.get('damage', ''))} {data.damage_name(w.get('damage_type', ''))}"
        if w.get("versatile"):
            line += f", двумя руками {ru_dice(w['versatile'])}"
        parts.append(line)
    a = d.get("armor")
    if isinstance(a, dict):
        line = f"доспех {ru(a.get('category', ''))}: КД {a.get('base', '')}"
        if a.get("dex"):
            line += " + Лов" + (f" (не больше {a['max_dex']})" if a.get("max_dex") is not None else "")
        if a.get("str_min"):
            line += f", Сил {a['str_min']}"
        if a.get("stealth_disadvantage"):
            line += ", помеха Скрытности"
        parts.append(line)
    if d.get("properties"):
        parts.append("свойства: " + ", ".join(map(str, d["properties"])))
    if isinstance(d.get("use"), dict):
        parts.append("использование: " + json.dumps(d["use"], ensure_ascii=False))
    return "; ".join(parts)


# --- the sheets: (title, columns, rows); a row is {"id": …, column: value} -----------------------------------------


def items_sheet(data: Data, magic: bool) -> tuple[str, list[str], list[dict]]:
    cols = ["Предмет", "id", "Команда", "Тип"] + (["Редкость", "Настройка"] if magic else []) + ["Цена, зм", "Источник", "Описание"]
    rows = []
    for item_id, d in sorted(data.items.items(), key=lambda kv: str(kv[1].get("name", kv[0]))):
        if is_magic(d) != magic:
            continue
        row = {"id": item_id, "Предмет": d.get("name", item_id), "Команда": f"give {item_id}", "Тип": ru(d.get("item_type", "")),
               "Цена, зм": round(int(d.get("value_cp", 0)) / 100, 2), "Источник": d["source"], "Описание": item_text(d, data)}
        if magic:
            row["Редкость"] = d.get("rarity", "common")
            row["Настройка"] = "да" if d.get("attunement") else ""
        rows.append(row)
    return ("Магические предметы" if magic else "Обычные предметы"), cols, rows


def monster_abilities(data: Data, m: dict) -> str:
    out: list[str] = []
    for t in m.get("traits", []):
        if t.get("id") != "spellcasting":
            out.append(f"черта: {t.get('name', t.get('id', ''))}")
    if m.get("multiattack"):
        out.append("мультиатака: " + ", ".join(str(x.get("name", x)) if isinstance(x, dict) else str(x) for x in m["multiattack"]))
    for a in m.get("actions", []):
        dmg = ", ".join(f"{ru_dice(x.get('dice', ''))} {data.damage_name(x.get('type', ''))}" for x in a.get("damage", []))
        extra = []
        if a.get("recharge"):
            extra.append(f"перезарядка {a['recharge']}")
        if a.get("save"):
            extra.append("спасбросок " + json.dumps(a["save"], ensure_ascii=False))
        out.append(f"{a.get('name', a.get('name_en', ''))}{' (' + dmg + ')' if dmg else ''}{' · ' + ', '.join(extra) if extra else ''}")
    for r in m.get("reactions", []):
        out.append(f"реакция: {r.get('name', r.get('name_en', ''))}")
    return "\n".join(out)


def monster_spells(data: Data, m: dict) -> str:
    sc = m.get("spellcasting")
    if not isinstance(sc, dict):
        return ""
    by_level: dict[int, list[str]] = {}
    for sp in sc.get("spells", []):
        sid = sp.get("id", "") if isinstance(sp, dict) else str(sp)
        by_level.setdefault(int(sp.get("level", data.spells.get(sid, {}).get("level", 0))) if isinstance(sp, dict) else 0, []).append(data.spell_name(sid))
    head = f"Сл {sc.get('dc', '')}, атака +{sc.get('attack', '')}"
    lines = [head] + [f"{'заговоры' if lv == 0 else f'{lv} круг'}: {', '.join(names)}" for lv, names in sorted(by_level.items())]
    return "\n".join(lines)


def monster_defenses(data: Data, m: dict) -> str:
    out = []
    for key, word in (("resistances", "сопротивление"), ("immunities", "иммунитет"), ("vulnerabilities", "уязвимость")):
        if m.get(key):
            out.append(f"{word}: {', '.join(map(str, m[key]))}")
    if m.get("condition_immunities"):
        out.append("иммунитет к состояниям: " + ", ".join(data.condition_name(str(c)) for c in m["condition_immunities"]))
    return "\n".join(out)


def monsters_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    cols = ["Монстр", "id", "Команда", "Союзник", "ПО", "КД", "Хиты", "Способности", "Заклинания", "Инвентарь", "Защиты"]
    kit = data.rules.get("creatures", {}).get("kit", {})
    rows = []
    for mid, m in sorted(data.monsters.items(), key=lambda kv: (float(kv[1].get("cr", 0)), str(kv[1].get("name", kv[0])))):
        gear = list(m.get("equipment", [])) + list(kit.get(mid, []))
        rows.append({"id": mid, "Монстр": m.get("name", mid), "Команда": f"spawn {mid}", "Союзник": f"spawn {mid} 1 ally",
                     "ПО": m.get("cr", ""), "КД": m.get("ac", ""), "Хиты": m.get("hp", ""), "Способности": monster_abilities(data, m),
                     "Заклинания": monster_spells(data, m), "Инвентарь": ", ".join(data.item_name(i) for i in gear),
                     "Защиты": monster_defenses(data, m)})
    return "Монстры", cols, rows


def abilities_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    cols = ["Способность", "id", "Команда", "На юнита", "Чья", "Уровень", "Действие в бою", "Описание"]
    acts: dict[str, list[str]] = {}
    for act_id, a in data.rules.get("feature_actions", {}).items():
        if isinstance(a, dict):
            for f in a.get("features", [a.get("feature")]):
                if f:
                    acts.setdefault(str(f), []).append(str(a.get("name", act_id)))
    rows = []
    for fid, f in sorted(data.features.items(), key=lambda kv: (str(kv[1].get("class", "")), int(kv[1].get("level", 0)), str(kv[1].get("name", "")))):
        whose = data.classes.get(str(f.get("class", "")), {}).get("name", f.get("class", ""))
        if f.get("subclass"):
            whose = f"{whose} · {data.subclasses.get(str(f['subclass']), {}).get('name', f['subclass'])}"
        rows.append({"id": fid, "Способность": f.get("name", fid), "Команда": f"feature {fid}", "На юнита": f"@<цель> feature {fid}",
                     "Чья": whose, "Уровень": f.get("level", ""), "Действие в бою": ", ".join(acts.get(fid, [])), "Описание": f.get("desc", "")})
    for tid, t in sorted(data.traits.items(), key=lambda kv: str(kv[1].get("name", kv[0]))):
        races = [r.get("name", rid) for rid, r in data.races.items() if tid in r.get("traits", [])]
        rows.append({"id": "trait:" + tid, "Способность": t.get("name", tid), "Команда": f"trait {tid}", "На юнита": f"@<цель> trait {tid}",
                     "Чья": "раса: " + ", ".join(races) if races else "черта", "Уровень": "", "Действие в бою": ", ".join(acts.get(tid, [])),
                     "Описание": t.get("desc", "")})
    return "Способности", cols, rows


def spells_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    cols = ["Заклинание", "id", "Команда", "Классы", "Круг", "Школа", "Время", "Дистанция", "Длительность", "Концентрация", "Описание"]
    rows = []
    for sid, sp in sorted(data.spells.items(), key=lambda kv: (int(kv[1].get("level", 0)), str(kv[1].get("name", kv[0])))):
        classes = [data.classes.get(c, {}).get("name", c) for c in sp.get("classes", [])]
        subs = [data.subclasses.get(c, {}).get("name", c) for c in sp.get("subclasses", [])]
        rows.append({"id": sid, "Заклинание": sp.get("name", sid), "Команда": f"spell {sid}",
                     "Классы": ", ".join(classes) + (" · подклассы: " + ", ".join(subs) if subs else ""),
                     "Круг": "заговор" if int(sp.get("level", 0)) == 0 else int(sp["level"]), "Школа": sp.get("school", ""),
                     "Время": sp.get("casting_time", ""), "Дистанция": sp.get("range", ""), "Длительность": sp.get("duration", ""),
                     "Концентрация": "да" if sp.get("concentration") else "", "Описание": sp.get("desc", "")})
    return "Заклинания", cols, rows


def defenses_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    """A row per damage type and defense, then per condition immunity: the commands and who has it by the data."""
    cols = ["Защита", "id", "Герою", "Юниту", "Монстры с ней", "Вещи с ней", "Черты рас"]
    he = data.rules.get("hero_effects", {})
    by_item: dict[str, str] = he.get("item_resist", {})
    by_trait: dict = he.get("trait_resist", {})
    rows = []
    for kind, key, word in (("resist", "resistances", "сопротивление"), ("immune", "immunities", "иммунитет"), ("vulnerable", "vulnerabilities", "уязвимость")):
        for dtype in data.damage:
            mons = [m.get("name", mid) for mid, m in data.monsters.items() if any(dtype in str(x).lower() for x in m.get(key, []))]
            things, races = [], []
            if kind == "resist":
                props = [p for p, t in by_item.items() if t == dtype]
                things = [d.get("name", i) for i, d in data.items.items() if set(map(str, d.get("properties", []))) & set(props)]
                races = [data.traits.get(t, {}).get("name", t) for t, v in by_trait.items() if isinstance(v, list) and dtype in v]
            rows.append({"id": f"{kind}:{dtype}", "Защита": f"{word}: {data.damage_name(dtype)}", "Герою": f"{kind} {dtype}",
                         "Юниту": f"@<цель> {kind} {dtype}", "Монстры с ней": ", ".join(sorted(mons)), "Вещи с ней": ", ".join(sorted(things)),
                         "Черты рас": ", ".join(races)})
    for cond in data.rules["conditions"]:
        mons = [m.get("name", mid) for mid, m in data.monsters.items() if cond in map(str, m.get("condition_immunities", []))]
        if not mons:
            continue
        rows.append({"id": f"condition:{cond}", "Защита": f"иммунитет к состоянию: {data.condition_name(cond)}", "Герою": f"cond {cond}",
                     "Юниту": f"@<цель> cond {cond}", "Монстры с ней": ", ".join(sorted(mons)), "Вещи с ней": "", "Черты рас": ""})
    return "Сопротивления и иммунитеты", cols, rows


# --- the workbook ----------------------------------------------------------------------------------------------------

WIDTHS = {"Описание": 70, "Способности": 50, "Заклинания": 45, "Инвентарь": 35, "Защиты": 35, "Комментарий": 40, "Монстры с ней": 50,
          "Вещи с ней": 35, "Классы": 30, "Команда": 30, "Союзник": 28, "На юнита": 32, "Юниту": 26, "Герою": 22}


def old_marks(path: Path) -> dict[tuple[str, str], dict]:
    """The author's marks already in the file: (sheet, id) → {column: value}."""
    if not path.exists():
        return {}
    out: dict[tuple[str, str], dict] = {}
    wb = load_workbook(path)
    for ws in wb.worksheets:
        head = [c.value for c in ws[1]]
        if "id" not in head:
            continue
        at = {name: head.index(name) for name in MARKS if name in head}
        for row in ws.iter_rows(min_row=2, values_only=True):
            rid = row[head.index("id")]
            if rid is not None:
                out[(ws.title, str(rid))] = {name: row[i] for name, i in at.items()}
    return out


def build(data: Data, path: Path) -> dict[str, int]:
    marks = old_marks(path)
    wb = Workbook()
    wb.remove(wb.active)
    counts = {}
    bold = Font(bold=True)
    head_fill = PatternFill("solid", fgColor="DDD5C4")
    for title, cols, rows in (items_sheet(data, False), items_sheet(data, True), monsters_sheet(data), abilities_sheet(data),
                              spells_sheet(data), defenses_sheet(data)):
        ws = wb.create_sheet(title)
        all_cols = cols + MARKS
        ws.append(all_cols)
        for c in ws[1]:
            c.font = bold
            c.fill = head_fill
            c.alignment = Alignment(vertical="center", wrap_text=True)
        for row in rows:
            kept = marks.get((title, str(row["id"])), {})
            values = [row.get(c, "") for c in cols]
            values += [bool(kept.get(f)) if kept.get(f) is not None else False for f in FLAGS] + [kept.get("Комментарий") or ""]
            ws.append(values)
        n = len(rows) + 1
        for i, name in enumerate(all_cols, start=1):
            letter = get_column_letter(i)
            ws.column_dimensions[letter].width = WIDTHS.get(name, 12 if name in FLAGS else 18)
            for cell in ws[letter][1:]:
                cell.alignment = Alignment(vertical="top", wrap_text=name in WIDTHS)
        flags_from = len(cols) + 1
        rng = f"{get_column_letter(flags_from)}2:{get_column_letter(flags_from + 2)}{n}"
        dv = DataValidation(type="list", formula1='"TRUE,FALSE"', allow_blank=True)
        ws.add_data_validation(dv)
        dv.add(rng)
        first = get_column_letter(1)
        last = get_column_letter(len(all_cols))
        checked, bug, fixed = (get_column_letter(flags_from + k) for k in range(3))
        whole = f"{first}2:{last}{n}"
        ws.conditional_formatting.add(whole, FormulaRule(formula=[f"AND(${bug}2=TRUE,${fixed}2<>TRUE)"], fill=PatternFill("solid", fgColor="F4C7C3")))
        ws.conditional_formatting.add(whole, FormulaRule(formula=[f"${checked}2=TRUE"], fill=PatternFill("solid", fgColor="D9EAD3")))
        ws.freeze_panes = "B2"
        ws.auto_filter.ref = f"A1:{last}{n}"
        counts[title] = len(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    return counts


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--world", default="frontier")
    args = ap.parse_args()
    counts = build(Data(args.world), args.out)
    for title, n in counts.items():
        print(f"{title}: {n}")
    print(f"→ {args.out}")


if __name__ == "__main__":
    main()
