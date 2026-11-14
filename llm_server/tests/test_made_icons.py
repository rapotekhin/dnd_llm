"""The icon of what the master made (0.130.0): `icon.request` — one frame of the icon model on a chroma ground."""

import asyncio
import base64
from types import SimpleNamespace

import pytest

from llm_server import images, prompts
from llm_server.config import ICON_MODEL
from llm_server.images import Drawn, icon_image
from llm_server.protocol import IconParams
from llm_server.session import RpcError

from conftest import AUTH, hello, make_services, request


def test_the_stub_server_answers_a_chroma_frame(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        request(ws, "i-1", "icon.request", {"kind": "item", "name": "Пепельный кинжал", "text": "клинок из обсидиана"})
        result = ws.receive_json()["result"]
    raw = base64.b64decode(result["data_b64"])
    assert result["mime"] == "image/png" and raw.startswith(b"\x89PNG")
    assert "«Пепельный кинжал» — клинок из обсидиана" in result["prompt"]
    assert "#00FF00" in result["prompt"]
    assert result["usage"]["model"] == "stub"


def test_a_spell_is_an_emblem_and_a_green_subject_goes_on_magenta():
    item = prompts.icon_prompt("item", "Кольцо", "медное кольцо", "green")
    spell = prompts.icon_prompt("spell", "Гнилостный шёпот", "облако зелёной гнили.", "magenta")
    assert item.startswith("The object: «Кольцо» — медное кольцо.\nIt is") and "painterly" in item
    assert spell.startswith("The spell: «Гнилостный шёпот» — облако зелёной гнили.\nIt is") and "emblem" in spell
    assert "#FF00FF" in spell and "#00FF00" not in spell
    assert "The condition: «Без слов».\nIt is" in prompts.icon_prompt("status", "Без слов", "", "green")


def test_bad_params_are_refused():
    with pytest.raises(ValueError):
        IconParams(kind="quest", name="x")
    with pytest.raises(ValueError):
        IconParams(kind="item", name="")


def _session(data_dir, exhausted: bool = False):
    services = make_services(data_dir, model_factory=lambda model: None)
    if exhausted:
        services.budget.set_limit(0.01)
        services.budget.add(0.02)
    return SimpleNamespace(services=services)


def test_one_frame_of_the_icon_model_by_the_seed(data_dir, monkeypatch):
    seen = {}

    async def fake_draw(spec, prompt, negative, aspect, api_key, client=None, seed=None):
        seen.update(model=spec.id, aspect=aspect, seed=seed, prompt=prompt)
        return Drawn("image/png", base64.b64encode(b"png").decode(), 0.009)

    monkeypatch.setattr(images, "draw", fake_draw)
    session = _session(data_dir)
    result = asyncio.run(icon_image(session, IconParams(kind="spell", name="Зеркальный шаг", seed=7)))
    assert seen["model"] == ICON_MODEL and seen["aspect"] == "1:1" and seen["seed"] == 7
    assert result.usage.model == ICON_MODEL and result.usage.cost_usd == 0.009
    assert session.services.budget.spent_today() == pytest.approx(0.009)


def test_a_spent_day_draws_nothing(data_dir, monkeypatch):
    async def fake_draw(*args, **kwargs):
        raise AssertionError("drawn past the day's limit")

    monkeypatch.setattr(images, "draw", fake_draw)
    with pytest.raises(RpcError) as exc:
        asyncio.run(icon_image(_session(data_dir, exhausted=True), IconParams(kind="item", name="Кольцо")))
    assert exc.value.code.name.lower() == "budget_exceeded"
