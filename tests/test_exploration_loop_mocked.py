"""Integration-style tests: exploration loop with agents replaced by fakes (no API keys)."""

from __future__ import annotations

import queue
import threading
from unittest.mock import MagicMock

import pytest

from _fakes import FakeAgent, collect_until, join_thread_or_stop
from core.data.game_state_base import MainGameState
from core.entities.location import Location, Room
from core.entities.player import Player
from core.gameplay import exploration as exp
from core.gameplay.schemas.exploration import (
    ActionList,
    ActionOption,
    ActionMetadata,
    AgentResolutionOutput,
    SceneDescription,
)


def _minimal_game_state_two_rooms() -> MainGameState:
    gs = MainGameState()
    gs.current_room_id = "r1"
    gs.current_location_id = "loc1"
    gs.rooms = {
        "r1": Room(name="Hall", level=0, description="A hall.", id="r1", location_id="loc1"),
        "r2": Room(name="Back room", level=0, description="Another.", id="r2", location_id="loc1"),
    }
    gs.locations = {
        "loc1": Location(
            name="Test Inn",
            type="town",
            subtype="tavern",
            description="Somewhere.",
            region="",
            city="",
            id="loc1",
        ),
    }
    gs.player = Player.create_random_character(name="Explorer", race="human", class_type="fighter")
    return gs


def test_exploration_loop_combat_transition(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(exp, "_generate_location_summary", lambda *a, **k: "")

    describe = FakeAgent([SceneDescription(environment_description="You are here.")])
    generate = FakeAgent(
        [
            ActionList(
                actions=[
                    ActionOption(id=1, description="Fight"),
                    ActionOption(id=2, description="Run"),
                ]
            ),
        ]
    )
    resolution = FakeAgent(
        [
            AgentResolutionOutput(
                narration="Steel clashes.",
                action="combat",
                question_to_player=None,
            ),
        ]
    )

    monkeypatch.setattr(exp, "_build_describe_agent", lambda _am, _gs: describe)
    monkeypatch.setattr(exp, "_build_generate_actions_agent", lambda _am, _gs: generate)
    monkeypatch.setattr(exp, "_build_resolution_agent", lambda _am, _gs: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    gs = _minimal_game_state_two_rooms()

    target = lambda: exp.run_exploration(MagicMock(model_name="stub"), gs, ui_q, in_q, stop)
    thr = threading.Thread(target=target, daemon=True, name="exploration-combat")
    thr.start()

    collect_until(ui_q, lambda m: m.get("type") == "scene")
    collect_until(ui_q, lambda m: m.get("type") == "actions")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "combat"

    join_thread_or_stop(thr, stop)


def test_exploration_change_current_room_updates_ids(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(exp, "_generate_location_summary", lambda *a, **k: "")

    describe = FakeAgent([SceneDescription(environment_description="Hall.")])
    generate = FakeAgent(
        [
            ActionList(
                actions=[
                    ActionOption(id=1, description="Go back"),
                ]
            ),
        ]
    )
    resolution = FakeAgent(
        [
            AgentResolutionOutput(
                narration="You slip through.",
                action="change_current_room",
                question_to_player=None,
                metadata=ActionMetadata(room_id="r2"),
            ),
        ]
    )

    monkeypatch.setattr(exp, "_build_describe_agent", lambda _am, _gs: describe)
    monkeypatch.setattr(exp, "_build_generate_actions_agent", lambda _am, _gs: generate)
    monkeypatch.setattr(exp, "_build_resolution_agent", lambda _am, _gs: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    gs = _minimal_game_state_two_rooms()

    thr = threading.Thread(
        target=lambda: exp.run_exploration(MagicMock(model_name="stub"), gs, ui_q, in_q, stop),
        daemon=True,
        name="exploration-room",
    )
    thr.start()

    collect_until(ui_q, lambda m: m.get("type") == "scene")
    collect_until(ui_q, lambda m: m.get("type") == "actions")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")
    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "change_current_room"
    assert gs.current_room_id == "r2"
    assert gs.current_location_id == "loc1"

    join_thread_or_stop(thr, stop)
