from functools import partial
from langgraph.graph import StateGraph, END
from langchain.tools import tool
from langchain.agents import create_openai_tools_agent, AgentExecutor
from langchain_core.prompts import ChatPromptTemplate

from core.llm_engine.api_manager import APIManager
from core.gameplay.schemas.exploration import GameState, SceneDescription, ActionList

@tool
def rule_db_lookup(rule_name: str, rule_section: str) -> str:
    """Lookup D&D rules in database."""
    return "res"