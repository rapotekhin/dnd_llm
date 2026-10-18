"""The turn agent end to end over a real WebSocket: a scripted FunctionModel plays the LLM, the test plays
Godot and answers engine.* calls (ADR-0008, ADR-0009). No network, no money."""

import re

from fastapi.testclient import TestClient
from pydantic_ai.exceptions import ModelHTTPError
from pydantic_ai.messages import ModelMessage, ModelResponse, RetryPromptPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel

from llm_server.app import create_app
from llm_server.protocol import GeneratedItem, ModelInfo

from conftest import AUTH, hello, make_services, request, tavern_snapshot

INNKEEPER = "a1f3c7c2-6b1e-4e92-9e2a-111111111111"
CHECK_OK = {"check_id": "c-1", "rolls": [15], "bonus": 3, "total": 18, "dc": 15, "success": True, "nat": 15}


def last_tool_text(messages: list[ModelMessage]) -> str:
    for part in reversed(messages[-1].parts):
        if isinstance(part, (ToolReturnPart, RetryPromptPart)):
            return str(part.content)
    return ""


def effect_id(messages: list[ModelMessage]) -> str:
    m = re.search(r"effect_id=(\S+?)\.", last_tool_text(messages))
    return m.group(1) if m else ""


def scripted(*steps, raise_first: Exception | None = None):
    """Each step: (tool_name, args) or ("final", args); args may be a function of the messages so far."""
    state = {"n": 0, "raised": False, "prompts": []}

    async def fn(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        if raise_first is not None and not state["raised"]:
            state["raised"] = True
            raise raise_first
        state["prompts"].append(messages)
        name, args = steps[min(state["n"], len(steps) - 1)]
        state["n"] += 1
        if callable(args):
            args = args(messages)
        return ModelResponse(parts=[ToolCallPart(info.output_tools[0].name if name == "final" else name, args)])

    fn.state = state  # type: ignore[attr-defined]
    return fn


def default_engine(method: str, params: dict) -> dict:
    return {
        "engine.check": CHECK_OK,
        "engine.validate": {"accepted": True, "effect_id": "e-1", "summary": "−5 HP"},
        "engine.lookup": {"found": True, "data": {"name": "Борик"}},
        "engine.find_items": {"items": []},
    }[method]


def play(data_dir, fn, engine=default_engine, services=None, **params):
    """One turn.request; returns (response, engine calls seen, services)."""
    services = services or make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent")
    turn = {"turn_id": "t-1", "mode": "exploration", "kind": "action", "input": "осматриваю зал", "snapshot": tavern_snapshot()}
    turn.update(params)
    calls = []
    with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        request(ws, "g-2", "turn.request", turn)
        while True:
            msg = ws.receive_json()
            if "method" not in msg:
                return msg, calls, services
            calls.append(msg)
            answer = engine(msg["method"], msg["params"])
            if "error" in answer:
                ws.send_json({"jsonrpc": "2.0", "id": msg["id"], "error": answer["error"]})
            else:
                ws.send_json({"jsonrpc": "2.0", "id": msg["id"], "result": answer})


def reason(msg: dict) -> str:
    return msg["error"]["data"]["reason"]


# --- happy path -------------------------------------------------------------------


def test_turn_with_check_and_effect(data_dir):
    fn = scripted(
        ("request_check", {"skill": "perception", "dc_tier": "medium", "reason": "заметить вора"}),
        ("propose_effect", {"effect": {"kind": "damage", "severity": "unpleasant", "damage_type": "колющий", "reason": "заноза"}}),
        ("final", lambda m: {"narration": "Ты замечаешь вора.", "options": ["Догнать вора"], "effect_ids": [effect_id(m)]}),
    )
    msg, calls, _ = play(data_dir, fn)
    result = msg["result"]
    assert [c["method"] for c in calls] == ["engine.check", "engine.validate"]
    assert calls[0]["params"] == {"turn_id": "t-1", "skill": "perception", "dc_tier": "medium"}
    assert calls[1]["params"]["effect"]["kind"] == "damage"
    assert result["check_ids"] == ["c-1"]
    assert result["effect_ids"] == ["e-1"]
    assert result["options"] == ["Догнать вора"]
    assert result["next_mode"] is None
    assert result["usage"]["model"] == "anthropic/claude-haiku-5.5"
    # the model saw the engine's verdict, not a number it made up
    assert "Успех: 18 против DC 15" in last_tool_text(fn.state["prompts"][1])


def test_system_prompt_has_scene_character_and_rules(data_dir):
    fn = scripted(("final", {"narration": "Таверна шумит."}))
    play(data_dir, fn)
    first = fn.state["prompts"][0]
    text = "\n".join(str(getattr(p, "content", "")) for msg in first for p in msg.parts)
    instructions = "\n".join(str(getattr(msg, "instructions", "") or "") for msg in first)
    full = text + instructions
    for needle in ("Главный зал", "Борик Каменный Бокал", INNKEEPER, "Айра", "женском роде", "request_check", "Не переспрашивай",
                   "Действие игрока: осматриваю зал"):
        assert needle in full, needle


def test_social_turn_and_mode_switch(data_dir):
    fn = scripted(("final", {"narration": "— Чего изволите?", "next_mode": "trade", "npc_id": INNKEEPER}))
    msg, _, _ = play(data_dir, fn, mode="social", npc_id=INNKEEPER, kind="enter", input="")
    assert msg["result"]["next_mode"] == {"mode": "trade", "npc_id": INNKEEPER}
    instructions = "\n".join(str(getattr(m, "instructions", "") or "") for m in fn.state["prompts"][0])
    assert "Ты — Борик Каменный Бокал" in instructions
    assert "О себе NPC говорит в мужском роде" in instructions


def test_exploration_to_social_needs_an_npc_from_the_scene(data_dir):
    fn = scripted(
        ("final", {"narration": "Ты подходишь к незнакомцу.", "next_mode": "social", "npc_id": "nobody"}),
        ("final", {"narration": "Ты подходишь к Борику.", "next_mode": "social", "npc_id": INNKEEPER}),
    )
    msg, _, _ = play(data_dir, fn)
    assert msg["result"]["next_mode"] == {"mode": "social", "npc_id": INNKEEPER}
    assert "npc_id из списка NPC сцены" in last_tool_text(fn.state["prompts"][1])


def test_social_mode_without_npc_is_invalid_params(data_dir):
    msg, _, _ = play(data_dir, scripted(("final", {"narration": "x"})), mode="social", npc_id="nobody")
    assert msg["error"]["code"] == -32602


# --- engine verdicts and limits -------------------------------------------------------


def test_rejected_effect_reaches_the_model_and_is_not_applied(data_dir):
    def engine(method, params):
        return {"accepted": False, "reason": "нет такого выхода"} if method == "engine.validate" else default_engine(method, params)

    fn = scripted(
        ("propose_effect", {"effect": {"kind": "move", "room_id": "moon"}}),
        ("final", {"narration": "Дверь не поддаётся."}),
    )
    msg, _, _ = play(data_dir, fn, engine)
    assert msg["result"]["effect_ids"] == []
    assert "Отклонено движком: нет такого выхода" in last_tool_text(fn.state["prompts"][1])


def test_unknown_effect_id_is_retried(data_dir):
    fn = scripted(
        ("final", {"narration": "Ты находишь кольцо.", "effect_ids": ["e-made-up"]}),
        ("final", {"narration": "Ты ничего не находишь."}),
    )
    msg, _, _ = play(data_dir, fn)
    assert msg["result"]["narration"] == "Ты ничего не находишь."
    assert "не принимались движком" in last_tool_text(fn.state["prompts"][1])


def test_second_check_is_refused_without_calling_the_engine(data_dir):
    fn = scripted(
        ("request_check", {"skill": "perception", "dc_tier": "easy", "reason": "a"}),
        ("request_check", {"skill": "stealth", "dc_tier": "easy", "reason": "b"}),
        ("final", {"narration": "Готово."}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert [c["method"] for c in calls] == ["engine.check"]
    assert "лимит проверок" in last_tool_text(fn.state["prompts"][2])
    assert msg["result"]["check_ids"] == ["c-1"]


def test_new_item_needs_a_search_first_and_lands_in_the_library(data_dir):
    item = GeneratedItem(name="Кинжал инея", item_type="weapon", base="dagger", rarity="uncommon", value_cp=20000,
                         properties=["finesse", "cold_damage"], description="Клинок покрыт изморозью.").model_dump()

    def engine(method, params):
        if method == "engine.validate":
            return {"accepted": True, "effect_id": "e-7", "summary": "Получено: Кинжал инея", "item_id": "gen-frost-dagger"}
        return default_engine(method, params)

    fn = scripted(
        ("propose_effect", {"effect": {"kind": "give_item", "item": item}}),
        ("find_items", {"query": "кинжал", "properties": ["cold_damage"]}),
        ("propose_effect", {"effect": {"kind": "give_item", "item": item}}),
        ("final", lambda m: {"narration": "Под камнем — кинжал в инее.", "effect_ids": [effect_id(m)]}),
    )
    msg, calls, services = play(data_dir, fn, engine)
    assert "перед созданием нового предмета" in last_tool_text(fn.state["prompts"][1])
    assert [c["method"] for c in calls] == ["engine.find_items", "engine.validate"]
    assert msg["result"]["effect_ids"] == ["e-7"]
    found = services.library.search("инея")
    assert [f.item_id for f in found] == ["gen-frost-dagger"]
    assert found[0].source == "library"


def test_lookup_passes_through(data_dir):
    fn = scripted(("lookup", {"kind": "npc", "id": INNKEEPER}), ("final", {"narration": "Борик кивает."}))
    _, calls, _ = play(data_dir, fn)
    assert calls[0]["params"] == {"turn_id": "t-1", "kind": "npc", "id": INNKEEPER}
    assert "Борик" in last_tool_text(fn.state["prompts"][1])


def test_engine_error_in_a_tool_fails_the_turn(data_dir):
    def engine(method, params):
        return {"error": {"code": -32603, "message": "boom"}}

    msg, _, _ = play(data_dir, scripted(("request_check", {"skill": "perception", "dc_tier": "easy", "reason": "a"})), engine)
    assert reason(msg) == "engine_error"


# --- models, budget, retries ------------------------------------------------------------


def test_model_outside_the_whitelist_is_rejected(data_dir):
    msg, _, _ = play(data_dir, scripted(("final", {"narration": "x"})), model="openai/gpt-9")
    assert msg["error"]["code"] == -32602


def test_player_picked_model_is_used(data_dir):
    msg, _, _ = play(data_dir, scripted(("final", {"narration": "x"})), model="qwen/qwen3.8-27b")
    assert msg["result"]["usage"]["model"] == "qwen/qwen3.8-27b"


def test_budget_is_spent_and_enforced(data_dir):
    fn = scripted(("final", {"narration": "x"}))
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent",
                             daily_budget_usd=0.0001)
    services.models._info["anthropic/claude-haiku-5.5"] = ModelInfo(
        id="anthropic/claude-haiku-5.5", name="Haiku", input_usd_per_mtok=1000.0, output_usd_per_mtok=1000.0)
    msg, _, _ = play(data_dir, fn, services=services)
    assert msg["result"]["usage"]["cost_usd"] > 0
    assert msg["result"]["usage"]["daily_budget_left_usd"] == 0
    msg, _, _ = play(data_dir, fn, services=services)
    assert reason(msg) == "budget_exceeded"


def test_openrouter_503_is_retried(data_dir, monkeypatch):
    monkeypatch.setattr("llm_server.turns._sleep", _no_sleep)
    fn = scripted(("final", {"narration": "Со второй попытки."}), raise_first=ModelHTTPError(503, "m"))
    msg, _, _ = play(data_dir, fn)
    assert msg["result"]["narration"] == "Со второй попытки."


def test_openrouter_failure_after_a_check_is_not_retried(data_dir, monkeypatch):
    monkeypatch.setattr("llm_server.turns._sleep", _no_sleep)
    state = {"n": 0}

    async def fn(messages, info):
        state["n"] += 1
        if state["n"] == 1:
            return ModelResponse(parts=[ToolCallPart("request_check", {"skill": "perception", "dc_tier": "easy", "reason": "a"})])
        raise ModelHTTPError(503, "m")

    msg, calls, _ = play(data_dir, fn)
    assert reason(msg) == "llm_unavailable"
    assert len(calls) == 1  # no second roll


def test_invalid_output_after_retries(data_dir):
    msg, _, _ = play(data_dir, scripted(("final", {"narration": "   "})))
    assert reason(msg) == "llm_invalid_output"


async def _no_sleep(_s):
    return None


# --- summary and status ----------------------------------------------------------------


def test_summary_request(data_dir):
    async def fn(messages, info):
        return ModelResponse(parts=[ToolCallPart(info.output_tools[0].name, {"summary": "Игрок выпил эля с Бориком."})])

    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent")
    with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        request(ws, "g-2", "summary.request", {"kind": "dialogue", "subject_id": INNKEEPER, "events": ["Игрок: эля!", "Борик: держи."]})
        msg = ws.receive_json()
        request(ws, "g-3", "session.status")
        status = ws.receive_json()["result"]
    assert msg["result"]["summary"] == "Игрок выпил эля с Бориком."
    assert status["budget"]["daily_usd"] == 1.0
    assert status["models"][0]["id"] == "anthropic/claude-haiku-5.5"
