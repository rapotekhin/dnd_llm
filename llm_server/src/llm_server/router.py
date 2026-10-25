"""The prompt router (v0.7.20.4): a turn that only needs words goes with a short system prompt (~1k tokens, no tools)
instead of the full one (~15k with the rules and the scene).

- A turn the engine already resolved (entering a room, a deal, a rest, a round of a fight…) is short by its kind —
  no router call.
- The player's own words (`kind = action`) are asked of the router: one small request to the same model.
- The short master may still find it needs more (a check, an effect): it answers `need_full`, nothing reached the
  engine yet, and the turn runs again with the full prompt.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field
from pydantic_ai import Agent
from pydantic_ai.models import Model

from . import prompts
from .agents import TurnOutput, scene_npc, settings_for
from .protocol import TurnRequestParams

# Turns that only retell what the engine did: the turn prompt says «эффектов не добавляй».
SHORT_KINDS = {"rest", "deal", "haggle", "quest", "theft", "law", "wait", "trap", "combat_start", "combat_round", "death", "resume", "shift"}

ROUTER_SYSTEM = (
    "Ты — диспетчер хода в текстовой D&D. Реши, хватит ли мастеру короткого промпта (только рассказ, без правил игры) "
    "или нужен полный (правила, проверки, эффекты).\n"
    "Полный (full = true), если ответ может потребовать: проверку (убеждение, обман, запугивание, поиск, осмотр зацепки, "
    "ловкость, опасность), любое изменение мира (взять, дать, купить, заплатить, украсть, ранить, лечить, перейти куда-то, "
    "ждать, колдовать, надеть, отношение NPC, обещание или долг), бой, торговлю, просьбу к NPC, новые места или людей, "
    "вопрос о правилах.\n"
    "Короткий (full = false) — только если хватит рассказа: реплика в разговоре без просьбы и давления, расспросы, "
    "приветствие, прощание, оглядеться без поиска, начать разговор с NPC сцены. Сомневаешься — full = true."
)


class RouteOutput(BaseModel):
    full: bool = Field(description="true — нужен полный промпт с правилами; false — хватит короткого.")


class ShortOutput(BaseModel):
    """What the master returns with the short prompt."""

    need_full: bool = Field(default=False, description="true — для ответа нужны проверка, эффект или правила; narration тогда пустой.")
    narration: str = Field(default="", description="Текст для игрока: описание мастера или реплика NPC.")
    options: list[str] = Field(default_factory=list, max_length=3, description="1–3 коротких варианта действий игрока от первого лица.")
    next_mode: Literal["exploration", "social"] | None = Field(default=None, description="social — начать разговор (нужен npc_id); exploration — закончить.")
    npc_id: str | None = Field(default=None, description="NPC сцены для social.")


def by_kind(params: TurnRequestParams) -> str:
    """"short" / "full" when the kind decides it, "" when the router has to."""
    if params.kind in SHORT_KINDS:
        return "short"
    if params.kind == "enter":
        scene = params.snapshot.scene
        return "full" if scene is not None and scene.furnish else "short"  # a new room is furnished with an effect
    if params.kind == "action" and params.mode != "combat" and "[движок уже" not in params.input:
        return ""
    return "full"


def router_prompt(params: TurnRequestParams) -> str:
    npc = scene_npc(params, params.npc_id)
    last = [f"{h.role}: {h.text[:200]}" for h in params.snapshot.history[-2:]]
    return (f"Режим: {params.mode}{f', собеседник: {npc.name}' if npc else ''}\n"
            + ("Перед этим:\n" + "\n".join(last) + "\n" if last else "")
            + f"Игрок: {params.input}")


def build_router_agent(model: Model) -> Agent[None, RouteOutput]:
    return Agent(model, output_type=RouteOutput, instructions=ROUTER_SYSTEM, retries=1, name="router",
                 model_settings=_no_thinking(settings_for(model, {"temperature": 0.0, "max_tokens": 600})))


def build_short_agent(model: Model, system: str) -> Agent[None, ShortOutput]:
    return Agent(model, output_type=ShortOutput, instructions=system, retries=1, name="short_turn",
                 model_settings=_no_thinking(settings_for(model, {"temperature": 0.8, "max_tokens": 2000})))


def _no_thinking(settings: dict) -> dict:
    """A short request needs no reasoning: DeepSeek thought the router's whole budget away (v0.7.21 `--route` goldens)."""
    settings = dict(settings)
    settings["openrouter_reasoning"] = {"enabled": False}
    return settings


def short_system(params: TurnRequestParams) -> str:
    return prompts.short_prompt(params.mode, params.snapshot, scene_npc(params, params.npc_id))


def to_turn_output(out: ShortOutput) -> TurnOutput:
    return TurnOutput(narration=out.narration, options=out.options, next_mode=out.next_mode, npc_id=out.npc_id)


def short_ok(params: TurnRequestParams, out: ShortOutput) -> bool:
    """A short answer the game can use: words, and a conversation only with an NPC of the scene."""
    if out.need_full or not out.narration.strip():
        return False
    return not (out.next_mode == "social" and scene_npc(params, out.npc_id) is None)
