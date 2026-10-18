"""SRD 5e (2014) JSON → game/data/srd/*.json and the item catalog of game/data/items.json (roadmap v0.5.0).

The source is a copy of the 5e SRD API, dnd5eapi.co /api/2014 (tools/srd/source/2014). Only what levels 1–5
need: races and subraces with traits, classes with levels 1–5 and SRD subclasses, features up to level 5,
spells of circles 0–3, mundane equipment, languages. Russian names and short descriptions are data in
tools/srd/ru.json: core terms come from the glossary below, the rest is translated once by an LLM and reviewed
by hand. Backgrounds (the SRD has only one) are written by hand in tools/srd/backgrounds.json.

    python tools/srd_import.py build                                      # SRD + ru.json → game/data (no network)
    uv run --project llm_server python tools/srd_import.py translate      # fill missing ru.json entries (cents)
    uv run --project llm_server python tools/srd_import.py translate --model qwen/qwen3.8-omni-flash
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SRD = ROOT / "tools" / "srd" / "source" / "2014"
OUT = ROOT / "game" / "data" / "srd"
ITEMS = ROOT / "game" / "data" / "items.json"
RU = ROOT / "tools" / "srd" / "ru.json"
BACKGROUNDS = ROOT / "tools" / "srd" / "backgrounds.json"

MAX_LEVEL = 5
MAX_SPELL_LEVEL = 3
ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]

# --- glossary: core terms by hand, always wins over ru.json -------------------------------------------

GLOSSARY: dict[str, str] = {
    # races and subraces
    "race:dwarf": "Дварф", "race:elf": "Эльф", "race:halfling": "Полурослик", "race:human": "Человек",
    "race:dragonborn": "Драконорождённый", "race:gnome": "Гном", "race:half-elf": "Полуэльф",
    "race:half-orc": "Полуорк", "race:tiefling": "Тифлинг",
    "subrace:hill-dwarf": "Холмовой дварф", "subrace:high-elf": "Высший эльф", "subrace:drow": "Тёмный эльф (дроу)",
    "subrace:lightfoot-halfling": "Легконогий полурослик", "subrace:rock-gnome": "Скальный гном",
    # classes and subclasses
    "class:barbarian": "Варвар", "class:bard": "Бард", "class:cleric": "Жрец", "class:druid": "Друид",
    "class:fighter": "Воин", "class:monk": "Монах", "class:paladin": "Паладин", "class:ranger": "Следопыт",
    "class:rogue": "Плут", "class:sorcerer": "Чародей", "class:warlock": "Колдун", "class:wizard": "Волшебник",
    "subclass:berserker": "Путь берсерка", "subclass:champion": "Чемпион", "subclass:devotion": "Клятва преданности",
    "subclass:draconic": "Наследие драконьей крови", "subclass:evocation": "Школа Воплощения",
    "subclass:fiend": "Исчадие", "subclass:hunter": "Охотник", "subclass:land": "Круг земли",
    "subclass:life": "Домен Жизни", "subclass:lore": "Коллегия знаний", "subclass:open-hand": "Путь открытой ладони",
    "subclass:thief": "Вор",
    "flavor:Primal Path": "Путь дикости", "flavor:Bard College": "Коллегия бардов",
    "flavor:Divine Domain": "Божественный домен", "flavor:Druid Circle": "Круг друидов",
    "flavor:Martial Archetype": "Воинский архетип", "flavor:Monastic Tradition": "Монастырская традиция",
    "flavor:Sacred Oath": "Священная клятва", "flavor:Ranger Archetype": "Архетип следопыта",
    "flavor:Roguish Archetype": "Архетип плута", "flavor:Sorcerous Origin": "Происхождение чародея",
    "flavor:Otherworldly Patron": "Потусторонний покровитель", "flavor:Arcane Tradition": "Магическая традиция",
    # languages
    "language:common": "Общий", "language:dwarvish": "Дварфийский", "language:elvish": "Эльфийский",
    "language:giant": "Великаний", "language:gnomish": "Гномий", "language:goblin": "Гоблинский",
    "language:halfling": "Язык полуросликов", "language:orc": "Орочий", "language:abyssal": "Язык Бездны",
    "language:celestial": "Небесный", "language:draconic": "Драконий", "language:deep-speech": "Глубинная речь",
    "language:infernal": "Инфернальный", "language:primordial": "Первичный", "language:sylvan": "Сильван",
    "language:undercommon": "Подземный общий",
    # schools of magic
    "school:abjuration": "Ограждение", "school:conjuration": "Вызов", "school:divination": "Прорицание",
    "school:enchantment": "Очарование", "school:evocation": "Воплощение", "school:illusion": "Иллюзия",
    "school:necromancy": "Некромантия", "school:transmutation": "Преобразование",
    # damage types
    "damage:acid": "кислота", "damage:bludgeoning": "дробящий", "damage:cold": "холод", "damage:fire": "огонь",
    "damage:force": "силовое поле", "damage:lightning": "электричество", "damage:necrotic": "некротическая энергия",
    "damage:piercing": "колющий", "damage:poison": "яд", "damage:psychic": "психическая энергия",
    "damage:radiant": "излучение", "damage:slashing": "рубящий", "damage:thunder": "звук",
    # equipment categories offered in starting equipment
    "category:simple-weapons": "простое оружие", "category:martial-weapons": "воинское оружие",
    "category:simple-melee-weapons": "простое рукопашное оружие",
    "category:martial-melee-weapons": "воинское рукопашное оружие",
    "category:simple-ranged-weapons": "простое дальнобойное оружие",
    "category:martial-ranged-weapons": "воинское дальнобойное оружие",
    "category:arcane-foci": "магическая фокусировка", "category:druidic-foci": "друидическая фокусировка",
    "category:holy-symbols": "священный символ", "category:musical-instruments": "музыкальный инструмент",
    "category:artisans-tools": "инструменты ремесленника", "category:gaming-sets": "игровой набор",
}

# Prototype catalog ids kept so the start scene, saves and tests keep working.
ITEM_ALIASES = {
    "arrow": "arrows", "rations-1-day": "rations", "rope-hempen-50-feet": "rope", "lantern-hooded": "lantern",
    "antitoxin-vial": "antitoxin", "holy-water-flask": "holy_water",
}
# Hand-made catalog items that are not SRD equipment (kept from the v0.4.x catalog).
EXTRA_ITEMS = ["healing_potion", "ale", "bread", "silver_ring"]
# Engine properties (items.json "properties") and item types the SRD does not have, by game id.
EXTRA_PROPERTIES = {"torch": ["light_source"], "lantern": ["light_source"], "lantern_bullseye": ["light_source"],
                    "candle": ["light_source"], "lamp": ["light_source"], "antitoxin": ["resist_poison"],
                    "holy_water": ["radiant_damage"], "alchemists_fire_flask": ["fire_damage"], "acid_vial": []}
CONSUMABLES = {"rations", "antitoxin", "holy_water", "alchemists_fire_flask", "acid_vial", "oil_flask"}
SKIP_GEAR = {"equipment-packs"}
SKIP_CATEGORIES = {"mounts-and-vehicles"}
WEAPON_PROPERTIES = {"finesse", "light", "heavy", "two-handed", "versatile", "thrown", "reach", "ammunition"}
WEAPON_PROF_ALIASES = {"hand-crossbows": "crossbow-hand", "light-crossbows": "crossbow-light",
                       "heavy-crossbows": "crossbow-heavy"}
PREPARED_CASTERS = {"cleric", "druid", "paladin", "wizard"}
OPTION_CATEGORIES = ["simple-weapons", "martial-weapons", "simple-melee-weapons", "martial-melee-weapons",
                     "simple-ranged-weapons", "martial-ranged-weapons", "arcane-foci", "druidic-foci",
                     "holy-symbols", "musical-instruments", "artisans-tools", "gaming-sets"]


def j(rel: str) -> Any:
    return json.loads((SRD / rel).read_text(encoding="utf-8"))


def all_of(folder: str) -> list[dict[str, Any]]:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((SRD / folder).glob("*.json"))]


def sid(index: str) -> str:
    """SRD index → game id: kebab-case → snake_case, prototype aliases kept."""
    return ITEM_ALIASES.get(index, index.replace("-", "_"))


def desc_text(d: dict[str, Any]) -> str:
    raw = d.get("desc", [])
    return "\n".join(raw) if isinstance(raw, list) else str(raw)


def options_of(choice: dict[str, Any]) -> list[dict[str, Any]]:
    return choice.get("from", {}).get("options", [])


def refs_of(choice: dict[str, Any]) -> list[str]:
    return [o["item"]["index"] for o in options_of(choice) if o.get("option_type") == "reference"]


# --- proficiencies -----------------------------------------------------------------------------------


def split_profs(indexes: list[str], weapons: set[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {"skills": [], "saves": [], "armor": [], "weapons": [], "tools": []}
    for p in indexes:
        if p.startswith("skill-"):
            out["skills"].append(sid(p.removeprefix("skill-")))
        elif p.startswith("saving-throw-"):
            out["saves"].append(p.removeprefix("saving-throw-"))
        elif p in ("light-armor", "medium-armor", "heavy-armor"):
            out["armor"].append(p.removesuffix("-armor"))
        elif p == "all-armor":
            out["armor"] += ["light", "medium", "heavy"]
        elif p == "shields":
            out["armor"].append("shield")
        elif p in ("simple-weapons", "martial-weapons"):
            out["weapons"].append(p.removesuffix("-weapons"))
        elif p in WEAPON_PROF_ALIASES or p.removesuffix("s") in weapons or p.removesuffix("es") in weapons:
            w = WEAPON_PROF_ALIASES.get(p) or (p.removesuffix("s") if p.removesuffix("s") in weapons else p.removesuffix("es"))
            out["weapons"].append(sid(w))
        else:
            out["tools"].append(sid(p))
    return out


def skill_choice(choices: list[dict[str, Any]]) -> dict[str, Any] | None:
    for c in choices:
        refs = refs_of(c)
        if refs and all(r.startswith("skill-") for r in refs):
            return {"choose": c["choose"], "from": [sid(r.removeprefix("skill-")) for r in refs]}
    return None


def language_choice(d: dict[str, Any]) -> int:
    lo = d.get("language_options")
    return int(lo["choose"]) if lo else 0


# --- equipment ---------------------------------------------------------------------------------------


def cost_cp(cost: dict[str, Any] | None, per: int = 1) -> int:
    if not cost:
        return 0
    mult = {"cp": 1, "sp": 10, "ep": 50, "gp": 100, "pp": 1000}[cost["unit"]]
    return max(1, round(cost["quantity"] * mult / per))


def item_def(e: dict[str, Any]) -> dict[str, Any] | None:
    cat = e["equipment_category"]["index"]
    gear = e.get("gear_category", {}).get("index", "")
    if cat in SKIP_CATEGORIES or gear in SKIP_GEAR or cat not in ("weapon", "armor", "adventuring-gear", "tools"):
        return None
    d: dict[str, Any] = {"name_en": e["name"], "weight": e.get("weight", 0)}
    if cat == "weapon":
        props = [p["index"] for p in e.get("properties", [])]
        d["item_type"] = "weapon"
        d["properties"] = sorted(p.replace("-", "_") for p in props if p in WEAPON_PROPERTIES)
        w: dict[str, Any] = {"category": e["weapon_category"].lower(), "range": e["weapon_range"].lower()}
        if e.get("damage"):
            w["damage"] = e["damage"]["damage_dice"]
            w["damage_type"] = e["damage"]["damage_type"]["index"]
        if e.get("two_handed_damage"):
            w["versatile"] = e["two_handed_damage"]["damage_dice"]
        if e.get("range", {}).get("long"):
            w["reach_ft"] = [e["range"]["normal"], e["range"]["long"]]
        d["weapon"] = w
        d["value_cp"] = cost_cp(e.get("cost"))
    elif cat == "armor":
        ac = e["armor_class"]
        kind = e["armor_category"].lower()
        d["item_type"] = "armor"
        d["properties"] = []
        d["armor"] = {"category": kind, "base": ac["base"],
                      "dex": bool(ac.get("dex_bonus")), "max_dex": ac.get("max_bonus"),
                      "str_min": e.get("str_minimum", 0), "stealth_disadvantage": bool(e.get("stealth_disadvantage"))}
        d["value_cp"] = cost_cp(e.get("cost"))
    else:
        qty = int(e.get("quantity", 1) or 1)
        d["item_type"] = "gear"
        d["properties"] = []
        d["value_cp"] = cost_cp(e.get("cost"), qty)
        if cat == "adventuring-gear":  # torches, rations, arrows… come in stacks
            d["stack"] = True
        if cat == "tools":
            d["tool"] = True
    return d


def pack_contents(index: str) -> list[dict[str, Any]] | None:
    p = SRD / "equipment" / f"{index}.json"
    if not p.exists():
        return None
    e = json.loads(p.read_text(encoding="utf-8"))
    if e.get("gear_category", {}).get("index") != "equipment-packs":
        return None
    return [{"id": sid(c["item"]["index"]), "qty": c["quantity"]} for c in e["contents"]]


def grant(index: str, qty: int) -> list[dict[str, Any]]:
    """An item reference of starting equipment; packs open into their contents."""
    contents = pack_contents(index)
    if contents is not None:
        return [{"id": c["id"], "qty": c["qty"] * qty} for c in contents]
    e = j(f"equipment/{index}.json")
    per = int(e.get("quantity", 1) or 1)  # «20 arrows» is one SRD item of quantity 20
    return [{"id": sid(index), "qty": qty * per if per > 1 and qty == 1 else qty}]


def parse_option(o: dict[str, Any]) -> dict[str, Any]:
    """One alternative of a starting equipment choice: fixed items plus category picks."""
    alt: dict[str, Any] = {"items": [], "picks": []}
    t = o.get("option_type")
    if t == "counted_reference":
        alt["items"] += grant(o["of"]["index"], o["count"])
    elif t == "reference":
        alt["items"] += grant(o["item"]["index"], 1)
    elif t == "multiple":
        for sub in o["items"]:
            part = parse_option(sub)
            alt["items"] += part["items"]
            alt["picks"] += part["picks"]
    elif t == "choice":
        c = o["choice"]
        src = c["from"]
        if src.get("option_set_type") == "equipment_category":
            alt["picks"].append({"category": sid(src["equipment_category"]["index"]), "count": c["choose"]})
        else:  # a nested list: take it as a category of its own references
            ids = [sid(x["of"]["index"]) for x in src["options"] if x.get("option_type") == "counted_reference"]
            alt["picks"].append({"items": ids, "count": c["choose"]})
    else:
        print(f"  ! unknown equipment option {t}", file=sys.stderr)
    return alt


def equipment_choices(cls: dict[str, Any]) -> list[dict[str, Any]]:
    out = []
    for c in cls.get("starting_equipment_options", []):
        src = c["from"]
        if src.get("option_set_type") == "equipment_category":
            alts = [{"items": [], "picks": [{"category": sid(src["equipment_category"]["index"]), "count": c["choose"]}]}]
        else:
            alts = [parse_option(o) for o in src["options"]]
        out.append({"alternatives": alts})
    return out


# --- build -------------------------------------------------------------------------------------------


def load_ru() -> dict[str, dict[str, str]]:
    return json.loads(RU.read_text(encoding="utf-8")) if RU.exists() else {}


def save_ru(ru: dict[str, Any]) -> None:
    RU.write_text(json.dumps(dict(sorted(ru.items())), ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")


class Builder:
    def __init__(self) -> None:
        self.ru = load_ru()
        self.wanted: dict[str, dict[str, str]] = {}  # key → {"en": name, "desc_en": text, "kind": ...}
        self.weapons = {e["index"] for e in all_of("equipment") if e["equipment_category"]["index"] == "weapon"}

    def tr(self, key: str, en: str, desc_en: str = "", extra: dict[str, str] | None = None) -> dict[str, str]:
        """Russian name (and desc) for a key; remembers what is missing for `translate`."""
        want = {"en": en}
        if desc_en:
            want["desc_en"] = desc_en
        if extra:
            want.update(extra)
        self.wanted[key] = want
        r = dict(self.ru.get(key, {}))
        if key in GLOSSARY:
            r["name"] = GLOSSARY[key]
        return {"name": r.get("name", en), **{k: v for k, v in r.items() if k not in ("name", "en")}}

    def items(self) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for e in all_of("equipment"):
            d = item_def(e)
            if d is None:
                continue
            id_ = sid(e["index"])
            d["name"] = self.tr(f"item:{id_}", e["name"])["name"]
            d["properties"] = sorted(set(d["properties"]) | set(EXTRA_PROPERTIES.get(id_, [])))
            if id_ in CONSUMABLES:
                d["item_type"] = "consumable"
            out[id_] = {"name": d.pop("name"), **d}
        return out

    def languages(self) -> dict[str, dict[str, Any]]:
        return {sid(l["index"]): {"name": self.tr(f"language:{l['index']}", l["name"])["name"], "type": l.get("type", "").lower()}
                for l in all_of("languages")}

    def traits(self, indexes: set[str]) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        todo = list(indexes)
        while todo:
            idx = todo.pop()
            if sid(idx) in out:
                continue
            t = j(f"traits/{idx}.json")
            ru = self.tr(f"trait:{idx}", t["name"], desc_text(t))
            d: dict[str, Any] = {"name": ru["name"], "name_en": t["name"], "desc": ru.get("desc", "")}
            profs = split_profs([p["index"] for p in t.get("proficiencies", [])], self.weapons)
            d.update({k: v for k, v in profs.items() if v})
            pc = t.get("proficiency_choices")
            if pc:
                refs = refs_of(pc)
                if all(r.startswith("skill-") for r in refs):
                    d["skill_choice"] = {"choose": pc["choose"], "from": [sid(r.removeprefix("skill-")) for r in refs]}
                else:
                    d["tool_choice"] = {"choose": pc["choose"], "from": [sid(r) for r in refs]}
            if t.get("language_options"):
                d["language_choice"] = int(t["language_options"]["choose"])
            spec = t.get("trait_specific", {})
            if spec.get("subtrait_options"):
                subs = refs_of(spec["subtrait_options"])
                d["options"] = {"choose": spec["subtrait_options"]["choose"], "from": [sid(s) for s in subs]}
                todo += subs
            if spec.get("spell_options"):
                d["spell_choice"] = {"choose": spec["spell_options"]["choose"],
                                     "from": [sid(s) for s in refs_of(spec["spell_options"])], "ability": "int"}
            if spec.get("damage_type"):
                d["damage_type"] = spec["damage_type"]["index"]
            out[sid(idx)] = d
        return out

    def races(self) -> dict[str, Any]:
        races, subraces, trait_ids = {}, {}, set()
        for r in all_of("races"):
            ru = self.tr(f"race:{r['index']}", r["name"])
            # The SRD race lists one colour of Draconic Ancestry; the parent trait offers all of them.
            traits = [("draconic-ancestry" if t["index"].startswith("draconic-ancestry-") else t["index"]) for t in r["traits"]]
            trait_ids |= set(traits)
            d: dict[str, Any] = {
                "name": ru["name"], "name_en": r["name"], "speed": r["speed"], "size": r["size"].lower(),
                "ability_bonuses": {b["ability_score"]["index"]: b["bonus"] for b in r["ability_bonuses"]},
                "languages": [sid(l["index"]) for l in r["languages"]], "language_choice": language_choice(r),
                "traits": [sid(t) for t in traits], "subraces": [sid(s["index"]) for s in r.get("subraces", [])],
            }
            abo = r.get("ability_bonus_options")
            if abo:
                d["ability_choice"] = {"choose": abo["choose"], "bonus": options_of(abo)[0]["bonus"],
                                       "from": [o["ability_score"]["index"] for o in options_of(abo)]}
            races[sid(r["index"])] = d
        for s in all_of("subraces"):
            ru = self.tr(f"subrace:{s['index']}", s["name"], s.get("desc", ""))
            traits = [t["index"] for t in s.get("racial_traits", [])]
            trait_ids |= set(traits)
            subraces[sid(s["index"])] = {
                "name": ru["name"], "name_en": s["name"], "race": sid(s["race"]["index"]), "desc": ru.get("desc", ""),
                "ability_bonuses": {b["ability_score"]["index"]: b["bonus"] for b in s["ability_bonuses"]},
                "traits": [sid(t) for t in traits],
            }
        return {"races": races, "subraces": subraces, "traits": self.traits(trait_ids)}

    def features(self) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for f in all_of("features"):
            if f["level"] > MAX_LEVEL:
                continue
            ru = self.tr(f"feature:{f['index']}", f["name"], desc_text(f))
            d: dict[str, Any] = {"name": ru["name"], "name_en": f["name"], "desc": ru.get("desc", ""), "level": f["level"],
                                 "class": f["class"]["index"]}
            if f.get("subclass"):
                d["subclass"] = f["subclass"]["index"]
            if f.get("parent"):
                d["parent"] = sid(f["parent"]["index"])
            spec = f.get("feature_specific", {})
            if spec.get("subfeature_options"):
                d["options"] = {"choose": spec["subfeature_options"]["choose"],
                                "from": [sid(x) for x in refs_of(spec["subfeature_options"])]}
            if spec.get("expertise_options"):
                eo = spec["expertise_options"]
                d["expertise"] = int(options_of(eo)[0]["choice"]["choose"]) if options_of(eo)[0].get("option_type") == "choice" else eo["choose"]
            out[sid(f["index"])] = d
        return out

    def classes(self) -> dict[str, Any]:
        classes, subclasses = {}, {}
        for c in all_of("classes"):
            idx = c["index"]
            ru = self.tr(f"class:{idx}", c["name"])
            profs = split_profs([p["index"] for p in c["proficiencies"]], self.weapons)
            levels: dict[str, Any] = {}
            for n in range(1, MAX_LEVEL + 1):
                lv = j(f"classes/{idx}/levels/{n}.json")
                sc = lv.get("spellcasting") or {}
                entry: dict[str, Any] = {"prof_bonus": lv["prof_bonus"], "features": [sid(f["index"]) for f in lv["features"]],
                                         "asi": lv.get("ability_score_bonuses", 0)}
                if sc:
                    entry["cantrips_known"] = sc.get("cantrips_known", 0)
                    if "spells_known" in sc:
                        entry["spells_known"] = sc["spells_known"]
                    entry["slots"] = [sc.get(f"spell_slots_level_{i}", 0) for i in range(1, 6)]
                if lv.get("class_specific"):
                    entry["class_specific"] = lv["class_specific"]
                levels[str(n)] = entry
            spell = c.get("spellcasting")
            d: dict[str, Any] = {
                "name": ru["name"], "name_en": c["name"], "hit_die": c["hit_die"],
                "saves": [s["index"] for s in c["saving_throws"]],
                "armor": profs["armor"], "weapons": profs["weapons"], "tools": profs["tools"],
                "skill_choice": skill_choice(c["proficiency_choices"]),
                "equipment": [x for e in c.get("starting_equipment", []) for x in grant(e["equipment"]["index"], e["quantity"])],
                "equipment_choices": equipment_choices(c),
                "levels": levels, "subclasses": [sid(s["index"]) for s in c.get("subclasses", [])],
            }
            if spell:
                d["spellcasting"] = {"ability": spell["spellcasting_ability"]["index"], "prepared": idx in PREPARED_CASTERS,
                                     "spellbook": idx == "wizard", "from_level": spell.get("level", 1)}
            classes[sid(idx)] = d
        for s in all_of("subclasses"):
            idx = s["index"]
            ru = self.tr(f"subclass:{idx}", s["name"], desc_text(s))
            feats: dict[str, list[str]] = {}
            for n in range(1, 21):
                p = SRD / "subclasses" / idx / "levels" / f"{n}.json"
                if n > MAX_LEVEL or not p.exists():
                    continue
                lv = json.loads(p.read_text(encoding="utf-8"))
                if lv.get("features"):
                    feats[str(n)] = [sid(f["index"]) for f in lv["features"]]
            spells: dict[str, list[str]] = {}
            for sp in s.get("spells", []):
                lvl = int(sp["prerequisites"][0]["index"].rsplit("-", 1)[1]) if sp.get("prerequisites") else 1
                if lvl <= MAX_LEVEL:
                    spells.setdefault(str(lvl), []).append(sid(sp["spell"]["index"]))
            flavor = s.get("subclass_flavor", "")
            subclasses[sid(idx)] = {
                "name": ru["name"], "name_en": s["name"], "class": sid(s["class"]["index"]), "desc": ru.get("desc", ""),
                "flavor": GLOSSARY.get(f"flavor:{flavor}", flavor), "features": feats, "spells": spells,
                "level": min((int(k) for k in feats), default=3),
            }
        for cid, c in classes.items():
            subs = [subclasses[s]["level"] for s in c["subclasses"] if s in subclasses]
            c["subclass_level"] = min(subs, default=3)
            first = next((subclasses[s]["flavor"] for s in c["subclasses"] if s in subclasses), "")
            c["subclass_flavor"] = first
        return {"classes": classes, "subclasses": subclasses}

    def spells(self) -> dict[str, dict[str, Any]]:
        out = {}
        for s in all_of("spells"):
            if s["level"] > MAX_SPELL_LEVEL:
                continue
            text = desc_text(s)
            if s.get("higher_level"):
                text += "\nAt higher levels: " + " ".join(s["higher_level"])
            ru = self.tr(f"spell:{s['index']}", s["name"], text, {
                "casting_time_en": s["casting_time"], "range_en": s["range"], "duration_en": s["duration"]})
            school = s["school"]["index"]
            out[sid(s["index"])] = {
                "name": ru["name"], "name_en": s["name"], "level": s["level"],
                "school": GLOSSARY.get(f"school:{school}", school),
                "casting_time": ru.get("casting_time", s["casting_time"]), "range": ru.get("range", s["range"]),
                "duration": ru.get("duration", s["duration"]), "components": s.get("components", []),
                "concentration": bool(s.get("concentration")), "ritual": bool(s.get("ritual")),
                "classes": [sid(c["index"]) for c in s.get("classes", [])],
                "subclasses": [sid(c["index"]) for c in s.get("subclasses", [])],
                "desc": ru.get("desc", ""),
            }
        return out

    def categories(self, items: dict[str, Any]) -> dict[str, dict[str, Any]]:
        out = {}
        for idx in OPTION_CATEGORIES:
            cat = j(f"equipment-categories/{idx}.json")
            ids = [sid(e["index"]) for e in cat["equipment"] if sid(e["index"]) in items]
            out[sid(idx)] = {"name": GLOSSARY[f"category:{idx}"], "items": ids}
        return out


def untranslated(wanted: dict[str, Any], ru: dict[str, Any]) -> list[str]:
    return [k for k in wanted if k not in ru and k not in GLOSSARY and not k.startswith(("language:", "category:"))]


def seed_ru_from_catalog(catalog: dict[str, Any]) -> None:
    """Hand-written names of the v0.4.x catalog (no `name_en` yet) become ru.json entries once: they are in
    saves, the start scene and the golden scenarios."""
    ru = load_ru()
    new = {f"item:{id_}": {"en": id_, "name": d["name"]} for id_, d in catalog.items()
           if "name_en" not in d and id_ not in EXTRA_ITEMS and f"item:{id_}" not in ru}
    if new:
        ru.update(new)
        RU.parent.mkdir(parents=True, exist_ok=True)
        save_ru(ru)


def build() -> None:
    old = json.loads(ITEMS.read_text(encoding="utf-8"))
    seed_ru_from_catalog(old["catalog"])
    b = Builder()
    items = b.items()
    for keep in EXTRA_ITEMS:
        items[keep] = old["catalog"][keep]
    races = b.races()
    classes = b.classes()
    data = {
        "races.json": races,
        "classes.json": {**classes, "features": b.features()},
        "spells.json": b.spells(),
        "misc.json": {"languages": b.languages(), "categories": b.categories(items),
                      "damage_types": {k.removeprefix("damage:"): v for k, v in GLOSSARY.items() if k.startswith("damage:")}},
        "backgrounds.json": json.loads(BACKGROUNDS.read_text(encoding="utf-8")),
    }
    OUT.mkdir(parents=True, exist_ok=True)
    for name, d in data.items():
        (OUT / name).write_text(json.dumps(d, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    old["catalog"] = dict(sorted(items.items()))
    ITEMS.write_text(json.dumps(old, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    missing = untranslated(b.wanted, b.ru)
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build" / "srd_wanted.json").write_text(json.dumps(b.wanted, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"srd -> {OUT.relative_to(ROOT)}: {len(races['races'])} races, {len(classes['classes'])} classes, "
          f"{len(data['spells.json'])} spells, {len(items)} items; untranslated: {len(missing)}")


# --- translate ---------------------------------------------------------------------------------------

INSTRUCTIONS = """Ты переводишь справочные данные D&D 5e (SRD 2014) на русский для русскоязычной игры.

