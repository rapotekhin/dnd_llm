"""
Social interaction mode: Pydantic AI + Logfire.

run_social() is designed to run in a background thread.
It communicates with the UI via two thread-safe queues:

  ui_queue   – social → UI
              message types:
                {"type": "greeting",   "text": str}      DM narration of the scene
                {"type": "npc_reply",  "text": str}      NPC in-character line
                {"type": "options",    "options": [{"id": int, "text": str}]}
                {"type": "thinking"}
                {"type": "resume"}                        returned from trade
                {"type": "transition", "action": str,
                 "npc_id": str|None, "room_id": str|None,
                 "summary": str}                          side-session report for exploration
                {"type": "error",      "text": str}

  input_queue – UI → social
              message types:
                {"type": "input",  "text": str}   player typed something
                {"type": "resume"}                 returned from trade
                {"type": "leave"}                  player clicked "Уйти" / pressed ESC

stop_event (threading.Event) — set by the caller to abort the thread.
"""
from __future__ import annotations

import os
import queue
import threading
import uuid
from contextlib import nullcontext
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import List, Optional, TYPE_CHECKING

from dotenv import load_dotenv
from pydantic_ai import Agent

from core.gameplay.schemas.exploration import ActionMetadata
from core.gameplay.schemas.social import (
    NpcGreeting,
    ResponseOptionList,
    SocialResolutionOutput,
    SocialSummary,
)
from core.tools.roll import RollDiceTool
from core.tools.db_lookup import RuleDbLookupTool
from core.prompts.social_prompts import (
    get_npc_system_prompt,
    get_social_resolution_instructions,
    prompt_initial_greeting,
    prompt_generate_response_options,
    prompt_social_resolution,
    prompt_generate_social_summary,
)
from core.data.game_state_base import MainGameState
from core.llm_engine.api_manager import APIManager
from core import data as game_data
from core.entities.base import ID
from core.logging_config import get_logger

log = get_logger(__name__)

if TYPE_CHECKING:
    from core.entities.npc import NPC
    from core.entities.player import Player

# Load .env before Logfire
_ENV_FILE = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_FILE)

import logfire

# Reuse logfire configuration done by exploration.py (or configure if not yet done).
# We do NOT call logfire.instrument_pydantic_ai() here — exploration.py owns that.
_LOGFIRE_ENABLED = False
try:
    _token = os.getenv("LOGFIRE_TOKEN") or os.getenv("LOGFIRE_AI_API_KEY")
    if _token:
        # Only configure if not already done (logfire.configure is idempotent but
        # calling it repeatedly can reset state in some versions).
        try:
            logfire.configure(token=_token)
        except Exception:
            pass
        _LOGFIRE_ENABLED = True
except Exception:
    pass


def _span(name: str, **kwargs):
    return logfire.span(name, **kwargs) if _LOGFIRE_ENABLED else nullcontext()


# =======================
# TOOLS
# =======================

_roll_dice_tool    = RollDiceTool()
_rule_db_lookup    = RuleDbLookupTool()


# =======================
# AGENT BUILDERS
# =======================

def _build_greeting_agent(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
) -> Agent[MainGameState, NpcGreeting]:
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=NpcGreeting,
        instructions=get_npc_system_prompt(game_state, npc_id),
    )


def _build_options_agent(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
) -> Agent[MainGameState, ResponseOptionList]:
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=ResponseOptionList,
        instructions=get_npc_system_prompt(game_state, npc_id),
    )


