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


def test_chat_message_llm_turn() -> None:
    from core.gameplay.social_interaction import ChatMessage, MessageRole

    m = ChatMessage(role=MessageRole.PLAYER, tag="Игрок", text="Hello.")
    d = m.to_llm_turn()
    assert d["role"] == "user"
    assert "Hello" in d["content"]
