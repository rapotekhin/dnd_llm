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
MAX_MONSTER_CR = 3  # the combat of v0.6.x: levels 1–5
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
EXTRA_ITEMS = ["healing_potion", "ale", "bread", "silver_ring", "goodberry", "herbal_remedy",
               "iron_ore", "iron_bar", "raw_hide", "leather", "timber", "herbs", "herbalist_notes"]
# Engine properties (items.json "properties") and item types the SRD does not have, by game id.
EXTRA_PROPERTIES = {"torch": ["light_source"], "lantern": ["light_source"], "lantern_bullseye": ["light_source"],
                    "candle": ["light_source"], "lamp": ["light_source"], "antitoxin": ["resist_poison"],
                    "holy_water": [], "alchemists_fire_flask": [], "acid_vial": []}
CONSUMABLES = {"rations", "antitoxin", "holy_water", "alchemists_fire_flask", "acid_vial", "oil_flask"}
SKIP_GEAR = {"equipment-packs"}
# Magic items of the SRD the engine knows (v0.6.3): +1 weapons and armor on common bases (the base's block, a +N
# property), a few wondrous items and a potion. Rarity and value by the DMG; no attunement in this version.
MAGIC_WEAPON_BASES = ["dagger", "shortsword", "longsword", "rapier", "scimitar", "mace", "handaxe", "battleaxe",
                      "warhammer", "greataxe", "greatsword", "quarterstaff", "spear", "shortbow", "longbow", "crossbow_light"]
MAGIC_ARMOR_BASES = ["leather_armor", "studded_leather_armor", "chain_shirt", "scale_mail", "breastplate", "chain_mail", "shield"]
# v0.7.12: the common and uncommon magic items of the SRD useful at levels 1-5. `look` — what an unidentified one
# looks like; `attunement`, `charges` {max, regain dice at dawn, crumble on the last}, `use` {spell, level, dc} or
# {recover_slot} — what the engine does with it; `master` — the engine has no rule for it, the master decides (its
# description is all there is).
def _w(id_: str, props: list[str], value: int, look: str, **kw: Any) -> dict[str, Any]:
    return {"id": id_, "item_type": "wondrous", "properties": props, "rarity": kw.pop("rarity", "uncommon"), "value_cp": value,
            "look": look, **kw}


def _potion(id_: str, value: int, rarity: str = "uncommon", **kw: Any) -> dict[str, Any]:
    return {"id": id_, "item_type": "consumable", "properties": [], "stack": True, "rarity": rarity, "value_cp": value,
            "look": "зелье", **kw}


