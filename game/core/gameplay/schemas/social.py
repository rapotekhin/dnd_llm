"""
Pydantic schemas for the social interaction (NPC dialogue) LLM agents.
"""
from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field

from core.gameplay.schemas.exploration import ActionMetadata

# Action types available during social interaction
SocialActionType = Literal[
    "social",             # continue the current conversation
    "trade",              # switch to trade screen (same NPC)
    "exploration",        # player leaves – return to main exploration
    "combat",             # combat begins
    "change_current_room",# player moves to an adjacent room
]


# ── Agent 1: Initial greeting ────────────────────────────────────────────────

class NpcGreeting(BaseModel):
    """Opening scene + NPC's first words, generated once per conversation."""

    greeting_scene: str = Field(
        description=(
            "2-4 sentence DM narration: set the atmosphere, "
            "briefly describe what the NPC is doing when the player approaches."
        )
    )
    npc_first_words: str = Field(
        description="The NPC's opening line, fully in character and in their voice."
    )


# ── Agent 2: Response options ────────────────────────────────────────────────

class ResponseOption(BaseModel):
    id: int
    text: str


class ResponseOptionList(BaseModel):
    """2-4 suggested player responses to the NPC's last message."""
    options: List[ResponseOption]


# ── Agent 3: Resolution ──────────────────────────────────────────────────────

class SocialResolutionOutput(BaseModel):
    """NPC reply + next game action after the player speaks."""

    npc_reply: str = Field(
        description="The NPC's full in-character response to the player."
    )
    action: SocialActionType = Field(
        description=(
            "Next game mode: social | trade | exploration | combat | change_current_room"
        )
    )
    question_to_player: Optional[str] = Field(
        default=None,
        description=(
            "GM clarification question for the player if more info is needed; "
            "null if no question."
        ),
    )
    metadata: ActionMetadata = Field(
        default_factory=ActionMetadata,
        description=(
            "Transition data: npc_id when action is 'trade'; "
            "room_id when action is 'change_current_room'."
        ),
    )

    @property
    def has_question(self) -> bool:
        return bool(self.question_to_player and self.question_to_player.strip())


# ── Agent 4: Summary ─────────────────────────────────────────────────────────

class SocialSummary(BaseModel):
    """Brief summary of the conversation, appended to location_history_summary."""

    summary: str = Field(
        description=(
            "2-4 sentence summary of the conversation: "
            "who said what, what was agreed, what changed."
        )
    )
