"""Moving the people and places the master made into the world pack, by the author's pick (roadmap v0.7.20.2).

    python tools/promote_world.py                                        # what the saves hold: made people and places
    python tools/promote_world.py --promote autosave:gen_npc_1           # into the pack with an id from the name
    python tools/promote_world.py --promote autosave:gen_npc_1=npc_ferryman
    python tools/promote_world.py --promote profiles/agent/slot_1:gen_room_2=pushcha-glade

The master makes NPCs and places within the engine's rules (WorldGen); they live in the save of that game only
(`session.generated`), with their final ids, rooms and exits. The author picks which become part of the world: a
promoted NPC goes into the pack's world.json under a permanent id (in its room; its links to people that stay made
are dropped); a promoted place takes the whole of it — every made room connected to the picked one, its made location,
the people who live there, and the exit from the pack room it grew from; the open edge it used leaves that room.
The pack is checked by tools/validate_data.py after the change and left as it was on errors. Saves are not touched:
an old game keeps its own copy (two of a kind there, the pack's and its own), a new game gets the pack's.
"""

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLDS = ROOT / "game" / "data" / "worlds"
USER_DIR = Path.home() / "AppData" / "Roaming" / "Godot" / "app_userdata" / "Between the Rolls"

TRANSLIT = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f",
                     "kh", "ts", "ch", "sh", "shch", "", "y", "", "e", "yu", "ya"]))

_spec = importlib.util.spec_from_file_location("validate_data", ROOT / "tools" / "validate_data.py")
validate_data = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_data)


def slug(name: str, sep: str = "_") -> str:
    s = "".join(TRANSLIT.get(ch, ch) for ch in name.lower())
    return re.sub(r"[^a-z0-9]+", sep, s).strip(sep)[:40] or "place"


def saves(user_dir: Path = USER_DIR) -> dict[str, Path]:
    """Saves by a short name: `autosave`, `profiles/agent/slot_1`."""
    out = {p.stem: p for p in sorted((user_dir / "saves").glob("*.json"))}
    for p in sorted((user_dir / "profiles").glob("*/saves/*.json")):
        out[f"profiles/{p.parent.parent.name}/{p.stem}"] = p
    return out


def load_save(path: Path) -> tuple[str, dict]:
    session = json.loads(path.read_text(encoding="utf-8")).get("session", {})
    return str(session.get("world_id", "")), session.get("generated") or {}


def place_of(gen: dict, room_id: str) -> list[str]:
    """The made rooms connected to this one (the whole place), entry first."""
    rooms = gen.get("rooms", {})
    seen, frontier = [room_id], [room_id]
    while frontier:
        rid = frontier.pop()
        near = [x for x in rooms[rid].get("exits", []) if x in rooms]
        near += [o for o, r in rooms.items() if rid in r.get("exits", [])]
        for x in near:
            if x not in seen:
                seen.append(x)
                frontier.append(x)
    entries = [r for rs in gen.get("edge_exits", {}).values() for r in rs]
    return sorted(seen, key=lambda r: (r not in entries, seen.index(r)))


def report(user_dir: Path = USER_DIR) -> list[str]:
    lines = []
    for name, path in saves(user_dir).items():
        world_id, gen = load_save(path)
        npcs, rooms = gen.get("npcs", {}), gen.get("rooms", {})
        if not npcs and not rooms:
            continue
        lines.append(f"{name} ({world_id})")
        for nid, d in npcs.items():
            lines.append(f"  {nid}: {d.get('name')} — {d.get('role')} (в {gen.get('npc_rooms', {}).get(nid, '?')})")
        done: set[str] = set()
        for rid in rooms:
            if rid in done:
                continue
            place = place_of(gen, rid)
            done.update(place)
            loc = rooms[place[0]].get("location_id", "")
            loc_name = gen.get("locations", {}).get(loc, {}).get("name")
            names = ", ".join(f"{r} «{rooms[r].get('name')}»" for r in place)
            lines.append(f"  место: {names}" + (f" — новая локация «{loc_name}»" if loc_name else ""))
    return lines or ["в сейвах нет созданного мастером"]


def _clean(d: dict) -> dict:
    d = json.loads(json.dumps(d))
    d.pop("generated", None)
    return d


def _free(taken: dict, want: str) -> str:
    out, n = want, 2
    while out in taken:
        out, n = f"{want}{n}", n + 1
    return out


def promote_npc(world: dict, gen: dict, nid: str, new_id: str, ids: dict[str, str]) -> str:
    d = gen["npcs"][nid]
    room = ids.get(gen.get("npc_rooms", {}).get(nid, ""), gen.get("npc_rooms", {}).get(nid, ""))
    if room not in world["rooms"]:
        return f"✗ {nid}: живёт в месте, созданном мастером ({room}) — перенесите место, люди уйдут с ним"
    if any(n.get("name") == d.get("name") for n in world["npcs"].values()):
        return f"✗ {nid}: «{d.get('name')}» уже есть в пакете"
    new_id = _free(world["npcs"], new_id or "npc_" + slug(d.get("name", nid)))
    ids[nid] = new_id
    npc = _clean(d)
    npc["links"] = [dict(l, npc_id=ids.get(l["npc_id"], l["npc_id"])) for l in npc.get("links", [])
                    if ids.get(l["npc_id"], l["npc_id"]) in world["npcs"]]
    if not npc["links"]:
        npc.pop("links")
    world["npcs"][new_id] = npc
    world["rooms"][room].setdefault("npcs", []).append(new_id)
    return f"✓ {nid} → {new_id} «{npc.get('name')}»"