Названия — устоявшиеся в русском переводе 5e (dnd.su, Hobby World): Magic Missile → Волшебная стрела,
Cure Wounds → Лечение ран, Second Wind → Второе дыхание, Sneak Attack → Скрытая атака, Rage → Ярость,
Darkvision → Тёмное зрение, Fey Ancestry → Наследие фей, Longsword → Длинный меч, Chain Mail → Кольчуга.
Если устоявшегося нет — короткое естественное русское название.

Термины: saving throw — спасбросок; advantage/disadvantage — преимущество/помеха; hit points — хиты;
Hit Dice — Кости хитов; temporary hit points — временные хиты; Armor Class — КД; proficiency bonus — бонус
мастерства; spell slot — ячейка заклинаний; cantrip — заговор; concentration — концентрация; action —
действие; bonus action — бонусное действие; reaction — реакция; short/long rest — короткий/долгий отдых;
attack roll — бросок атаки; ability check — проверка характеристики. Характеристики: Сила, Ловкость,
Телосложение, Интеллект, Мудрость, Харизма. Навыки: Акробатика, Анализ, Атлетика, Внимательность, Выживание,
Выступление, Запугивание, История, Ловкость рук, Магия, Медицина, Обман, Природа, Проницательность, Религия,
Скрытность, Убеждение, Уход за животными. Кости: «2d6» оставляй как «2к6». Расстояния — в футах («30 футов»).

