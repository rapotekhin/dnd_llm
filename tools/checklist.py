"""The author's test checklist: every item, monster, ability, spell and defense of the game with its dev console command.

One .xlsx with a sheet per kind (ordinary items, magic items, monsters, abilities, spells, conditions, resistances and
immunities, damage types);
each row has the command to put it into the game (the dev console, `--dev` or «Режим разработчика»: docs/tech/godot-client.md
«Отладка»), the engine's own check of the row (ChecklistProbe: «Автотест» — работает, нет механики, через мастера,
ошибка; its steps beside, from game/test/fixtures/checklist_probes.json written by game/tools/checklist_probes.gd) and the
author's columns: проверено, есть баг, исправлено, комментарий. Run again after the data changes: the marks and comments
already in the file stay with their rows (by the sheet and the id).

    uv run --with openpyxl python tools/checklist.py            # → docs/checklist/test-checklist.xlsx
    uv run --with openpyxl python tools/checklist.py --out x.xlsx --world frontier
"""
from __future__ import annotations

import argparse
import json
import re
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
# The engine's check of every row (ChecklistProbe), before the author's columns.
PROBES = ROOT / "game" / "test" / "fixtures" / "checklist_probes.json"
AUTO = ["Автотест", "Автотест: что проверено"]
# A status of the check → its cell's colour.
AUTO_FILL = {"работает": "D9EAD3", "через мастера": "FFF2CC", "нет механики": "FCE5CD", "ошибка": "F4C7C3", "без механики": "EEEEEE"}
# Magic by its kind: what is not plain gear even when its rarity is common (a potion, a wand, a wondrous thing).
MAGIC_TYPES = {"wondrous"}
DICE = str.maketrans({"d": "к"})
# Words of the data in Russian for the sheet: an item's kind, a weapon's category and range, an armour's category.
WORDS = {"gear": "снаряжение", "weapon": "оружие", "armor": "доспех", "consumable": "расходник", "wondrous": "чудесный",
         "treasure": "сокровище", "quest": "квест", "simple": "простое", "martial": "воинское", "melee": "ближнее",
         "ranged": "дальнобойное", "hour": "час", "minute": "минуту", "day": "день", "light": "лёгкий", "medium": "средний", "heavy": "тяжёлый", "shield": "щит"}


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

    def monster_name(self, mid: str) -> str:
        return str(self.monsters.get(mid, {}).get("name", mid))


def is_magic(d: dict) -> bool:
    use = d.get("use")
    spelled = bool(d.get("charges")) or (isinstance(use, dict) and bool(use.get("spell")))
    return (d.get("rarity", "common") != "common" or bool(d.get("attunement")) or bool(d.get("caster"))
            or d.get("item_type") in MAGIC_TYPES or (spelled and d.get("item_type") != "gear"))


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
    if isinstance(d.get("wear"), dict):
        parts.append("пока работает: " + json.dumps(d["wear"], ensure_ascii=False))
    return "; ".join(parts)


