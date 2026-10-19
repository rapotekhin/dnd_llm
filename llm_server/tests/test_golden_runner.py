"""The golden runner offline: every scenario adapts to protocol 0.2.0, hard checks work, a scripted model runs
through the mock engine. The real run (OpenRouter, judge) is manual: `uv run python -m llm_server.golden`."""

import asyncio

from pydantic_ai.models.function import FunctionModel

from llm_server import golden

from test_agent import effect_id, scripted


def scenarios() -> dict[str, dict]:
    return {sc["id"]: sc for sc in golden.load_scenarios()}


def test_every_scenario_adapts_or_is_marked_unsupported():
    for sc in golden.load_scenarios():
        if golden.unsupported(sc):
            continue
        params = golden.to_turn_params(sc)
        assert params.snapshot.scene is not None, sc["id"]
        assert params.snapshot.character is not None, sc["id"]


def test_unsupported_ones_say_why():
    by_id = scenarios()
    assert golden.unsupported(by_id["attack_innkeeper"]) == ""  # combat mode since 0.7.0
    assert "состязан" in golden.unsupported(by_id["lie_to_guard_contest"])
    assert golden.unsupported(by_id["dm_style_dry"]) == ""  # style and content limits travel in 0.2.2
    veil = golden.to_turn_params(by_id["content_veil_respected"]).snapshot.world
    assert veil is not None and veil.veils == ["пытки"]
    assert golden.to_turn_params(by_id["dm_style_dry"]).snapshot.world.dm_style == "dry"
    assert golden.unsupported(by_id["search_room_fail"]) == ""


def test_adapter_keeps_what_the_master_needs():
    params = golden.to_turn_params(scenarios()["narration_matches_effects"])
    scene = params.snapshot.scene
    assert "потёртый кошелёк (37 мм внутри)" in scene.room_description
    assert [n.attitude for n in scene.npcs] == [0, 0]
    assert params.snapshot.character.hp == 20
    social = golden.to_turn_params(scenarios()["social_to_trade"])
    assert social.npc_id == "npc_innkeeper"


def test_hard_checks():
    engine = golden.MockEngine({})
    engine.calls = [("engine.check", {"skill": "stealth", "dc_tier": "hard"}),
                    ("engine.validate", {"effect": {"kind": "coins", "delta_cp": 50}})]
    out = {"narration": "Ты находишь тайник. Выпало 17.", "options": [], "next_mode": {"mode": "social", "npc_id": "x"}}
    fails = golden.check_expect({
        "check": {"required": True, "skill_in": ["perception"], "dc_tier_in": ["easy"]},
        "effects": {"forbidden_kinds": ["coins"], "coins_max": 10},
        "next_mode": None,
        "narration": {"must_not_match": ["тайник"], "max_sentences": 1},
        "options": {"min": 1},
        "tools_required": ["find_items"],
    }, out, engine, [])
    joined = " | ".join(fails)
    for needle in ("навык", "сложность", "запрещённые", "монет 50", "лишняя смена", "тайник", "предложений 2", "вариантов 0", "find_items"):
        assert needle in joined, needle


def test_severity_alias():
    engine = golden.MockEngine({})
    engine.calls = [("engine.validate", {"effect": {"kind": "damage", "severity": "unpleasant"}})]
    assert golden.check_expect({"effects": {"damage_severity_in": ["setback"]}}, {"narration": ""}, engine, []) == []


def test_scripted_run_through_the_mock_engine():
    sc = scenarios()["search_room_fail"]
    fn = scripted(
        ("request_check", {"skill": "perception", "dc_tier": "medium", "reason": "поиск"}),
        ("final", {"narration": "Ты обшариваешь зал, но ничего не находишь.", "options": ["Спросить хозяина"]}),
    )
    o = asyncio.run(golden.run_one(sc, FunctionModel(fn, model_name="m"), "m", None, {}))
    assert o.status == "pass", o.fails
    assert o.checks == [{"turn_id": "t-1", "skill": "perception", "dc_tier": "medium"}]
    assert "request_check" in o.tools
    assert "Провал: 14 против DC 15" in str(fn.state["prompts"][1][-1].parts[0].content)


def test_scripted_failure_is_reported():
    sc = scenarios()["item_dedupe"]
    item = {"name": "Кинжал ворона", "item_type": "weapon", "rarity": "uncommon", "value_cp": 100, "properties": ["finesse"]}
    fn = scripted(
        ("find_items", {"query": "кинжал"}),
        ("propose_effect", {"effect": {"kind": "give_item", "item": item}}),
        ("final", lambda m: {"narration": "Ты берёшь кинжал.", "effect_ids": [effect_id(m)]}),
    )
    o = asyncio.run(golden.run_one(sc, FunctionModel(fn, model_name="m"), "m", None, {}))
    assert o.status == "fail"
    assert any("create_item" in f for f in o.fails)
    md = golden.report_markdown("m", None, [o])
    assert "`item_dedupe`" in md and "✗" in md