MAGIC_OTHER = {
    "potion-of-healing-greater": {"id": "potion_of_greater_healing", "item_type": "consumable", "properties": ["healing"],
                                  "stack": True, "rarity": "uncommon", "value_cp": 15000, "look": "зелье"},
    "cloak-of-protection": _w("cloak_of_protection", ["ac_plus1", "saves_plus1"], 50000, "плащ", attunement=True),
    "boots-of-elvenkind": _w("boots_of_elvenkind", ["stealth_advantage"], 40000, "сапоги"),
    "cloak-of-elvenkind": _w("cloak_of_elvenkind", ["stealth_advantage"], 50000, "плащ", attunement=True),
    "bracers-of-archery": _w("bracers_of_archery", ["ranged_damage_plus2"], 50000, "наручи", attunement=True),
    "brooch-of-shielding": _w("brooch_of_shielding", ["resist_force"], 50000, "брошь", attunement=True),
    "boots-of-striding-and-springing": _w("boots_of_striding_and_springing", ["speed_30"], 40000, "сапоги", attunement=True),
    "boots-of-the-winterlands": _w("boots_of_the_winterlands", ["resist_cold"], 40000, "сапоги", attunement=True),
    "ring-of-warmth": _w("ring_of_warmth", ["resist_cold"], 40000, "кольцо", attunement=True),
    "eyes-of-the-eagle": _w("eyes_of_the_eagle", ["perception_advantage"], 40000, "линзы", attunement=True),
    "eyes-of-minute-seeing": _w("eyes_of_minute_seeing", ["investigation_advantage"], 25000, "линзы"),
    "goggles-of-night": _w("goggles_of_night", ["darkvision"], 30000, "очки"),
    "gauntlets-of-ogre-power": _w("gauntlets_of_ogre_power", ["str_19"], 50000, "латные перчатки", attunement=True),
    "headband-of-intellect": _w("headband_of_intellect", ["int_19"], 50000, "обруч", attunement=True),
    "periapt-of-health": _w("periapt_of_health", ["immune_disease"], 30000, "амулет"),
    "periapt-of-wound-closure": _w("periapt_of_wound_closure", ["wound_closure"], 50000, "амулет", attunement=True),
    "stone-of-good-luck-luckstone": _w("stone_of_good_luck", ["saves_plus1", "checks_plus1"], 50000, "камень", attunement=True),
    "helm-of-comprehending-languages": _w("helm_of_comprehending_languages", ["understand_all"], 30000, "шлем"),
    "gloves-of-missile-snaring": _w("gloves_of_missile_snaring", ["missile_snaring"], 30000, "перчатки", attunement=True),
    "bag-of-holding": _w("bag_of_holding", ["carry_plus_500"], 40000, "сумка"),
    "lantern-of-revealing": _w("lantern_of_revealing", ["light_source"], 50000, "фонарь", master=True),
    "pearl-of-power": _w("pearl_of_power", [], 50000, "жемчужина", attunement=True, caster=True,
                         charges={"max": 1, "regain": "1"}, use={"recover_slot": 3}),
    "wand-of-magic-missiles": _w("wand_of_magic_missiles", [], 50000, "волшебная палочка",
                                 charges={"max": 7, "regain": "1d6+1", "crumble": True}, use={"spell": "magic_missile", "level": 1}),
    "wand-of-web": _w("wand_of_web", [], 50000, "волшебная палочка", attunement=True, caster=True,
                      charges={"max": 7, "regain": "1d6+1", "crumble": True}, use={"spell": "web", "level": 2, "dc": 15}),
    "wand-of-the-war-mage": _w("wand_of_the_war_mage_1", ["spell_attack_plus1"], 50000, "волшебная палочка",
                               attunement=True, caster=True),
    "restorative-ointment": _w("restorative_ointment", [], 30000, "баночка мази", charges={"max": 5},
                               use={"heal": [2, 8, 2], "remove": ["poisoned"], "cure": ["disease"]}),
    "dust-of-disappearance": _potion("dust_of_disappearance", 30000, look="мешочек с пылью", use={"invisible_minutes": "2d4"}),
    "potion-of-climbing": _potion("potion_of_climbing", 7500, "common", use={"check_adv": "athletics", "duration": "hour"}),
    "potion-of-growth": _potion("potion_of_growth", 27000, use={"enlarged": True, "duration": "hour"}),
    "potion-of-poison": _potion("potion_of_poison", 10000, use={"poison": {"dice": "3d6", "save": "con", "dc": 13}}),
    # The master's: what they do is in the description.
    **{i: _w(i.replace("-", "_"), [], v, look, master=True, **kw) for i, v, look, kw in [
        ("amulet-of-proof-against-detection-and-location", 40000, "амулет", {"attunement": True}),
        ("bag-of-tricks", 30000, "сумка", {}), ("broom-of-flying", 50000, "метла", {}),
        ("circlet-of-blasting", 30000, "обруч", {}), ("cloak-of-the-manta-ray", 30000, "плащ", {}),
        ("decanter-of-endless-water", 30000, "графин", {}), ("deck-of-illusions", 30000, "колода карт", {}),
        ("dust-of-dryness", 12000, "мешочек с пылью", {"stack": True}),
        ("dust-of-sneezing-and-choking", 12000, "мешочек с пылью", {"stack": True}),
        ("efficient-quiver", 30000, "колчан", {}), ("elemental-gem", 30000, "самоцвет", {}),
        ("eversmoking-bottle", 30000, "бутыль", {}), ("eyes-of-charming", 30000, "линзы", {"attunement": True}),
        ("gem-of-brightness", 30000, "самоцвет", {}),
        ("gloves-of-swimming-and-climbing", 30000, "перчатки", {"attunement": True}),
        ("hat-of-disguise", 30000, "шляпа", {"attunement": True}), ("helm-of-telepathy", 50000, "шлем", {"attunement": True}),
        ("immovable-rod", 50000, "жезл", {}), ("medallion-of-thoughts", 30000, "медальон", {"attunement": True}),
        ("necklace-of-adaptation", 30000, "ожерелье", {"attunement": True}), ("pipes-of-haunting", 30000, "свирель", {}),
        ("pipes-of-the-sewers", 30000, "свирель", {"attunement": True}), ("ring-of-jumping", 30000, "кольцо", {"attunement": True}),
        ("ring-of-mind-shielding", 50000, "кольцо", {"attunement": True}), ("ring-of-swimming", 30000, "кольцо", {}),
        ("ring-of-water-walking", 30000, "кольцо", {}), ("robe-of-useful-items", 30000, "мантия", {}),
        ("rope-of-climbing", 30000, "верёвка", {}), ("slippers-of-spider-climbing", 30000, "туфли", {"attunement": True}),
        ("wand-of-magic-detection", 15000, "волшебная палочка", {"charges": {"max": 3, "regain": "1d3"}}),
        ("wand-of-secrets", 15000, "волшебная палочка", {"charges": {"max": 3, "regain": "1d3"}}),
        ("wind-fan", 30000, "веер", {}), ("winged-boots", 50000, "сапоги", {"attunement": True}),
    ]},
    **{i: _potion(i.replace("-", "_"), v, master=True) for i, v in [
        ("potion-of-animal-friendship", 20000), ("potion-of-water-breathing", 18000), ("oil-of-slipperiness", 48000),
        ("philter-of-love", 9000)]},
}
# Potion of Resistance: one per damage type the pack meets (the SRD leaves the type to the DM).
RESIST_POTIONS = {"fire": "огня", "cold": "холода", "poison": "яда", "lightning": "электричества", "acid": "кислоты", "necrotic": "некротической энергии"}
# Mithral and adamantine armor on the medium and heavy bases (DMG): no Strength need and no stealth disadvantage; a
# critical hit becomes a normal one.
SPECIAL_ARMOR_BASES = ["chain_shirt", "scale_mail", "breastplate", "half_plate_armor", "chain_mail", "splint_armor", "plate_armor"]
# Spell scrolls (DMG): the spells the engine resolves, circles 0-2; DC and attack by the circle.
SCROLL_EXTRA = ["identify"]
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
            t = self.tr(f"item:{id_}", e["name"], desc_text(e))
            d["name"] = t["name"]
            if t.get("desc"):
                d["description"] = t["desc"]  # v0.7.7: shown in the inventory and the trade
            d["properties"] = sorted(set(d["properties"]) | set(EXTRA_PROPERTIES.get(id_, [])))
            if id_ in CONSUMABLES:
                d["item_type"] = "consumable"
            out[id_] = {"name": d.pop("name"), **d}
        return out

    def magic_items(self, items: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for base in MAGIC_WEAPON_BASES:
            b = items[base]
            out[f"{base}_plus_1"] = {"name": f"{b['name']} +1", "name_en": f"{b['name_en']} +1", "base": base,
                                     "item_type": "weapon", "properties": ["magic_plus1"], "rarity": "uncommon",
                                     "value_cp": 50000, "weight": b.get("weight", 0)}
        for base in MAGIC_ARMOR_BASES:
            b = items[base]
            shield = base == "shield"
            out[f"{base}_plus_1"] = {"name": f"{b['name']} +1", "name_en": f"{b['name_en']} +1", "base": base,
                                     "item_type": "armor", "properties": ["ac_plus1"], "rarity": "uncommon" if shield else "rare",
                                     "value_cp": 40000 if shield else 150000, "weight": b.get("weight", 0)}
        for index, spec in MAGIC_OTHER.items():
            e = j(f"magic-items/{index}.json")
            t = self.tr(f"item:{spec['id']}", e["name"], desc_text(e))
            d = {k: v for k, v in spec.items() if k != "id"}
            out[spec["id"]] = {"name": t["name"], "name_en": e["name"], **d, "description": t.get("desc", "")}
        e = j("magic-items/potion-of-resistance.json")
        t = self.tr("item:potion_of_resistance", e["name"], desc_text(e))
        for dtype, ru in RESIST_POTIONS.items():
            out[f"potion_of_resistance_{dtype}"] = {"name": f"{t['name']} ({ru})", "name_en": f"{e['name']} ({dtype})",
                                                   **_potion("", 30000, use={"resist": dtype, "duration": "hour"}), "description": t.get("desc", "")}
            del out[f"potion_of_resistance_{dtype}"]["id"]
        for kind, props, ru_m, ru_a in [("mithral", ["mithral"], "мифриловый", "Мифрил"), ("adamantine", ["no_crit"], "адамантиновый", "Адамантин")]:
            e = j(f"magic-items/{kind}-armor.json")
            t = self.tr(f"item:{kind}_armor", e["name"], desc_text(e))
            for base in SPECIAL_ARMOR_BASES:
                b = items[base]
                out[f"{kind}_{base}"] = {"name": f"{b['name']} ({ru_a.lower()})", "name_en": f"{kind.title()} {b['name_en']}", "base": base,
                                         "item_type": "armor", "properties": props, "rarity": "uncommon",
                                         "value_cp": int(b.get("value_cp", 0)) + (80000 if kind == "mithral" else 50000),
                                         "weight": b.get("weight", 0) // (2 if kind == "mithral" else 1), "look": b["name"].lower(),
                                         "description": t.get("desc", "")}
        return out

    def scrolls(self, spells: dict[str, Any], rules: dict[str, Any]) -> dict[str, dict[str, Any]]:
        """Spell scrolls of the engine's spells, circles 0-2 (DMG prices; the DC and attack bonus — rules.scrolls)."""
        ids = set(rules["combat"]["engine_spells"]) | set(k for k in rules["combat"]["condition_spells"] if not k.startswith("_")) | set(SCROLL_EXTRA)
        out: dict[str, dict[str, Any]] = {}
        for sp in sorted(ids):
            if sp not in spells or int(spells[sp]["level"]) > 2:
                continue
            lv = int(spells[sp]["level"])
            out[f"spell_scroll_{sp}"] = {"name": f"Свиток: {spells[sp]['name']}", "name_en": f"Spell Scroll ({spells[sp].get('name_en', sp)})",
                                         "item_type": "consumable", "properties": [], "stack": True,
                                         "rarity": "common" if lv <= 1 else "uncommon", "value_cp": [2500, 7500, 15000][lv],
                                         "weight": 0, "look": "свиток", "use": {"spell": sp, "level": lv, "scroll": True},
                                         "description": f"Прочесть свиток — сотворить «{spells[sp]['name']}» ({lv} круг) без ячейки; свиток рассыпается. "
                                                        "Заклинание своего класса и по силам — без проверки, иначе проверка Магии Сл 10 + круг."}
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
                "school": GLOSSARY.get(f"school:{school}", school), "school_id": school,  # the frame colour of a spell (v0.7.22.21)
                "casting_time": ru.get("casting_time", s["casting_time"]), "range": ru.get("range", s["range"]),
                "duration": ru.get("duration", s["duration"]), "components": s.get("components", []),
                "concentration": bool(s.get("concentration")), "ritual": bool(s.get("ritual")),
                "classes": [sid(c["index"]) for c in s.get("classes", [])],
                "subclasses": [sid(c["index"]) for c in s.get("subclasses", [])],
                "desc": ru.get("desc", ""),
                **spell_combat(s),
            }
        return out

    def monsters(self) -> dict[str, dict[str, Any]]:
        """Monsters of CR ≤ MAX_MONSTER_CR in the engine's shape (v0.6.1): numbers, attacks, saves, traits."""
        items = {sid(e["index"]) for e in all_of("equipment")}
        out = {}
        for m in all_of("monsters"):
            if m["challenge_rating"] > MAX_MONSTER_CR:
                continue
            ru = self.tr(f"monster:{m['index']}", m["name"])
            abilities = {a[:3]: m[a] for a in ("strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma")}
            saves, skills = {}, {}
            for p in m.get("proficiencies", []):
                idx = p["proficiency"]["index"]
                if idx.startswith("saving-throw-"):
                    saves[idx.removeprefix("saving-throw-")] = p["value"]
                elif idx.startswith("skill-"):
                    skills[sid(idx.removeprefix("skill-"))] = p["value"]
            actions, multi = [], []
            for a in m.get("actions", []):
                if a["name"] == "Multiattack":
                    multi = multiattack(a)
                    continue
                act = monster_action(a, RIDERS.get(f"{m['index']}:{a['name']}", {}))
                if act is None:
                    continue
                act["name"] = self.tr(f"monster_action:{a['name']}", a["name"])["name"]
                actions.append(act)
            if not actions:
                continue  # nothing to fight with in the engine yet (pure spellcasters, swarms of effects)
            traits = []
            for t in m.get("special_abilities", []):
                tr = self.tr(f"monster_trait:{t['name']}", t["name"], t.get("desc", ""))
                trait = {"id": sid(t["name"].lower().replace(" ", "_").replace("(", "").replace(")", "").replace("'", "")),
                         "name": tr["name"], "desc": tr.get("desc", "")}
                fx = parse_effect(t.get("desc", ""))  # v0.7.9: charge, pounce, death burst, relentless — numbers for the engine
                if fx:
                    trait["effect"] = fx
                traits.append(trait)
            gear = [sid(x["index"]) for ac in m.get("armor_class", []) for x in ac.get("armor", [])]
            for a in actions:
                guess = sid(a["name_en"].lower().replace(" ", "-"))
                if guess in items and guess not in gear:
                    gear.append(guess)
            speed = m.get("speed", {})
            out[sid(m["index"])] = {
                "name": ru["name"], "name_en": m["name"], "size": m["size"].lower(), "type": m["type"],
                "cr": m["challenge_rating"], "xp": m["xp"], "ac": m["armor_class"][0]["value"], "hp": m["hit_points"],
                "hit_dice": m["hit_dice"], "speed": ft(speed.get("walk", "30 ft.")), "fly": ft(speed.get("fly", "0 ft.")),
                "swim": ft(speed.get("swim", "0 ft.")), "darkvision": ft(m.get("senses", {}).get("darkvision", "0 ft.")),
                "abilities": abilities, "prof": m.get("proficiency_bonus", 2), "saves": saves, "skills": skills,
                "passive_perception": m.get("senses", {}).get("passive_perception", 10),
                "resistances": m.get("damage_resistances", []), "immunities": m.get("damage_immunities", []),
                "vulnerabilities": m.get("damage_vulnerabilities", []),
                "condition_immunities": [sid(c["index"]) for c in m.get("condition_immunities", [])],
                "actions": actions, "multiattack": multi, "traits": traits, "equipment": gear,
                "languages": m.get("languages", ""),  # v0.7.9: kept for v0.7.11
                "reactions": [{"id": sid(r["name"].lower().replace(" ", "_")), "name_en": r["name"],
                               **({"ac": int(x.group(1))} if (x := re.search(r"adds (\d+) to its AC", r.get("desc", ""))) else {})}
                              for r in m.get("reactions", [])],
            }
            spells = monster_spells(m)
            if spells:
                out[sid(m["index"])]["spellcasting"] = spells
        return out

    def categories(self, items: dict[str, Any]) -> dict[str, dict[str, Any]]:
        out = {}
        for idx in OPTION_CATEGORIES:
            cat = j(f"equipment-categories/{idx}.json")
            ids = [sid(e["index"]) for e in cat["equipment"] if sid(e["index"]) in items]
            out[sid(idx)] = {"name": GLOSSARY[f"category:{idx}"], "items": ids}
        return out


