"""
Game NPC - wrapper around dnd_5e_core Character
"""

from core.entities.character import Character
import random

POSSIBLE_ROLES = [
    "merchant", 
    "guard", 
    "alchemist",
    "priest",
    "doctor",
    "farmer",
    "fisher",
    "hunter",
    "miner",
    "blacksmith",
    "tailor",
    "woodworker",
    "innkeeper",
    "waiter",
    "cook",
    "baker",
    "butcher",
    "jeweler",
    "banker",
    "weapon_merchant",
    "armor_merchant",
    "general_merchant",
    "supply_merchant",
    "food_merchant",
    "magic_items_merchant",
]

class NPC(Character):
    """Game NPC with simplified creation"""
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.role = random.choice(POSSIBLE_ROLES)
