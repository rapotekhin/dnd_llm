"""Connection, handshake and turn path over a real WebSocket (ADR-0009 §1, §2, §5–§7)."""

import pytest
from fastapi.testclient import TestClient
from starlette.testclient import WebSocketDenialResponse
from starlette.websockets import WebSocketDisconnect

from llm_server.app import create_app
from llm_server.protocol import PROTOCOL_VERSION, protocol_compatible

from conftest import AUTH, hello, make_settings, request



def reason(msg: dict) -> str:
    return msg["error"]["data"]["reason"]


def turn(ws, req_id: str, turn_id: str, kind: str = "action") -> None:
    request(ws, req_id, "turn.request", {"turn_id": turn_id, "mode": "exploration", "kind": kind, "input": "осматриваюсь"})


CHECK_RESULT = {"check_id": "c-1", "rolls": [14], "bonus": 3, "total": 17, "dc": 15, "success": True, "nat": 14}


# --- connection ----------------------------------------------------------------


def test_healthz(client):
    assert client.get("/healthz").json()["status"] == "ok"


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer wrong-token-0123456789"}, {"Authorization": "Basic x"}])
def test_bad_token_gets_401_before_socket_opens(client, headers):
    with pytest.raises(WebSocketDenialResponse) as exc:
        with client.websocket_connect("/ws", headers=headers):
            pass
    assert exc.value.status_code == 401


def test_method_before_hello_is_not_initialized(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        turn(ws, "g-1", "t-1")
        assert reason(ws.receive_json()) == "not_initialized"


def test_hello_returns_versions_limits_and_models(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        result = hello(ws)["result"]
    assert result["protocol_version"] == PROTOCOL_VERSION
    assert result["model"] == "anthropic/claude-haiku-5.5"
    assert [m["id"] for m in result["models"]][0] == "anthropic/claude-haiku-5.5"
    assert result["server_version"]
    assert result["limits"]["max_message_bytes"] == 1024 * 1024
    assert result["limits"]["turn_timeout_s"] == 90


def test_version_mismatch_errors_and_closes(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        msg = hello(ws, protocol_version="9.0.0")
        assert reason(msg) == "version_mismatch"
        assert msg["error"]["data"]["retryable"] is False
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 4001


def test_no_hello_in_time_closes():
    with TestClient(create_app(make_settings(hello_timeout=0.2))) as c:
        with c.websocket_connect("/ws", headers=AUTH) as ws:
            with pytest.raises(WebSocketDisconnect) as exc:
                ws.receive_json()
    assert exc.value.code == 4002


def test_protocol_compatibility_rules():
    assert protocol_compatible("0.1.0", "0.1.3")
    assert not protocol_compatible("0.2.0", "0.1.0")  # 0.x: minor is breaking
    assert protocol_compatible("1.4.0", "1.0.0")
    assert not protocol_compatible("2.0.0", "1.0.0")
    assert not protocol_compatible("garbage", "1.0.0")


def test_parse_error_unknown_method_bad_params(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        ws.send_text("{not json")
        assert ws.receive_json()["error"]["code"] == -32700
        request(ws, "g-2", "world.destroy")
        assert ws.receive_json()["error"]["code"] == -32601
        request(ws, "g-3", "turn.request", {"turn_id": "bad", "mode": "exploration", "kind": "action"})
        assert ws.receive_json()["error"]["code"] == -32602


# --- turns ----------------------------------------------------------------------


def test_enter_turn_needs_no_engine_call(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1", kind="enter")
        msg = ws.receive_json()
    assert msg["id"] == "g-2"
    assert msg["result"]["turn_id"] == "t-1"
    assert msg["result"]["narration"]


def test_action_turn_calls_engine_check_back():
    with TestClient(create_app(make_settings())) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        call = ws.receive_json()
        assert call["method"] == "engine.check"
        assert call["id"].startswith("s-")
        assert call["params"] == {"turn_id": "t-1", "skill": "perception", "dc_tier": "medium"}
        ws.send_json({"jsonrpc": "2.0", "id": call["id"], "result": CHECK_RESULT})
        result = ws.receive_json()["result"]
    assert result["check_ids"] == ["c-1"]
    assert "17 против 15" in result["narration"]


def test_engine_error_fails_the_turn(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        call = ws.receive_json()
        ws.send_json({"jsonrpc": "2.0", "id": call["id"], "error": {"code": -32603, "message": "boom"}})
        assert reason(ws.receive_json()) == "engine_error"


def test_engine_timeout_fails_the_turn():
    with TestClient(create_app(make_settings(engine_timeout=0.2))) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        assert ws.receive_json()["method"] == "engine.check"
        msg = ws.receive_json()
    assert reason(msg) == "engine_timeout"
    assert msg["error"]["data"]["retryable"] is True


def test_turn_timeout():
    settings = make_settings(turn_timeout=0.2, engine_timeout=5)
    with TestClient(create_app(settings)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        assert ws.receive_json()["method"] == "engine.check"
        assert reason(ws.receive_json()) == "turn_timeout"


def test_second_turn_during_active_is_rejected(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        call = ws.receive_json()
        turn(ws, "g-3", "t-2")
        busy = ws.receive_json()
        assert busy["id"] == "g-3" and reason(busy) == "turn_in_progress"
        ws.send_json({"jsonrpc": "2.0", "id": call["id"], "result": CHECK_RESULT})
        assert ws.receive_json()["result"]["turn_id"] == "t-1"


def test_turn_cancel(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        turn(ws, "g-2", "t-1")
        ws.receive_json()  # engine.check, never answered
        request(ws, "g-3", "turn.cancel", {"turn_id": "t-1"})
        replies = {m["id"]: m for m in (ws.receive_json(), ws.receive_json())}
    assert replies["g-3"]["result"] == {"ok": True}
    assert reason(replies["g-2"]) == "turn_cancelled"


def test_server_wide_turn_limit(client):
    with client.websocket_connect("/ws", headers=AUTH) as a, client.websocket_connect("/ws", headers=AUTH) as b:
        hello(a)
        hello(b)
        turn(a, "g-2", "t-1")
        call = a.receive_json()
        turn(b, "g-2", "t-1")
        assert reason(b.receive_json()) == "server_busy"
        a.send_json({"jsonrpc": "2.0", "id": call["id"], "result": CHECK_RESULT})
        assert "result" in a.receive_json()
        # the slot is free again
        turn(b, "g-3", "t-2", kind="enter")
        assert "result" in b.receive_json()


def test_disconnect_mid_turn_frees_the_slot(client):
    with client.websocket_connect("/ws", headers=AUTH) as a:
        hello(a)
        turn(a, "g-2", "t-1")
        a.receive_json()
    with client.websocket_connect("/ws", headers=AUTH) as b:
        hello(b)
        turn(b, "g-2", "t-1", kind="enter")
        assert "result" in b.receive_json()
