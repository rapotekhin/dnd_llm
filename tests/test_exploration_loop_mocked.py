"""Integration-style test: exploration loop with agents replaced by fakes (no API keys)."""

from __future__ import annotations

import queue
import threading
import time
from unittest.mock import MagicMock

import pytest

from core.data.game_state_base import MainGameState
from core.entities.location import Location, Room
from core.gameplay import exploration as exp
from core.gameplay.schemas.exploration import (
    ActionList,
    ActionOption,
    AgentResolutionOutput,
    SceneDescription,
)


class _FakeRun:
    def __init__(self, output):
        self.output = output


class _FakeAgent:
    model = "stub-model"

    def __init__(self, outputs: list):
        self._outputs = list(outputs)

    def run_sync(self, *_args, **_kwargs):
        if not self._outputs:
            raise RuntimeError("fake agent ran out of scripted outputs")
        return _FakeRun(self._outputs.pop(0))


def _minimal_game_state() -> MainGameState:
    gs = MainGameState()
    gs.current_room_id = "r1"
    gs.current_location_id = "loc1"
    gs.rooms = {
        "r1": Room(name="Hall", level=0, description="A hall.", id="r1", location_id="loc1"),
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
    player = MagicMock()
    player.abilities.str = 10
    player.abilities.dex = 10
    player.abilities.con = 10
    player.abilities.int = 10
    player.abilities.wis = 10
    player.abilities.cha = 10
    player.abilities.get_modifier = MagicMock(return_value=0)
    player.features = []
    player.sc = MagicMock()
    player.sc.cantrips = []
    player.sc.leveled_spells = []
    player.conditions = []
    gs.player = player
    return gs


def _collect_until(q: queue.Queue, predicate, timeout: float = 5.0):
    deadline = time.monotonic() + timeout
    found = []
    while time.monotonic() < deadline:
        try:
            msg = q.get(timeout=0.1)
        except queue.Empty:
            continue
        found.append(msg)
        if predicate(msg):
            return found
    raise AssertionError(f"timeout waiting for message; got {found!r}")


def test_exploration_loop_combat_transition(monkeypatch: pytest.MonkeyPatch) -> None:
    # Avoid real Logfire spans (can crash in CI / broken numpy+pandas stacks).
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(exp, "_generate_location_summary", lambda *a, **k: "")

    describe = _FakeAgent([SceneDescription(environment_description="You are here.")])
    generate = _FakeAgent(
        [
            ActionList(
                actions=[
                    ActionOption(id=1, description="Fight"),
                    ActionOption(id=2, description="Run"),
                ]
            ),
        ]
    )
    resolution = _FakeAgent(
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
    gs = _minimal_game_state()

    def target():
        exp.run_exploration(MagicMock(), gs, ui_q, in_q, stop)

    threading.Thread(target=target, daemon=True).start()

    _collect_until(ui_q, lambda m: m.get("type") == "scene")
    _collect_until(ui_q, lambda m: m.get("type") == "actions")
    in_q.put({"type": "input", "text": "1"})
    msgs = _collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "combat"

    stop.set()