Для каждой записи верни key без изменений, name и, если есть desc_en, desc — точный и короткий пересказ
механики по-русски: 1–3 предложения (заклинания — до 4), все числа, кости, дистанции и условия сохранены, без
воды и без художественных подробностей. Если есть casting_time_en / range_en / duration_en — переведи их в
casting_time / range / duration («1 действие», «На себя», «Касание», «60 футов», «Концентрация, вплоть до 1 минуты»)."""


def translate(model_id: str, batch: int, limit: int | None) -> None:
    import asyncio
    import os

    from dotenv import load_dotenv
    from pydantic import BaseModel
    from pydantic_ai import Agent

    sys.path.insert(0, str(ROOT / "llm_server" / "src"))
    from llm_server.agents import settings_for
    from llm_server.llm.catalog import openrouter_factory

    class Entry(BaseModel):
        key: str
        name: str
        desc: str = ""
        casting_time: str = ""
        range: str = ""
        duration: str = ""

    build()  # refresh build/srd_wanted.json
    wanted = json.loads((ROOT / "build" / "srd_wanted.json").read_text(encoding="utf-8"))
    ru = load_ru()
    todo = untranslated(wanted, ru)
    if limit:
        todo = todo[:limit]
    print(f"to translate: {len(todo)} with {model_id}")
    if not todo:
        return
    load_dotenv(ROOT / ".env", override=False)
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        sys.exit("OPENROUTER_API_KEY is not set (env or the root .env)")
    model = openrouter_factory(key)(model_id)
    agent = Agent(model, output_type=list[Entry], instructions=INSTRUCTIONS,
                  model_settings={**settings_for(model), "max_tokens": 8000})
    sem = asyncio.Semaphore(4)
    usage = {"in": 0, "out": 0}

    async def one(keys: list[str]) -> list[Entry]:
        payload = [{"key": k, **wanted[k]} for k in keys]
        async with sem:
            for attempt in range(3):
                try:
                    r = await agent.run(json.dumps(payload, ensure_ascii=False))
                    usage["in"] += r.usage.input_tokens or 0
                    usage["out"] += r.usage.output_tokens or 0
                    return r.output
                except Exception as e:  # noqa: BLE001 — a failed batch is retried, then skipped
                    print(f"  ! batch {keys[0]}…: {type(e).__name__}: {e}", file=sys.stderr)
            return []

    async def run() -> None:
        chunks = [todo[i:i + batch] for i in range(0, len(todo), batch)]
        done = 0
        for res in asyncio.as_completed([one(c) for c in chunks]):
            for e in await res:
                if e.key in wanted:
                    entry = {"en": wanted[e.key]["en"], "name": e.name.strip()}
                    for f in ("desc", "casting_time", "range", "duration"):
                        if getattr(e, f) and (f != "desc" or "desc_en" in wanted[e.key]) and (f == "desc" or f"{f}_en" in wanted[e.key]):
                            entry[f] = getattr(e, f).strip()
                    ru[e.key] = entry
            done += 1
            save_ru(ru)
            print(f"  {done}/{len(chunks)} batches, tokens in {usage['in']} out {usage['out']}")

    asyncio.run(run())
    build()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build")
    t = sub.add_parser("translate")
    t.add_argument("--model", default="anthropic/claude-haiku-5.5")
    t.add_argument("--batch", type=int, default=12)
    t.add_argument("--limit", type=int, default=None, help="translate only the first N missing keys (a trial run)")
    a = p.parse_args()
    if a.cmd == "build":
        build()
    else:
        translate(a.model, a.batch, a.limit)


if __name__ == "__main__":
    main()