# How to see a property of a thing work: the console's commands and what to look at. {t} — a damage type, {d} — the probe.
PROP_CHECKS = {
    "ac_plus1": "Лист: КД +1 (сравнить без неё)",
    "magic_plus1": "spawn goblin, в бою удар — +1 к атаке и урону (разбор при наведении); spawn wererat_human — урон не режется (магическое)",
    "checks_plus1": "любая проверка — +1 в разборе броска",
    "saves_plus1": "любой спасбросок — +1 в разборе броска; лист: спасброски +1",
    "darkvision": "goto brod-tavern-cellar без света — комната видна",
    "light_source": "goto brod-tavern-cellar, вещь на пояс — свет, комната видна",
    "int_19": "Лист: Интеллект 19 (если был ниже)",
    "str_19": "Лист: Сила 19 (если была ниже); удар — бонус от 19",
    "investigation_advantage": "проверка Анализа — с преимуществом (разбор броска)",
    "perception_advantage": "проверка Внимательности — с преимуществом (разбор броска)",
    "stealth_advantage": "«Красться» — Скрытность с преимуществом",
    "missile_snaring": "hit 1d8 piercing ranged — реакция «Перчатки ловли снарядов»: урон −1к10 + Лов",
    "no_crit": "hit 2d6 slashing crit — крит становится обычным попаданием (кости один раз)",
    "mithral": "Лист: нет помехи Скрытности, нет требования Силы",
    "ranged_damage_plus2": "выстрел из длинного или короткого лука — урон +2",
    "speed_30": "Лист: скорость 30 футов и в тяжёлом доспехе, и с грузом",
    "spell_attack_plus1": "атака заклинанием (например «Огненный снаряд») — +1 к броску",
    "understand_all": "разговор с NPC без общего языка — речь понятна",
    "warm": "ночь на морозе без укрытия (погода) — без спасброска Телосложения",
    "wound_closure": "бой, герой на 0 хитов — стабилизируется сам; короткий отдых — кости хитов лечат вдвое",
    "water_source": "goto в комнату без воды, бурдюк пуст — «Набрать воды» доступно",
    "carry_plus_500": "Лист: полоса веса — грузоподъёмность +500",
    "immune_disease": "spawn giant_rat_diseased враг, дать укусить — болезнь не цепляется",
    "healing": "dmg 3d1, затем «Использовать» — хиты растут",
    "finesse": "удар — с Ловкостью, если она выше Силы (разбор)",
    "reach": "удар по цели в 10 футах",
    "thrown": "«Бросить» по цели на расстоянии",
    "ammunition": "выстрел тратит боеприпас (стрелы, болты)",
    "two_handed": "занимает обе руки: щит снимается",
    "light": "лёгкое: вторым оружием во вторую руку — бонусный удар",
    "heavy": "тяжёлое: маленький народ бьёт с помехой",
    "versatile": "",
}
# Properties a thing's use already shows: its probe is the use's own.
USE_SAYS = {"healing", "thrown", "resist_poison"}
# What the description of one thing promises and its data does not carry: a check that shows the gap.
ITEM_EXTRA = {
    "brooch_of_shielding": "spawn mage враг — его «Волшебная стрела» по герою → 0 урона (в данных броши этого нет: скорее всего не работает)",
}


def wear_slot(d: dict, data: "Data") -> str:
    """CharacterRules.slot_for: the slot a thing is worn in, "" — it works carried."""
    if "armor" in d:
        return "shield" if d["armor"].get("category") == "shield" else "armor"
    if "weapon" in d or d.get("item_type") == "weapon":
        return "main_hand"
    if d.get("slot"):
        return str(d["slot"])
    if d.get("item_type") != "wondrous":
        return ""
    by = data.rules["wear_slots"]["by_look"]
    look = str(d.get("look", "")).lower()
    if look in by:
        return str(by[look])
    first = str(d.get("name", "")).lower().split(" ")[0]
    return next((str(v) for k, v in by.items() if first.startswith(k.split(" ")[0])), "")