def _build_resolution_agent(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
) -> Agent[MainGameState, SocialResolutionOutput]:
    npc = game_state.npcs.get(npc_id) if game_state.npcs else None
    npc_name = getattr(npc, "name", "НПС") if npc else "НПС"

    model = api_manager.get_pydantic_ai_model()
    agent: Agent[MainGameState, SocialResolutionOutput] = Agent(
        model,
        deps_type=MainGameState,
        output_type=SocialResolutionOutput,
        instructions=(
            get_npc_system_prompt(game_state, npc_id)
            + "\n\n"
            + get_social_resolution_instructions(npc_name, npc_id)
        ),
    )

    @agent.tool_plain
    def roll_dice(
        expression: str,
        has_advantage: bool = False,
        has_disadvantage: bool = False,
        difficulty_class: Optional[int] = None,
    ) -> dict:
        """Roll dice using D&D 5e advantage/disadvantage rules.

        Args:
            expression: Dice expression in standard notation ONLY — e.g. "1d20",
                "1d20+3", "2d6+2". For ability checks use "1d20+<modifier>" where
                <modifier> is the numeric ability modifier (e.g. CHA +2 → "1d20+2").
                NEVER pass a skill or ability name — always use dice notation.
            has_advantage: Roll twice, take the higher result.
            has_disadvantage: Roll twice, take the lower result.
            difficulty_class: Target DC as an integer; None for damage rolls.
        """
        return _roll_dice_tool.run(
            expression=expression,
            has_advantage=has_advantage,
            has_disadvantage=has_disadvantage,
            difficulty_class=difficulty_class,
        )

    @agent.tool_plain
    def rule_db_lookup(rule_name: str, rule_section: str) -> str:
        """Lookup D&D 5e rules in the database."""
        return _rule_db_lookup.run(rule_name, rule_section)

    return agent


def _build_summary_agent(api_manager: APIManager) -> Agent[MainGameState, SocialSummary]:
    model = api_manager.get_pydantic_ai_model()
    return Agent(model, deps_type=MainGameState, output_type=SocialSummary)


# =======================
# HELPERS
# =======================

def _wait_for_input(
    input_queue: queue.Queue,
    stop_event: threading.Event,
    timeout: float = 0.15,
) -> Optional[dict]:
    """Block until a message arrives or stop_event is set. Returns None if aborted."""
    while not stop_event.is_set():
        try:
            return input_queue.get(timeout=timeout)
        except queue.Empty:
            continue
    return None


def _generate_social_summary(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
    session_history: List[str],
) -> str:
    """Generate a summary of the conversation and persist it to location_history_summary."""
    loc_id   = game_state.current_location_id
    location = game_state.locations.get(loc_id) if loc_id else None
    if not location:
        return ""
    npc = game_state.npcs.get(npc_id) if game_state.npcs else None
    npc_name = getattr(npc, "name", "НПС") if npc else "НПС"
    past     = location.location_history_summary or ""
    prompt   = prompt_generate_social_summary(
        past, session_history, npc_name, location.name
    )
    try:
        agent  = _build_summary_agent(api_manager)
        result = agent.run_sync(prompt, deps=game_state)
        new_summary = result.output.summary
        location.location_history_summary = new_summary
        log.info("social summary saved (%d chars) for npc=%r", len(new_summary), npc_id)
        return new_summary
    except Exception:
        log.exception("social summary generation failed; keeping previous summary")
        return past


# =======================
# LEAVE TRANSITION HELPER
# =======================

def _emit_leave_transition(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
    history: List[str],
    ui_queue: queue.Queue,
) -> None:
    """Synchronously generate the social summary and emit a clean transition to exploration.

    Used when the player exits via the "Уйти" button / ESC rather than via an LLM
    action="exploration" decision. Keeping summary generation on this same thread
    (instead of a daemon-spawned one) guarantees that location_history_summary is
    written before the exploration thread rebuilds its agents.
    """
    log.info("leave signal received; generating summary synchronously (npc=%r, history=%d entries)",
             npc_id, len(history))
    ui_queue.put({"type": "thinking"})
    new_summary = _generate_social_summary(api_manager, game_state, npc_id, history)
    log.info("transition: social -> exploration (leave path), summary=%d chars", len(new_summary))
    ui_queue.put({
        "type":    "transition",
        "action":  "exploration",
        "npc_id":  None,
        "room_id": None,
        "summary": new_summary,
    })


# =======================
# RUN LOOP
# =======================

