"""Regression tests for playtest bugs fixed in v0.3.3 (B24–B29, docs/production/review-2026-10.md)."""

from __future__ import annotations

import pytest

from core.entities.player import Player
from helpers import make_game_equipment


# ── B24: starting gear worn, AC and unarmed damage by 5e ────────────────────

def _armor(index: str, base: int, dex_bonus: bool, max_dex=None):
    from dnd_5e_core.equipment.equipment import EquipmentCategory

    item = make_game_equipment(index=index, name=index, gp=10)
    item.category = EquipmentCategory(index="armor", name="Armor", url="/api/2014/equipment-categories/armor")
    item.armor_class_base = base
    item.armor_dex_bonus = dex_bonus
    item.armor_max_dex = max_dex
    return item


@pytest.mark.parametrize("armor, expected", [
    (None, 13),                                      # unarmored: 10 + DEX 3
    (("leather-armor", 11, True, None), 14),         # light: 11 + 3
    (("scale-mail", 14, True, 2), 16),               # medium: 14 + min(3, 2)
    (("chain-mail", 16, False, None), 16),           # heavy: no DEX
])
def test_b24_armor_class_by_armor_type(armor, expected) -> None:
    from core.utils.armor_class import compute_armor_class

    p = Player.create_random_character(name="AC", race="human", class_type="fighter")
    p.abilities.dex = 16  # +3
    p.inventory = []
    if armor:
        item = _armor(*armor)
        item.equipped, item.equipped_slot = True, "body"
        p.inventory.append(item)
    assert compute_armor_class(p) == expected
    assert p.armor_class == expected  # Character property uses the same rule


def test_b24_shield_adds_two() -> None:
    from core.utils.armor_class import compute_armor_class

    p = Player.create_random_character(name="SH", race="human", class_type="fighter")
    p.abilities.dex = 10
    shield = _armor("shield", 2, False)
    shield.equipped, shield.equipped_left_hand = True, True
    p.inventory = [shield]
    assert compute_armor_class(p) == 12


@pytest.mark.parametrize("cls", ["fighter", "wizard", "cleric", "rogue"])
def test_b24_new_character_wears_starting_gear(cls: str) -> None:
    """Kits are random choices (e.g. fighter: chain mail, or leather + longbow, with or
    without a shield), so the expected AC is derived from what ended up worn."""
    from core.builders.character_builder import STARTING_COINS_WITH_KIT_CP, CharacterBuild
    from core.database.json_database import JsonDatabase
    from core.utils.armor_class import armor_ac, is_body_armor, is_shield

    p = CharacterBuild(
        name="Kit", race="human", class_type=cls,
        class_data=JsonDatabase().get(f"/classes/{cls}.json"),
        alignment="neutral",
        abilities={"str": 15, "dex": 14, "con": 13, "int": 10, "wis": 12, "cha": 8},
        points_remaining=0,
    ).create_character()
    dex = p.abilities.get_modifier("dex")
    owned_armor = [it for it in p.inventory if hasattr(it, "armor_class_base") and is_body_armor(it)]
    worn_armor = [it for it in owned_armor if it.equipped]
    assert len(worn_armor) == (1 if owned_armor else 0), "best body armor is worn"
    shields = [it for it in p.inventory if hasattr(it, "armor_class_base") and is_shield(it)]
    assert all(it.equipped for it in shields), "shield is taken"

    expected = (armor_ac(worn_armor[0], dex) if worn_armor else 10 + dex) + 2 * len(shields)
    assert p.armor_class == expected
    assert any(getattr(it, "equipped_right_hand", False) for it in p.inventory), "weapon in hand"
    assert p.coins == STARTING_COINS_WITH_KIT_CP


def test_b24_unarmed_damage_is_one_plus_str() -> None:
    from core.utils.armor_class import unarmed_damage

    p = Player.create_random_character(name="U", race="human", class_type="fighter")
    p.abilities.str = 16
    assert unarmed_damage(p) == 4
    p.abilities.str = 6
    assert unarmed_damage(p) == 1  # never below 1


# ── B28: NPC loader keeps authored description, race and placement ──────────

def test_b28_npc_loader_keeps_description_and_race(tmp_path, patched_game_state) -> None:
    from core.loaders.npcs_loader import load_npcs_from_jsonl

    f = tmp_path / "npcs.jsonl"
    f.write_text(
        '{"id": "n1", "name": "Борик", "description": "Коренастый хозяин", "role": "innkeeper",'
        ' "location": "room-1", "quests": ["q1"]}\n', encoding="utf-8")
    load_npcs_from_jsonl(str(f))
    npc = patched_game_state.npcs["n1"]
    assert npc.description == "Коренастый хозяин"
    assert npc.location == "room-1" and npc.quests == ["q1"]
    assert str(getattr(npc.race, "index", npc.race)).lower().startswith("human")


# ── B26 / B29: dialogue prompt knows what just happened and the player's gender ──

def _social_state():
    from core.data.game_state_base import MainGameState
    from core.entities.npc import NPC

    gs = MainGameState()
    npc = NPC.create_random_character(name="Борик", race="human", class_type="fighter", level=1)
    npc.id = "n1"
    gs.npcs["n1"] = npc
    gs.player = Player.create_random_character(name="Ирма", race="human", class_type="fighter")
    return gs


def test_b26_b29_npc_prompt_has_recent_events_and_gender() -> None:
    from core.prompts.social_prompts import get_npc_system_prompt

    gs = _social_state()
    gs.player.gender = "female"
    prompt = get_npc_system_prompt(gs, "n1", "PLAYER: бью Мелвина\nDM: Мелвин падает со скамьи")
    assert "бью Мелвина" in prompt
    assert "женском роде" in prompt


def test_b29_exploration_prompt_has_gender() -> None:
    from test_exploration_loop_mocked import _minimal_game_state_two_rooms
    from core.gameplay.exploration import get_exploration_system_prompt

    gs = _minimal_game_state_two_rooms()
    gs.player.gender = "male"
    assert "мужском роде" in get_exploration_system_prompt(gs)


def test_b26_game_hands_exploration_context_to_dialogue() -> None:
    from unittest.mock import MagicMock
    from core.game import Game

    game = Game.__new__(Game)
    main, social = MagicMock(), MagicMock()
    main.pop_side_context.return_value = "DM: в таверне драка"
    game.screens = {"main": main, "social": social}
    game.current_screen_name = "main"
    game.api_manager = MagicMock()

    game._handle_screen_result("social:n1")

    social.set_npc.assert_called_once_with("n1")
    social.set_recent_events.assert_called_once_with("DM: в таверне драка")


def test_b25_prompt_forbids_resolving_attacks() -> None:
    from core.prompts.exploration_prompts import AGENT_RESOLUTION_INSTRUCTIONS

    assert "Атаки и урон решаешь НЕ ты" in AGENT_RESOLUTION_INSTRUCTIONS
