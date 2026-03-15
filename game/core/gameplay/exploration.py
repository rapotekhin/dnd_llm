"""
Exploration mode: Pydantic AI + Logfire.

run_exploration() is designed to run in a background thread.
It communicates with the UI via two thread-safe queues:

  ui_queue   – exploration → UI
              message types:
                {"type": "scene",    "text": str}
                {"type": "actions",  "actions": [{"id": int, "description": str}]}
                {"type": "narration","text": str}
                {"type": "question", "text": str}
                {"type": "thinking"}
                {"type": "transition", "action": str,
                 "npc_id": str|None, "room_id": str|None}
                {"type": "error",    "text": str}

  input_queue – UI → exploration
              message types:
                {"type": "input", "text": str}

stop_event (threading.Event) — set by the caller to abort the thread.
"""

import json
import os
import queue
import re
import threading
import uuid
from contextlib import nullcontext
from pathlib import Path
from typing import cast, Optional

from dotenv import load_dotenv
from pydantic_ai import Agent
from core.gameplay.schemas.exploration import (
    SceneDescription,
    ActionList,
    AgentResolutionOutput,
    ActionMetadata,
    LocationSummary,
    AgentActionType,
)
from core.tools.roll import RollDiceTool
from core.tools.db_lookup import RuleDbLookupTool
from core.prompts.exploration_prompts import (
    AGENT_SYSTEM_PROMPT,
    prompt_describe_scene_user,
    prompt_generate_actions,
    AGENT_RESOLUTION_INSTRUCTIONS,
    prompt_agent_resolution,
    prompt_generate_location_summary,
)
from core.data.game_state_base import MainGameState
from core.llm_engine.api_manager import APIManager

# Load .env before Logfire
_ENV_FILE = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_FILE)

import logfire

_LOGFIRE_ENABLED = False
try:
    _token = os.getenv("LOGFIRE_TOKEN") or os.getenv("LOGFIRE_AI_API_KEY")
    if _token:
        logfire.configure(token=_token)
        logfire.instrument_pydantic_ai()
        _LOGFIRE_ENABLED = True
except Exception:
    pass


def _span(name: str, **kwargs):
    return logfire.span(name, **kwargs) if _LOGFIRE_ENABLED else nullcontext()


# =======================
# TOOLS
# =======================

_roll_dice_tool = RollDiceTool()
_rule_db_lookup_tool = RuleDbLookupTool()


# =======================
# SYSTEM PROMPT BUILDER
# =======================

def get_exploration_system_prompt(game_state: MainGameState) -> str:
    """Build the DM system prompt, including NPC and room IDs for metadata transitions."""
    if not game_state.current_room_id or not game_state.current_location_id:
        raise ValueError("game_state has no current_room_id / current_location_id")

    current_room     = game_state.rooms[game_state.current_room_id]
    current_location = game_state.locations[game_state.current_location_id]

    # Connected rooms formatted with IDs so the LLM can use them in metadata
    connected_rooms_lines = []
    for room_id in current_room.connections:
        room = game_state.rooms.get(room_id)
        if not room:
            continue
        loc_obj = game_state.locations.get(room.location_id) if room.location_id else None
        loc_info = f" [{loc_obj.name} / {loc_obj.subtype}]" if loc_obj else ""
        connected_rooms_lines.append(f"  - {room.name} (id: {room_id}){loc_info}")
    connected_rooms_with_ids = "\n".join(connected_rooms_lines) or "  (нет)"

    # NPCs in room with IDs
    npc_lines = []
    for npc_id in current_room.npcs:
        npc = game_state.npcs.get(npc_id)
        if not npc:
            continue
        role = getattr(npc, "role", "") or ""
        desc = getattr(npc, "description", "") or ""
        npc_lines.append(f"  - {npc.name} (id: {npc_id}){(', ' + role) if role else ''}: {desc[:80]}")
    npcs_in_room_with_ids = "\n".join(npc_lines) or "  (нет)"

    player = game_state.player
    if player is None:
        raise ValueError("game_state.player is None")

    abilities = ", ".join([
        f"STR: {player.abilities.str} ({player.abilities.get_modifier('str')})",
        f"DEX: {player.abilities.dex} ({player.abilities.get_modifier('dex')})",
        f"CON: {player.abilities.con} ({player.abilities.get_modifier('con')})",
        f"INT: {player.abilities.int} ({player.abilities.get_modifier('int')})",
        f"WIS: {player.abilities.wis} ({player.abilities.get_modifier('wis')})",
        f"CHA: {player.abilities.cha} ({player.abilities.get_modifier('cha')})",
    ])

    return AGENT_SYSTEM_PROMPT.format(
        character_description=repr(player),
        abilities=abilities,
        character_features=repr(player.features),
        character_cantrips=repr(player.sc.cantrips if player.sc else []),
        character_spells=repr(player.sc.leveled_spells if player.sc else []),
        character_conditions=repr(player.conditions),
        location_name=current_location.name,
        location_type=current_location.type,
        location_subtype=current_location.subtype,
        location_description=current_location.description,
        room_name=current_room.name,
        room_description=current_room.description,
        connected_rooms_with_ids=connected_rooms_with_ids,
        location_region=current_location.region,
        location_city=current_location.city,
        npcs_in_room_with_ids=npcs_in_room_with_ids,
        treasures_in_room=current_room.treasures,
        open_location_quests=current_location.get_open_quests(),
        hidden_location_quests=current_location.get_hidden_quests(),
        location_history_summary=current_location.location_history_summary,
    )