# Choices the SRD lists only in prose (v0.7.10): favored enemy, favored terrain, eldritch invocations, the Lore bard's
# three skills. Each option becomes a feature of its own so that creation and level-up offer it like a fighting style.
FAVORED_ENEMIES = {"aberration": "Аберрации", "beast": "Звери", "celestial": "Небожители", "construct": "Конструкты",
                   "dragon": "Драконы", "elemental": "Элементали", "fey": "Феи", "fiend": "Исчадия", "giant": "Великаны",
                   "humanoid": "Гуманоиды", "monstrosity": "Монстры", "ooze": "Слизи", "plant": "Растения", "undead": "Нежить"}
FAVORED_TERRAINS = {"arctic": "Арктика", "coast": "Побережье", "desert": "Пустыня", "forest": "Лес", "grassland": "Равнины",
                    "mountain": "Горы", "swamp": "Болота", "underdark": "Подземье"}
SKILL_NAMES = {"acrobatics": "Акробатика", "animal_handling": "Уход за животными", "arcana": "Магия", "athletics": "Атлетика",
               "deception": "Обман", "history": "История", "insight": "Проницательность", "intimidation": "Запугивание",
               "investigation": "Анализ", "medicine": "Медицина", "nature": "Природа", "perception": "Внимательность",
               "performance": "Выступление", "persuasion": "Убеждение", "religion": "Религия", "sleight_of_hand": "Ловкость рук",
               "stealth": "Скрытность", "survival": "Выживание"}
