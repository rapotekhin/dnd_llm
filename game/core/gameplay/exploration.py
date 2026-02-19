import json
import os
import re
import uuid
from functools import partial
from typing import Dict, Any, Optional, cast

from langgraph.graph import StateGraph, END
from langchain_core.runnables import RunnableConfig
from langchain.agents import create_openai_tools_agent, AgentExecutor
from langchain_core.prompts import ChatPromptTemplate

from core.llm_engine.api_manager import APIManager, LANGFUSE_AVAILABLE
from core.gameplay.schemas.exploration import (
    SceneDescription,
    ActionList,
    AgentResolutionOutput,
    AgentActionType,
)
from core.tools.roll import roll_dice
from core.tools.db_lookup import rule_db_lookup
from core.prompts.exploration_prompts import (
    AGENT_SYSTEM_PROMPT,
    prompt_describe_scene_user,
    prompt_generate_actions,
    prompt_agent_resolution,
)
from core.data import MainGameState

if LANGFUSE_AVAILABLE:
    from core.llm_engine.langfuse_callbacks import get_openrouter_cost_callback_handler
    CallbackHandler = get_openrouter_cost_callback_handler()


# =======================
# MERGE (КЛЮЧЕВОЙ ФИКС)
# =======================

def merge(state: Dict[str, Any], updates: Dict[str, Any]):
    new_state = dict(state)
    new_state.update(updates)
    return new_state


# =======================
# AGENT
# =======================

