"""Social dialogue loop with LLM agents mocked (no API keys)."""

from __future__ import annotations

import queue
import threading
from unittest.mock import MagicMock

import pytest

from _fakes import FakeAgent, collect_until, join_thread_or_stop
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

    greeting = FakeAgent(
        [
            NpcGreeting(greeting_scene="The inn is quiet.", npc_first_words="Evening."),
        ]
    )
    options = FakeAgent(
        [
            ResponseOptionList(options=[ResponseOption(id=1, text="Leave politely.")]),
        ]
    )
    resolution = FakeAgent(
        [
            SocialResolutionOutput(
                npc_reply="Till next time.",
                action="exploration",
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

    thr = threading.Thread(
        target=lambda: social.run_social(MagicMock(model_name="stub"), gs, npc_id, ui_q, in_q, stop),
        daemon=True,
        name="social-explore",
    )
    thr.start()

    collect_until(ui_q, lambda m: m.get("type") == "greeting")
    collect_until(ui_q, lambda m: m.get("type") == "npc_reply")
    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "exploration"

    join_thread_or_stop(thr, stop)


def test_social_loop_includes_summary_in_transition(monkeypatch: pytest.MonkeyPatch) -> None:
    """LLM-driven exit (action=exploration) must carry a non-empty summary field."""
    monkeypatch.setattr(social, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(
        social,
        "_generate_social_summary",
        lambda *a, **k: "Игрок поговорил с НПС и ушёл.",
    )

    greeting   = FakeAgent([NpcGreeting(greeting_scene="Quiet.", npc_first_words="Hi.")])
    options    = FakeAgent([ResponseOptionList(options=[ResponseOption(id=1, text="Bye.")])])
    resolution = FakeAgent(
        [SocialResolutionOutput(npc_reply="Farewell.", action="exploration")]
    )

    monkeypatch.setattr(social, "_build_greeting_agent", lambda *_a, **_k: greeting)
    monkeypatch.setattr(social, "_build_options_agent", lambda *_a, **_k: options)
    monkeypatch.setattr(social, "_build_resolution_agent", lambda *_a, **_k: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    npc_id = "social-summary-npc"
    gs = _minimal_social_state(npc_id)

    thr = threading.Thread(
        target=lambda: social.run_social(MagicMock(model_name="stub"), gs, npc_id, ui_q, in_q, stop),
        daemon=True,
        name="social-summary",
    )
    thr.start()

    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "exploration"
    assert transition["summary"] == "Игрок поговорил с НПС и ушёл."

    join_thread_or_stop(thr, stop)


def test_social_loop_leave_signal_emits_synchronous_summary(monkeypatch: pytest.MonkeyPatch) -> None:
    """When the player clicks 'Уйти', the loop must synchronously generate a summary
    and emit a transition with action=exploration. No async daemon thread involved."""
    monkeypatch.setattr(social, "_LOGFIRE_ENABLED", False)

    calls: list = []

    def _fake_summary(_api, gs, npc_id, history):
        # Capture invocation so we can assert it ran in-thread before transition.
        calls.append({"npc_id": npc_id, "history": list(history)})
        loc = gs.locations.get(gs.current_location_id) if gs.current_location_id else None
        text = "Игрок ушёл после короткого приветствия."
        if loc is not None:
            loc.location_history_summary = text
        return text

    monkeypatch.setattr(social, "_generate_social_summary", _fake_summary)

    greeting = FakeAgent([NpcGreeting(greeting_scene="Quiet.", npc_first_words="Hi.")])
    options  = FakeAgent([ResponseOptionList(options=[ResponseOption(id=1, text="Hello.")])])
    # Resolution agent must NOT be invoked on the leave path.
    resolution = FakeAgent([])

    monkeypatch.setattr(social, "_build_greeting_agent", lambda *_a, **_k: greeting)
    monkeypatch.setattr(social, "_build_options_agent", lambda *_a, **_k: options)
    monkeypatch.setattr(social, "_build_resolution_agent", lambda *_a, **_k: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    npc_id = "leave-npc"
    gs = _minimal_social_state(npc_id)

    thr = threading.Thread(
        target=lambda: social.run_social(MagicMock(model_name="stub"), gs, npc_id, ui_q, in_q, stop),
        daemon=True,
        name="social-leave",
    )
    thr.start()

    # Wait until the loop is parked at the options prompt before sending leave.
    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "leave"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")

    transition = next(m for m in msgs if m.get("type") == "transition")
    assert transition["action"] == "exploration"
    assert transition["summary"] == "Игрок ушёл после короткого приветствия."
    assert len(calls) == 1, "summary must be generated exactly once, synchronously"

    join_thread_or_stop(thr, stop)


def test_social_loop_continues_with_two_npc_replies(monkeypatch: pytest.MonkeyPatch) -> None:
    """Two consecutive player turns must each produce an npc_reply message and stay in social,
    proving the loop no longer awaits GM clarification questions between turns."""
    monkeypatch.setattr(social, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(social, "_generate_social_summary", lambda *a, **k: "")

    greeting = FakeAgent([NpcGreeting(greeting_scene="Quiet.", npc_first_words="Hi.")])
    options = FakeAgent(
        [
            ResponseOptionList(options=[ResponseOption(id=1, text="Hello.")]),
            ResponseOptionList(options=[ResponseOption(id=1, text="Tell me more.")]),
            # Third entry needed because the loop generates options again after turn 2
            # before we get a chance to stop it.
            ResponseOptionList(options=[ResponseOption(id=1, text="…")]),
        ]
    )
    resolution = FakeAgent(
        [
            SocialResolutionOutput(npc_reply="Pleased to meet you.", action="social"),
            SocialResolutionOutput(npc_reply="What would you like to know?", action="social"),
        ]
    )

    monkeypatch.setattr(social, "_build_greeting_agent", lambda *_a, **_k: greeting)
    monkeypatch.setattr(social, "_build_options_agent", lambda *_a, **_k: options)
    monkeypatch.setattr(social, "_build_resolution_agent", lambda *_a, **_k: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    npc_id = "two-turn-npc"
    gs = _minimal_social_state(npc_id)

    thr = threading.Thread(
        target=lambda: social.run_social(MagicMock(model_name="stub"), gs, npc_id, ui_q, in_q, stop),
        daemon=True,
        name="social-two-turn",
    )
    thr.start()

    npc_replies: list = []

    # Turn 1: wait for options → reply with "1" → collect up to (and including) the npc_reply.
    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs1 = collect_until(ui_q, lambda m: m.get("type") == "npc_reply")
    npc_replies += [m["text"] for m in msgs1 if m.get("type") == "npc_reply"]

    # Turn 2: same — get the second options round, then reply, then collect npc_reply.
    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs2 = collect_until(ui_q, lambda m: m.get("type") == "npc_reply")
    npc_replies += [m["text"] for m in msgs2 if m.get("type") == "npc_reply"]

    # Two distinct NPC replies; no "question" messages must have been emitted.
    assert "Pleased to meet you." in npc_replies
    assert "What would you like to know?" in npc_replies
    all_msgs = msgs1 + msgs2
    assert not any(m.get("type") == "question" for m in all_msgs), (
        f"social loop must not emit GM clarification questions any more; got {all_msgs!r}"
    )

    stop.set()
    join_thread_or_stop(thr, stop)


def test_chat_message_llm_turn() -> None:
    from core.gameplay.social_interaction import ChatMessage, MessageRole

    m = ChatMessage(role=MessageRole.PLAYER, tag="Игрок", text="Hello.")
    d = m.to_llm_turn()
    assert d["role"] == "user"
    assert "Hello" in d["content"]
