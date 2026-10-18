import json

import pytest
from fastapi.testclient import TestClient

from llm_server import REPO_ROOT
from llm_server.app import create_app
from llm_server.config import Settings
from llm_server.services import Services

TOKEN = "test-token-0123456789abcdef"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def make_settings(**overrides) -> Settings:
    overrides.setdefault("turn_handler", "stub")
    return Settings(token=TOKEN, **overrides)


@pytest.fixture(autouse=True)
def _no_banner(monkeypatch):
    monkeypatch.setenv("PYDANTIC_AI_NO_BANNER", "1")


@pytest.fixture
def data_dir(tmp_path):
    return tmp_path / "var"


@pytest.fixture
def client(data_dir):
    with TestClient(create_app(make_settings(data_dir=data_dir))) as c:
        yield c


def hello(ws, protocol_version: str = "0.2.0", req_id: str = "g-1") -> dict:
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


def tavern_snapshot() -> dict:
    """A snapshot as Godot builds it for the start room (game/data/start/*.json)."""
    world = json.loads((REPO_ROOT / "game" / "data" / "start" / "world.json").read_text(encoding="utf-8"))
    char = json.loads((REPO_ROOT / "game" / "data" / "start" / "character.json").read_text(encoding="utf-8"))
    room_id = world["start_room"]
    room = world["rooms"][room_id]
    loc = world["locations"][room["location_id"]]
    return {
        "scene": {
            "location_id": room["location_id"], "location_name": loc["name"], "location_description": loc["description"],
            "room_id": room_id, "room_name": room["name"], "room_description": room["description"],
            "exits": [{"room_id": e, "name": world["rooms"][e]["name"]} for e in room["exits"]],
            "npcs": [{"npc_id": n, **{k: world["npcs"][n][k] for k in ("name", "role", "race", "gender", "description", "personality")}}
                     for n in room["npcs"]],
        },
        "character": {
            "name": char["name"], "gender": char["gender"], "race": char["race"], "class_name": char["class_name"],
            "level": 1, "hp": 12, "max_hp": 12, "ac": 16, "skills": char["skills"], "saves": char["saves"],
            "gold_cp": char["gold_cp"], "inventory": [{"item_id": k, "name": k, "qty": v} for k, v in char["inventory"].items()],
        },
        "history": [{"role": "dm", "text": "Таверна шумит."}],
    }


def make_services(data_dir, model_factory=None, **settings) -> Services:
    return Services.create(make_settings(data_dir=data_dir, **settings), model_factory)
