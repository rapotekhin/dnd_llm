"""
Exploration mode: Pydantic AI + Logfire.

run_exploration() is designed to run in a background thread.
It communicates with the UI via two thread-safe queues:

  ui_queue   – exploration → UI
              message types:
                {"type": "scene",        "text": str}
                {"type": "actions",      "actions": [{"id": int, "description": str}]}
                {"type": "narration",    "text": str}
                {"type": "question",     "text": str}
                {"type": "system_marker","text": str}   subtle in-chat divider
                {"type": "thinking"}
                {"type": "transition",   "action": str,
                 "npc_id": str|None, "room_id": str|None}
                {"type": "error",        "text": str}

  input_queue – UI → exploration
              message types:
                {"type": "input",  "text": str}
                {"type": "resume", "summary": str}   side-session report on return

stop_event (threading.Event) — set by the caller to abort the thread.
"""

import os
import queue
import threading
import uuid
from contextlib import nullcontext
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from pydantic_ai import Agent
from core.gameplay.schemas.exploration import (
    SceneDescription,
    ActionList,
    AgentResolutionOutput,
    ActionMetadata,
    LocationSummary,
)
from core.tools.roll import RollDiceTool
from core.prompts.exploration_prompts import (
    AGENT_SYSTEM_PROMPT,
    prompt_describe_scene_user,
    prompt_describe_scene_resume,
    prompt_generate_actions,
    AGENT_RESOLUTION_INSTRUCTIONS,
    prompt_agent_resolution,
    prompt_generate_location_summary,
)
from core.data.game_state_base import MainGameState
from core.llm_engine.api_manager import APIManager
from core.prompts.common import player_gender_line
from core.logging_config import get_logger

log = get_logger(__name__)

# Load .env before Logfire
_ENV_FILE = Path(__file__).resolve().parents[4] / ".env"  # repository root
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
        character_gender=player_gender_line(player),
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
# HELPERS
# =======================

# The LLM picks transition targets by id; anything it names that is not in the
# scene (hallucinated NPC, non-adjacent room) keeps the player in exploration.
NPC_NOT_HERE_MARKER = "— Этого собеседника здесь нет: сцена продолжается —"
ROOM_UNREACHABLE_MARKER = "— Туда отсюда не пройти: сцена продолжается —"


def npc_in_current_room(game_state: MainGameState, npc_id: Optional[str]) -> bool:
    """True if ``npc_id`` is a known NPC standing in the player's current room."""
    room = game_state.rooms.get(game_state.current_room_id) if game_state.current_room_id else None
    return bool(npc_id) and room is not None and npc_id in room.npcs and npc_id in game_state.npcs


def room_reachable(game_state: MainGameState, room_id: Optional[str]) -> bool:
    """True if ``room_id`` exists and is connected to the player's current room."""
    room = game_state.rooms.get(game_state.current_room_id) if game_state.current_room_id else None
    return bool(room_id) and room is not None and room_id in room.connections and room_id in game_state.rooms


# Combat mode is not implemented yet: a "combat" decision keeps the player in
# exploration instead of transitioning to a screen that does not exist.
COMBAT_UNAVAILABLE_MARKER = "— Бой пока не реализован: сцена продолжается —"
COMBAT_UNAVAILABLE_HISTORY = (
    "СИСТЕМА: боевой режим пока недоступен. Продолжай сцену без боя: "
    "противники медлят, отступают или конфликт решается иначе."
)

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


AGENT_ATTEMPTS = 2  # one retry for transient OpenRouter / validation failures


def run_agent_with_retry(agent, prompt: str, *, what: str, **kwargs):
    """``agent.run_sync`` with a retry; re-raises the last error."""
    last_error: Optional[Exception] = None
    for attempt in range(1, AGENT_ATTEMPTS + 1):
        try:
            return agent.run_sync(prompt, **kwargs)
        except Exception as e:  # noqa: BLE001 — any provider / validation error
            last_error = e
            log.warning("%s failed (attempt %d/%d): %s", what, attempt, AGENT_ATTEMPTS, e)
    assert last_error is not None
    raise last_error


def agent_unavailable_text(error: Exception) -> str:
    return f"[Мастер не ответил: {error}]"


def _fallback_scene(game_state: MainGameState) -> str:
    """Static room description when the LLM cannot describe the scene."""
    room = game_state.rooms.get(game_state.current_room_id) if game_state.current_room_id else None
    return (room.description or room.name) if room else ""


