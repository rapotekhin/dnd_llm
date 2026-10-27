"""The turn agent end to end over a real WebSocket: a scripted FunctionModel plays the LLM, the test plays
Godot and answers engine.* calls (ADR-0008, ADR-0009). No network, no money."""

import json
import re

from fastapi.testclient import TestClient
from pydantic_ai.exceptions import ModelHTTPError, UnexpectedModelBehavior
from pydantic_ai.messages import ModelMessage, ModelResponse, RetryPromptPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel

from llm_server.app import create_app
from llm_server.protocol import GeneratedItem, ModelInfo

from conftest import AUTH, hello, make_services, request, tavern_snapshot

INNKEEPER = "npc_innkeeper"
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
        if name == "propose_effect" and isinstance(args.get("effect"), dict):
            args = {**args, "effect": json.dumps(args["effect"], ensure_ascii=False)}  # the tool takes a JSON string
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
    assert result["usage"]["model"] == "deepseek/deepseek-v4.1-flash-1017"
    # the model saw the engine's verdict, not a number it made up
    assert "Успех: 18 против DC 15" in last_tool_text(fn.state["prompts"][1])


def test_system_prompt_has_scene_character_and_rules(data_dir):
    fn = scripted(("final", {"narration": "Таверна шумит."}))
    play(data_dir, fn)
    first = fn.state["prompts"][0]
    text = "\n".join(str(getattr(p, "content", "")) for msg in first for p in msg.parts)
    instructions = "\n".join(str(getattr(msg, "instructions", "") or "") for msg in first)
    full = text + instructions
    for needle in ("общий зал", "Бруно Хмель", INNKEEPER, "Айра", "женском роде", "request_check", "Не переспрашивай",
                   "Действие игрока: осматриваю зал"):
        assert needle in full, needle


def test_social_turn_and_mode_switch(data_dir):
    fn = scripted(("final", {"narration": "— Чего изволите?", "next_mode": "trade", "npc_id": INNKEEPER}))
    msg, _, _ = play(data_dir, fn, mode="social", npc_id=INNKEEPER, kind="enter", input="")
    assert msg["result"]["next_mode"] == {"mode": "trade", "npc_id": INNKEEPER}
    instructions = "\n".join(str(getattr(m, "instructions", "") or "") for m in fn.state["prompts"][0])
    assert "Ты — Бруно Хмель" in instructions
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


