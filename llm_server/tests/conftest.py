import pytest
from fastapi.testclient import TestClient

from llm_server.app import create_app
from llm_server.config import Settings

TOKEN = "test-token-0123456789abcdef"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def make_settings(**overrides) -> Settings:
    return Settings(token=TOKEN, **overrides)


@pytest.fixture
def client():
    with TestClient(create_app(make_settings())) as c:
        yield c


def hello(ws, protocol_version: str = "0.1.0", req_id: str = "g-1") -> dict:
    ws.send_json(
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": "session.hello",
            "params": {"protocol_version": protocol_version, "client_version": "test"},
        }
    )
    return ws.receive_json()


def request(ws, req_id: str, method: str, params: dict | None = None) -> None:
    ws.send_json({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}})