SIDE_CONTEXT_ENTRIES = 6  # last history entries handed to social/trade


def recent_scene_context(history: list) -> str:
    """The last few exploration entries (player actions + DM narration)."""
    return "\n".join(str(h) for h in history[-SIDE_CONTEXT_ENTRIES:])


def _wait_for_player_text(
    input_queue: queue.Queue,
    stop_event: threading.Event,
) -> Optional[str]:
    """Block until the player sends text input. Returns None if aborted.

    Control messages (e.g. a stray ``resume`` after the player came back from the
    inventory) are not player actions, so they are skipped instead of crashing.
    """
    while True:
        msg = _wait_for_input(input_queue, stop_event)
        if msg is None:
            return None
        if isinstance(msg, dict) and msg.get("type") == "input":
            return str(msg.get("text") or "").strip()
        log.warning("ignoring non-input message while waiting for player: %r", msg)


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
    except Exception:
        # Non-fatal: keep existing summary, but log the cause.
        log.exception("location summary generation failed; keeping previous summary")
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

    log.info("exploration start session=%s room=%s location=%s",
             session_id[:8], game_state.current_room_id, game_state.current_location_id)
    with span_ctx:
        try:
            _exploration_loop(api_manager, game_state, ui_queue, input_queue, stop_event)
        except Exception as e:
            log.exception("exploration loop crashed")
            ui_queue.put({"type": "error", "text": f"[Ошибка движка: {e}]"})
    log.info("exploration stop session=%s", session_id[:8])


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
    log.debug("describe_scene: starting")
    with _span("describe_scene"):
        try:
            result = run_agent_with_retry(describe_agent, prompt_describe_scene_user(),
                                          what="describe_scene", deps=game_state)
            scene = result.output.environment_description
        except Exception as e:
            log.exception("describe_scene failed; using static room description")
            ui_queue.put({"type": "error", "text": agent_unavailable_text(e)})
            scene = _fallback_scene(game_state)
        state["history"].append(scene)
        state["scene"] = scene
    log.info("describe_scene: %d chars", len(scene))
    ui_queue.put({"type": "scene", "text": scene})

    # ── Main action loop ─────────────────────────────────────────────
    while not stop_event.is_set():

        # Generate action options
        ui_queue.put({"type": "thinking"})
        with _span("generate_actions"):
            prompt = prompt_generate_actions(state["history"], state["scene"])
            try:
                result = run_agent_with_retry(generate_agent, prompt,
                                              what="generate_actions", deps=game_state)
                state["actions"] = result.output.actions
            except Exception as e:
                # No suggestions this turn; the player can still type an action.
                log.exception("generate_actions failed")
                ui_queue.put({"type": "error", "text": agent_unavailable_text(e)
                              + " Опиши действие сам."})
                state["actions"] = []
        ui_queue.put({
            "type": "actions",
            "actions": [{"id": a.id, "description": a.description} for a in state["actions"]],
        })

        # Wait for player choice
        raw_choice = _wait_for_player_text(input_queue, stop_event)
        if raw_choice is None:
            return

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
            log.info("resolution: choice=%r", state["choice"])
            with _span("agent_resolution"):
                prompt = prompt_agent_resolution(
                    state["history"],
                    state["scene"],
                    state["choice"],
                )
                try:
                    run_result = run_agent_with_retry(resolution_agent, prompt,
                                                      what="agent_resolution", deps=game_state)
                    parsed = run_result.output
                except Exception as e:
                    log.exception("resolution agent crashed")
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
            answer = _wait_for_player_text(input_queue, stop_event)
            if answer is None:
                return
            state["choice"] = answer

        # ── Non-exploration transition ───────────────────────────────
        if stop_event.is_set():
            return

        next_act = state.get("next_activity")
        if next_act == "combat":
            log.info("combat requested but not implemented; staying in exploration")
            ui_queue.put({"type": "system_marker", "text": COMBAT_UNAVAILABLE_MARKER})
            state["history"].append(COMBAT_UNAVAILABLE_HISTORY)
            continue

        meta = parsed.metadata  # type: ignore[possibly-undefined]
        if next_act in ("social", "trade") and not npc_in_current_room(
                game_state, meta.npc_id if meta else None):
            log.warning("transition %s to unknown npc %r; staying in exploration",
                        next_act, meta.npc_id if meta else None)
            ui_queue.put({"type": "system_marker", "text": NPC_NOT_HERE_MARKER})
            state["history"].append(
                "СИСТЕМА: такого НПС нет в комнате. Переходи в диалог или торговлю "
                "только с НПС из списка «НПС в комнате», указывая его id."
            )
            continue
        if next_act == "change_current_room" and not room_reachable(
                game_state, meta.room_id if meta else None):
            log.warning("transition to unreachable room %r; staying in exploration",
                        meta.room_id if meta else None)
            ui_queue.put({"type": "system_marker", "text": ROOM_UNREACHABLE_MARKER})
            state["history"].append(
                "СИСТЕМА: в эту комнату отсюда не пройти. Переход возможен только "
                "в комнаты из списка «Связанные комнаты», указывая их id."
            )
            continue

        if next_act and next_act != "exploration":

            if next_act in ("social", "trade"):
                # Pause the thread instead of exiting so we can resume
                # without a fresh run_exploration spin-up.
                log.info("transition: exploration -> %s (npc=%s) [pause]",
                         next_act, meta.npc_id if meta else None)
                ui_queue.put({
                    "type": "transition",
                    "action": next_act,
                    "npc_id":  meta.npc_id  if meta else None,
                    "room_id": None,
                    # What just happened, so the NPC does not greet as if nothing did.
                    "context": recent_scene_context(state["history"]),
                })
                resume = _wait_for_input(input_queue, stop_event)
                if resume is None:
                    return  # stop_event was set while waiting

                # Side-session summary (synchronous report from social/trade).
                side_summary = ""
                if isinstance(resume, dict):
                    side_summary = (resume.get("summary") or "").strip()
                log.info("resume: side_summary=%d chars", len(side_summary))

                # Rebuild all agents so their system prompt reflects the updated
                # location_history_summary written by the side-session.
                describe_agent   = _build_describe_agent(api_manager, game_state)
                generate_agent   = _build_generate_actions_agent(api_manager, game_state)
                resolution_agent = _build_resolution_agent(api_manager, game_state)

                # Fresh history; seed with the side-session report (DM voice) so the
                # LLM knows what happened off-screen and does not "continue" the
                # dialogue in exploration.
                state["history"] = []
                if side_summary:
                    state["history"].append(f"DM: {side_summary}")

                # Make the return visible to the player: subtle marker + the
                # summary as DM narration. Without this the chat jumps from old
                # entries straight to a fresh scene, with no closure on the
                # side-session.
                ui_queue.put({"type": "system_marker", "text": "— Возвращение к исследованию —"})
                if side_summary:
                    ui_queue.put({"type": "narration", "text": side_summary})

                # Re-describe the scene so state["scene"] reflects post-dialogue
                # ground truth (NPC may have left, inventory changed, etc.). The
                # resume-specific prompt tells the LLM this is a continuation —
                # otherwise it writes a "first impression" of the room.
                ui_queue.put({"type": "thinking"})
                with _span("describe_scene_resume"):
                    try:
                        result = run_agent_with_retry(
                            describe_agent, prompt_describe_scene_resume(side_summary),
                            what="describe_scene_resume", deps=game_state,
                        )
                        new_scene = result.output.environment_description
                    except Exception as e:
                        log.exception("describe_scene_resume failed; using static room description")
                        ui_queue.put({"type": "error", "text": agent_unavailable_text(e)})
                        new_scene = _fallback_scene(game_state)
                state["history"].append(new_scene)
                state["scene"] = new_scene
                ui_queue.put({"type": "scene", "text": new_scene})

                ui_queue.put({"type": "resume"})
                # Continue the while-loop → go to generate_actions with fresh context
                continue

            # For room/combat: update state then exit (full restart required)
            if next_act == "change_current_room":
                new_room = game_state.rooms[meta.room_id]
                game_state.current_room_id = meta.room_id
                if new_room.location_id:
                    game_state.current_location_id = new_room.location_id

            # Generate and persist location summary before leaving
            ui_queue.put({"type": "thinking"})
            _generate_location_summary(api_manager, game_state, state["history"])

            log.info("transition: exploration -> %s (npc=%s room=%s) [exit]",
                     next_act,
                     meta.npc_id if meta else None,
                     meta.room_id if meta else None)
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
