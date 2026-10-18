"""
Game equipment - extends dnd_5e_core Equipment with slot tracking.
equipped = True when equipped in hand or body. equipped_slot = body slot key if any.
"""

from dataclasses import dataclass
from dnd_5e_core.equipment.equipment import Equipment, Cost, EquipmentCategory
from typing import Optional, List
from core.entities.base import BaseEntity


@dataclass
class GameEquipment(BaseEntity, Equipment):
    """Extended Equipment with equipped_left_hand, equipped_right_hand, equipped_slot.
    equipped is True when equipped in any slot. equipped_slot = head|body|hands|feet|... for body.
    armor_class_base used for AC when category is armor."""

    equipped_left_hand: bool = False
    equipped_right_hand: bool = False
    equipped_slot: Optional[str] = None  # head, body, hands, feet, cloak, amulet, ring_1, ring_2
    armor_class_base: Optional[int] = None  # from armor JSON; used for AC display
    damage_dice_str: Optional[str] = None  # from weapon JSON; e.g. "1d4", "1d6+1"

    def __hash__(self):
        return hash((self.index, id(self)))

    def __repr__(self):
        return f"{self.index} ({self.category.index})"