# =======================
# AGENT BUILDERS
# =======================

def _build_resolution_agent(
    api_manager: APIManager,
    game_state: MainGameState,
) -> Agent[MainGameState, AgentResolutionOutput]:
    model = api_manager.get_pydantic_ai_model()

    agent = Agent(
        model,
        deps_type=MainGameState,
        output_type=AgentResolutionOutput,
        instructions=(
            get_exploration_system_prompt(game_state)
            + "\n\n"
            + AGENT_RESOLUTION_INSTRUCTIONS
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
                "1d20+3", "2d6+2", "1d8+1". For ability checks and saving throws
                use "1d20+<modifier>" where <modifier> is the numeric ability
                modifier from the character sheet (e.g. WIS +1 → "1d20+1",
                STR -1 → "1d20-1"). NEVER pass a skill or ability name such as
                "wisdom check" or "Perception" — always compute the modifier and
                use dice notation.
            has_advantage: Roll twice and take the higher result (D&D advantage).
            has_disadvantage: Roll twice and take the lower result (D&D disadvantage).
            difficulty_class: Target DC as an integer (e.g. 12). Pass None for
                damage rolls where success/failure is not applicable.
        """
        return _roll_dice_tool.run(
            expression=expression,
            has_advantage=has_advantage,
            has_disadvantage=has_disadvantage,
            difficulty_class=difficulty_class,
        )

    @agent.tool_plain
    def rule_db_lookup(rule_name: str, rule_section: str) -> str:
        """Lookup D&D rules in database."""
        return _rule_db_lookup_tool.run(rule_name, rule_section)

    return agent


def _build_describe_agent(
    api_manager: APIManager,
    game_state: MainGameState,
) -> Agent[MainGameState, SceneDescription]:
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=SceneDescription,
        instructions=get_exploration_system_prompt(game_state),
    )


def _build_generate_actions_agent(
    api_manager: APIManager,
    game_state: MainGameState,
) -> Agent[MainGameState, ActionList]:
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=ActionList,
        instructions=get_exploration_system_prompt(game_state),
    )


def _build_summary_agent(api_manager: APIManager) -> Agent[None, LocationSummary]:
    """Lightweight agent for updating location history summaries."""
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        output_type=LocationSummary,
        instructions=(
            "Ты — архивариус. Составляй краткие (2-4 предложения) записи о событиях в локации. "
            "Только важные факты: кого встретил игрок, что произошло, что изменилось. "
            "Не упоминай механику игры."
        ),
    )


# =======================
# PARSING
# =======================

def _parse_agent_resolution_output(text: str) -> AgentResolutionOutput:
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


# =======================
# HELPERS
# =======================

def _wait_for_input(
    input_queue: queue.Queue,
    stop_event: threading.Event,
    timeout: float = 0.15,
) -> Optional[dict]:
    """Block until a message arrives in input_queue or stop_event is set.
    Returns the message dict, or None if aborted."""
    while not stop_event.is_set():
        try:
            return input_queue.get(timeout=timeout)
        except queue.Empty:
            continue
    return None


def _generate_location_summary(
    api_manager: APIManager,
    game_state: MainGameState,
    session_history: list,
) -> str:
    """Generate an updated location summary via LLM and persist it to game_state."""
    loc_id   = game_state.current_location_id
    location = game_state.locations.get(loc_id) if loc_id else None
    if not location:
        return ""
    past = location.location_history_summary or ""
    prompt = prompt_generate_location_summary(past, session_history, location.name)
    try:
        agent = _build_summary_agent(api_manager)
        result = agent.run_sync(prompt)
        new_summary = result.output.summary
        location.location_history_summary = new_summary
        return new_summary
    except Exception as e:
        # Non-fatal: keep existing summary
        return past


# =======================
# RUN LOOP
# =======================

def run_exploration(
    api_manager: APIManager,
    game_state: MainGameState,
    ui_queue: queue.Queue,
    input_queue: queue.Queue,
    stop_event: threading.Event,
) -> None:
    """
    Main exploration loop. Runs in a background thread.

    Sends structured messages to ui_queue and reads player input from input_queue.
    Exits when stop_event is set or a non-exploration transition occurs.
    """
    session_id = str(uuid.uuid4())
    user_id = os.getenv("USER_NAME") or os.getenv("LOGFIRE_USER_ID", "")

    span_ctx = (
        logfire.span(
            "exploration",
            session_id=session_id,
            user_id=user_id or None,
            model=api_manager.model_name,
        )
        if _LOGFIRE_ENABLED
        else nullcontext()
    )

    with span_ctx:
        try:
            _exploration_loop(api_manager, game_state, ui_queue, input_queue, stop_event)
        except Exception as e:
            ui_queue.put({"type": "error", "text": f"[Ошибка движка: {e}]"})


def _exploration_loop(
    api_manager: APIManager,
    game_state: MainGameState,
    ui_queue: queue.Queue,
    input_queue: queue.Queue,
    stop_event: threading.Event,
) -> None:
    describe_agent    = _build_describe_agent(api_manager, game_state)
    generate_agent    = _build_generate_actions_agent(api_manager, game_state)
    resolution_agent  = _build_resolution_agent(api_manager, game_state)

    state: dict = {
        "history": [],
        "scene": None,
        "actions": [],
        "choice": None,
        "next_activity": None,
        "awaiting_player_input": False,
        "outcome_text": "",
    }

    # ── Describe initial scene ───────────────────────────────────────
    if stop_event.is_set():
        return
    ui_queue.put({"type": "thinking"})
    with _span("describe_scene"):
        result = describe_agent.run_sync(prompt_describe_scene_user(), deps=game_state)
        scene = result.output.environment_description
        state["history"].append(scene)
        state["scene"] = scene
    ui_queue.put({"type": "scene", "text": scene})

    # ── Main action loop ─────────────────────────────────────────────
    while not stop_event.is_set():

        # Generate action options
        ui_queue.put({"type": "thinking"})
        with _span("generate_actions"):
            prompt = prompt_generate_actions(state["history"], state["scene"])
            result = generate_agent.run_sync(prompt, deps=game_state)
            state["actions"] = result.output.actions
        ui_queue.put({
            "type": "actions",
            "actions": [{"id": a.id, "description": a.description} for a in state["actions"]],
        })

        # Wait for player choice
        msg = _wait_for_input(input_queue, stop_event)
        if msg is None:
            return
        raw_choice = msg["text"].strip()

        # Allow selecting action by number
        if raw_choice.isdigit():
            action_id = int(raw_choice)
            matched = next(
                (a.description for a in state["actions"] if a.id == action_id),
                raw_choice,
            )
        else:
            matched = raw_choice
        state["choice"] = matched

        # ── Resolution loop (may include follow-up question) ─────────
        while not stop_event.is_set():
            ui_queue.put({"type": "thinking"})
            with _span("agent_resolution"):
                prompt = prompt_agent_resolution(
                    state["history"],
                    state["scene"],
                    state["choice"],
                )
                try:
                    run_result = resolution_agent.run_sync(prompt, deps=game_state)
                    parsed = run_result.output
                except Exception as e:
                    parsed = AgentResolutionOutput(
                        narration=f"[Ошибка агента: {e}]",
                        action="exploration",
                        question_to_player=None,
                    )

            narration = parsed.narration or ""
            activity  = parsed.action
            question  = (parsed.question_to_player or "").strip()
            awaiting  = parsed.has_question and activity == "exploration"

            new_scene = state["scene"] if awaiting else narration

            if awaiting:
                ui_queue.put({"type": "question", "text": question})
            else:
                ui_queue.put({"type": "narration", "text": narration})

            state["outcome_text"]         = question if awaiting else narration
            state["awaiting_player_input"] = awaiting
            state["scene"]    = new_scene
            state["history"] += [
                f"PLAYER: {state['choice']}",
                f"DM: {(question if awaiting else narration)}",
            ]
            state["next_activity"] = activity if not awaiting else "exploration"
            state["choice"] = None

            if not awaiting:
                break

            # Follow-up question → wait for player answer
            msg = _wait_for_input(input_queue, stop_event)
            if msg is None:
                return
            state["choice"] = msg["text"].strip()

        # ── Non-exploration transition ───────────────────────────────
        if stop_event.is_set():
            return

        next_act = state.get("next_activity")
        if next_act and next_act != "exploration":
            meta = parsed.metadata  # type: ignore[possibly-undefined]

            if next_act in ("social", "trade"):
                # Pause the thread instead of exiting so we can resume
                # seamlessly without a slow describe_scene on return.
                ui_queue.put({
                    "type": "transition",
                    "action": next_act,
                    "npc_id":  meta.npc_id  if meta else None,
                    "room_id": None,
                })
                resume = _wait_for_input(input_queue, stop_event)
                if resume is None:
                    return  # stop_event was set while waiting
                # Rebuild agents so their system prompt includes any updated
                # location_history_summary written by the social/trade session.
                generate_agent   = _build_generate_actions_agent(api_manager, game_state)
                resolution_agent = _build_resolution_agent(api_manager, game_state)
                # Clear in-session history: events before the side-session are now
                # stale — they contradict the updated location_history_summary in
                # the system prompt.  The rebuilt system prompt already carries the
                # full location context, so starting with an empty history is correct.
                state["history"] = []
                ui_queue.put({"type": "resume"})
                # Continue the while-loop → go straight to generate_actions
                continue

            # For room/combat: update state then exit (full restart required)
            if next_act == "change_current_room" and meta.room_id:
                new_room = game_state.rooms.get(meta.room_id)
                if new_room:
                    game_state.current_room_id = meta.room_id
                    if new_room.location_id:
                        game_state.current_location_id = new_room.location_id

            # Generate and persist location summary before leaving
            ui_queue.put({"type": "thinking"})
            _generate_location_summary(api_manager, game_state, state["history"])

            ui_queue.put({
                "type": "transition",
                "action": next_act,
                "npc_id":  meta.npc_id  if meta else None,
                "room_id": meta.room_id if meta else None,
            })
            return


if __name__ == "__main__":
    import core.data as data_module
    from core.data.game_state_base import MainGameState

    gs = MainGameState()
    data_module.game_state = gs
    gs = gs.load(1)

    _ui_q: queue.Queue = queue.Queue()
    _in_q: queue.Queue = queue.Queue()
    _stop = threading.Event()

    def _console_ui(uq: queue.Queue, iq: queue.Queue, se: threading.Event):
        """Simple console UI for testing without pygame."""
        while not se.is_set():
            try:
                msg = uq.get(timeout=0.2)
            except queue.Empty:
                continue
            t = msg["type"]
            if t == "scene":
                print("\n📍 Scene:", msg["text"])
            elif t == "actions":
                print("\nActions:")
                for a in msg["actions"]:
                    print(f"  {a['id']}. {a['description']}")
                answer = input("Choice: ")
                iq.put({"type": "input", "text": answer})
            elif t == "narration":
                print("\n🎲 DM:", msg["text"])
            elif t == "question":
                print("\n❓ DM:", msg["text"])
                answer = input("Answer: ")
                iq.put({"type": "input", "text": answer})
            elif t == "thinking":
                print("  ...", end="", flush=True)
            elif t == "transition":
                print(f"\n→ Transition: {msg['action']} npc={msg.get('npc_id')} room={msg.get('room_id')}")
                se.set()
            elif t == "error":
                print("\n⚠️", msg["text"])
                se.set()
    import threading as _threading
    am = APIManager()
    thr = _threading.Thread(target=run_exploration, args=(am, gs, _ui_q, _in_q, _stop), daemon=True)
    thr.start()
    _console_ui(_ui_q, _in_q, _stop)
