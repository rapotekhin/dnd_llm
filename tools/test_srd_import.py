"""Every creature of the SRD through the import and the things it carries (v0.8.4.4).

Runs the importer on tools/srd/source in memory, writes nothing. A creature is dropped only when the engine has nothing
for it to fight with; what it strikes with and wears is a thing of the catalog, and it lies on its body after a fight.
"""

import json
import re
import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srd_import as imp  # noqa: E402

MONSTERS = imp.OUT / "monsters.json"


@pytest.fixture(scope="module")
def built() -> dict[str, Any]:
    return imp.Builder().monsters()


@pytest.fixture(scope="module")
def catalog() -> dict[str, Any]:
    return json.loads(imp.ITEMS.read_text(encoding="utf-8"))["catalog"]


@pytest.fixture(scope="module")
def source() -> dict[str, Any]:
    return {imp.sid(m["index"]): m for m in imp.all_of("monsters")}


def in_scope(m: dict[str, Any]) -> bool:
    return m["challenge_rating"] <= imp.MAX_MONSTER_CR or m["index"] in imp.NPC_TEMPLATES


def blows(m: dict[str, Any]) -> list[dict[str, Any]]:
    return [a for a in m.get("actions", []) if a["name"] != "Multiattack" and "attack_bonus" in a]


def test_the_data_in_the_repo_is_what_the_import_builds(built: dict[str, Any]) -> None:
    assert built == json.loads(MONSTERS.read_text(encoding="utf-8")), "run python tools/srd_import.py build"


def test_every_creature_that_can_fight_is_imported(built: dict[str, Any], source: dict[str, Any]) -> None:
    lost = [id_ for id_, m in source.items() if in_scope(m) and blows(m) and id_ not in built]
    assert not lost
    assert not [id_ for id_, m in source.items() if not in_scope(m) and id_ in built]


def test_every_creature_has_a_name_numbers_and_something_to_fight_with(built: dict[str, Any]) -> None:
    for id_, m in built.items():
        assert m["name"], id_
        assert m["hp"] > 0 and m["ac"] > 0, id_
        assert m["actions"], id_
        assert all(a["name"] for a in m["actions"]), id_


def test_every_thing_of_a_creature_is_in_the_catalog(built: dict[str, Any], catalog: dict[str, Any]) -> None:
    lost = [(id_, item) for id_, m in built.items() for item in m["equipment"] if item not in catalog]
    assert not lost
    for id_, m in built.items():
        assert len(m["equipment"]) == len(set(m["equipment"])), id_
        for item in m["equipment"]:
            assert catalog[item]["name"], item
            assert "weight" in catalog[item] and "value_cp" in catalog[item], item


def test_the_armor_of_a_statblock_is_worn(built: dict[str, Any], source: dict[str, Any]) -> None:
    for id_, m in built.items():
        for ac in source[id_].get("armor_class", []):
            for armor in ac.get("armor", []):
                assert imp.sid(armor["index"]) in m["equipment"], (id_, armor["index"])


def test_a_blow_with_a_weapon_of_the_catalog_names_it_and_it_is_carried(built: dict[str, Any], catalog: dict[str, Any]) -> None:
    by_name = {v["name_en"].lower(): k for k, v in catalog.items() if "weapon" in v and "name_en" in v}
    assert "crossbow_light" in by_name.values()
    for id_, m in built.items():
        for a in m["actions"]:
            words = re.sub(r"\s*\(.*\)", "", a["name_en"]).lower().split()
            for name in (" ".join(words), " ".join(reversed(words)), ", ".join(reversed(words))):
                if name in by_name:
                    assert a.get("item") == by_name[name], (id_, a["name_en"])
            if "item" in a:
                assert a["item"] in m["equipment"], (id_, a["name_en"])
                assert a["item"] in catalog, (id_, a["name_en"])


@pytest.mark.parametrize("name, item", [("Light Crossbow", "crossbow_light"), ("Hand Crossbow", "crossbow_hand"), ("Heavy Crossbow", "crossbow_heavy"),
                                        ("War Pick", "war_pick"), ("Scimitar", "scimitar"), ("Shortsword (Humanoid Form Only)", "shortsword"),
                                        ("Poisoned Dart", "dart"), ("Heavy Club", "club"), ("Harpoon", "spear"), ("Bite", ""), ("Rock", "")])
def test_the_thing_behind_a_blow(name: str, item: str) -> None:
    assert imp.action_item(name, imp.Builder().weapons) == item


def test_a_weapon_word_in_a_blow_is_never_left_without_a_thing(built: dict[str, Any], catalog: dict[str, Any]) -> None:
    words = {w for k, v in catalog.items() if "weapon" in v and "name_en" in v and "item_type" in v and not v.get("rarity")
             for w in re.findall(r"[a-z]+", v["name_en"].lower())}
    lost = [(id_, a["name_en"]) for id_, m in built.items() for a in m["actions"] if "item" not in a
            and words & set(re.findall(r"[a-z]+", a["name_en"].lower()))]
    assert not lost


def test_the_things_behind_blows_are_of_the_catalog(catalog: dict[str, Any]) -> None:
    assert not [item for item in imp.ACTION_ITEMS.values() if item not in catalog]


def test_a_weapon_shot_with_has_its_ammunition(built: dict[str, Any], catalog: dict[str, Any]) -> None:
    rules = json.loads((imp.ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))
    ammo = rules["item_rules"]["ammo"]
    for id_, m in built.items():
        for item in m["equipment"]:
            if "ammunition" in catalog[item].get("weapon", {}).get("properties", catalog[item].get("properties", [])):
                assert ammo.get(item) in catalog, (id_, item)
