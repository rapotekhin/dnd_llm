"""Every creature of our base against its statblock in the SRD (v0.8.4.4): one test of a kind for each creature.

What the import reads wrong or drops shows here by name. NOT_IN_ENGINE is the list of what the engine has no action
for yet: an action is left out of the game only by a line here.
"""

import json
import re
import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srd_import as imp  # noqa: E402

BASE: dict[str, Any] = json.loads((imp.OUT / "monsters.json").read_text(encoding="utf-8"))
SOURCE: dict[str, Any] = {imp.sid(m["index"]): m for m in imp.all_of("monsters")}
IDS = sorted(BASE)
ABILITIES = {"str": "strength", "dex": "dexterity", "con": "constitution", "int": "intelligence", "wis": "wisdom", "cha": "charisma"}
# Non-attack actions of the statblocks, no engine concept behind them yet.
NOT_IN_ENGINE = {
    "blink_dog": ["Teleport"], "darkmantle": ["Darkness Aura"], "doppelganger": ["Read Thoughts"], "duergar": ["Enlarge", "Invisibility"],
    "giant_frog": ["Swallow"], "giant_octopus": ["Ink Cloud"], "giant_toad": ["Swallow"], "green_hag": ["Illusory Appearance", "Invisible Passage"],
    "imp": ["Invisibility"], "knight": ["Leadership"], "nightmare": ["Ethereal Stride"], "octopus": ["Ink Cloud"], "quasit": ["Invisibility"],
    "rust_monster": ["Antennae"], "sea_hag": ["Death Glare", "Illusory Appearance"], "sprite": ["Heart Sight", "Invisibility"],
    "will_o_wisp": ["Invisibility"],
}


def actions_of(id_: str) -> dict[str, Any]:
    return {a["name_en"]: a for a in BASE[id_]["actions"]}


def source_actions(id_: str) -> list[dict[str, Any]]:
    return [a for a in SOURCE[id_].get("actions", []) if a["name"] != "Multiattack"]


def rider(id_: str, name: str) -> dict[str, Any]:
    return imp.RIDERS.get(f"{SOURCE[id_]['index']}:{name}", {})


def test_the_base_covers_the_source() -> None:
    wanted = {id_ for id_, m in SOURCE.items() if m["challenge_rating"] <= imp.MAX_MONSTER_CR or m["index"] in imp.NPC_TEMPLATES}
    assert wanted - set(BASE) == {"frog", "sea_horse", "shrieker"}  # nothing to fight with: not fighters of the engine


@pytest.mark.parametrize("id_", IDS)
def test_numbers(id_: str) -> None:
    b, m = BASE[id_], SOURCE[id_]
    assert b["name"] and b["name_en"] == m["name"]
    assert (b["size"], b["type"], b["cr"], b["xp"], b["hp"], b["hit_dice"], b["prof"]) == (
        m["size"].lower(), m["type"], m["challenge_rating"], m["xp"], m["hit_points"], m["hit_dice"], m["proficiency_bonus"])
    assert b["ac"] == m["armor_class"][0]["value"]
    speed = m.get("speed", {})
    assert (b["speed"], b["fly"], b["swim"]) == (imp.ft(speed.get("walk", "30 ft.")), imp.ft(speed.get("fly", "0 ft.")), imp.ft(speed.get("swim", "0 ft.")))
    senses = m.get("senses", {})
    assert (b["darkvision"], b["blindsight"], b["passive_perception"]) == (imp.ft(senses.get("darkvision", "0 ft.")), imp.ft(senses.get("blindsight", "0 ft.")), senses.get("passive_perception", 10))


@pytest.mark.parametrize("id_", IDS)
def test_ability_scores_saves_and_skills(id_: str) -> None:
    b, m = BASE[id_], SOURCE[id_]
    assert b["abilities"] == {short: m[full] for short, full in ABILITIES.items()}
    saves = {p["proficiency"]["index"].removeprefix("saving-throw-"): p["value"] for p in m["proficiencies"] if p["proficiency"]["index"].startswith("saving-throw-")}
    skills = {imp.sid(p["proficiency"]["index"].removeprefix("skill-")): p["value"] for p in m["proficiencies"] if p["proficiency"]["index"].startswith("skill-")}
    assert b["saves"] == saves
    assert b["skills"] == skills


