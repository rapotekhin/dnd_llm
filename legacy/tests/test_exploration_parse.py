"""Pure parsing helpers from exploration — no LLM."""

from __future__ import annotations

import pytest

from core.gameplay.agent_resolution_parse import parse_agent_resolution_output
from core.gameplay.schemas.exploration import AgentResolutionOutput


def test_parse_json_block() -> None:
    text = """```json
{"narration": "You open the door.", "action": "exploration", "question_to_player": null,
 "metadata": {"npc_id": null, "room_id": "room-2"}}
```"""
    out = parse_agent_resolution_output(text)
    assert out.narration == "You open the door."
    assert out.action == "exploration"
    assert out.question_to_player is None
    assert out.metadata.room_id == "room-2"


def test_parse_invalid_action_defaults_to_exploration() -> None:
    raw = '{"narration": "x", "action": "invalid_mode"}'
    out = parse_agent_resolution_output(raw)
    assert out.action == "exploration"


def test_parse_bare_json_without_fence() -> None:
    raw = '{"narration": "Wind howls.", "action": "social", "question_to_player": null}'
    out = parse_agent_resolution_output(raw)
    assert out.narration == "Wind howls."
    assert out.action == "social"


def test_parse_question_to_player_coerced_from_number() -> None:
    raw = '{"narration": "n", "action": "exploration", "question_to_player": 42}'
    out = parse_agent_resolution_output(raw)
    assert out.question_to_player == "42"
    assert out.has_question is True


def test_parse_russian_labels_activity_only_falls_back_full_text_as_narration() -> None:
    text = "ДЕЙСТВИЕ: combat\n"
    out = parse_agent_resolution_output(text)
    assert out.action == "combat"
    assert "ДЕЙСТВИЕ" in out.narration


def test_parse_russian_labels() -> None:
    text = """НАРРАЦИЯ: Ты делаешь шаг.
ДЕЙСТВИЕ: combat
ВОПРОС_ИГРОКУ:"""
    out = parse_agent_resolution_output(text)
    assert "шаг" in out.narration
    assert out.action == "combat"
    assert out.has_question is False


def test_has_question_property() -> None:
    o = AgentResolutionOutput(
        narration="n",
        action="exploration",
        question_to_player="Which way?",
    )
    assert o.has_question is True
