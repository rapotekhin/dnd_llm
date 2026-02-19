from functools import partial
from pydantic import BaseModel, Field
from typing import List, Literal, Optional, TypedDict


# =======================
# STRUCTURED OUTPUT MODELS
# =======================

class SceneDescription(BaseModel):
    environment_description: str


class ActionOption(BaseModel):
    id: int
    description: str


class ActionList(BaseModel):
    actions: List[ActionOption]


# Ответ агента при разрешении действия игрока (structured output)
AgentActionType = Literal["exploration", "combat", "social", "trade", "change_current_room"]


class AgentResolutionOutput(BaseModel):
    """Структурированный ответ агента: наррация, следующее действие, опциональный вопрос игроку."""

    narration: str = Field(description="Текст наррации / итоговая сцена для игрока.")
    action: AgentActionType = Field(
        description="Режим игры после действия: exploration | combat | social | trade | change_current_room"
    )
    question_to_player: Optional[str] = Field(
        default=None,
        description="Вопрос игроку, если нужны уточнения. Пустая строка или null — вопроса нет.",
    )

    @property
    def has_question(self) -> bool:
        return bool(self.question_to_player and self.question_to_player.strip())


class RollOptions(BaseModel):
    """Parameters for performing a dice roll using D&D 5e rules."""

    expression: str = Field(
        description=(
            "Dice expression to roll, e.g. '1d20', '1d20+5', '2d6+1', format like (AdB)*C±D. "
            "Use either a d20 check (attacks, skill checks, saves) OR damage dice, "
            "but not both in the same roll request."
        )
    )

    has_advantage: Optional[bool] = Field(
        default=False,
        description="If true, roll twice and take the higher result (D&D advantage rule). Only applies to d20 rolls."
    )

    has_disadvantage: Optional[bool] = Field(
        default=False,
        description="If true, roll twice and take the lower result (D&D disadvantage rule). Only applies to d20 rolls."
    )

    difficulty_class: Optional[int] = Field(
        default=None,
        description=(
            "Target Difficulty Class (DC) for d20 checks in combat or non-combat scenes. "
            "Not used for damage rolls."
        )
    )

class RuleLookupOptions(BaseModel):
    rule_name: str
    rule_section: str


class ToolDecision(BaseModel):
    needs_roll: bool
    roll_options: Optional[RollOptions] = None
    needs_rule_lookup: bool
    rule_lookup_options: Optional[RuleLookupOptions] = None


class ToolResult(BaseModel):
    roll_result: Optional[tuple[int, bool | None]] = None
    rule_info: Optional[str] = None


class Outcome(BaseModel):
    narrative: str
    inventory_update: Optional[str] = None
    quest_update: Optional[str] = None
    character_update: Optional[str] = None
    location_change: bool = False
    gameplay_mode_change: Optional[str] = None


# =======================
# LANGGRAPH STATE
# =======================

class BaseState(TypedDict, total=False):
    system_prompt: str

class GameState(BaseState):
    system_prompt: str
    scene: str
    actions: List[ActionOption]
    choice: str
    tool_decision: ToolDecision
    tool_result: ToolResult
    outcome: Outcome
    continue_loop: bool