# Invocations a warlock of level 2 may take; the rest need level 5 or a pact (offered at level 5).
INVOCATIONS_L2 = ["agonizing_blast", "armor_of_shadows", "beast_speech", "beguiling_influence", "devils_sight", "eldritch_sight",
                  "eldritch_spear", "eyes_of_the_rune_keeper", "fiendish_vigor", "gaze_of_two_minds", "mask_of_many_faces",
                  "misty_visions", "repelling_blast", "thief_of_five_fates"]
INVOCATIONS_L5 = ["mire_the_mind", "one_with_shadows", "sign_of_ill_omen", "thirsting_blade", "book_of_ancient_secrets",
                  "voice_of_the_chain_master"]


def add_choices(classes: dict[str, Any]) -> dict[str, Any]:
    feats = classes["features"]
    fe = feats["favored_enemy_1_type"]
    fe["options"] = {"choose": 1, "from": [f"favored_enemy_{k}" for k in FAVORED_ENEMIES]}
    for k, name in FAVORED_ENEMIES.items():
        feats[f"favored_enemy_{k}"] = {"name": f"Любимый враг: {name.lower()}", "name_en": f"Favored Enemy: {k}", "level": 1,
                                       "class": "ranger", "parent": "favored_enemy_1_type", "creature_type": k,
                                       "desc": f"{name}: преимущество на Выживание, чтобы их выследить, и на Интеллект, чтобы о них вспомнить."}
    ne = feats["natural_explorer_1_terrain_type"]
    ne["options"] = {"choose": 1, "from": [f"natural_explorer_{k}" for k in FAVORED_TERRAINS]}
    for k, name in FAVORED_TERRAINS.items():
        feats[f"natural_explorer_{k}"] = {"name": f"Родная местность: {name.lower()}", "name_en": f"Favored Terrain: {k}", "level": 1,
                                          "class": "ranger", "parent": "natural_explorer_1_terrain_type", "terrain": k,
                                          "desc": f"{name}: удвоенный бонус мастерства к проверкам Интеллекта и Мудрости о ней; здесь не заблудиться."}
    feats["eldritch_invocations"]["options"] = {"choose": 2, "from": [f"eldritch_invocation_{k}" for k in INVOCATIONS_L2]}
    feats["eldritch_invocations_5"] = {"name": "Жуткие воззвания (третье)", "name_en": "Eldritch Invocations (third)", "level": 5,
                                       "class": "warlock", "desc": feats["eldritch_invocations"].get("desc", ""),
                                       "options": {"choose": 1, "from": [f"eldritch_invocation_{k}" for k in INVOCATIONS_L2 + INVOCATIONS_L5]}}
    lv5 = classes["classes"]["warlock"]["levels"]["5"]["features"]
    if "eldritch_invocations_5" not in lv5:
        lv5.append("eldritch_invocations_5")
    if "bonus_proficiencies" in feats:
        feats["bonus_proficiencies"]["options"] = {"choose": 3, "from": [f"skill_prof_{k}" for k in SKILL_NAMES]}
        for k, name in SKILL_NAMES.items():
            feats[f"skill_prof_{k}"] = {"name": f"Навык: {name}", "name_en": f"Skill: {k}", "level": 3, "class": "bard",
                                        "parent": "bonus_proficiencies", "skill": k, "desc": f"Владение навыком «{name}»."}
    return classes