def run_social(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
    ui_queue: queue.Queue,
    input_queue: queue.Queue,
    stop_event: threading.Event,
) -> None:
    """
    Main social loop. Runs in a background thread.

    Sends structured messages to ui_queue and reads player input from input_queue.
    Pauses on 'trade' transitions (waits for resume), exits on others.
    """
    session_id = str(uuid.uuid4())
    span_ctx = (
        logfire.span("social", session_id=session_id, npc_id=npc_id)
        if _LOGFIRE_ENABLED
        else nullcontext()
    )

    log.info("social start session=%s npc=%r", session_id[:8], npc_id)
    try:
        with span_ctx:
            try:
                _social_loop(api_manager, game_state, npc_id, ui_queue, input_queue, stop_event)
            except Exception as e:
                log.exception("social loop crashed")
                ui_queue.put({"type": "error", "text": f"[Ошибка движка: {e}]"})
    except BaseException as e:
        # Catches BaseException (asyncio.CancelledError etc.) that slips past span_ctx
        log.critical("social loop BaseException: %s", type(e).__name__, exc_info=True)
        try:
            ui_queue.put({"type": "error", "text": f"[Критическая ошибка: {e}]"})
        except Exception:
            log.exception("could not enqueue critical-error message")
    log.info("social stop session=%s npc=%r", session_id[:8], npc_id)


def _social_loop(
    api_manager: APIManager,
    game_state: MainGameState,
    npc_id: str,
    ui_queue: queue.Queue,
    input_queue: queue.Queue,
    stop_event: threading.Event,
) -> None:
    npc      = game_state.npcs.get(npc_id) if game_state.npcs else None
    npc_name = getattr(npc, "name", "НПС") if npc else "НПС"
    log.info("social loop starting npc_id=%r npc_name=%r", npc_id, npc_name)

    state: dict = {
        "history":        [],
        "last_npc_reply": "",
        "next_action":    "social",
    }

    # ── Initial greeting ──────────────────────────────────────────────────────
    if stop_event.is_set():
        return

    ui_queue.put({"type": "thinking"})
    log.debug("greeting: building agent")
    try:
        user_prompt = prompt_initial_greeting(npc_name)
        greeting_agent = _build_greeting_agent(api_manager, game_state, npc_id)
        log.debug("greeting: model=%r", greeting_agent.model)
    except Exception:
        log.exception("greeting agent build failed")
        raise

    try:
        with _span("greeting"):
            greeting_result = greeting_agent.run_sync(user_prompt, deps=game_state)
    except Exception:
        log.exception("greeting run_sync failed")
        raise

    scene       = greeting_result.output.greeting_scene
    first_words = greeting_result.output.npc_first_words
    log.info("greeting ok: scene=%d chars, first_words=%d chars",
             len(scene), len(first_words))

    state["history"].append(f"НПС: {first_words}")
    state["last_npc_reply"] = first_words

    ui_queue.put({"type": "greeting", "text": scene})
    ui_queue.put({"type": "npc_reply", "text": first_words})

    # Build remaining agents only after greeting succeeded
    log.debug("building options + resolution agents")
    options_agent    = _build_options_agent(api_manager, game_state, npc_id)
    resolution_agent = _build_resolution_agent(api_manager, game_state, npc_id)
    log.debug("social agents ready")

    # ── Main dialogue loop ────────────────────────────────────────────────────
    while not stop_event.is_set():

        # Generate response options
        ui_queue.put({"type": "thinking"})
        with _span("generate_options"):
            opts_result = options_agent.run_sync(
                prompt_generate_response_options(
                    state["history"], state["last_npc_reply"]
                ),
                deps=game_state,
            )
            options = opts_result.output.options

        ui_queue.put({
            "type": "options",
            "options": [{"id": o.id, "text": o.text} for o in options],
        })

        # Wait for player choice
        msg = _wait_for_input(input_queue, stop_event)
        if msg is None:
            return

        # Player clicked "Уйти" / pressed ESC — exit cleanly with a synchronous summary
        if msg.get("type") == "leave":
            _emit_leave_transition(api_manager, game_state, npc_id, state["history"], ui_queue)
            return

        # Handle a stray "resume" in the input queue (e.g. double-signal)
        if msg.get("type") == "resume":
            ui_queue.put({"type": "resume"})
            continue

        raw_choice = msg["text"].strip()

        # Allow selecting option by number
        if raw_choice.isdigit():
            action_id = int(raw_choice)
            matched   = next(
                (o.text for o in options if o.id == action_id),
                raw_choice,
            )
        else:
            matched = raw_choice

        state["history"].append(f"ИГРОК: {matched}")

        # ── Resolution: a single LLM round produces the NPC reply and next action ──
        ui_queue.put({"type": "thinking"})
        with _span("resolution"):
            try:
                run_result = resolution_agent.run_sync(
                    prompt_social_resolution(
                        state["history"],
                        state["last_npc_reply"],
                        matched,
                    ),
                    deps=game_state,
                )
                parsed = run_result.output
            except Exception as e:
                log.exception("social resolution agent crashed")
                parsed = SocialResolutionOutput(
                    npc_reply=f"[Ошибка агента: {e}]",
                    action="social",
                )

        npc_reply = (parsed.npc_reply or "").strip()
        if not npc_reply:
            # Defensive: the prompt forbids empty replies, but if the model still
            # returns one we keep the conversation going with a neutral in-character line.
            log.warning("social resolution returned empty npc_reply; substituting placeholder")
            npc_reply = "…"

        state["history"].append(f"НПС: {npc_reply}")
        state["last_npc_reply"] = npc_reply
        state["next_action"]    = parsed.action

        ui_queue.put({"type": "npc_reply", "text": npc_reply})

        # ── Transition check ──────────────────────────────────────────────
        if stop_event.is_set():
            return

        next_action = state.get("next_action", "social")
        meta        = parsed.metadata if parsed else ActionMetadata()  # type: ignore[possibly-undefined]

        if next_action == "social":
            continue  # keep chatting

        if next_action == "trade":
            # Pause: player goes to trade screen, may return to conversation
            log.info("transition: social -> trade (npc=%s) [pause]", meta.npc_id or npc_id)
            ui_queue.put({
                "type":   "transition",
                "action": "trade",
                "npc_id": meta.npc_id or npc_id,
                "room_id": None,
            })
            resume = _wait_for_input(input_queue, stop_event)
            if resume is None:
                return  # stop_event was set
            # If the player chose to leave entirely instead of returning to chat
            if resume.get("type") == "leave":
                _emit_leave_transition(api_manager, game_state, npc_id, state["history"], ui_queue)
                return
            # Rebuild agents in case inventory changed after trade
            options_agent    = _build_options_agent(api_manager, game_state, npc_id)
            resolution_agent = _build_resolution_agent(api_manager, game_state, npc_id)
            ui_queue.put({"type": "resume"})
            continue  # continue dialogue after trade

        # For exploration / combat / change_current_room → exit
        if next_action == "change_current_room" and meta.room_id:
            new_room = game_state.rooms.get(meta.room_id)
            if new_room:
                game_state.current_room_id = meta.room_id
                if getattr(new_room, "location_id", None):
                    game_state.current_location_id = new_room.location_id

        # Generate and persist conversation summary before leaving
        ui_queue.put({"type": "thinking"})
        new_summary = _generate_social_summary(api_manager, game_state, npc_id, state["history"])

        log.info("transition: social -> %s (npc=%s room=%s) [exit], summary=%d chars",
                 next_action,
                 meta.npc_id if meta else None,
                 meta.room_id if meta else None,
                 len(new_summary))
        ui_queue.put({
            "type":    "transition",
            "action":  next_action,
            "npc_id":  meta.npc_id  if meta else None,
            "room_id": meta.room_id if meta else None,
            "summary": new_summary,
        })
        return


