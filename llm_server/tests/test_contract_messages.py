"""Every message of a real turn, in both directions, validates against contract/schema (ADR-0009 §8).
Godot builds its messages by hand, so the schemas are the meeting point of the two sides."""

import json

import jsonschema
import pytest
from fastapi.testclient import TestClient
from pydantic_ai.models.function import FunctionModel
from starlette.websockets import WebSocketDisconnect

from llm_server import contract
from llm_server.app import create_app
from llm_server.protocol import PROTOCOL_VERSION

from conftest import AUTH, hello, make_services, make_settings, request, tavern_snapshot
from test_agent import INNKEEPER, default_engine, effect_id, scripted

SCHEMAS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in contract.SCHEMA_DIR.glob("*.json")}


def validate(name: str, instance: object) -> None:
    jsonschema.validate(instance, SCHEMAS[name])


def test_a_full_turn_matches_the_contract(data_dir):
    fn = scripted(
        ("lookup", {"kind": "npc", "id": INNKEEPER}),
        ("find_items", {"query": "эль"}),
        ("request_check", {"skill": "persuasion", "dc_tier": "easy", "reason": "скидка", "target_id": INNKEEPER}),
        ("propose_effect", {"effect": json.dumps({"kind": "coins", "delta_cp": -4, "reason": "эль"}, ensure_ascii=False)}),
        ("final", lambda m: {"narration": "Борик наливает.", "options": ["Выпить"], "effect_ids": [effect_id(m)],
                             "next_mode": "social", "npc_id": INNKEEPER}),
    )
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent")
    sent_methods: dict[str, str] = {}
    seen: set[str] = set()
    turn = {"turn_id": "t-1", "mode": "exploration", "kind": "action", "input": "эля!", "snapshot": tavern_snapshot()}
    with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello_params = {"protocol_version": PROTOCOL_VERSION, "client_version": "test"}
        validate("session.hello.params", hello_params)
        validate("session.hello.result", hello(ws)["result"])
        validate("turn.request.params", turn)
        request(ws, "g-2", "turn.request", turn)
        while True:
            msg = ws.receive_json()
            if "method" in msg:
                validate(f"{msg['method']}.params", msg["params"])
                answer = default_engine(msg["method"], msg["params"])
                validate(f"{msg['method']}.result", answer)
                seen.add(msg["method"])
                sent_methods[msg["id"]] = msg["method"]
                ws.send_json({"jsonrpc": "2.0", "id": msg["id"], "result": answer})
                continue
            validate("turn.request.result", msg["result"])
            break
        request(ws, "g-3", "session.status")
        validate("session.status.result", ws.receive_json()["result"])
        request(ws, "g-4", "turn.cancel", {"turn_id": "t-9"})
        validate("turn.cancel.result", ws.receive_json()["result"])
    assert seen == {"engine.lookup", "engine.find_items", "engine.check", "engine.validate"}


def test_errors_match_the_contract(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        request(ws, "g-1", "turn.request", {"turn_id": "t-1", "mode": "exploration", "kind": "enter"})
        validate("error_data", ws.receive_json()["error"]["data"])


@pytest.mark.parametrize("effect", [
    {"kind": "move", "room_id": "r"},
    {"kind": "damage", "severity": "deadly", "damage_type": "огонь", "reason": "x"},
    {"kind": "heal", "tier": "minor", "reason": "x"},
    {"kind": "coins", "delta_cp": 5, "reason": "x"},
    {"kind": "give_item", "item": {"name": "X", "item_type": "weapon", "rarity": "common", "value_cp": 1, "properties": ["light"]}},
    {"kind": "take_item", "item_id": "torch", "qty": 2},
    {"kind": "npc_attitude", "npc_id": "n", "delta": -1, "reason": "x"},
    {"kind": "flag", "flag": "door_open"},
])
def test_every_effect_kind_is_in_the_contract(effect):
    validate("engine.validate.params", {"turn_id": "t-1", "effect": effect})


def test_message_over_one_megabyte_closes_the_socket():
    with TestClient(create_app(make_settings())) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        ws.send_text(json.dumps({"jsonrpc": "2.0", "id": "g-2", "method": "turn.request", "params": {"input": "x" * (1024 * 1024)}}))
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 1009