def ft(text: str) -> int:
    m = re.match(r"(\d+)", str(text))
    return int(m.group(1)) if m else 0


def dice_text(d: str) -> str:
    return d.replace(" ", "")


def spell_combat(s: dict[str, Any]) -> dict[str, Any]:
    """What the engine needs to resolve a spell in combat: attack roll or save, damage by slot or character level,
    area, healing. Empty for spells the master narrates."""
    out: dict[str, Any] = {}
    if s.get("attack_type"):
        out["attack"] = s["attack_type"]
    dmg = s.get("damage") or {}
    if dmg.get("damage_type"):
        out["damage_type"] = dmg["damage_type"]["index"]
    if dmg.get("damage_at_slot_level"):
        out["damage_at_slot"] = {k: dice_text(v) for k, v in dmg["damage_at_slot_level"].items() if int(k) <= 5}
    if dmg.get("damage_at_character_level"):
        out["damage_at_level"] = {k: dice_text(v) for k, v in dmg["damage_at_character_level"].items()}
    if s.get("dc"):
        out["save"] = {"ability": s["dc"]["dc_type"]["index"], "success": s["dc"].get("dc_success", "none")}
    if s.get("area_of_effect"):
        out["area"] = {"type": s["area_of_effect"]["type"], "size": s["area_of_effect"]["size"]}
    if s.get("heal_at_slot_level"):
        out["heal_at_slot"] = {k: dice_text(v) for k, v in s["heal_at_slot_level"].items() if int(k) <= 5}
    rng = str(s.get("range", ""))
    out["range_ft"] = 0 if rng in ("Self", "Touch") else ft(rng)
    if rng == "Touch":
        out["range_ft"] = 5
    out.update(SPELL_FIXES.get(s["index"], {}))
    return out