def promote_place(world: dict, gen: dict, rid: str, new_id: str, ids: dict[str, str]) -> list[str]:
    rooms = place_of(gen, rid)
    made = gen["rooms"]
    pack_names = {str(r.get("name", "")).lower() for r in world["rooms"].values()}
    if any(str(made[r].get("name", "")).lower() in pack_names for r in rooms):
        return [f"✗ {rid}: место уже в пакете"]
    entry = rooms[0]
    origin = next((f for f, to in gen.get("edge_exits", {}).items() if entry in to), "")
    if origin not in world["rooms"]:
        return [f"✗ {rid}: выросло из комнаты {origin or '?'}, которой нет в пакете"]
    base = new_id or slug(made[entry].get("name", entry), "-")
    for i, r in enumerate(rooms):
        ids[r] = _free(world["rooms"], base if i == 0 else f"{base}-{i + 1}")
        world["rooms"][ids[r]] = {}  # reserve
    loc = made[entry].get("location_id", "")
    if loc in gen.get("locations", {}):
        ids[loc] = _free(world["locations"], slug(gen["locations"][loc].get("name", loc), "-"))
        world["locations"][ids[loc]] = _clean(gen["locations"][loc])
    for r in rooms:
        room = _clean(made[r])
        room["location_id"] = ids.get(room["location_id"], room["location_id"])
        room["exits"] = [ids.get(x, x) for x in room.get("exits", [])]
        room["npcs"] = []
        if room.get("encounter"):
            room["encounter"]["id"] = ids[r] + "_enc"
        world["rooms"][ids[r]] = room
    world["rooms"][origin].setdefault("exits", []).append(ids[entry])
    edges = world["rooms"][origin].get("open_edges", [])
    for used in gen.get("edges_used", []):
        room_id, _, idx = used.rpartition(":")
        if room_id == origin and idx.isdigit() and int(idx) < len(edges) and made_from(gen, origin, used, entry):
            edges.pop(int(idx))
            break
    if "open_edges" in world["rooms"][origin] and not edges:
        world["rooms"][origin].pop("open_edges")
    lines = [f"✓ место {', '.join(f'{r} → {ids[r]}' for r in rooms)}" + (f"; локация {loc} → {ids[loc]}" if loc in ids else "")]
    for nid, room in gen.get("npc_rooms", {}).items():
        if room in rooms and nid in gen.get("npcs", {}) and nid not in ids:
            lines.append("  " + promote_npc(world, gen, nid, "", ids))
    return lines


def made_from(gen: dict, origin: str, used: str, entry: str) -> bool:
    """The edge `used` of `origin` is the one this entry grew from: edges are used in the order the exits were made."""
    mine = [u for u in gen.get("edges_used", []) if u.rpartition(":")[0] == origin]
    exits = gen.get("edge_exits", {}).get(origin, [])
    return entry in exits and mine.index(used) == exits.index(entry)


def promote(picks: list[str], user_dir: Path = USER_DIR, worlds: Path = WORLDS) -> list[str]:
    known = saves(user_dir)
    ids_known = validate_data.known()
    lines: list[str] = []
    for pick in picks:
        ref, _, new_id = pick.partition("=")
        save, _, gid = ref.rpartition(":")
        if save not in known:
            lines.append(f"✗ {pick}: нет сейва {save or '?'} (есть: {', '.join(known)})")
            continue
        world_id, gen = load_save(known[save])
        pack_dir = worlds / world_id
        pack = json.loads((pack_dir / "pack.json").read_text(encoding="utf-8"))
        path = pack_dir / pack.get("world", "world.json")
        raw = path.read_bytes()
        world = json.loads(raw.decode("utf-8"))
        ids: dict[str, str] = {}
        if gid in gen.get("npcs", {}):
            out = [promote_npc(world, gen, gid, new_id, ids)]
        elif gid in gen.get("rooms", {}):
            out = promote_place(world, gen, gid, new_id, ids)
        else:
            out = [f"✗ {pick}: в сейве нет {gid}"]
        lines += out
        if not out[0].startswith("✓"):
            continue
        text = json.dumps(world, ensure_ascii=False, indent="\t") + "\n"
        path.write_bytes(text.replace("\n", "\r\n").encode("utf-8") if b"\r\n" in raw else text.encode("utf-8"))
        errors = validate_data.validate_pack(pack_dir, ids_known)
        if errors:
            path.write_bytes(raw)
            lines.append(f"✗ {pick}: пакет не прошёл проверку, оставлен как был")
            lines += [f"     {e}" for e in errors]
    return lines


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--promote", nargs="+", metavar="SAVE:ID[=NEW_ID]", help="move made people and places into the pack")
    ap.add_argument("--user-dir", type=Path, default=USER_DIR, help="the game's user folder (saves, profiles)")
    args = ap.parse_args()
    lines = promote(args.promote, args.user_dir) if args.promote else report(args.user_dir)
    print("\n".join(lines))
    return 1 if any(line.startswith("✗") for line in lines) else 0


if __name__ == "__main__":
    sys.exit(main())
