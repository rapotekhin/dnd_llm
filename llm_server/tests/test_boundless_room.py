"""A room of boundless making (v0.8.4.44.6, protocol 0.132.0): the dream's sixth hall tells the master it makes things,
recipes and spells there without limits of price and power, with the rules of items, of making and of recipes whole in
the prompt, no budget line, and the player's turn always on the full prompt."""

from llm_server import prompts, router
from llm_server.protocol import Snapshot, TurnRequestParams

from conftest import tavern_snapshot


def _snapshot(boundless: bool) -> Snapshot:
    raw = tavern_snapshot()
    raw["scene"]["boundless"] = boundless
    if raw.get("character") is not None:
        raw["character"]["reward_left_cp"] = 1500
    return Snapshot.model_validate(raw)


def test_the_boundless_room_tells_the_master_its_rules_and_drops_the_budget():
    text = prompts.system_prompt("exploration", _snapshot(True), None)
    assert "Здесь создают без ограничений" in text and "без бюджета наград" in text
    assert "до долгого отдыха — ещё на" not in text
    assert {"items", "make", "craft"} <= set(prompts.auto_topics("exploration", _snapshot(True), "осмотреться"))
    plain = prompts.system_prompt("exploration", _snapshot(False), None)
    assert "Здесь создают без ограничений" not in plain and "до долгого отдыха — ещё на" in plain
    assert "make" not in prompts.auto_topics("exploration", _snapshot(False), "осмотреться")


def test_a_player_s_words_there_go_to_the_full_prompt():
    def params(boundless: bool) -> TurnRequestParams:
        return TurnRequestParams.model_validate({"session_id": "s", "turn_id": "t-1", "mode": "exploration", "kind": "action",
                                                 "input": "Сделай жезл цепной молнии с 10 зарядами",
                                                 "snapshot": _snapshot(boundless).model_dump()})
    assert router.by_kind(params(True)) == "full"
    assert router.by_kind(params(False)) == ""
