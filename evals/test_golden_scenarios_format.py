"""Format check for the golden LLM scenarios (evals/golden/scenarios.yaml).

The scenarios are run against a real model later (llm_server/evals); here we only
keep the file loadable and consistent with docs/tech/golden-scenarios.md.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

SCENARIOS_FILE = Path(__file__).resolve().parent / "golden" / "scenarios.yaml"

MODES = {"exploration", "social", "trade", "combat"}
KINDS = {"enter", "resume", "action", "rest", "deal", "haggle", "quest", "ability", "downed", "combat_start", "combat_round", "death", "trap", "wait", "theft", "law", "goal", "shift"}
NO_INPUT_KINDS = {"enter", "resume", "rest", "downed"}  # deal / haggle / quest carry the engine facts in input
DC_TIERS = {"very_easy", "easy", "medium", "hard", "very_hard", "nearly_impossible"}
EFFECT_KINDS = {"give_item", "take_item", "coins", "damage", "heal", "condition", "cast", "use_feature", "use_item", "start_combat", "advance_time", "furnish", "take_prop", "prop_state",
                "quest_update", "flag", "xp", "npc_attitude", "advance_time", "move", "note", "equip", "crime_known", "crime_release", "npc_discount", "npc_favor", "accept_quest", "reveal_secret", "reputation", "take_from", "put_in", "unlock", "drop_item", "create_npc", "create_place", "npc_follow", "create_quest", "goal_assess", "goal_hint", "owner", "door", "disease", "recipe", "job", "property", "bank", "supplier"}
TOOLS = {"find_items", "create_item", "lookup_rule", "lookup_spell", "find_npcs", "find_places", "find_quests"}
EXPECT_KEYS = {"check", "max_checks", "effects", "next_mode", "narration", "options",
               "tools_required", "tools_forbidden", "missing_concept"}
CHECK_KEYS = {"required", "skill_in", "dc_tier_in", "contest_npc", "contest_skill_in", "tool_in"}
EFFECT_KEYS = {"required_kinds_any", "required_kinds_all", "forbidden_kinds", "max_count", "coins_max",
               "damage_severity_in", "forbidden_fields", "condition_save", "condition_tag_in", "condition_in"}
NARRATION_KEYS = {"must_match", "must_not_match", "max_sentences"}


@pytest.fixture(scope="module")
def data() -> dict:
    return yaml.safe_load(SCENARIOS_FILE.read_text(encoding="utf-8"))


def test_file_header(data: dict) -> None:
    assert data["format_version"] == 1
    assert data["bases"], "at least one base"
    assert len(data["scenarios"]) >= 10


def test_ids_unique_and_extends_known(data: dict) -> None:
    ids = [s["id"] for s in data["scenarios"]]
    assert len(ids) == len(set(ids)), "duplicate scenario ids"
    for s in data["scenarios"]:
        assert s["extends"] in data["bases"], s["id"]


def _resolved(data: dict, scenario: dict) -> dict:
    base = data["bases"][scenario["extends"]]
    return {**base, **scenario}


def test_scenarios_are_well_formed(data: dict) -> None:
    for raw in data["scenarios"]:
        s = _resolved(data, raw)
        sid = s["id"]
        assert s["title"] and s["category"], sid
        assert s["mode"] in MODES, sid
        assert s["kind"] in KINDS, sid
        assert (s["input"] is None) == (s["kind"] in NO_INPUT_KINDS), f"{sid}: input for action, deal, haggle only"
        assert raw.get("expect") or raw.get("rubric"), f"{sid}: nothing to evaluate"

        expect = raw.get("expect", {})
        assert set(expect) <= EXPECT_KEYS, f"{sid}: unknown expect keys {set(expect) - EXPECT_KEYS}"

        check = expect.get("check", {})
        assert set(check) <= CHECK_KEYS, sid
        assert set(check.get("dc_tier_in", [])) <= DC_TIERS, sid

        effects = expect.get("effects", {})
        assert set(effects) <= EFFECT_KEYS, sid
        for key in ("required_kinds_any", "required_kinds_all", "forbidden_kinds"):
            assert set(effects.get(key, [])) <= EFFECT_KINDS, f"{sid}: {key}"

        for key in ("tools_required", "tools_forbidden"):
            assert set(expect.get(key, [])) <= TOOLS, f"{sid}: {key}"

        next_mode = expect.get("next_mode")
        if next_mode is not None:
            assert next_mode["mode"] in MODES, sid

        narration = expect.get("narration", {})
        assert set(narration) <= NARRATION_KEYS, sid
        for pattern in narration.get("must_match", []) + narration.get("must_not_match", []):
            re.compile(pattern)
