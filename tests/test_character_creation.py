"""Character creation: point-buy ``CharacterBuild`` and ``create_character``."""

from __future__ import annotations

from core.builders.character_builder import CharacterBuild
from core.database.json_database import JsonDatabase
from core.entities.player import Player


def test_character_build_point_buy_cycle() -> None:
    b = CharacterBuild()
    assert b.points_remaining == 27
    assert b.abilities["str"] == 8
    assert b.decrease_ability("str") is False

    assert b.increase_ability("str") is True
    assert b.abilities["str"] == 9
    assert b.decrease_ability("str") is True
    assert b.abilities["str"] == 8

    spent = b.calculate_points_spent()
    assert spent == 0

    for _ in range(7):
        assert b.increase_ability("str") is True
    assert b.abilities["str"] == 15
    assert b.can_increase_ability("str") is False


def test_create_character_fighter_human_sets_stats_and_inventory() -> None:
    db = JsonDatabase()
    fighter_doc = db.get("/classes/fighter.json")

    b = CharacterBuild(
        name="Pytest Fighter",
        race="human",
        class_type="fighter",
        class_data=fighter_doc,
        alignment="lawful-good",
        abilities={"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
        points_remaining=0,
    )

    player = b.create_character()
    assert player.name == "Pytest Fighter"
    assert player.level == 1
    assert player.alignment == "lawful-good"
    assert player.class_type.index == "fighter"
    assert player.abilities.str == 15
    assert player.hit_points > 0
    assert player.xp == 5000
    gear = [x for x in player.inventory if x is not None]
    assert len(gear) >= 1


def test_human_race_data_applies_plus_one_to_all_abilities() -> None:
    db = JsonDatabase()
    fighter_doc = db.get("/classes/fighter.json")
    human_doc = db.get("/races/human.json")

    b = CharacterBuild(
        name="Human bonuses",
        race="human",
        race_data=human_doc,
        class_type="fighter",
        class_data=fighter_doc,
        alignment="neutral",
        abilities={"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
        points_remaining=0,
    )
    p = b.create_character()
    assert p.abilities.str == 16
    assert p.abilities.dex == 15
    assert p.abilities.con == 14
    assert p.abilities.int == 13
    assert p.abilities.wis == 11
    assert p.abilities.cha == 9


def test_create_wizard_has_spellcaster() -> None:
    db = JsonDatabase()
    wizard_doc = db.get("/classes/wizard.json")
    # Valid 27-point buy focused on INT
    b = CharacterBuild(
        name="Pytest Wizard",
        race="human",
        class_type="wizard",
        class_data=wizard_doc,
        alignment="true-neutral",
        abilities={"str": 8, "dex": 13, "con": 14, "int": 15, "wis": 12, "cha": 10},
        points_remaining=0,
    )
    p = b.create_character()
    assert p.class_type.index == "wizard"
    assert p.sc is not None
    assert hasattr(p.sc, "spell_slots")


def test_add_dagger_to_inventory_via_builder() -> None:
    db = JsonDatabase()
    build = CharacterBuild()
    player = Player.create_random_character(name="Invtest", race="human", class_type="fighter")
    player.inventory = []
    build._add_item_to_inventory(player, "dagger", 2, db)
    daggers = [x for x in player.inventory if x is not None and getattr(x, "index", "") == "dagger"]
    assert len(daggers) == 2