# Where the SRD JSON lacks what its text says (v0.6.4): Scorching Ray makes ranged spell attacks; Produce Flame is
# thrown up to 30 feet.
SPELL_FIXES = {"scorching-ray": {"attack": "ranged"}, "produce-flame": {"range_ft": 30}}


# What a monster's action or trait does besides its damage (v0.7.9), parsed from the SRD text; RIDERS overrides it.
ABILITY_BY_NAME = {"Strength": "str", "Dexterity": "dex", "Constitution": "con", "Intelligence": "int", "Wisdom": "wis", "Charisma": "cha"}
CONDITION_WORDS = [("knocked prone", "prone"), ("be poisoned", "poisoned"), ("become poisoned", "poisoned"), ("be paralyzed", "paralyzed"),
                   ("be blinded", "blinded"), ("be frightened", "frightened"), ("become frightened", "frightened"),
                   ("be magically charmed", "charmed"), ("be charmed", "charmed"), ("fall unconscious", "unconscious"),
                   ("be stunned", "stunned"), ("restrained by webbing", "restrained")]


def parse_effect(desc: str) -> dict[str, Any]:
    """The engine's shape of a rider: save {ability, dc}, condition, duration, repeat, grapple escape_dc (with
    restrained while grappled), save damage {dice, type, half}, extra damage of a charge (`extra`), unconscious when the
    save fails by 5 (`fail_by_5`), paralysis when the poison drops the target to 0 (`zero_hp_paralyzed`), who is immune
    (`immune_races`, `immune_types`), the biggest size it works on (`size_max`), an area (`area` {shape, ft})."""
    fx: dict[str, Any] = {}
    sv = re.search(r"DC (\d+) (Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throw", desc)
    if sv:
        fx["save"] = {"ability": ABILITY_BY_NAME[sv.group(2)], "dc": int(sv.group(1))}
    for words, cond in CONDITION_WORDS:
        if words in desc:
            fx["condition"] = cond
            break
    g = re.search(r"grappled \(escape DC (\d+)\)", desc)
    if g:
        fx["condition"] = "grappled"
        fx["escape_dc"] = int(g.group(1))
        if re.search(r"Until this grapple ends, the (target|creature) is restrained", desc):
            fx["also"] = "restrained"
    esc = re.search(r"DC (\d+) Strength check", desc)
    if esc and fx.get("condition") == "restrained":
        fx["escape_dc"] = int(esc.group(1))
    dm = re.search(r"taking \d+ \((\d+d\d+)\) (\w+) damage on a failed save, or half", desc) \
        or re.search(r"saving throw,? taking \d+ \((\d+d\d+)\) (\w+) damage", desc)
    if dm:
        fx["damage"] = {"dice": dm.group(1), "type": dm.group(2), "half": "half as much" in desc}
    else:
        dm = re.search(r"or take \d+ \((\d+d\d+)\) (\w+) damage", desc)
        if dm:
            fx["damage"] = {"dice": dm.group(1), "type": dm.group(2), "half": False}
    ex = re.search(r"(?:takes|deal|deals) an extra \d+ \((\d+d\d+)\)(?: (\w+))? damage", desc)
    if ex:
        fx["extra"] = {"dice": ex.group(1), "type": ex.group(2) or ""}
    mv = re.search(r"moves at least (\d+) (?:ft\.|feet) straight toward", desc)
    if mv:
        fx["charge_ft"] = int(mv.group(1))
    if "until the end of" in desc and "next turn" in desc:
        fx["duration"] = "round"
    elif re.search(r"(lasts|for) 24 hours", desc) and "next 24 hours" not in desc:
        fx["duration"] = "day"
    elif "for 1 minute" in desc:
        fx["duration"] = "minute"
    elif "for 1 hour" in desc:
        fx["duration"] = "hour"
    if "repeat the saving throw at the end of each of its turns" in desc:
        fx["repeat"] = True
    if "fails by 5 or more" in desc or "saving throw result is 5 or lower" in desc:
        fx["fail_by_5"] = "unconscious"
    rel = re.search(r"takes (\d+) damage or less that would reduce it to 0", desc)
    if rel:
        fx["relentless"] = int(rel.group(1))
    if "reduces the target to 0 hit points, the target is stable but poisoned for 1 hour" in desc:
        fx["zero_hp_paralyzed"] = True
    if "takes damage or" in desc and fx.get("condition") == "unconscious" or fx.get("fail_by_5"):
        fx["wake"] = True
    im = re.search(r"creature other than (?:an? )?([\w ]+?)(?:,|\.| it)", desc)
    if im:
        words = [w.strip() for w in re.split(r" or | and ", im.group(1).replace("an ", "").replace("a ", ""))]
        fx["immune_races"] = [w for w in words if w in ("elf", "dwarf")]
        fx["immune_types"] = [w for w in words if w in ("undead", "construct")]
    size = re.search(r"(Tiny|Small|Medium|Large|Huge) or smaller", desc)
    if size:
        fx["size_max"] = size.group(1).lower()
    area = re.search(r"(\d+)-foot(?:-radius)? (cone|line|sphere|cube)", desc) or re.search(r"within (\d+) (?:ft\.|feet) of (it|the flash|the mephit)", desc)
    if area:
        fx["area"] = {"shape": area.group(2) if area.group(2) in ("cone", "line", "sphere", "cube") else "burst", "ft": int(area.group(1))}
    if "magically" in desc or "magic" in desc:
        fx["magic"] = True
    return fx if any(k in fx for k in ("condition", "damage", "extra", "save", "zero_hp_paralyzed", "relentless")) else {}


