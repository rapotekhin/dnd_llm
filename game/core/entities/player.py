"""
Game Player - wrapper around dnd_5e_core Character
"""

from core.entities.character import Character


def _opt(s, default: str = "—") -> str:
    """Return string or default if empty/None."""
    return str(s).strip() if s else default


class Player(Character):
    """Game Player with simplified creation"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.role = "player"

    def __repr__(self) -> str:
        race_display = self.subrace.name if self.subrace else self.race.name
        lines = [
            f"{_opt(self.name)} — {_opt(self.role, 'player')}",
            f"Уровень {self.level} | XP: {self.xp}",
            f"{race_display} {self.class_type.name}",
            f"Пол: {_opt(self.gender)} | Возраст: {_opt(self.age)} | Рост: {_opt(self.height)} | Вес: {_opt(self.weight)}",
            f"Происхождение: {_opt(self.ethnic)}",
            f"Предыстория: {_opt(self.background)}",
            f"Класс брони (AC): {self.armor_class} | Здоровье: {self.hit_points}/{self.max_hit_points}",
            f"Скорость: {self.speed} фт.",
        ]
        return "\n".join(lines)
