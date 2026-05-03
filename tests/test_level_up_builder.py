"""Smoke tests for ``LevelUpBuild.apply_level_up`` (level / ASI / features)."""

from __future__ import annotations

from core.builders.level_up_builder import LevelUpBuild
from core.entities.player import Player


def test_apply_level_up_sets_level_only() -> None:
    p = Player.create_random_character(name="L1", race="human", class_type="fighter")
    assert p.level == 1
    build = LevelUpBuild(new_level=2)
    build.apply_level_up(p)
    assert p.level == 2


def test_apply_level_up_increases_abilities_when_bonus_budget_set() -> None:
    p = Player.create_random_character(name="L2", race="human", class_type="fighter")
    p.abilities.str = 14
    build = LevelUpBuild(
        new_level=2,
        ability_score_bonuses=2,
        abilities={"str": 2, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0},
    )
    build.apply_level_up(p)
    assert p.abilities.str == 16


def test_apply_level_up_substitutes_subfeature_choice() -> None:
    p = Player.create_random_character(name="L3", race="human", class_type="fighter")
    p.features = ["parent-feature"]
    # Substitution runs only inside the ``if self.features`` branch of ``apply_level_up``.
    build = LevelUpBuild(
        new_level=2,
        features=["parent-feature"],
        feature_choices={"parent-feature": "child-feature"},
    )
    build.apply_level_up(p)
    assert "parent-feature" not in p.features
    assert "child-feature" in p.features
