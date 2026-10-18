"""
Game NPC - wrapper around dnd_5e_core Character
"""

from core.entities.character import Character
from core.entities.base import ID
from typing import Optional, List
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
    """Game NPC with simplified creation."""
    _id_prefix: str = "npc"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        
        if "id" in kwargs:
            self.id = kwargs["id"]  # str or UUID
        self.role = kwargs.get("role", random.choice(POSSIBLE_ROLES))
        self.name: str = kwargs.get("name", "")
        self.description: str = kwargs.get("description", "")
        self.location: Optional[ID] = kwargs.get("location", None)
        self.quests: List[ID] = kwargs.get("quests", [])

if __name__ == "__main__":
    npc = NPC.create_random_character(
        name="Test NPC",
        race="human",
        class_type="fighter",
        level=1,
        alignment="neutral",
        coins=10000,
    )
    print(npc.__dict__)