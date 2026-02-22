"""
Social interaction logic – NPC dialogue, decoupled from pygame UI.

SocialState holds the full conversation state for one session with an NPC:
  - structured message history (ready for LLM context)
  - game-state accessors (player / NPC)
  - helpers for adding messages by role

━━━ Planned LLM integration (Pydantic AI, similar to exploration.py) ━━━━━━━

Future: an Agent that simultaneously:
  1. plays the NPC (generates voiced, in-character replies)
  2. acts as Game Master (decides skill-check triggers, combat start,
     quest updates, item rewards, etc.)

Entry point will be something like:

    result: SocialResolutionOutput = await social_state.run_npc_reply(
        api_manager, player_text
    )
    # result.npc_reply  – what the NPC says
    # result.action     – "dialogue" | "combat" | "trade" | "end"
    # result.gm_notes   – internal DM reasoning / state changes

Schemas will live in  core/gameplay/schemas/social.py  (by analogy with
core/gameplay/schemas/exploration.py).

The Agent will receive:
  - system prompt = NPC personality + current room / quest context
  - conversation_history = [ChatMessage, …] formatted as LLM turns
  - player_text = latest player input
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, TYPE_CHECKING

from core import data as game_data
from core.entities.base import ID

if TYPE_CHECKING:
    from core.entities.npc import NPC
    from core.entities.player import Player


# ── Author roles ────────────────────────────────────────────────────────────

class MessageRole(str, Enum):
    PLAYER = "player"
    NPC    = "npc"
    SYSTEM = "system"


# ── Message DTO ─────────────────────────────────────────────────────────────

@dataclass
class ChatMessage:
    """
    A single dialogue entry.

    `role`  – semantic author (used for LLM context building).
    `tag`   – display label shown in the UI, e.g. "[Арвен]", "[Игрок]".
    `text`  – raw message content.
    """
    role: MessageRole
    tag:  str
    text: str

    def formatted(self) -> str:
        """Return the string rendered in the chat window."""
        return f"{self.tag}: {self.text}"

    def to_llm_turn(self) -> dict:
        """
        Convert to a dict suitable for building LLM message history.
        Role mapping:  player → "user",  npc/system → "assistant".
        """
        llm_role = "user" if self.role == MessageRole.PLAYER else "assistant"
        return {"role": llm_role, "content": self.formatted()}


# ── State ────────────────────────────────────────────────────────────────────

class SocialState:
    """
    All non-UI state for a dialogue session with a single NPC.

    Lifecycle:
      1. Instantiate once (e.g. in SocialScreen.__init__).
      2. Call reset(npc_id) each time the screen is opened for a new NPC.
      3. The screen calls add_player_message() / add_system_message() and
         reads chat_lines for rendering.
      4. (Future) call run_npc_reply() to get an LLM-generated NPC response.
    """

    def __init__(self) -> None:
        self.npc_id:  Optional[ID] = None
        self.history: List[ChatMessage] = []

    # ------------------------------------------------------------------
    # SESSION LIFECYCLE
    # ------------------------------------------------------------------

    def reset(self, npc_id: ID) -> None:
        """Start a fresh session with the given NPC."""
        self.npc_id = npc_id
        self.history.clear()
        # Opening stub greeting from the NPC
        npc = self.get_npc()
        if npc:
            self.add_npc_message("...")

    # ------------------------------------------------------------------
    # GAME-STATE ACCESSORS
    # ------------------------------------------------------------------

    def get_player(self) -> Optional["Player"]:
        gs = game_data.game_state
        return gs.player if gs else None

    def get_npc(self) -> Optional["NPC"]:
        gs = game_data.game_state
        if not gs or not gs.npcs or self.npc_id is None:
            return None
        return gs.npcs.get(self.npc_id) or gs.npcs.get(str(self.npc_id))

    # ------------------------------------------------------------------
    # CHAT LINE ACCESSORS  (used by the UI)
    # ------------------------------------------------------------------

    @property
    def chat_lines(self) -> List[str]:
        """Flat list of formatted strings for the chat renderer."""
        return [m.formatted() for m in self.history]

    # ------------------------------------------------------------------
    # MESSAGE HELPERS
    # ------------------------------------------------------------------

    def add_player_message(self, text: str) -> None:
        player = self.get_player()
        name = getattr(player, "name", "Вы") if player else "Вы"
        self.history.append(ChatMessage(MessageRole.PLAYER, f"[{name}]", text))

    def add_npc_message(self, text: str) -> None:
        npc = self.get_npc()
        name = getattr(npc, "name", "???") if npc else "???"
        self.history.append(ChatMessage(MessageRole.NPC, f"[{name}]", text))

    def add_system_message(self, text: str) -> None:
        self.history.append(ChatMessage(MessageRole.SYSTEM, "[Система]", text))

    # ------------------------------------------------------------------
    # LLM CONTEXT BUILDER
    # ------------------------------------------------------------------

    def build_llm_history(self) -> List[dict]:
        """
        Return conversation history as a list of {"role": …, "content": …}
        dicts, suitable for passing to a Pydantic AI Agent as context.

        Excludes system messages (those are part of the agent system prompt).
        """
        return [
            m.to_llm_turn()
            for m in self.history
            if m.role != MessageRole.SYSTEM
        ]

    def build_npc_system_prompt(self) -> str:
        """
        Build the NPC personality + world-context system prompt fragment.

        Placeholder implementation; will be expanded when the LLM agent
        is wired in.  Should include:
          - NPC name, race, class/role, personality traits
          - current room description and active quests
          - known player reputation / relationship value
        """
        npc    = self.get_npc()
        player = self.get_player()
        npc_name    = getattr(npc,    "name", "???")    if npc    else "???"
        player_name = getattr(player, "name", "Герой")  if player else "Герой"
        npc_desc    = getattr(npc,    "description", "") if npc    else ""
        return (
            f"Ты — {npc_name}.  {npc_desc}\n"
            f"Ты разговариваешь с {player_name}.\n"
            "Отвечай от первого лица, в духе своего персонажа."
        )

    # ------------------------------------------------------------------
    # LLM AGENT STUB  (future: Pydantic AI + Logfire)
    # ------------------------------------------------------------------
    #
    # async def run_npc_reply(
    #     self,
    #     api_manager: "APIManager",
    #     player_text: str,
    # ) -> "SocialResolutionOutput":
    #     """
    #     Call the social Agent:
    #       - Adds player_text to history
    #       - Runs the agent with NPC system prompt + history
    #       - Appends NPC reply (and possible GM action) to history
    #       - Returns structured output with npc_reply + gm_action
    #     """
    #     self.add_player_message(player_text)
    #     agent = _build_social_agent(api_manager, self)
    #     result = await agent.run(
    #         player_text,
    #         message_history=self.build_llm_history(),
    #     )
    #     self.add_npc_message(result.output.npc_reply)
    #     return result.output