@pytest.mark.parametrize("id_", IDS)
def test_resistances_immunities_and_vulnerabilities(id_: str) -> None:
    b, m = BASE[id_], SOURCE[id_]
    assert b["resistances"] == m["damage_resistances"]
    assert b["immunities"] == m["damage_immunities"]
    assert b["vulnerabilities"] == m["damage_vulnerabilities"]
    assert b["condition_immunities"] == [imp.sid(c["index"]) for c in m["condition_immunities"]]


@pytest.mark.parametrize("id_", IDS)
def test_special_abilities(id_: str) -> None:
    b, m = BASE[id_], SOURCE[id_]
    assert [t["id"] for t in b["traits"]] == [imp.sid(t["name"].lower().replace(" ", "_").replace("(", "").replace(")", "").replace("'", "")) for t in m["special_abilities"]]
    for t in b["traits"]:
        assert t["name"] and t["desc"], t["id"]
    casts = [t for t in m["special_abilities"] if t.get("spellcasting")]
    assert bool(casts) == ("spellcasting" in b)


@pytest.mark.parametrize("id_", IDS)
def test_every_action_is_there_or_named_as_left_out(id_: str) -> None:
    have = actions_of(id_)
    assert have
    wanted = {a["name"] for a in source_actions(id_)}
    assert wanted - set(have) == set(NOT_IN_ENGINE.get(id_, []))
    assert not set(have) - wanted
    assert all(a["name"] for a in have.values())


@pytest.mark.parametrize("id_", IDS)
def test_attacks_by_the_statblock(id_: str) -> None:
    have = actions_of(id_)
    for a in source_actions(id_):
        b = have.get(a["name"])
        over = rider(id_, a["name"])
        if b is None or "attack_bonus" not in a or "kind" in over:
            continue
        assert b["to_hit"] == a["attack_bonus"], a["name"]
        desc = over.get("desc", a.get("desc", ""))
        far = re.search(r"range (\d+)(?: ft\.)?/(\d+) ft", desc)
        if far:
            assert b["range"] == [int(far.group(1)), int(far.group(2))], a["name"]
        assert b["kind"] == ("ranged" if far and not desc.startswith("Melee") else "melee"), a["name"]
        if "damage" in over:
            continue
        parts = [d["from"]["options"][0] if isinstance(d, dict) and d.get("from") else d for d in a.get("damage", [])]
        assert b["damage"] == [{"dice": imp.dice_text(d["damage_dice"]), "type": d["damage_type"]["index"]} for d in parts if d.get("damage_dice") and d.get("damage_type")], a["name"]


@pytest.mark.parametrize("id_", IDS)
def test_saves_and_uses_of_actions(id_: str) -> None:
    have = actions_of(id_)
    for a in source_actions(id_):
        b = have.get(a["name"])
        if b is None:
            continue
        if a.get("dc") and "attack_bonus" not in a and "save" not in rider(id_, a["name"]):
            assert b["save"]["ability"] == a["dc"]["dc_type"]["index"] and b["save"]["dc"] == a["dc"]["dc_value"], a["name"]
        use = a.get("usage") or {}
        if use.get("type") == "recharge on roll":
            assert b["recharge"] == int(use["min_value"]), a["name"]
        elif use.get("type") == "per day":
            assert b["per_day"] == int(use["times"]), a["name"]
        elif use.get("type") == "recharge after rest":
            assert b["per_day"] == 1, a["name"]


@pytest.mark.parametrize("id_", IDS)
def test_multiattack_strikes_with_its_own_actions(id_: str) -> None:
    have = actions_of(id_)
    for x in BASE[id_]["multiattack"]:
        assert x["action"] in have, x
        assert x["count"] >= 1, x
    if any(a["name"] == "Multiattack" and (a.get("actions") or a.get("action_options")) for a in SOURCE[id_]["actions"]):
        assert BASE[id_]["multiattack"]


@pytest.mark.parametrize("id_", IDS)
def test_reactions(id_: str) -> None:
    assert [r["name_en"] for r in BASE[id_]["reactions"]] == [r["name"] for r in SOURCE[id_]["reactions"]]
