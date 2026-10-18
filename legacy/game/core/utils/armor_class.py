"""
Armor class and unarmed damage by D&D 5e rules (PHB ch. 5).

AC: worn body armor gives its base plus DEX (capped for medium armor, none for
heavy); without armor it is 10 + DEX. A shield adds its bonus. ``ac_bonus`` on
the character (magic, features) is added on top.
"""

from typing import Iterable, Optional

from core.entities.equipment import GameEquipment

SHIELD_INDEX = "shield"


def _dex_mod(character) -> int:
    try:
        return character.abilities.get_modifier("dex")
    except Exception:
        return 0


def _str_mod(character) -> int:
    try:
        return character.abilities.get_modifier("str")
    except Exception:
        return 0


def _equipped(character) -> Iterable[GameEquipment]:
    for it in getattr(character, "inventory", None) or []:
        if isinstance(it, GameEquipment) and it.equipped:
            yield it


def is_shield(item: GameEquipment) -> bool:
    return item.index == SHIELD_INDEX


def is_body_armor(item: GameEquipment) -> bool:
    cat = item.category.index if item.category else ""
    return cat == "armor" and not is_shield(item) and item.armor_class_base is not None


def armor_ac(item: GameEquipment, dex_mod: int) -> int:
    """AC granted by a piece of body armor for a given DEX modifier."""
    ac = item.armor_class_base or 10
    # Old pickled items lack the DEX fields; treat them as heavy armor (no DEX).
    if getattr(item, "armor_dex_bonus", False):
        max_dex: Optional[int] = getattr(item, "armor_max_dex", None)
        ac += dex_mod if max_dex is None else min(dex_mod, max_dex)
    return ac


def compute_armor_class(character) -> int:
    dex = _dex_mod(character)
    equipped = list(_equipped(character))
    body = [it for it in equipped if is_body_armor(it)]
    ac = max(armor_ac(it, dex) for it in body) if body else 10 + dex
    ac += sum((it.armor_class_base or 2) for it in equipped if is_shield(it))
    return ac + (getattr(character, "ac_bonus", 0) or 0)


def unarmed_damage(character) -> int:
    """Unarmed strike: 1 + STR modifier bludgeoning damage (at least 1)."""
    return max(1, 1 + _str_mod(character))