# =======================
# STATE  (used by the UI)
# =======================

class MessageRole(str, Enum):
    PLAYER = "player"
    NPC    = "npc"
    SYSTEM = "system"


@dataclass
class ChatMessage:
    """A single dialogue entry (kept for legacy UI compatibility)."""
    role: MessageRole
    tag:  str
    text: str

    def formatted(self) -> str:
        return f"{self.tag}: {self.text}"

    def to_llm_turn(self) -> dict:
        llm_role = "user" if self.role == MessageRole.PLAYER else "assistant"
        return {"role": llm_role, "content": self.formatted()}


class SocialState:
    """
    Lightweight non-UI state for a dialogue session with a single NPC.
    The LLM loop (run_social) manages the actual conversation; this class
    provides accessors and a local history for non-LLM screens.
    """

    def __init__(self) -> None:
        self.npc_id:  Optional[ID] = None

    def reset(self, npc_id: ID) -> None:
        self.npc_id = npc_id

    def get_player(self) -> Optional["Player"]:
        gs = game_data.game_state
        return gs.player if gs else None

    def get_npc(self) -> Optional["NPC"]:
        gs = game_data.game_state
        if not gs or not gs.npcs or self.npc_id is None:
            return None
        return gs.npcs.get(self.npc_id) or gs.npcs.get(str(self.npc_id))