def load_riders() -> dict[str, Any]:
    path = ROOT / "tools" / "srd" / "riders.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


RIDERS = load_riders()


def monster_spells(m: dict[str, Any]) -> dict[str, Any]:
    """A caster's spells (v0.7.9): DC, attack bonus, slots, the list with per-day uses of innate casting."""
    for t in m.get("special_abilities", []):
        sc = t.get("spellcasting")
        if not sc:
            continue
        spells = []
        for x in sc.get("spells", []):
            use = x.get("usage", {})
            spells.append({"id": sid(x["url"].rsplit("/", 1)[-1]), "level": x.get("level", 0),
                           **({"per_day": int(use["times"])} if use.get("type") == "per day" else {})})
        return {"dc": sc.get("dc", 10), "attack": sc.get("modifier", 0), "ability": sc.get("ability", {}).get("index", ""), "level": sc.get("level", 1),
                "slots": {str(k): int(v) for k, v in sc.get("slots", {}).items()}, "spells": spells,
                "innate": "Innate" in t["name"]}
    return {}


def monster_action(a: dict[str, Any], override: dict[str, Any] | None = None) -> dict[str, Any] | None:
    override = override or {}
    if override.get("skip"):
        return None
    desc = override.get("desc", a.get("desc", ""))
    parts = []
    for d in a.get("damage", []):
        if isinstance(d, dict) and d.get("from"):  # a choice (one- or two-handed): the first option
            d = d["from"]["options"][0]
        parts.append(d)
    dmg = [{"dice": dice_text(d["damage_dice"]), "type": d["damage_type"]["index"]}
           for d in parts if isinstance(d, dict) and d.get("damage_dice") and d.get("damage_type")]
    if override.get("damage"):
        dmg = override["damage"]
    act: dict[str, Any] = {"name_en": a["name"], "damage": dmg}
    if "attack_bonus" in a:
        act["to_hit"] = a["attack_bonus"]
        rng = re.search(r"range (\d+)/(\d+) ft", desc)
        reach = re.search(r"reach (\d+) ft", desc)
        if rng and not desc.startswith("Melee"):
            act["kind"], act["range"] = "ranged", [int(rng.group(1)), int(rng.group(2))]
        else:
            act["kind"], act["reach"] = "melee", int(reach.group(1)) if reach else 5
            if rng:  # a thrown melee weapon: also usable at range
                act["range"] = [int(rng.group(1)), int(rng.group(2))]
    elif a.get("dc") or override.get("save"):  # a save of its own (breath, gaze, song)
        act["kind"] = "save"
        dc = a.get("dc") or {}
        act["save"] = override.get("save") or {"ability": dc["dc_type"]["index"], "dc": dc["dc_value"], "success": dc.get("success_type", "none")}
    else:
        return None
    fx = {} if override.get("master") else parse_effect(desc)
    if override.get("master"):
        act["master_effect"] = override["master"]  # what the hit also does stays with the master, on purpose
    if act["kind"] == "save":  # the save is the action's own: its effect is what a failure brings
        fx.pop("save", None)
        fx.pop("damage", None)
    fx.update(override.get("effect", {}))
    for k in override.get("drop", []):  # what the text parser read but the rider replaces (a disease, v0.7.23.1)
        fx.pop(k, None)
    if fx:
        act["effect"] = fx
    use = a.get("usage") or {}
    if use.get("type") == "recharge on roll":
        act["recharge"] = int(use.get("min_value", 6))
    elif use.get("type") == "per day":
        act["per_day"] = int(use.get("times", 1))
    elif use.get("type") == "recharge after rest":
        act["per_day"] = 1
    if not dmg and act["kind"] != "save" and not fx.get("condition"):
        return None
    if act["kind"] == "save" and not dmg and not fx.get("condition"):
        return None
    for k in ("damage", "kind", "range"):
        if k in override:
            act[k] = override[k]
    return act


