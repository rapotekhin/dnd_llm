"""Pure helpers for tests (avoid importing ``conftest`` as a module)."""

from __future__ import annotations


def make_game_equipment(*, index: str, name: str, gp: int):
    """Minimal ``GameEquipment`` with ``price`` derived from cost (copper)."""
    from dnd_5e_core.equipment.equipment import Cost, EquipmentCategory
    from core.entities.equipment import GameEquipment

    cat = EquipmentCategory(
        index="weapon",
        name="Weapon",
        url="/api/2014/equipment-categories/weapon",
    )
    cost = Cost(quantity=gp, unit="gp")
    return GameEquipment(
        index=index,
        name=name,
        cost=cost,
        weight=0,
        desc=[],
        category=cat,
        equipped=False,
    )
