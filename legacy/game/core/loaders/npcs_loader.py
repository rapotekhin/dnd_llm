# Load NPCs from JSONL file stored in assets/ru/start_npcs.jsonl

import random
from typing import Optional
from core.utils.load_functions import load_jsonl_file
from core.entities.npc import NPC
from core.entities.equipment import GameEquipment
from core.database.json_database import JsonDatabase

NPC_ROLE_TO_INVENTORY = {
    "general_merchant": [
        {
            'url': "equipment-categories/standard-gear",
            'num_random_equipments': 30,
        },
        {
            'url': "equipment-categories/adventuring-gear",
            'num_random_equipments': 10,
        },
        {
            'url': "equipment-categories/simple-weapons",
            'num_random_equipments': 5,
        },
    ],
    "alchemist": [
        {
            'url': "magic-items/potion-of-healing",
            'quantity': 10,
        },
        {
            'url': "equipment-categories/potion",
            'num_random_equipments': 10,
        },
        {
            'url': "equipment-categories/scroll",
            'num_random_equipments': 10,
        },
        {
            'url': "equipment-categories/ring",
            'num_random_equipments': 2,
        },
        {
            'url': "equipment-categories/wand",
            'num_random_equipments': 1,
        },
        {
            'url': "equipment-categories/staff",
            'num_random_equipments': 1,
        },
        {
            'url': "equipment-categories/rod",
            'num_random_equipments': 1,
        },
    ],
    "blacksmith": [
        {
            'url': "equipment-categories/ammunition",
            'num_random_equipments': 10,
        },
        {
            'url': "equipment-categories/armor",
            'num_random_equipments': 10,
        },
        {
            'url': "equipment-categories/weapon",
            'num_random_equipments': 10,
        },
    ],
    "miner": [],
    "hunter": [],
    "farmer": [],
    "cook": [],
    "waiter": [],
    "innkeeper": [],
}

def _resolve_item_data(raw_data: dict, db: JsonDatabase) -> Optional[dict]:
    """
    Return the "leaf" item data suitable for equipment creation.

    If *raw_data* is a variant-parent (has non-empty ``variants`` list and
    ``"variant": false``), a random variant is loaded and returned instead.
    Otherwise returns *raw_data* unchanged.
    """
    if not raw_data.get("variant", True) and raw_data.get("variants"):
        variant = random.choice(raw_data["variants"])
        variant_url: str = str(variant.get("url") or "")
        if not variant_url:
            return None
        try:
            return db.get(f"{variant_url}.json")
        except Exception as e:
            print(f"  [inventory] Could not load variant '{variant_url}': {e}")
            return None
    return raw_data


def _create_equipment_from_data(item_data: dict) -> Optional[GameEquipment]:
    """Build a GameEquipment instance from raw D&D 5e JSON data."""
    try:
        from dnd_5e_core.equipment.equipment import Cost, EquipmentCategory

        eq_cat         = item_data.get("equipment_category", {})
        category_index = eq_cat.get("index", "adventuring-gear")
        category_name  = eq_cat.get("name",  "Adventuring Gear")
        category_url   = eq_cat.get("url",   f"/api/2014/equipment-categories/{category_index}")
        category = EquipmentCategory(index=category_index, name=category_name, url=category_url)

        cost_raw = item_data.get("cost", {})
        cost = Cost(
            quantity=cost_raw.get("quantity", 0),
            unit=cost_raw.get("unit", "gp"),
        )

        weight = item_data.get("weight", 0)

        armor_class_base = None
        damage_dice_str  = None
        if category_index == "armor":
            ac = item_data.get("armor_class", {})
            armor_class_base = ac.get("base", 10) if isinstance(ac, dict) else (ac if isinstance(ac, int) else None)
        elif category_index == "weapon":
            dmg = item_data.get("damage", {})
            if isinstance(dmg, dict):
                damage_dice_str = dmg.get("damage_dice")

        desc = item_data.get("desc", [])
        if isinstance(desc, str):
            desc = [desc]

        return GameEquipment(
            index=item_data.get("index", ""),
            name=item_data.get("name", ""),
            cost=cost,
            weight=weight,
            desc=desc if desc else None,
            category=category,
            equipped=False,
            equipped_left_hand=False,
            equipped_right_hand=False,
            equipped_slot=None,
            armor_class_base=armor_class_base,
            damage_dice_str=damage_dice_str,
        )
    except Exception as e:
        print(f"  [inventory] Could not build item '{item_data.get('index', '?')}': {e}")
        return None


def fill_npc_inventory(npc: NPC) -> None:
    """
    Populate *npc.inventory* according to NPC_ROLE_TO_INVENTORY rules.

    Rule formats:
      {'url': "equipment-categories/X", 'num_random_equipments': N}
          → pick N random items from the category (without replacement when N ≤ pool size,
            with replacement for the excess when N > pool size).

      {'url': "equipment/X"  | "magic-items/X", 'quantity': N}
          → add N identical copies of the specific item.
    """
    role  = getattr(npc, "role", None)
    if not role or not isinstance(role, str):
        return
    rules = NPC_ROLE_TO_INVENTORY.get(role)
    if not rules:
        return

    db = JsonDatabase()
    if npc.inventory is None:
        npc.inventory = []

    for rule in rules:
        url: str = rule.get("url", "")
        if not url:
            continue
        try:
            # ── Case 1: pick random items from a category ──────────────
            if "num_random_equipments" in rule:
                n = rule["num_random_equipments"]
                category_data = db.get(f"/{url}.json")
                pool: list = category_data.get("equipment", [])
                if not pool:
                    continue

                # sample without replacement up to pool size, then top up with replacement
                k       = min(n, len(pool))
                chosen  = random.sample(pool, k=k)
                if n > len(pool):
                    chosen += random.choices(pool, k=n - len(pool))

                for ref in chosen:
                    # Use the url field from the category entry — items can live in
                    # magic-items/, equipment/, weapons/, etc., not just equipment/.
                    item_url: str = str(ref.get("url") or "")
                    if not item_url:
                        continue
                    try:
                        raw = db.get(f"{item_url}.json")
                        resolved = _resolve_item_data(raw, db)
                        if resolved is None:
                            continue
                        eq = _create_equipment_from_data(resolved)
                        if eq:
                            npc.inventory.append(eq)
                    except Exception as e:
                        item_label = ref.get("index") or item_url
                        print(f"  [inventory] Skipping '{item_label}': {e}")

            # ── Case 2: fixed quantity of a specific item ──────────────
            elif "quantity" in rule:
                n = rule["quantity"]
                raw = db.get(f"/{url}.json")
                resolved = _resolve_item_data(raw, db)
                if resolved is None:
                    continue
                for _ in range(n):
                    eq = _create_equipment_from_data(resolved)
                    if eq:
                        npc.inventory.append(eq)

        except Exception as e:
            print(f"  [inventory] Rule {rule} failed: {e}")


def load_npcs_from_jsonl(file_path: str):
    """Load NPCs from JSONL file and add them to game_state.npcs"""
    from core.data import game_state

    if game_state.npcs is None:
        assert False, "game_state.npcs is not initialized"

    npcs = load_jsonl_file(file_path)
    for npc_data in npcs:
        npc = NPC.create_random_character(
            name=npc_data.get("name"),
            race=npc_data.get("race"),
            class_type=npc_data.get("class_type"),
            level=npc_data.get("level", 1),
        )
        if npc_data.get("id") is not None:
            npc.id = npc_data["id"]
        if npc_data.get("role") is not None:
            npc.role = npc_data["role"]
        fill_npc_inventory(npc)
        game_state.npcs[npc.id] = npc
