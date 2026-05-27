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


def test_exploration_resume_reruns_describe_scene_and_seeds_summary(monkeypatch: pytest.MonkeyPatch) -> None:
    """After returning from a side-session, exploration must:
      1. read the summary from the resume message,
      2. re-run describe_scene so state["scene"] is fresh,
      3. only then call generate_actions — so its prompt sees summary + new scene.
    """
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(exp, "_generate_location_summary", lambda *a, **k: "")

    # describe_scene runs twice: once at startup, once on resume.
    describe = FakeAgent(
        [
            SceneDescription(environment_description="Initial scene — NPC at the bar."),
            SceneDescription(environment_description="Post-dialogue scene — NPC walked off."),
        ]
    )

    # generate_actions runs twice: once before the social transition,
    # once after resume. We capture both prompts to assert the second one
    # contains both the summary and the refreshed scene.
    captured_prompts: list = []

    class CapturingFakeAgent:
        model = "stub-model"

        def __init__(self, outputs):
            self._outputs = list(outputs)

        def run_sync(self, prompt, *_args, **_kwargs):
            captured_prompts.append(prompt)
            return type("R", (), {"output": self._outputs.pop(0)})()

    generate = CapturingFakeAgent(
        [
            ActionList(actions=[ActionOption(id=1, description="Talk to NPC")]),
            ActionList(actions=[ActionOption(id=1, description="Look around")]),
        ]
    )

    # First resolution → transition into social. After that, the second
    # generate_actions call should be enough to verify the resume path.
    resolution = FakeAgent(
        [
            AgentResolutionOutput(
                narration="You start a conversation.",
                action="social",
                question_to_player=None,
                metadata=ActionMetadata(npc_id="npc1"),
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
        name="exploration-resume",
    )
    thr.start()

    # Initial scene + actions, then choose action 1 (→ social transition).
    collect_until(ui_q, lambda m: m.get("type") == "scene")
    collect_until(ui_q, lambda m: m.get("type") == "actions")
    in_q.put({"type": "input", "text": "1"})

    # Wait for the social transition message, drain ui_queue past it.
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")
    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "social"

    # Simulate the social loop returning with a summary.
    in_q.put({"type": "resume", "summary": "НПС рассказал о квесте и отошёл."})

    # On resume we must observe: system_marker → narration(summary) → thinking →
    # scene (refreshed) → actions.
    msgs2 = collect_until(ui_q, lambda m: m.get("type") == "actions")

    marker_msg = next(m for m in msgs2 if m.get("type") == "system_marker")
    assert "Возвращение" in marker_msg["text"]

    narration_msg = next(m for m in msgs2 if m.get("type") == "narration")
    assert narration_msg["text"] == "НПС рассказал о квесте и отошёл."

    refreshed_scene_msg = next(m for m in msgs2 if m.get("type") == "scene")
    assert refreshed_scene_msg["text"] == "Post-dialogue scene — NPC walked off."

    # Marker and narration must arrive BEFORE the new scene.
    types_in_order = [m.get("type") for m in msgs2]
    assert types_in_order.index("system_marker") < types_in_order.index("scene")
    assert types_in_order.index("narration") < types_in_order.index("scene")

    # Second generate_actions prompt must contain both the summary and the new scene.
    assert len(captured_prompts) == 2
    second = captured_prompts[1]
    assert "НПС рассказал о квесте и отошёл." in second
    assert "Post-dialogue scene — NPC walked off." in second

    stop.set()
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
