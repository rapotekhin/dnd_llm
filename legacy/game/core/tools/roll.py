"""
D&D 5e dice rolling tool for Pydantic AI agents.

Only plain dice notation is accepted ("1d20+3", "2d6+1d4-1") with hard limits:
the expression comes from the LLM, which may relay arbitrary player text.
"""

import random
import re
from typing import Optional

from core.logging_config import get_logger

log = get_logger(__name__)

MAX_EXPRESSION_LEN = 40
MAX_DICE = 20
ALLOWED_FACES = {4, 6, 8, 10, 12, 20, 100}
MAX_MODIFIER = 30

_TERM_RE = re.compile(r"([+-]?)(\d*)d(\d+)|([+-]?)(\d+)")


class DiceExpressionError(ValueError):
    """Expression is not plain dice notation or exceeds the limits."""


def parse_expression(expression: str) -> tuple[list[tuple[int, int, int]], int]:
    """Parse "1d20+3" into ([(sign, count, faces), ...], modifier)."""
    expr = (expression or "").replace(" ", "").lower()
    if not expr or len(expr) > MAX_EXPRESSION_LEN:
        raise DiceExpressionError(f"expression must be 1..{MAX_EXPRESSION_LEN} chars")

    dice_terms: list[tuple[int, int, int]] = []
    modifier = 0
    pos = 0
    while pos < len(expr):
        m = _TERM_RE.match(expr, pos)
        if not m or m.end() == pos or (pos > 0 and expr[pos] not in "+-"):
            raise DiceExpressionError(f"not dice notation: {expression!r}; use e.g. '1d20+3'")
        if m.group(3) is not None:
            sign = -1 if m.group(1) == "-" else 1
            count = int(m.group(2) or 1)
            faces = int(m.group(3))
            if faces not in ALLOWED_FACES:
                raise DiceExpressionError(f"d{faces} is not a D&D die")
            dice_terms.append((sign, count, faces))
        else:
            sign = -1 if m.group(4) == "-" else 1
            modifier += sign * int(m.group(5))
        pos = m.end()

    total_dice = sum(count for _, count, _ in dice_terms)
    if total_dice == 0 or total_dice > MAX_DICE:
        raise DiceExpressionError(f"expression must roll 1..{MAX_DICE} dice")
    if abs(modifier) > MAX_MODIFIER:
        raise DiceExpressionError(f"modifier must be within ±{MAX_MODIFIER}")
    return dice_terms, modifier


class RollDiceTool:
    """
    Roll dice using D&D 5e advantage/disadvantage rules and optionally compare
    against a Difficulty Class. ``rng`` can be injected for deterministic tests.
    """

    def __init__(self, rng: Optional[random.Random] = None) -> None:
        self._rng = rng or random.Random()

    def run(
        self,
        expression: str,
        has_advantage: bool = False,
        has_disadvantage: bool = False,
        difficulty_class: int | None = None,
    ) -> dict:
        """
        Returns ``{"roll_result", "roll_success", "natural", "rolls"}`` or, for an
        invalid expression, ``{"error": ...}`` so the model can correct itself.
        ``natural`` is the kept d20 when the expression has exactly one d20.
        """
        try:
            dice_terms, modifier = parse_expression(expression)
        except DiceExpressionError as e:
            log.warning("roll_dice rejected %r: %s", expression, e)
            return {"error": str(e)}

        single_d20 = [t for t in dice_terms if t[2] == 20] == [(1, 1, 20)]
        # Advantage and disadvantage cancel out; they only apply to a single d20.
        use_adv = single_d20 and has_advantage and not has_disadvantage
        use_dis = single_d20 and has_disadvantage and not has_advantage

        rolls: list[int] = []
        total = modifier
        natural: Optional[int] = None
        for sign, count, faces in dice_terms:
            if faces == 20 and single_d20:
                pair = [self._rng.randint(1, 20) for _ in range(2 if (use_adv or use_dis) else 1)]
                kept = max(pair) if use_adv else min(pair) if use_dis else pair[0]
                rolls.extend(pair)
                natural = kept
                total += sign * kept
                continue
            for _ in range(count):
                r = self._rng.randint(1, faces)
                rolls.append(r)
                total += sign * r

        roll_success: Optional[bool] = None
        if difficulty_class is not None:
            roll_success = total >= int(difficulty_class)
            # House rule (ADR-0008): natural 20 / 1 on a d20 check always succeeds / fails.
            if natural == 20:
                roll_success = True
            elif natural == 1:
                roll_success = False

        log.info("roll_dice %s adv=%s dis=%s dc=%s -> %s (rolls=%s, natural=%s, success=%s)",
                 expression, use_adv, use_dis, difficulty_class, total, rolls, natural, roll_success)
        return {"roll_result": total, "roll_success": roll_success, "natural": natural, "rolls": rolls}

    def __call__(
        self,
        expression: str,
        has_advantage: bool = False,
        has_disadvantage: bool = False,
        difficulty_class: int | None = None,
    ) -> dict:
        return self.run(
            expression=expression,
            has_advantage=has_advantage,
            has_disadvantage=has_disadvantage,
            difficulty_class=difficulty_class,
        )


# Singleton for reuse
_roll_dice_tool = RollDiceTool()


def roll_dice(
    expression: str,
    has_advantage: bool = False,
    has_disadvantage: bool = False,
    difficulty_class: int | None = None,
) -> dict:
    """Standalone function for direct calls and agent tools."""
    return _roll_dice_tool.run(
        expression=expression,
        has_advantage=has_advantage or False,
        has_disadvantage=has_disadvantage or False,
        difficulty_class=difficulty_class,
    )
