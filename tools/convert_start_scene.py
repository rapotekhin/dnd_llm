"""One-off: the prototype's start locations and NPCs (legacy/game/assets/ru/*.jsonl) → game/data/start/world.json.

Temporary content for v0.4.x so the Godot client can play with the real master before world packs
(ADR-0010, v0.5+). Adds what the prototype lacked: NPC gender/race/personality, trader stock, Russian roles.

    python tools/convert_start_scene.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "legacy" / "game" / "assets" / "ru"
OUT = ROOT / "game" / "data" / "start" / "world.json"

ROLES = {
    "innkeeper": "хозяин таверны", "waiter": "подавальщица", "cook": "повар", "farmer": "завсегдатай",
    "hunter": "охотница", "miner": "шахтёр", "general_merchant": "торговец всякой всячиной",
    "alchemist": "алхимик", "blacksmith": "кузнец",
}
# By prototype NPC name prefix: gender, race, personality, what they sell (catalog item ids).
EXTRA = {
    "Борик": ("male", "дварф", "радушный, любит сплетни, не терпит драк в зале", ["ale", "bread", "rations"]),
    "Лира": ("female", "полурослик", "весёлая и наблюдательная, знает всех гостей", []),
    "Грам": ("male", "полуорк", "ворчливый, но добрый, гордится своей похлёбкой", []),
    "Старик": ("male", "человек", "болтливый, любит приукрасить, иногда говорит правду", []),
    "Рина": ("female", "полуэльфийка", "немногословная, осторожная, что-то ищет", []),
    "Том": ("male", "человек", "задиристый и шумный, быстро обижается", []),
}
MERCHANT_STOCK = {
    "general_merchant": ["torch", "rope", "rations", "waterskin", "bedroll", "tinderbox", "backpack", "lantern", "crowbar"],
    "alchemist": ["healing_potion", "antitoxin", "holy_water"],
    "blacksmith": ["dagger", "shortsword", "longsword", "handaxe", "shield", "leather_armor", "chain_shirt", "arrows"],
}
MERCHANT_EXTRA = {
    "general_merchant": ("male", "человек", "деловитый, торгуется до последнего медяка"),
    "alchemist": ("female", "гномка", "рассеянная, увлечена опытами, честна в ценах"),
    "blacksmith": ("male", "дварф", "суровый, уважает силу и хорошую сталь"),
}
HOOKS = {
    "tavern-room-000": ["одна из бочек стоит чуть в стороне от остальных"],
    "caves-room-003": ["у воды видны свежие следы"],
    "caves-room-006": ["из глубины тянет холодом и чем-то металлическим"],
}


def main() -> None:
    npcs = {}
    for line in (SRC / "start_npcs.jsonl").read_text(encoding="utf-8").splitlines():
        d = json.loads(line)
        role = d["role"]
        first = d["name"].split()[0]
        if role in MERCHANT_EXTRA:
            gender, race, personality = MERCHANT_EXTRA[role]
            stock = MERCHANT_STOCK[role]
        else:
            gender, race, personality, stock = EXTRA.get(first, ("other", "человек", "", []))
        npcs[d["id"]] = {
            "name": d["name"], "role": ROLES.get(role, role), "race": race, "gender": gender,
            "description": d["description"], "personality": personality, "trader": bool(stock), "stock": stock,
        }

    locations, rooms = {}, {}
    for line in (SRC / "start_locations.jsonl").read_text(encoding="utf-8").splitlines():
        loc = json.loads(line)
        locations[loc["id"]] = {"name": loc["name"], "description": loc["description"]}
        for level in loc["levels"]:
            for r in level["rooms"]:
                rooms[r["id"]] = {
                    "name": r["name"], "description": r["description"], "location_id": loc["id"],
                    "exits": r["connections"], "npcs": r["npcs"], "hooks": HOOKS.get(r["id"], []),
                }
    missing = [e for r in rooms.values() for e in r["exits"] if e not in rooms] + \
              [n for r in rooms.values() for n in r["npcs"] if n not in npcs]
    assert not missing, missing
    OUT.parent.mkdir(parents=True, exist_ok=True)
    data = {"start_room": "tavern-room-001", "locations": locations, "rooms": rooms, "npcs": npcs}
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(ROOT)}: {len(locations)} locations, {len(rooms)} rooms, {len(npcs)} npcs")


if __name__ == "__main__":
    main()