def item_check(item_id: str, d: dict, data: "Data") -> str:
    """How to see the thing work, step by step: get it, wear or attune it, then a probe per property and per use."""
    steps = [f"give {item_id}"]
    slot = wear_slot(d, data)
    if slot:
        steps.append("Лист → " + {"main_hand": "В основную руку", "shield": "Взять щит"}.get(slot, "Надеть"))
    if d.get("attunement"):
        steps.append("Лист → Настроиться (1 ч)")
    w = d.get("weapon")
    if isinstance(w, dict) and w.get("damage"):
        steps.append(f"spawn goblin, в бою удар — {ru_dice(w.get('damage', ''))} {data.damage_name(w.get('damage_type', ''))}"
                     + (f"; двумя руками {ru_dice(w['versatile'])}" if w.get("versatile") else ""))
    a = d.get("armor")
    if isinstance(a, dict):
        steps.append(f"Лист: КД {a.get('base', '')}" + (" + Лов" if a.get("dex") else "")
                     + (f" (не больше {a['max_dex']})" if a.get("max_dex") is not None else ""))
        if a.get("stealth_disadvantage"):
            steps.append("«Красться» — Скрытность с помехой")
        if a.get("str_min"):
            steps.append(f"с Силой ниже {a['str_min']} — скорость −10")
    use = data.rules.get("consumables", {}).get(item_id) or d.get("use")  # ItemRules.consumable: the rules' row first
    moves = {row["status"]: row["word"] for row in data.rules["combat"]["moves"].values() if isinstance(row, dict) and row.get("word")}
    for key, value in (d.get("wear") or {}).items():  # ItemRules.wear: a status while it works
        feet = "скорость ходьбы" if value == "walk" else f"{value} фт"
        steps.append(f"Лист → «От вещей»: {moves[key]} {feet}; в бою по воде, стене или в воздухе" if key in moves
                     else f"Лист → «От вещей»: {key}" + (" (вещь на поясе)" if "light_source" in d.get("properties", []) else ""))
    for p in map(str, d.get("properties", [])):
        if isinstance(use, dict) and p in USE_SAYS:
            continue
        if p.startswith("resist_"):
            t = p.removeprefix("resist_")
            steps.append(f"dmg {PROBE.format(t)} → {EXPECT['resist']} (без вещи {EXPECT['']})")
        elif PROP_CHECKS.get(p):
            steps.append(PROP_CHECKS[p])
    if isinstance(use, dict):
        if use.get("spell"):
            spell = data.spell_name(str(use["spell"]))
            steps.append(f"«Использовать» — заклинание «{spell}»" + (f", {use['level']} круг" if use.get("level") else "")
                         + ("; свиток чужого класса — проверка" if use.get("scroll") else "")
                         + ("; сколько угодно раз, вещь не тратится" if use.get("at_will") else ""))
        if use.get("summon"):
            row = data.rules["allies"]["summons"].get(str(use["summon"]), {})
            who = " или ".join(data.monster_name(m) for m in row.get("pick", [row.get("monster", "")]))
            steps.append(f"«Использовать» — призыв: {who} идёт с героем, в бою — союзник")
        for_time = f" (на {ru(use['duration'])})" if use.get("duration") else ""
        if use.get("resist"):
            steps.append(f"«Использовать», затем dmg {PROBE.format(use['resist'])} → {EXPECT['resist']}{for_time}")
        if use.get("heal"):
            n, die, plus = use["heal"]
            steps.append(f"dmg 3d6, затем «Использовать» — хиты +{f'{n}к{die}' if n else ''}{f'+{plus}' if plus and n else plus if plus else ''}")
        if use.get("adv_tag"):
            steps.append(f"«Использовать» — спасброски против «{data.damage_name(use['adv_tag'])}» с преимуществом{for_time}")
        if isinstance(use.get("throw"), dict):
            th = use["throw"]
            hurt = f": {ru_dice(th['damage'][0])} {data.damage_name(th['damage'][1])}" if th.get("damage") else ""
            held = f": {data.condition_name(th['condition'])}, вырваться СЛ {th.get('escape_dc', '')}" if th.get("condition") else ""
            steps.append(f"spawn goblin, в бою «Бросить» на {th.get('range', '')} фт{hurt}{held}"
                         + (f", горение {ru_dice(th['burning'])} в ход" if th.get("burning") else "")
                         + (" (только по нежити и исчадиям)" if th.get("types") else ""))
        if isinstance(use.get("meal"), dict):
            steps.append("«Поесть» — " + ("полосы голода и жажды растут" if use["meal"].get("water") else "полоса голода растёт"))
        if use.get("poison"):
            steps.append("«Использовать» — яд: спасбросок, урон ядом, отравление")
        if use.get("invisible_minutes"):
            steps.append(f"«Использовать» — невидимость на {ru_dice(use['invisible_minutes'])} мин")
        if use.get("recover_slot"):
            steps.append(f"slots, потратить ячейку, «Использовать» — ячейка до {use['recover_slot']} круга вернулась")
        if use.get("check_adv"):
            steps.append(f"«Использовать» — преимущество на проверки ({use['check_adv']}){for_time}")
        if use.get("enlarged"):
            steps.append(f"«Использовать» — увеличение: урон оружием +1к4, преимущество Силы{for_time}")
        for cond in use.get("remove", []):
            steps.append(f"cond {cond}, затем «Использовать» — состояние снято")
        if use.get("cure"):
            steps.append("spawn giant_rat_diseased враг, заразиться, затем «Использовать» — болезнь излечена")
    if d.get("charges"):
        ch = d["charges"]
        steps.append(f"«Использовать» — заряды убывают (из {ch.get('max', '')})"
                     + (f", на рассвете +{ru_dice(ch['regain'])}" if ch.get("regain") else "")
                     + ("; на последнем заряде может рассыпаться" if ch.get("crumble") else ""))
    if d.get("spoils_days"):
        steps.append(f"через {d['spoils_days']} дн. портится (ждать или долгий отдых)")
    if d.get("master"):  # its effect is the master's by its description (ItemInfo: ITEM_MASTER)
        steps.append("сказать мастеру, что применяешь вещь, — он решает по описанию; проверить, что эффект совпал с описанием")
    if item_id in ITEM_EXTRA:
        steps.append(ITEM_EXTRA[item_id])
    return "\n".join(steps)


