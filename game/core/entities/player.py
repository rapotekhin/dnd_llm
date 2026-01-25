"""
Game Player - wrapper around dnd_5e_core Character
"""

from core.entities.character import Character

class Player(Character):
    """Game Player with simplified creation"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.role = "player"
