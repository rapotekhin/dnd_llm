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


def test_add_dagger_to_inventory_via_builder() -> None:
    db = JsonDatabase()
    build = CharacterBuild()
    player = Player.create_random_character(name="Invtest", race="human", class_type="fighter")
    player.inventory = []
    build._add_item_to_inventory(player, "dagger", 2, db)
    daggers = [x for x in player.inventory if x is not None and getattr(x, "index", "") == "dagger"]
    assert len(daggers) == 2