# --- the sheets: (title, columns, rows); a row is {"id": …, column: value} -----------------------------------------


def items_sheet(data: Data, magic: bool) -> tuple[str, list[str], list[dict]]:
    cols = ["Предмет", "id", "Команда", "Как проверить", "Тип"] + (["Редкость", "Настройка"] if magic else []) + ["Цена, зм", "Источник", "Описание"]
    rows = []
    for item_id, d in sorted(data.items.items(), key=lambda kv: str(kv[1].get("name", kv[0]))):
        if is_magic(d) != magic:
            continue
        row = {"id": item_id, "Предмет": d.get("name", item_id), "Команда": f"give {item_id}",
               "Как проверить": item_check(item_id, d, data), "Тип": ru(d.get("item_type", "")),
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


# The defenses against a damage type: the cheat's word, the monsters' field, its Russian name.
DEFENSE_KINDS = (("resist", "resistances", "сопротивление"), ("immune", "immunities", "иммунитет"),
                 ("vulnerable", "vulnerabilities", "уязвимость"))
# The probe of a defense: fixed dice that always land critically, 4d1 rolled twice — 8 before a defense, then what each leaves.
PROBE = "4d1 {} crit"
EXPECT = {"": 8, "resist": 4, "immune": 0, "vulnerable": 16}


def defenses_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    """A row per damage type and defense, then per condition immunity: the commands and who has it by the data."""
    cols = ["Защита", "id", "Герою", "Юниту", "Проверить ударом", "Проверить без боя", "Монстры с ней", "Вещи с ней", "Черты рас"]
    he = data.rules.get("hero_effects", {})
    by_item: dict[str, str] = he.get("item_resist", {})
    by_trait: dict = he.get("trait_resist", {})
    rows = []
    for kind, key, word in DEFENSE_KINDS:
        for dtype in data.damage:
            mons = [m.get("name", mid) for mid, m in data.monsters.items() if any(dtype in str(x).lower() for x in m.get(key, []))]
            things, races = [], []
            if kind == "resist":
                props = [p for p, t in by_item.items() if t == dtype]
                things = [d.get("name", i) for i, d in data.items.items() if set(map(str, d.get("properties", []))) & set(props)]
                races = [data.traits.get(t, {}).get("name", t) for t, v in by_trait.items() if isinstance(v, list) and dtype in v]
            rows.append({"id": f"{kind}:{dtype}", "Защита": f"{word}: {data.damage_name(dtype)}", "Герою": f"{kind} {dtype}",
                         "Юниту": f"@<цель> {kind} {dtype}",
                         "Проверить ударом": f"@<цель> hit {PROBE.format(dtype)} → {EXPECT[kind]} урона (без защиты {EXPECT['']})",
                         "Проверить без боя": f"{kind} {dtype}, затем dmg {PROBE.format(dtype)} → {EXPECT[kind]} урона", "Монстры с ней": ", ".join(sorted(mons)), "Вещи с ней": ", ".join(sorted(things)),
                         "Черты рас": ", ".join(races)})
    for cond in data.rules["conditions"]:
        mons = [m.get("name", mid) for mid, m in data.monsters.items() if cond in map(str, m.get("condition_immunities", []))]
        if not mons:
            continue
        rows.append({"id": f"condition:{cond}", "Защита": f"иммунитет к состоянию: {data.condition_name(cond)}", "Герою": f"cond {cond}",
                     "Юниту": f"@<цель> cond {cond}", "Монстры с ней": ", ".join(sorted(mons)), "Вещи с ней": "", "Черты рас": ""})
    return "Сопротивления и иммунитеты", cols, rows


def damage_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    """A row per damage type: `dmg` and `hit` with what each must give, the defenses laid and lifted, the nonmagical blow on a
    monster that resists it (Sheet.defenses), and what deals it in the game's data."""
    cols = ["Тип урона", "id", "Герою без боя", "Юниту ударом", "Крит", "Защиты", "Немагическое", "Заклинания", "Оружие", "Монстры бьют"]
    rows = []
    for dtype in data.damage:
        spells = sorted(s["name"] for s in data.spells.values() if s.get("damage_type") == dtype)
        weapons = sorted(d.get("name", i) for i, d in data.items.items() if isinstance(d.get("weapon"), dict) and d["weapon"].get("damage_type") == dtype)
        mons = sorted({m.get("name", mid) for mid, m in data.monsters.items()
                       for a in m.get("actions", []) if any(isinstance(x, dict) and x.get("type") == dtype for x in a.get("damage", []))})
        bare = ""
        probe = PROBE.format(dtype)
        for kind, key, word in DEFENSE_KINDS[1::-1]:  # an immunity first: it shows the bypass best
            found = next(((mid, str(x)) for mid, m in data.monsters.items() for x in m.get(key, [])
                          if dtype in str(x) and "nonmagical" in str(x) and "adamantine" not in str(x)), None)
            if found:
                mid, text = found
                bare = (f"spawn {mid} ({word} к немагическому)\n@<цель> hit {probe} → {EXPECT[kind]}"
                        f"\n@<цель> hit {probe} magic → {EXPECT['']}")
                if "silvered" in text:
                    bare += f"\n@<цель> hit {probe} silver → {EXPECT['']}"
                break
        rows.append({"id": dtype, "Тип урона": data.damage_name(dtype), "Герою без боя": f"dmg 2d6 {dtype} → 2–12 урона",
                     "Юниту ударом": f"@<цель> hit 2d6 {dtype} → при попадании 2–12",
                     "Крит": f"dmg {probe} → {EXPECT['']} (кости дважды)",
                     "Защиты": "\n".join([f"{kind} {dtype}, dmg {probe} → {EXPECT[kind]}" for kind, _, _ in DEFENSE_KINDS]
                                         + [f"снять: resist {dtype} off (и так же immune, vulnerable)"]),
                     "Немагическое": bare, "Заклинания": ", ".join(spells), "Оружие": ", ".join(weapons), "Монстры бьют": ", ".join(mons)})
    return "Типы урона", cols, rows


def liquid_text(k: dict) -> dict[str, str]:
    """What a row of rules.liquids says, cell by cell."""
    drink = k.get("drink", {})
    coat = k.get("coat", {})
    puddle = k.get("puddle", {})
    throw = k.get("throw", {})
    return {
        "Выпить": ", ".join(w for w, on in (("утоляет жажду", "water" in drink), ("сытит", "food" in drink), ("пьянит", "drunk" in drink),
                                             ("риск болезни", "disease" in drink)) if on) if drink else "не пьют",
        "Бросить": (("урон " + " ".join(map(str, throw["damage"])) if throw.get("damage") else "без урона")
                    + (" по " + ", ".join(throw["types"]) if throw.get("types") else "")) if throw else "",
        "Облить": ", ".join(w for w, on in ((f"огонь +{coat.get('fire_plus')}", "fire_plus" in coat), (f"горит {coat.get('burns')}", "burns" in coat),
                                             ("гасит огонь", coat.get("douses"))) if on) if coat else "",
        "Лужа": "клетка горит" if puddle.get("fire") else ", ".join(w for w, on in (("скользко", puddle.get("cond") == "prone"), ("горит", puddle.get("burns")),
                                                                                ("гасит огонь", puddle.get("douses"))) if on) if puddle else "",
    }


def liquids_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    """A row per liquid (rules.liquids): its ready thing, how to pour it (and with which tool), drink, throw, coat and spill."""
    cfg = data.rules["liquids"]
    cols = ["Жидкость", "id", "Готовая вещь", "Сосуды", "Налить", "Выпить", "Бросить", "Облить", "Лужа", "Клинок"]
    rows = []
    for lid, k in cfg["kinds"].items():
        vessels = [data.item_name(v) for v, spec in cfg["vessels"].items() if not spec.get("only") or lid in spec["only"]]
        item = k.get("item", "")
        need = k.get("needs", "")
        give = f"give {item}" if item else "give jug_or_pitcher, у источника: «набираю»"
        pour = f"{give}\ngive jug_or_pitcher\nлист → «Перелить»" + (f"\nбез «{data.item_name(need)}» серо; tool {need} + give {need}" if need else "")
        blade = k.get("blade", {})
        rows.append({"id": lid, "Жидкость": k.get("name", lid),
                     "Готовая вещь": f"{data.item_name(item)} ({data.item_name(k['vessel'])}, {k['pints']} пинт)" if item else "",
                     "Сосуды": ", ".join(vessels), "Налить": pour, **liquid_text(k),
                     "Клинок": f"{blade.get('dice')} {blade.get('type')}, спасбросок {blade.get('save')} Сл {blade.get('dc')}" if blade else ""})
    return "Жидкости", cols, rows


def creature_conditions(data: Data) -> list[str]:
    """What `cond` lays (Cheats.conditions): the rules' conditions and the spells' statuses, not a thing's nor an exhaustion step."""
    effects = data.rules.get("condition_effects", {})
    ids = list(data.rules["conditions"]) + [k for k in effects if not k.startswith("_") and k not in data.rules["conditions"]]
    return [i for i in ids if "thing" not in effects.get(i, {}).get("on", []) and not re.fullmatch(r"exhaustion_\d+", i)]


# A status row's words (rules.condition_effects): what it does to rolls.
MODES = {"advantage": "преимущество", "disadvantage": "помеха", "auto_fail": "автопровал"}
EFFECT_WORDS = {"attack": "его атаки", "attacked": "атаки по нему", "attacked_near": "атаки по нему вблизи",
                "attacked_far": "атаки по нему издалека", "checks": "его проверки"}


def effect_text(row: dict) -> str:
    parts = [f"{word}: {MODES.get(str(row[k]), row[k])}" for k, word in EFFECT_WORDS.items() if k in row]
    parts += [f"{k}" for k in ("no_move", "no_threat", "resist_all", "crit_near") if row.get(k)]
    return "; ".join(parts)


def _holds(value: object, cond: str, keys: tuple[str, ...]) -> bool:
    """`cond` under one of `keys` anywhere in a row of data (a list or a value)."""
    if isinstance(value, dict):
        return any((k in keys and (v == cond or (isinstance(v, list) and cond in v))) or _holds(v, cond, keys) for k, v in value.items())
    if isinstance(value, list):
        return any(_holds(v, cond, keys) for v in value)
    return False


def conditions_sheet(data: Data) -> tuple[str, list[str], list[dict]]:
    """A row per status: the commands to lay it and lift it, what it does, who lays it and lifts it in the game's data."""
    cols = ["Состояние", "id", "Вид", "Герою", "Юниту", "Снять", "Что делает", "Накладывают заклинания", "Накладывают монстры",
            "Снимают", "Иммунны"]
    lay_keys = ("conditions", "condition", "curse", "cond", "flag", "status", "hold")
    combat = data.rules.get("combat", {})
    by_spell: dict[str, list] = {}  # a spell → its rows in every table that lays a status: condition_spells, spell_effects, riders
    for table in (combat.get("condition_spells", {}), data.rules.get("spell_effects", {}), combat.get("riders", {})):
        for k, v in table.items():
            by_spell.setdefault(k, []).append(v)
    cures = {**data.rules.get("spell_effects", {}), **data.rules.get("hero_effects", {}).get("spell_cures", {})}
    rows = []
    for cond in creature_conditions(data):
        text = str(data.rules["conditions"].get(cond, ""))
        text = text.split(":", 1)[1].strip() if ":" in text else text
        spells = sorted({data.spell_name(s) for s, v in by_spell.items() if not s.startswith("_") and _holds(v, cond, lay_keys)})
        if not text:
            text = effect_text(data.rules.get("condition_effects", {}).get(cond, {})) or "по правилам заклинания: " + ", ".join(spells)
        mons = sorted({f"{m.get('name', mid)}: {a.get('name', '')}" for mid, m in data.monsters.items()
                       for a in m.get("actions", []) + m.get("reactions", []) if _holds(a.get("effect", {}), cond, lay_keys)})
        lift = sorted({data.spell_name(s) for s, v in cures.items() if not s.startswith("_") and _holds(v, cond, ("remove", "immune"))})
        immune = sorted(m.get("name", mid) for mid, m in data.monsters.items() if cond in map(str, m.get("condition_immunities", [])))
        rows.append({"id": cond, "Состояние": data.condition_name(cond), "Вид": "5e" if cond in data.rules["conditions"] else "статус заклинания",
                     "Герою": f"cond {cond}", "Юниту": f"@<цель> cond {cond}", "Снять": f"cond {cond} off", "Что делает": text,
                     "Накладывают заклинания": ", ".join(spells), "Накладывают монстры": "\n".join(mons),
                     "Снимают": ", ".join(lift), "Иммунны": ", ".join(immune)})
    return "Состояния", cols, rows


# --- the workbook ----------------------------------------------------------------------------------------------------

WIDTHS = {"Автотест: что проверено": 60, "Описание": 70, "Как проверить": 60, "Что делает": 60, "Накладывают заклинания": 35, "Накладывают монстры": 45, "Снимают": 30, "Иммунны": 40,
          "Снять": 24, "Способности": 50, "Заклинания": 45, "Инвентарь": 35, "Защиты": 45, "Комментарий": 40, "Монстры с ней": 50,
          "Вещи с ней": 35, "Классы": 30, "Команда": 30, "Союзник": 28, "На юнита": 32, "Юниту": 26, "Герою": 22, "Проверить ударом": 40, "Проверить без боя": 40, "Юниту ударом": 32, "Герою без боя": 26,
          "Крит": 30, "Немагическое": 45, "Оружие": 35, "Монстры бьют": 50}


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
                out[(ws.title, str(rid))] = {name: flag(row[i]) if name in FLAGS else row[i] for name, i in at.items()}
    return out


def flag(value: object) -> bool:
    """A mark as Excel keeps it: a boolean, or a formula «=TRUE()» / «=FALSE()» typed by hand."""
    if isinstance(value, str):
        return value.strip().upper().lstrip("=").rstrip("()") == "TRUE"
    return bool(value)


def probes(path: Path = PROBES) -> dict:
    """The engine's check of every row: {sheet: {id: {status, steps}}}; {} before the first run of checklist_probes.gd."""
    return load(path) if path.exists() else {}


def build(data: Data, path: Path, run: dict | None = None) -> dict[str, int]:
    marks = old_marks(path)
    run = probes() if run is None else run
    wb = Workbook()
    wb.remove(wb.active)
    counts = {}
    bold = Font(bold=True)
    head_fill = PatternFill("solid", fgColor="DDD5C4")
    for title, cols, rows in (items_sheet(data, False), items_sheet(data, True), monsters_sheet(data), abilities_sheet(data),
                              spells_sheet(data), conditions_sheet(data), defenses_sheet(data), damage_sheet(data), liquids_sheet(data)):
        ws = wb.create_sheet(title)
        all_cols = cols + AUTO + MARKS
        auto = run.get(title, {})
        ws.append(all_cols)
        for c in ws[1]:
            c.font = bold
            c.fill = head_fill
            c.alignment = Alignment(vertical="center", wrap_text=True)
        for row in rows:
            kept = marks.get((title, str(row["id"])), {})
            values = [row.get(c, "") for c in cols]
            got = auto.get(str(row["id"]), {})
            values += [got.get("status", ""), "\n".join(got.get("steps", []))]
            values += [bool(kept.get(f)) if kept.get(f) is not None else False for f in FLAGS] + [kept.get("Комментарий") or ""]
            ws.append(values)
            cell = ws.cell(row=ws.max_row, column=len(cols) + 1)
            if cell.value in AUTO_FILL:
                cell.fill = PatternFill("solid", fgColor=AUTO_FILL[cell.value])
        n = len(rows) + 1
        for i, name in enumerate(all_cols, start=1):
            letter = get_column_letter(i)
            ws.column_dimensions[letter].width = WIDTHS.get(name, 12 if name in FLAGS else 18)
            for cell in ws[letter][1:]:
                cell.alignment = Alignment(vertical="top", wrap_text=name in WIDTHS)
        flags_from = len(cols) + len(AUTO) + 1
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