def test_a_wrong_check_is_refused_not_a_failed_turn(data_dir):
    # v0.7.22.16 (the author's trace): request_check without a skill or with a wrong tier lost three turns in a row
    fn = scripted(
        ("request_check", {"dc_tier": "medium", "reason": "a"}),
        ("request_check", {"skill": "perception", "dc_tier": "trivial", "reason": "b"}),
        ("request_check", {"skill": "perception", "save": "", "dc_tier": "easy", "reason": "c", "sense": "smell"}),
        ("final", {"narration": "Готово."}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert "ровно одно" in last_tool_text(fn.state["prompts"][1])
    assert "dc_tier" in last_tool_text(fn.state["prompts"][2])
    assert [c["method"] for c in calls] == ["engine.check"]
    assert calls[0]["params"].get("sense") is None  # a sense the engine does not know is dropped
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
    services.models._info["deepseek/deepseek-v4.1-flash-1017"] = ModelInfo(
        id="deepseek/deepseek-v4.1-flash-1017", name="Haiku", input_usd_per_mtok=1000.0, output_usd_per_mtok=1000.0)
    msg, _, _ = play(data_dir, fn, services=services)
    assert msg["result"]["usage"]["cost_usd"] > 0
    assert services.budget.left() == 0
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
    assert status["models"][0]["id"] == "deepseek/deepseek-v4.1-flash-1017"


def test_effect_sent_as_a_json_string_is_accepted(data_dir):
    # Qwen 3.x sends nested tool arguments as JSON strings.
    fn = scripted(
        ("propose_effect", {"effect": '{"kind": "flag", "flag": "door_open"}'}),
        ("final", lambda m: {"narration": "Дверь открыта.", "effect_ids": [effect_id(m)]}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert calls[0]["params"]["effect"] == {"kind": "flag", "flag": "door_open", "value": True}
    assert msg["result"]["effect_ids"] == ["e-1"]


def test_effect_string_with_a_stray_bracket_after_it_is_accepted(data_dir):
    # DeepSeek at times sends the effect as a string with a stray `]` after the object (a place was never made).
    fn = scripted(
        ("rules", {"topic": "social"}),
        ("propose_effect", {"effect": '{"kind": "npc_follow", "npc_id": "npc_guard"}]'}),
        ("final", lambda m: {"narration": "Ведда идёт с тобой.", "effect_ids": [effect_id(m)]}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert calls[0]["params"]["effect"] == {"kind": "npc_follow", "npc_id": "npc_guard", "follow": True, "home": False}
    assert msg["result"]["effect_ids"] == ["e-1"]


def test_a_search_check_passes_what_the_engine_revealed(data_dir):
    def engine(method, params):
        if method == "engine.check":
            return {**CHECK_OK, "revealed": ["за бочками — старый лаз в стене"]}
        return default_engine(method, params)
    fn = scripted(("request_check", {"skill": "investigation", "dc_tier": "medium", "reason": "обыск"}),
                  ("final", {"narration": "Ты находишь лаз."}))
    play(data_dir, fn, engine=engine)
    text = last_tool_text(fn.state["prompts"][1])
    assert "Движок открыл скрытое" in text and "старый лаз" in text


def test_rest_turn_describes_the_morning(data_dir):
    fn = scripted(("final", {"narration": "Утро в Броде."}))
    msg, _, _ = play(data_dir, fn, kind="rest", input="")
    assert msg["result"]["narration"] == "Утро в Броде."
    assert "провёл ночь здесь" in str(fn.state["prompts"][0][-1].parts[-1].content)


def test_a_haggle_check_passes_the_engine_note(data_dir):
    def engine(method, params):
        if method == "engine.check":
            return {**CHECK_OK, "note": "Торг удался (Убеждение 17 против DC 13): скидка 10%."}
        return default_engine(method, params)
    fn = scripted(("request_check", {"skill": "persuasion", "dc_tier": "medium", "reason": "торг", "target_id": "npc_innkeeper"}),
                  ("final", {"narration": "Ладно, уступлю."}))
    play(data_dir, fn, engine=engine)
    text = last_tool_text(fn.state["prompts"][1])
    assert "Торг удался" in text and "ничего не меняй эффектами" in text


def test_cast_and_condition_effects_reach_the_engine(data_dir):
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "cast", "spell": "Волшебная стрела"}}),
        ("rules", {"topic": "conditions"}),
        ("propose_effect", {"effect": {"kind": "condition", "condition": "poisoned", "duration": "hour", "reason": "яд в кружке",
                                       "save": {"ability": "con", "dc_tier": "medium"}, "tag": "poison"}}),
        ("final", lambda m: {"narration": "Стрелы срываются с пальцев.", "effect_ids": ["e-1", "e-2"]}),
    )
    msg, calls, _ = play(data_dir, fn)
    kinds = [c["params"]["effect"]["kind"] for c in calls if c["method"] == "engine.validate"]
    assert kinds == ["cast", "condition"]


def test_an_effect_of_a_topic_waits_for_its_rules(data_dir):
    # v0.7.20.4: the rules of a topic left the system prompt; its effect is refused until the master reads them
    # (v0.7.34.3: the refusal carries them)
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "equip", "slot": "armor"}}),
        ("rules", {"topic": "equip"}),
        ("propose_effect", {"effect": {"kind": "equip", "slot": "armor"}}),
        ("final", lambda m: {"narration": "Ты снимаешь кольчугу.", "effect_ids": [effect_id(m)]}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert [c["params"]["effect"]["kind"] for c in calls if c["method"] == "engine.validate"] == ["equip"]
    texts = [last_tool_text(p) for p in fn.state["prompts"][1:3]]
    assert all("Снаряжение — эффектом `equip`" in t for t in texts)


def test_a_turn_out_of_output_tokens_is_tried_again_with_more(data_dir):
    # v0.7.4: the fight start in the burrow failed with «Model token limit (1500) exceeded» and the player saw an error.
    seen = []

    async def fn(messages, info):
        seen.append(info.model_settings.get("max_tokens") if info.model_settings else None)
        if len(seen) == 1:
            raise UnexpectedModelBehavior("Model token limit (2500) exceeded before any response was generated.")
        return ModelResponse(parts=[ToolCallPart(info.output_tools[0].name, {"narration": "Со второй попытки."})])

    msg, _, _ = play(data_dir, fn)
    assert msg["result"]["narration"] == "Со второй попытки."
    assert seen[-1] == 6000



def test_the_library_finds_items_by_words(tmp_path):
    # v0.7.18: any word of the query by its stem — «серебряный кинжал» finds «Кинжал инея».
    from llm_server.llm.library import ItemLibrary

    lib = ItemLibrary(tmp_path / "library.jsonl")
    lib.add("gen-a", GeneratedItem(name="Кинжал инея", item_type="weapon", base="dagger", rarity="uncommon", value_cp=1,
                                   properties=["cold_damage"]))
    lib.add("gen-b", GeneratedItem(name="Письмо Бруно", item_type="gear", rarity="common", value_cp=0, text="Илва, приходи."))
    assert [f.item_id for f in lib.search("серебряный кинжал")] == ["gen-a"]
    assert [f.item_id for f in lib.search("письмо")] == ["gen-b"]
    assert lib.search("меч") == []


def test_forgotten_effect_ids_are_taken_from_the_turn(data_dir):
    # v0.7.20: the model proposed a payment (accepted) and then forgot effect_ids — the turn keeps it instead of failing.
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "coins", "delta_cp": -10, "reason": "серебряный за слухи"}}),
        ("final", lambda m: {"narration": "Горм сгребает монету.", "changes": ["Бран заплатил серебряный"], "effect_ids": []}),
    )
    msg, calls, services = play(data_dir, fn)
    assert msg["result"]["effect_ids"] == ["e-1"]