def get_exploration_system_prompt(game_state: MainGameState) -> str:
    """Единственное место задания первого/системного промпта для exploration (агент и описание сцены)."""

    connected_rooms_and_locations="\n".join([
        "{} - {} / {}".format(
            game_state.rooms[room_id].name, 
            game_state.locations[game_state.rooms[room_id].location_id].name,
            game_state.locations[game_state.rooms[room_id].location_id].subtype
        ) for room_id in game_state.rooms[game_state.current_room_id].connections
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


def build_agent(api_manager: APIManager, game_state: MainGameState):
    llm = api_manager.llm
    tools = [roll_dice, rule_db_lookup]

    system_prompt = get_exploration_system_prompt(game_state)

    print(f"------------- <SYSTEM PROMPT START> ------------------")
    print(system_prompt)
    print(f"------------- <SYSTEM PROMPT END> ------------------")

    prompt = ChatPromptTemplate.from_messages([
        ("system", system_prompt),
        ("human", "{input}"),
        ("placeholder", "{agent_scratchpad}")
    ])

    agent = create_openai_tools_agent(llm, tools, prompt)
    return AgentExecutor(agent=agent, tools=tools, verbose=True)


# =======================
# SAFE STATE
# =======================

def ensure(state: Dict[str, Any]):
    state.setdefault("history", [])
    state.setdefault("scene", None)
    state.setdefault("actions", [])
    state.setdefault("choice", None)
    state.setdefault("next_activity", None)
    state.setdefault("continue_loop", True)
    return state


# =======================
# NODES
# =======================

def describe_scene(state, config: Optional[RunnableConfig] = None, *, api_manager=None, game_state=None):
    state = ensure(state)

    if state["scene"] is None:
        scene = api_manager.generate_with_format(
            prompt_describe_scene_user(),
            SceneDescription,
            config=config,
            system_prompt=get_exploration_system_prompt(game_state),
        ).environment_description
        history = state["history"]
        state["history"] = history + [scene]
        return merge(state, {
            "scene": scene,
            "history": history
        })
    return state


def generate_actions(state, config: Optional[RunnableConfig] = None, *, api_manager=None, game_state=None):
    state = ensure(state)
    if not state["scene"]:
        return state

    prompt = prompt_generate_actions(state["history"], state["scene"])
    actions = api_manager.generate_with_format(
        prompt,
        ActionList,
        config=config,
        system_prompt=get_exploration_system_prompt(game_state),
    ).actions
    return merge(state, {"actions": actions})

def player_answer_node(state, config: Optional[RunnableConfig] = None, *, game_state=None):
    state = ensure(state)
    if not state.get("awaiting_player_input"):
        return state

    print("---- PLAYER ANSWER NODE <START> ----")
    answer = input("\nYour answer: ")
    print("---- PLAYER ANSWER NODE <END> ----")

    return merge(state, {
        "choice": answer,
        "awaiting_player_input": False
    })

def player_choice(state, config: Optional[RunnableConfig] = None):
    state = ensure(state)
    if not state["actions"]:
        return state

    print("---- PLAYER CHOICE NODE <START> ----")
    print("\n📍 Environment:", state["scene"])
    for a in state["actions"]:
        print(f"{a.id}: {a.description}")
    print("---- PLAYER CHOICE NODE <END> ----")

    choice = input("Choose action: ")
    if choice.isdigit():
        choice = int(choice)
        selected = next(a.description for a in state["actions"] if a.id == choice)
    else:
        selected = choice

    return merge(state, {"choice": selected})


def _parse_agent_resolution_output(text: str) -> AgentResolutionOutput:
    """Парсит ответ агента: сначала JSON + Pydantic, при ошибке — fallback на старый текстовый формат."""
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

    # Попытка 1: JSON (возможно внутри ```json ... ```)
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

    # Fallback: старый текстовый формат
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


def agent_resolution_node(state, config: Optional[RunnableConfig] = None, *, agent=None, game_state=None):
    state = ensure(state)
    if not state.get("choice"):
        return state

    prompt = prompt_agent_resolution(
        state.get("history", []),
        state.get("scene", ""),
        state["choice"],
    )

    print(" ----- AGENT INVOCATION <START> -----")
    try:
        result = agent.invoke({"input": prompt}, config=config or {})
        text = result.get("output") or result.get("final_output") or ""
    except Exception as e:
        text = json.dumps({
            "narration": f"[Agent error: {e}]",
            "action": "exploration",
            "question_to_player": None,
        })
    print(" ----- AGENT INVOCATION <END> -----")

    # --- structured output: JSON -> Pydantic, fallback на старый текстовый разбор ---
    parsed = _parse_agent_resolution_output(text)
    narration = parsed.narration or text.strip()
    activity = parsed.action
    question = (parsed.question_to_player or "").strip() if parsed.question_to_player else ""
    awaiting = parsed.has_question

    # если вопрос — НЕ меняем сцену, просто ждём ответ
    new_scene = state.get("scene") if awaiting else narration

    print("---- AGENT RESOLUTION NODE <START> ----")
    print("activity:", activity)
    print("narration:", narration)
    print("awaiting:", awaiting)
    print("question:", question)
    print("new_scene:", new_scene)
    print("history:", state.get("history", []))
    print("next_activity:", state.get("next_activity"))
    print("choice:", state.get("choice"))
    print("---- AGENT RESOLUTION NODE <END> ----")

    return merge(state, {
        "outcome_text": (question if awaiting else narration),
        "awaiting_player_input": awaiting,
        "pending_question": question if awaiting else None,
        "scene": new_scene,
        "history": state.get("history", []) + [
            f"PLAYER: {state['choice']}",
            f"DM: {(question if awaiting else narration)}"
        ],
        "next_activity": activity if not awaiting else "exploration",  # пока вопрос — не переключаем режим
        "choice": None
    })


def update_agent_state(state, config: Optional[RunnableConfig] = None):
    state = ensure(state)

    # если сцена не изменилась (агент просто продолжил механику) — пропускаем
    if state.get("awaiting_player_input"):
        return state

    print("\n--- RESULT ---")
    print(state["outcome_text"])
    print("continue_loop:", state.get("next_activity") and state["next_activity"] != "exploration")

    # 🔥 если агент инициировал смену режима игры — выходим
    if state.get("next_activity") and state["next_activity"] != "exploration":
        return merge(state, {"continue_loop": False})

    cont = "y" # input("\nContinue adventure? (y/n): ").strip().lower()
    return merge(state, {"continue_loop": cont == "y"})


# =======================
# GRAPH
# =======================

def generate_graph(api_manager, game_state: MainGameState):
    agent = build_agent(api_manager, game_state)
    builder = StateGraph(dict)

    builder.add_node("describe_scene", partial(describe_scene, api_manager=api_manager, game_state=game_state))
    builder.add_node("generate_actions", partial(generate_actions, api_manager=api_manager, game_state=game_state))
    builder.add_node("player_choice", player_choice)
    builder.add_node("agent_resolution", partial(agent_resolution_node, agent=agent, game_state=game_state))
    builder.add_node("update_state", update_agent_state)

    builder.set_entry_point("describe_scene")

    builder.add_edge("describe_scene", "generate_actions")
    builder.add_edge("generate_actions", "player_choice")
    builder.add_edge("player_choice", "agent_resolution")
    builder.add_conditional_edges(
        "agent_resolution",
        lambda s: "player_answer" if s.get("awaiting_player_input") else "update_state"
    )
    builder.add_node("player_answer", partial(player_answer_node, game_state=game_state))
    builder.add_edge("player_answer", "agent_resolution")

    builder.add_conditional_edges(
        "update_state",
        lambda s: "generate_actions" if s.get("continue_loop") else END
    )

    return builder.compile()


# =======================
# RUN
# =======================

def run_exploration(api_manager: APIManager, game_state: MainGameState):
    """
    Запуск exploration-сессии. Первый/системный промпт задаётся только
    в get_exploration_system_prompt(game_state). Каждая сессия создаёт
    свой trace в Langfuse с тегом "exploration" и уникальным session_id.
    """
    graph = generate_graph(api_manager, game_state)

    handler = None
    config: RunnableConfig = {}
    if LANGFUSE_AVAILABLE:
        session_id = str(uuid.uuid4())
        # user_id для Langfuse Users (USER_NAME или LANGFUSE_USER_ID в .env)
        user_id = os.getenv("USER_NAME") or os.getenv("LANGFUSE_USER_ID")
        handler = CallbackHandler()
        metadata = {
            "langfuse_tags": ["exploration"],
            "langfuse_session_id": session_id,
            "model": getattr(api_manager.llm, "model_name", None) or getattr(api_manager.llm, "model", None) or "unknown",
        }
        if user_id:
            metadata["langfuse_user_id"] = str(user_id)
        config = {
            "callbacks": [handler],
            "metadata": metadata,
        }

    try:
        graph.invoke({}, config=config)
    finally:
        if handler is not None:
            handler.client.flush()


if __name__ == "__main__":
    import core.data as data_module
    gs = MainGameState()
    data_module.game_state = gs  # loaders import from core.data — must set the module attribute
    gs = gs.load(1)
    api_manager = APIManager()
    run_exploration(api_manager, gs)
