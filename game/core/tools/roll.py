"""
D&D 5e dice rolling tool. OOP pattern for reuse in Pydantic AI agents.
"""

import dice


def _to_int(r) -> int:
    """Coerce dice.roll result to int (handles tuple/list from some dice libs)."""
    if isinstance(r, (list, tuple)):
        return int(r[0]) if r else 0
    return int(r)


class RollDiceTool:
    """
    Roll dice using D&D 5e advantage/disadvantage rules.
    Can be used via .run() or as callable. Reusable by exploration agents.
    """

    def run(
        self,
        expression: str,
        has_advantage: bool = False,
        has_disadvantage: bool = False,
        difficulty_class: int | None = None,
    ) -> dict[str, int | bool | None]:
        """
        Roll dice using D&D 5e advantage/disadvantage rules and optionally
        evaluate the result against a Difficulty Class (DC).
        """
        if has_advantage and has_disadvantage:
            result = _to_int(dice.roll(expression))
        elif has_advantage:
            r1 = _to_int(dice.roll(expression))
            r2 = _to_int(dice.roll(expression))
            result = max(r1, r2)
            print(f"Advantage rolls: {r1}, {r2} → {result}")
        elif has_disadvantage:
            r1 = _to_int(dice.roll(expression))
            r2 = _to_int(dice.roll(expression))
            result = min(r1, r2)
            print(f"Disadvantage rolls: {r1}, {r2} → {result}")
        else:
            result = _to_int(dice.roll(expression))

        roll_success = int(result) >= int(difficulty_class) if difficulty_class else None
        print(f"Final roll: {result}, success: {roll_success}")
        return {"roll_result": result, "roll_success": roll_success}

    def __call__(
        self,
        expression: str,
        has_advantage: bool = False,
        has_disadvantage: bool = False,
        difficulty_class: int | None = None,
    ) -> dict[str, int | bool | None]:
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
) -> dict[str, int | bool | None]:
    """Standalone function for direct calls and agent tools."""
    return _roll_dice_tool.run(
        expression=expression,
        has_advantage=has_advantage or False,
        has_disadvantage=has_disadvantage or False,
        difficulty_class=difficulty_class,
    )


if __name__ == "__main__":
    _roll_dice_tool.run("1d20", has_advantage=True, difficulty_class=15)
    _roll_dice_tool.run("(2d4)*2+1")
