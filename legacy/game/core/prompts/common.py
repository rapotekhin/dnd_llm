"""
Prompt fragments shared by exploration and social modes.
"""


def player_gender_line(player) -> str:
    """How the DM should address the player in Russian (verb/adjective agreement)."""
    gender = str(getattr(player, "gender", "") or "").lower()
    if gender in ("female", "f", "женский"):
        return "женский — обращайся к игроку в женском роде («ты вошла», «готова»)"
    if gender in ("male", "m", "мужской"):
        return "мужской — обращайся к игроку в мужском роде («ты вошёл», «готов»)"
    return "не указан — избегай родовых форм при обращении к игроку"
