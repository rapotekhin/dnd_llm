import dice
from core.gameplay.schemas.exploration import RollOptions
from langchain_core.tools import tool

@tool(args_schema=RollOptions)
def roll_dice(
    expression: str, 
    has_advantage: bool | None = None, 
    has_disadvantage: bool | None = None, 
    difficulty_class: int | None = None
) -> dict[str, int | bool | None]:
    """
    Roll dice using D&D 5e advantage/disadvantage rules and optionally
    evaluate the result against a Difficulty Class (DC).

    The function performs a roll based on the provided dice expression.
    If advantage or disadvantage is set, the expression is rolled twice:
    """

    # отменяют друг друга
    if has_advantage and has_disadvantage:
        result = int(dice.roll(expression))

    elif has_advantage:
        r1 = int(dice.roll(expression))
        r2 = int(dice.roll(expression))
        result = max(r1, r2)
        print(f"Advantage rolls: {r1}, {r2} → {result}")

    elif has_disadvantage:
        r1 = int(dice.roll(expression))
        r2 = int(dice.roll(expression))
        result = min(r1, r2)
        print(f"Disadvantage rolls: {r1}, {r2} → {result}")

    else:
        result = int(dice.roll(expression))

    if difficulty_class:
        roll_success = int(result) >= int(difficulty_class)
    else:
        roll_success = None

    print(f"Final roll: {result}, success: {roll_success}")
    return {"roll_result": result, "roll_success": roll_success}

if __name__ == "__main__":
    # run: 
    # venv\Scripts\activate
    # cd game
    # python -m core.tools.roll

    roll_dice.invoke({"expression": "1d20", "has_advantage": True, "difficulty_class": 15})
    roll_dice.invoke({"expression": "(2d4)*2+1"})