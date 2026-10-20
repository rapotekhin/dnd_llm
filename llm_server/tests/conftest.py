import json

import pytest
from fastapi.testclient import TestClient

from llm_server import REPO_ROOT
from llm_server.app import create_app
from llm_server.config import Settings
from llm_server.services import Services
from llm_server.protocol import PROTOCOL_VERSION

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


def hello(ws, protocol_version: str = PROTOCOL_VERSION, req_id: str = "g-1") -> dict:
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
    """A snapshot as Godot builds it for the start room of the start pack (game/data/worlds/frontier)."""
    pack_dir = REPO_ROOT / "game" / "data" / "worlds" / "frontier"
    pack = json.loads((pack_dir / "pack.json").read_text(encoding="utf-8"))
    world = json.loads((pack_dir / "world.json").read_text(encoding="utf-8"))
    room_id = world["start_room"]
    room = world["rooms"][room_id]
    loc = world["locations"][room["location_id"]]
    return {
        "world": {"name": pack["name"], "lore": pack["lore"], "tone": pack["tone"], "magic": pack["magic"],
                  "dm_style": pack["dm_style"], **pack["content"]},
        "scene": {
            "location_id": room["location_id"], "location_name": loc["name"], "location_description": loc["description"],
            "room_id": room_id, "room_name": room["name"], "room_description": room["description"],
            "exits": [{"room_id": e, "name": world["rooms"][e]["name"]} for e in room["exits"]],
            "npcs": [{"npc_id": n, **{k: world["npcs"][n][k] for k in ("name", "role", "race", "gender", "description", "personality")}}
                     for n in room["npcs"]],
        },
        "character": {  # Айра, fighter 1 (the start pack's first ready-made character as CharacterBuilder builds it)
            "name": "Айра", "gender": "female", "race": "Человек", "class_name": "Воин", "level": 1,
            "hp": 12, "max_hp": 12, "ac": 19, "background": "Солдат", "proficiency_bonus": 2, "speed": 30,
            "abilities": {"str": 16, "dex": 14, "con": 15, "int": 9, "wis": 13, "cha": 11},
            "skills": {"athletics": 5, "acrobatics": 2, "perception": 3, "survival": 3, "intimidation": 2, "stealth": 2,
                       "arcana": -1, "persuasion": 0, "insight": 1},
            "skill_proficiencies": ["athletics", "intimidation", "perception", "survival"],
            "saves": {"str": 5, "dex": 2, "con": 4, "int": -1, "wis": 1, "cha": 0},
            "gold_cp": 1000, "features": ["Боевой стиль: защита", "Второе дыхание"],
            "backstory": "Айра стояла на стене Серой заставы в ту ночь, когда пришёл огонь Пепельного Князя.",
            "equipped": ["armor: Кольчуга [chain_mail]", "shield: Щит [shield]", "main_hand: Длинный меч [longsword]"],
            "inventory": [{"item_id": k, "name": k, "qty": v} for k, v in
                          {"chain_mail": 1, "shield": 1, "longsword": 1, "handaxe": 2, "torch": 10, "rations": 10}.items()],
        },
        "history": [{"role": "dm", "text": "Таверна шумит."}],
    }


def make_services(data_dir, model_factory=None, **settings) -> Services:
    return Services.create(make_settings(data_dir=data_dir, **settings), model_factory)