def multiattack(a: dict[str, Any]) -> list[dict[str, Any]]:
    seq = a.get("actions") or []
    if not seq and a.get("action_options"):
        first = a["action_options"]["from"]["options"][0]
        seq = first.get("items", [first])
    return [{"action": x["action_name"], "count": int(x["count"]) if str(x.get("count", 1)).isdigit() else 1}
            for x in seq if x.get("action_name")]


def untranslated(wanted: dict[str, Any], ru: dict[str, Any]) -> list[str]:
    """Keys with no Russian entry, or with an English text but no Russian one yet (item descriptions, v0.7.7)."""
    return [k for k in wanted if (k not in ru or ("desc_en" in wanted[k] and not ru[k].get("desc")))
            and k not in GLOSSARY and not k.startswith(("language:", "category:"))]


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
    promoted = ROOT / "tools" / "srd" / "promoted.json"  # items the author moved from the master's library (v0.7.18.3)
    if promoted.exists():
        items.update(json.loads(promoted.read_text(encoding="utf-8")))
    items.update(b.magic_items(items))
    races = b.races()
    classes = b.classes()
    spells = b.spells()
    items.update(b.scrolls(spells, json.loads((ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))))
    data = {
        "races.json": races,
        "classes.json": add_choices({**classes, "features": b.features()}),
        "spells.json": spells,
        "misc.json": {"languages": b.languages(), "categories": b.categories(items),
                      "damage_types": {k.removeprefix("damage:"): v for k, v in GLOSSARY.items() if k.startswith("damage:")}},
        "backgrounds.json": json.loads(BACKGROUNDS.read_text(encoding="utf-8")),
        "monsters.json": b.monsters(),
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
          f"{len(data['spells.json'])} spells, {len(data['monsters.json'])} monsters, {len(items)} items; untranslated: {len(missing)}")


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
                    entry = {"en": wanted[e.key]["en"], "name": ru.get(e.key, {}).get("name") or e.name.strip()}  # a name once set stays
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
