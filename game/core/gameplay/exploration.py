"""
Exploration mode: Pydantic AI + Logfire.
Replaces LangGraph + Langfuse with Pydantic AI agents and Logfire tracing.
"""

import json
import os
import re
import uuid
from contextlib import nullcontext
from pathlib import Path
from typing import cast

from dotenv import load_dotenv
from pydantic_ai import Agent
from core.gameplay.schemas.exploration import (
    SceneDescription,
    ActionList,
    AgentResolutionOutput,
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
)
from core.data.game_state_base import MainGameState
from core.llm_engine.api_manager import APIManager

# Load .env before Logfire
_ENV_FILE = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_FILE)

import logfire

_LOGFIRE_ENABLED = False
try:
    # Logfire expects LOGFIRE_TOKEN; LOGFIRE_AI_API_KEY supported as fallback
    _token = os.getenv("LOGFIRE_TOKEN") or os.getenv("LOGFIRE_AI_API_KEY")
    if _token:
        logfire.configure(token=_token)
        logfire.instrument_pydantic_ai()
        _LOGFIRE_ENABLED = True
except Exception:
    pass


def _span(name: str, **kwargs):
    """Context manager: logfire.span if enabled, else no-op."""
    return logfire.span(name, **kwargs) if _LOGFIRE_ENABLED else nullcontext()


# =======================
# TOOLS (from core.tools, OOP)
# =======================

_roll_dice_tool = RollDiceTool()
_rule_db_lookup_tool = RuleDbLookupTool()


# =======================
# MODEL & AGENTS (via api_manager)
# =======================


def get_exploration_system_prompt(game_state: MainGameState) -> str:
    """Единственное место задания первого/системного промпта для exploration."""

    connected_rooms_and_locations = "\n".join([
        "{} - {} / {}".format(
            game_state.rooms[room_id].name,
            game_state.locations[game_state.rooms[room_id].location_id].name,
            game_state.locations[game_state.rooms[room_id].location_id].subtype,
        )
        for room_id in game_state.rooms[game_state.current_room_id].connections
    ])

    abilities = ", ".join([
        f"STR: {game_state.player.abilities.str} ({game_state.player.abilities.get_modifier('str')})",
        f"DEX: {game_state.player.abilities.dex} ({game_state.player.abilities.get_modifier('dex')})",
        f"CON: {game_state.player.abilities.con} ({game_state.player.abilities.get_modifier('con')})",
        f"INT: {game_state.player.abilities.int} ({game_state.player.abilities.get_modifier('int')})",
        f"WIS: {game_state.player.abilities.wis} ({game_state.player.abilities.get_modifier('wis')})",
        f"CHA: {game_state.player.abilities.cha} ({game_state.player.abilities.get_modifier('cha')})",
    ])

    return AGENT_SYSTEM_PROMPT.format(
        character_description=repr(game_state.player),
        abilities=abilities,
        character_features=repr(game_state.player.features),
        character_cantrips=repr(game_state.player.sc.cantrips),
        character_spells=repr(game_state.player.sc.leveled_spells),
        character_conditions=repr(game_state.player.conditions),
        location_name=game_state.locations[game_state.current_location_id].name,
        location_type=game_state.locations[game_state.current_location_id].type,
        location_subtype=game_state.locations[game_state.current_location_id].subtype,
        location_description=game_state.locations[game_state.current_location_id].description,
        room_name=game_state.rooms[game_state.current_room_id].name,
        room_description=game_state.rooms[game_state.current_room_id].description,
        connected_rooms_and_locations=connected_rooms_and_locations,
        location_region=game_state.locations[game_state.current_location_id].region,
        location_city=game_state.locations[game_state.current_location_id].city,
        npcs_in_room=game_state.rooms[game_state.current_room_id].npcs,
        treasures_in_room=game_state.rooms[game_state.current_room_id].treasures,
        open_location_quests=game_state.locations[game_state.current_location_id].get_open_quests(),
        hidden_location_quests=game_state.locations[game_state.current_location_id].get_hidden_quests(),
        location_history_summary=game_state.locations[game_state.current_location_id].location_history_summary,
    )


def _build_resolution_agent(
    api_manager: APIManager,
    game_state: MainGameState,
) -> Agent[MainGameState, AgentResolutionOutput]:
    """Build Pydantic AI agent for action resolution (with tools). Model from api_manager."""
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
        difficulty_class: int | None = None,
    ) -> dict:
        """Roll dice using D&D 5e advantage/disadvantage rules and optionally
        evaluate the result against a Difficulty Class (DC).
        Use for skill checks, saves, attacks (expression like 1d20+5) or damage (e.g. 2d6+3)."""
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
    """Build agent for scene description. Model from api_manager."""
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=SceneDescription,
        instructions=get_exploration_system_prompt(game_state),
    )