def _routed(data_dir, fn):
    return make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent", router=True)


def test_a_turn_the_engine_resolved_goes_short_without_a_router(data_dir):
    # v0.7.20.4: a deal is only retold — the short prompt, no rules, no tools, no router call
    fn = scripted(("final", {"narration": "Бруно ставит кружку перед тобой.", "options": ["Выпить"]}))
    msg, calls, _ = play(data_dir, fn, services=_routed(data_dir, fn), kind="deal", input="куплено: эль")
    assert msg["result"]["narration"] == "Бруно ставит кружку перед тобой." and calls == []
    system = str(fn.state["prompts"][0][0].instructions)
    assert "Короткий ход" in system and len(system) < 4000 and fn.state["n"] == 1


def test_the_router_sends_words_short_and_deeds_full(data_dir):
    fn = scripted(("final", {"full": False}), ("final", {"narration": "Борик кивает: тихий вечер."}))
    msg, _, _ = play(data_dir, fn, services=_routed(data_dir, fn), input="спрашиваю, как вечер")
    assert msg["result"]["narration"] == "Борик кивает: тихий вечер." and fn.state["n"] == 2
    fn = scripted(("final", {"full": True}), ("request_check", {"skill": "investigation", "dc_tier": "medium", "reason": "обыск"}),
                  ("final", {"narration": "Под стойкой — ничего."}))
    msg, calls, _ = play(data_dir, fn, services=_routed(data_dir, fn), input="обыскиваю стойку")
    assert [c["method"] for c in calls] == ["engine.check"] and "Подробные правила" in str(fn.state["prompts"][1][0].instructions)


def test_the_short_master_may_ask_for_the_full_prompt(data_dir):
    fn = scripted(("final", {"full": False}), ("final", {"need_full": True}), ("final", {"narration": "Ты отдаёшь монету."}))
    msg, _, _ = play(data_dir, fn, services=_routed(data_dir, fn), input="кидаю монету нищему")
    assert msg["result"]["narration"] == "Ты отдаёшь монету." and fn.state["n"] == 3


def test_a_model_that_rejects_big_schemas_sends_the_effect_as_json_text(data_dir):
    # v0.7.21: Google rejected the 33-kind union outright — for it the effect is a JSON string, checked by the backend
    seen = {}

    def fn_tools(messages, info):
        seen["param"] = next(t for t in info.function_tools if t.name == "propose_effect").parameters_json_schema["properties"]["effect"]
        return fn(messages, info)

    fn = scripted(
        ("propose_effect", {"effect": '{"kind": "flag", "flag": "door_open"}'}),
        ("propose_effect", {"effect": '{"kind": "flag", "flag": "door_open", "colour": "red"}'}),
        ("final", lambda m: {"narration": "Дверь открыта.", "effect_ids": [effect_id(m)]}),
    )
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn_tools, model_name=m), turn_handler="agent")
    msg, calls, _ = play(data_dir, fn, services=services, model="google/gemini-3.8-flash")
    assert seen["param"]["type"] == "string"
    assert [c["params"]["effect"] for c in calls if c["method"] == "engine.validate"] == [{"kind": "flag", "flag": "door_open", "value": True}]
    assert "не по схеме" in last_tool_text(fn.state["prompts"][2])


def test_a_malformed_effect_is_refused_and_the_turn_goes_on(data_dir):
    # v0.7.21.2: a mistyped effect is a refusal of the tool, not a failed turn
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "create_quest", "title": "Заказ", "scale": "trifle", "steps": []}}),
        ("propose_effect", {"effect": {"kind": "create_quest", "title": "Заказ", "scale": "huge"}}),
        ("propose_effect", {"effect": {"kind": "create_quest"}}),
        ("final", {"narration": "На доске ничего не разобрать."}),
    )
    msg, calls, _ = play(data_dir, fn)
    assert msg["result"]["narration"] == "На доске ничего не разобрать." and calls == []
    assert "заверши ход словами" in last_tool_text(fn.state["prompts"][3])


