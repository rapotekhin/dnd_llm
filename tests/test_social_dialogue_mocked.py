"""Social dialogue loop with LLM agents mocked (no API keys)."""

from __future__ import annotations

import queue
import threading
import time
from unittest.mock import MagicMock

import pytest

from core.data.game_state_base import MainGameState
from core.entities.npc import NPC
from core.entities.player import Player
from core.gameplay import social_interaction as social
from core.gameplay.schemas.social import (
    NpcGreeting,
    ResponseOption,
    ResponseOptionList,
    SocialResolutionOutput,
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
            raise RuntimeError("fake social agent ran out of outputs")
        return _FakeRun(self._outputs.pop(0))


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


def _minimal_social_state(npc_id: str) -> MainGameState:
    gs = MainGameState()
    npc = NPC.create_random_character(name="Dialog NPC", race="human", class_type="cleric", level=1)
    npc.id = npc_id
    gs.npcs[npc_id] = npc
    gs.player = Player.create_random_character(name="Hero", race="human", class_type="fighter")
    return gs


def test_social_loop_exploration_transition(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(social, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(social, "_generate_social_summary", lambda *a, **k: "")

    greeting = _FakeAgent(
        [
            NpcGreeting(greeting_scene="The inn is quiet.", npc_first_words="Evening."),
        ]
    )
    options = _FakeAgent(
        [
            ResponseOptionList(options=[ResponseOption(id=1, text="Leave politely.")]),
        ]
    )
    resolution = _FakeAgent(
        [
            SocialResolutionOutput(
                npc_reply="Till next time.",
                action="exploration",
                question_to_player=None,
            ),
        ]
    )

    monkeypatch.setattr(social, "_build_greeting_agent", lambda *_a, **_k: greeting)
    monkeypatch.setattr(social, "_build_options_agent", lambda *_a, **_k: options)
    monkeypatch.setattr(social, "_build_resolution_agent", lambda *_a, **_k: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    npc_id = "social-test-npc"
    gs = _minimal_social_state(npc_id)

    def target():
        social.run_social(MagicMock(), gs, npc_id, ui_q, in_q, stop)

    threading.Thread(target=target, daemon=True).start()

    _collect_until(ui_q, lambda m: m.get("type") == "greeting")
    _collect_until(ui_q, lambda m: m.get("type") == "npc_reply")
    _collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs = _collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "exploration"

    stop.set()


def test_chat_message_llm_turn() -> None:
    from core.gameplay.social_interaction import ChatMessage, MessageRole

    m = ChatMessage(role=MessageRole.PLAYER, tag="Игрок", text="Hello.")
    d = m.to_llm_turn()
    assert d["role"] == "user"
    assert "Hello" in d["content"]