def _build_generate_actions_agent(
    api_manager,
    game_state: MainGameState,
) -> Agent[MainGameState, ActionList]:
    """Build agent for action list generation. Model from api_manager."""
    model = api_manager.get_pydantic_ai_model()
    return Agent(
        model,
        deps_type=MainGameState,
        output_type=ActionList,
        instructions=get_exploration_system_prompt(game_state),
    )


# =======================
# PARSING
# =======================

def _parse_agent_resolution_output(text: str) -> AgentResolutionOutput:
    """Парсит ответ агента: JSON -> Pydantic, fallback на старый текстовый формат."""
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
            return AgentResolutionOutput(
                narration=data.get("narration") or "",
                action=cast(AgentActionType, action),
                question_to_player=q if (q and q.strip()) else None,
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
    )


# =======================
# RUN LOOP
# =======================

def run_exploration(api_manager: APIManager, game_state: MainGameState):
    """
    Запуск exploration-сессии на Pydantic AI + Logfire.
    Все настройки LLM (модель, провайдер) берутся из api_manager.
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
        describe_agent = _build_describe_agent(api_manager, game_state)
        generate_agent = _build_generate_actions_agent(api_manager, game_state)
        resolution_agent = _build_resolution_agent(api_manager, game_state)

        state: dict = {
            "history": [],
            "scene": None,
            "actions": [],
            "choice": None,
            "next_activity": None,
            "continue_loop": True,
            "awaiting_player_input": False,
            "outcome_text": "",
        }

        # describe_scene
        if state["scene"] is None:
            with _span("describe_scene"):
                result = describe_agent.run_sync(
                    prompt_describe_scene_user(),
                    deps=game_state,
                )
                scene = result.output.environment_description
                state["history"] = state["history"] + [scene]
                state["scene"] = scene

        while True:
            # generate_actions
            if not state["scene"]:
                break
            with _span("generate_actions"):
                prompt = prompt_generate_actions(state["history"], state["scene"])
                result = generate_agent.run_sync(prompt, deps=game_state)
                state["actions"] = result.output.actions

            # player_choice
            print("---- PLAYER CHOICE NODE <START> ----")
            print("\n📍 Environment:", state["scene"])
            for a in state["actions"]:
                print(f"{a.id}: {a.description}")
            print("---- PLAYER CHOICE NODE <END> ----")
            choice = input("Choose action: ")
            if choice.isdigit():
                selected = next(
                    (a.description for a in state["actions"] if a.id == int(choice)),
                    choice,
                )
            else:
                selected = choice
            state["choice"] = selected

            # agent_resolution (may loop on question)
            while True:
                with _span("agent_resolution"):
                    prompt = prompt_agent_resolution(
                        state["history"],
                        state["scene"],
                        state["choice"],
                    )
                    print(" ----- AGENT INVOCATION <START> -----")
                    try:
                        run_result = resolution_agent.run_sync(prompt, deps=game_state)
                        parsed = run_result.output
                    except Exception as e:
                        parsed = AgentResolutionOutput(
                            narration=f"[Agent error: {e}]",
                            action="exploration",
                            question_to_player=None,
                        )
                    print(" ----- AGENT INVOCATION <END> -----")

                narration = parsed.narration or ""
                activity = parsed.action
                question = (parsed.question_to_player or "").strip()
                # При смене сцены/режима (combat, social, trade, change_current_room) — агент закрыт, не ждём
                awaiting = parsed.has_question and activity == "exploration"

                new_scene = state["scene"] if awaiting else narration

                print("---- AGENT RESOLUTION NODE <START> ----")
                print("activity:", activity)
                print("narration:", narration)
                print("awaiting:", awaiting)
                print("question:", question)
                print("---- AGENT RESOLUTION NODE <END> ----")

                state["outcome_text"] = question if awaiting else narration
                state["awaiting_player_input"] = awaiting
                state["scene"] = new_scene
                state["history"] = state["history"] + [
                    f"PLAYER: {state['choice']}",
                    f"DM: {(question if awaiting else narration)}",
                ]
                state["next_activity"] = activity if not awaiting else "exploration"
                state["choice"] = None

                if not awaiting:
                    break

                # player_answer
                print("---- PLAYER ANSWER NODE <START> ----")
                answer = input("\nYour answer: ")
                print("---- PLAYER ANSWER NODE <END> ----")
                state["choice"] = answer

            # update_state
            print("\n--- RESULT ---")
            print(state["outcome_text"])
            print(
                "continue_loop:",
                state.get("next_activity") and state["next_activity"] != "exploration",
            )

            if state.get("next_activity") and state["next_activity"] != "exploration":
                break

            cont = "y"
            if cont != "y":
                break


if __name__ == "__main__":
    import core.data as data_module
    from core.data.game_state_base import MainGameState

    gs = MainGameState()
    data_module.game_state = gs
    gs = gs.load(1)
    from core.llm_engine.api_manager import APIManager

    api_manager = APIManager()
    run_exploration(api_manager, gs)