def test_a_search_brings_its_topic_and_a_library_good_goes_to_stock_new(data_dir):
    # v0.7.22.25.1 (the author's trace): find_npcs answered without the rules, and create_npc was refused «read
    # rules first»; a bread of the library was refused as «not of the catalog».
    seen = []

    def engine(method, params):
        if method == "engine.find_npcs":
            return {"npcs": []}
        if method == "engine.validate":
            seen.append(params["effect"])
            return {"accepted": True, "effect_id": "e-3", "summary": "Новый человек: Сарра — пекарша"}
        return default_engine(method, params)

    fn = scripted(
        ("find_npcs", {"query": "пекарша"}),
        ("propose_effect", {"effect": {"kind": "create_npc", "npc": {"name": "Сарра", "role": "пекарша", "trader": True,
                                                                     "stock": ["gen_bread", "rations"]}}}),
        ("final", lambda m: {"narration": "Сарра вытирает руки о передник.", "effect_ids": ["e-3"]}),
    )
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent")
    services.library.add("gen_bread", GeneratedItem(name="Краюха хлеба", item_type="consumable", rarity="common", value_cp=2))
    msg, _, _ = play(data_dir, fn, engine, services=services)
    assert "Правила темы «people»" in last_tool_text(fn.state["prompts"][1])
    assert msg["result"]["effect_ids"] == ["e-3"]
    npc = seen[0]["npc"]
    assert npc["stock"] == ["rations"]
    assert [i["name"] for i in npc["stock_new"]] == ["Краюха хлеба"]


def test_the_entry_turn_takes_only_the_furnishing_and_notes(data_dir):
    # v0.7.34.3, the author's trace t-10: walking into the square brought a gift, a flag and the trader's favour
    seen = {}
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "give_item", "item_id": "dagger"}}),
        ("propose_effect", {"effect": {"kind": "note", "text": "Герой пришёл в таверну"}}),
        ("final", lambda m: {"narration": "Таверна шумит.", "effect_ids": [effect_id(m)]}),
    )
    snapshot = tavern_snapshot()
    snapshot["scene"]["furnish"] = True

    async def watched(messages, info):
        seen["tools"] = sorted(t.name for t in info.function_tools)
        return await fn(messages, info)

    msg, calls, _ = play(data_dir, watched, kind="enter", input="", snapshot=snapshot)
    assert seen["tools"] == ["find_items", "propose_effect"]
    assert "только вошёл" in last_tool_text(fn.state["prompts"][1])
    assert [c["params"]["effect"]["kind"] for c in calls if c["method"] == "engine.validate"] == ["note"]
    assert msg["result"]["effect_ids"] == ["e-1"]


def test_a_topic_refusal_brings_the_topics_rules(data_dir):
    # v0.7.34.3: no extra `rules` call — the refusal carries them and the next proposal goes through
    fn = scripted(
        ("propose_effect", {"effect": {"kind": "npc_follow", "npc_id": "npc_guard"}}),
        ("propose_effect", {"effect": {"kind": "npc_follow", "npc_id": "npc_guard"}}),
        ("final", lambda m: {"narration": "Ведда идёт с тобой.", "effect_ids": [effect_id(m)]}),
    )
    msg, calls, _ = play(data_dir, fn, input="зову Ведду с собой")
    refusal = last_tool_text(fn.state["prompts"][1])
    assert refusal.startswith("Отказ: эффект темы «social»") and "npc_follow" in refusal
    assert len([c for c in calls if c["method"] == "engine.validate"]) == 1
    assert msg["result"]["effect_ids"] == ["e-1"]


def test_the_item_search_ends_after_one_wave_and_the_entry_turn_does_not_think(data_dir):
    # v0.7.34.4, the author's trace t-17: 30 find_items and 116 s for one room
    seen = {}
    fn = scripted(*([("find_items", {"query": "грабли"})] * 7),
                  ("final", {"narration": "Огород зарос бурьяном."}))

    async def watched(messages, info):
        seen["settings"] = info.model_settings
        return await fn(messages, info)

    snapshot = tavern_snapshot()
    snapshot["scene"]["furnish"] = True
    play(data_dir, watched, kind="enter", input="", snapshot=snapshot)
    assert "Ничего похожего — не ищи это снова" in last_tool_text(fn.state["prompts"][1])
    assert "поиск вещей на этот ход исчерпан" in last_tool_text(fn.state["prompts"][7])
    assert seen["settings"]["openrouter_reasoning"] == {"enabled": False}
