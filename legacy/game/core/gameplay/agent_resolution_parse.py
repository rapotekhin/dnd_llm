"""Parse DM resolution output (JSON or Russian-labelled fallback). Used without LLM client deps."""

from __future__ import annotations

import json
import re
from typing import cast

from core.gameplay.schemas.exploration import (
    ActionMetadata,
    AgentActionType,
    AgentResolutionOutput,
)


def parse_agent_resolution_output(text: str) -> AgentResolutionOutput:
    """Parse agent output: JSON → Pydantic, with text-format fallback."""
    allowed_actions = {"exploration", "combat", "social", "trade", "change_current_room"}

    def _extract_block(src: str, key: str) -> str:
        marker = f"{key}:"
        if marker not in src:
            return ""
        tail = src.split(marker, 1)[1]
        for nxt in ["НАРРАЦИЯ:", "ДЕЙСТВИЕ:", "ВОПРОС_ИГРОКУ:"]:
            if nxt != marker and nxt in tail:
                tail = tail.split(nxt, 1)[0]
        return tail.strip()

    stripped = text.strip()
    json_match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", stripped)
    if json_match:
        stripped = json_match.group(1).strip()
    try:
        data = json.loads(stripped)
        if isinstance(data, dict):
            action = (data.get("action") or "exploration").strip().lower()
            if action not in allowed_actions:
                action = "exploration"
            q = data.get("question_to_player")
            if q is not None and not isinstance(q, str):
                q = str(q)
            meta_raw = data.get("metadata") or {}
            meta = ActionMetadata(
                npc_id=meta_raw.get("npc_id"),
                room_id=meta_raw.get("room_id"),
            )
            return AgentResolutionOutput(
                narration=data.get("narration") or "",
                action=cast(AgentActionType, action),
                question_to_player=q if (q and q.strip()) else None,
                metadata=meta,
            )
    except (json.JSONDecodeError, Exception):
        pass

    narration = _extract_block(text, "НАРРАЦИЯ") or text.strip()
    activity = (_extract_block(text, "ДЕЙСТВИЕ") or "exploration").strip().split()[0].lower()
    question = _extract_block(text, "ВОПРОС_ИГРОКУ")
    if activity not in allowed_actions:
        activity = "exploration"
    return AgentResolutionOutput(
        narration=narration,
        action=cast(AgentActionType, activity),
        question_to_player=question.strip() or None,
        metadata=ActionMetadata(),
    )
