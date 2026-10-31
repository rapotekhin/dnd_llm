"""Moving the people and places the master made into the world pack, by the author's pick (roadmap v0.7.20.2).

    python tools/promote_world.py                                        # what the saves hold: made people and places
    python tools/promote_world.py --promote autosave:gen_npc_1           # into the pack with an id from the name
    python tools/promote_world.py --promote autosave:gen_npc_1=npc_ferryman
    python tools/promote_world.py --promote profiles/agent/slot_1:gen_room_2=pushcha-glade
    python tools/promote_world.py --promote autosave:gen_quest_1=quest_lost_ring

The master makes NPCs and places within the engine's rules (WorldGen); they live in the save of that game only
(`session.generated`), with their final ids, rooms and exits. The author picks which become part of the world: a
promoted NPC goes into the pack's world.json under a permanent id (in its room; its links to people that stay made
are dropped); a promoted place takes the whole of it — every made room connected to the picked one, its made location,
the people who live there, and the exit from the pack room it grew from; the open edge it used leaves that room.
A promoted quest (v0.7.21.3) takes what it stands on: the made people and places of its giver and steps (whole, as
above; one already in the pack — found by its name), its thing (a made item goes into the pack's `items`) and the
hiding place of it; every id in its steps and rewards is rewritten. The player's own deed has no giver and stays.
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
    return str(session.get("world_id", "")), overlaid(session.get("generated") or {})


def overlaid(gen: dict) -> dict:
    """The made people and rooms with what the game changed in them (v0.7.60.1). A site's overlay is the hero's
    ownership of it: that stays in the save."""
    for ref, changed in gen.get("overlay", {}).items():
        kind, _, rid = ref.partition(":")
        table = {"npc": "npcs", "room": "rooms"}.get(kind, "")
        if rid in gen.get(table, {}):
            gen[table][rid].update(changed)
    return gen


def save_items(path: Path) -> dict:
    """The items this game made (their full descriptions live in the save)."""
    return json.loads(path.read_text(encoding="utf-8")).get("session", {}).get("items") or {}


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
        npcs, rooms, quests = gen.get("npcs", {}), gen.get("rooms", {}), gen.get("quests", {})
        if not npcs and not rooms and not quests:
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
        for qid, q in quests.items():
            kind = "своё дело — не переносится" if q.get("own") else "заказ на доске" if q.get("board") else f"от {q.get('giver')}"
            lines.append(f"  {qid}: задание «{q.get('title')}» — {kind}, шагов {len(q.get('steps', []))}")
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


def faction_of(world: dict, gen: dict, fid: str) -> str:
    """A faction of the master comes with whoever belongs to it; a person made before factions — the free folk."""
    made = gen.get("factions", {})
    if fid in made:
        world.setdefault("factions", {}).setdefault(fid, {k: v for k, v in made[fid].items() if k != "generated"})
        return fid
    return fid or "wild_folk"


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
    npc["faction"] = faction_of(world, gen, str(npc.get("faction", "")))
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
    # v0.7.22.24: the place's site comes along; an old save's place without one becomes a site of its own
    world.setdefault("sites", {})
    sid = made[entry].get("site_id", "")
    site = dict(gen.get("sites", {}).get(sid, {})) or {"name": made[entry].get("name", entry)}
    site.pop("inside", None)
    site["location_id"] = ids.get(made[entry].get("location_id", ""), made[entry].get("location_id", ""))
    site["entry"] = ids[entry]
    new_site = _free(world["sites"], ids[entry])
    world["sites"][new_site] = _clean(site)
    for r in rooms:
        room = _clean(made[r])
        room["site_id"] = new_site
        room["location_id"] = ids.get(room["location_id"], room["location_id"])
        room["exits"] = [ids.get(x, x) for x in room.get("exits", [])]
        room["npcs"] = []
        if room.get("encounter"):
            room["encounter"]["id"] = ids[r] + "_enc"
            if room["encounter"].get("faction"):
                room["encounter"]["faction"] = faction_of(world, gen, room["encounter"]["faction"])
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


def _by_name(table: dict, name: str) -> str:
    return next((k for k, v in table.items() if str(v.get("name", "")).lower() == name.lower()), "")


def promote_quest(world: dict, gen: dict, items: dict, qid: str, new_id: str, ids: dict[str, str]) -> list[str]:
    q = gen["quests"][qid]
    if q.get("own"):
        return [f"✗ {qid}: своё дело игрока — без заказчика его в пакете никто не предложит"]
    if any(str(x.get("title", "")).lower() == str(q.get("title", "")).lower() for x in world.get("quests", {}).values()):
        return [f"✗ {qid}: «{q.get('title')}» уже есть в пакете"]
    if q.get("acts") and int(q.get("built", 0)) < len(q["acts"]):  # v0.7.39.6: the next act is built only in its game
        return [f"✗ {qid}: собрано актов {int(q.get('built', 0))} из {len(q['acts'])} — доиграйте задание до последнего акта"]
    lines: list[str] = []
    steps = q.get("steps", [])
    made_rooms, made_npcs = gen.get("rooms", {}), gen.get("npcs", {})
    # what the quest stands on: rooms first (people may live there), then people
    rooms: list[str] = []
    npcs: list[str] = [str(q.get("giver", ""))]
    for st in steps:
        for w in _facts(st.get("when", {})) + _facts(st.get("needs", {})):
            if w.get("room") or w.get("arrive") or w.get("choice"):
                rooms.append(str(w.get("room") or w.get("arrive") or w["choice"]))
            if w.get("encounter"):
                rooms.append(_encounter_room(gen, str(w["encounter"])))
            if w.get("secret"):
                rooms.append(str(w["secret"]).split(":")[0])
            if w.get("talk"):
                npcs.append(str(w["talk"]))
        npcs += list(st.get("attitude", {}))
        for c in st.get("choices", []):
            npcs += list(c.get("attitude", {}))
    for room, variants in gen.get("room_variants", {}).items():  # an ambush in a known room, a place changed by a choice
        if any(_mine(qid, v) for v in variants):
            rooms.append(room)
    if q.get("board"):
        rooms.append(str(q["board"]["room"]))
    rooms += [str(gen.get("npc_rooms", {}).get(n, "")) for n in npcs if n in made_npcs]
    for r in dict.fromkeys(rooms):
        if r not in made_rooms or r in ids:
            continue
        known = _by_name(world["rooms"], str(made_rooms[r].get("name", "")))
        if known:
            ids[r] = known
            continue
        out = promote_place(world, gen, r, "", ids)
        if not out[0].startswith("✓"):
            return [f"✗ {qid}: место задания — {out[0][2:]}"]
        lines += ["  " + x for x in out]
    for n in dict.fromkeys(npcs):
        if n not in made_npcs or n in ids:
            continue
        known = _by_name(world["npcs"], str(made_npcs[n].get("name", "")))
        if known:
            ids[n] = known
            continue
        out = promote_npc(world, gen, n, "", ids)
        if not out.startswith("✓"):
            return [f"✗ {qid}: человек задания — {out[2:]}"]
        lines.append("  " + out)
    new_id = _free(world.setdefault("quests", {}), new_id or "quest_" + slug(str(q.get("title", qid))))
    pack_items = world.setdefault("items", {})
    item_ids: dict[str, str] = {}

    def item(i: str) -> str:  # a made item into the pack's items under a readable id
        if i in item_ids:
            return item_ids[i]
        if i not in items or i in pack_items:
            item_ids[i] = i
            return i
        d = items[i]
        if d.get("properties") or d.get("use"):  # the pack keeps plain things; a wand or a potion is the catalog's
            raise ValueError(f"вещь {i} «{d.get('name')}» с механикой — сначала в каталог (tools/promote_items.py), потом задание")
        nid = _free(pack_items, slug(str(d.get("name", i))))
        pack_items[nid] = {k: v for k, v in {"name": d.get("name", i), "item_type": "quest", "description": d.get("description") or d.get("name", i),
                                              "text": d.get("text", ""), "weight": d.get("weight", 0), "value_cp": int(d.get("value_cp", 0))}.items()
                           if v != ""}
        item_ids[i] = nid
        lines.append(f"  вещь {i} → {nid} «{items[i].get('name')}»")
        return nid

    try:
        return _quest_into(world, gen, q, qid, new_id, ids, item, lines)
    except ValueError as exc:
        return [f"✗ {qid}: {exc}"]


def _facts(w: dict) -> list[dict]:
    """A step's fact and the parts of its all / any."""
    return [w] + [p for k in ("all", "any") for p in w.get(k, [])]


def _encounter_room(gen: dict, enc: str) -> str:
    """The room of an encounter: a made room that holds it, a room whose quest variant holds it, or the old «<room>_enc»."""
    for r, room in gen.get("rooms", {}).items():
        if room.get("encounter", {}).get("id") == enc:
            return r
    for r, variants in gen.get("room_variants", {}).items():
        if any(v.get("encounter", {}).get("id") == enc for v in variants):
            return r
    return enc.removesuffix("_enc")


def _mine(qid: str, v: dict) -> bool:
    """A room variant the quest made (v0.7.39.6): its fight while taken, or a change by its choice's flag."""
    return v.get("if_quest") == qid or str(v.get("if_flag", "")).startswith(qid + "_")


def _renamed(s: str, qid: str, new_id: str) -> str:
    return new_id + s[len(qid):] if s.startswith(qid + "_") else s


def _quest_into(world: dict, gen: dict, q: dict, qid: str, new_id: str, ids: dict[str, str], item, lines: list[str]) -> list[str]:
    quest = _clean(q)
    for k in ("depth", "scale", "own", "fights", "made_steps", "xp_paid", "items"):
        quest.pop(k, None)
    encounters: dict[str, str] = {}  # the quest's encounter ids → the pack's
    for r, room in gen.get("rooms", {}).items():
        enc = room.get("encounter", {}).get("id", "")
        if enc and r in ids:
            encounters[enc] = ids[r] + "_enc"
            world["rooms"][ids[r]].get("encounter", {}).pop("quest", None)
    for room, variants in gen.get("room_variants", {}).items():
        for v in variants:
            if not _mine(qid, v):
                continue
            v = json.loads(json.dumps(v))
            v["vid"] = _renamed(str(v.get("vid", "")), qid, new_id)
            if "if_quest" in v:
                v["if_quest"] = new_id
            if "if_flag" in v:
                v["if_flag"] = _renamed(str(v["if_flag"]), qid, new_id)
            if v.get("encounter"):
                old = str(v["encounter"]["id"])
                v["encounter"]["id"] = encounters[old] = _renamed(old, qid, new_id)
                v["encounter"]["quest"] = new_id
            world["rooms"][ids.get(room, room)].setdefault("variants", []).append(v)
    quest["giver"] = ids.get(quest["giver"], quest["giver"])
    quest["description"] = quest.get("description") or quest["title"]
    if quest.get("board"):
        quest["board"]["room"] = ids.get(quest["board"]["room"], quest["board"]["room"])
    if quest.get("offer_items"):  # the parcel its giver hands over (v0.7.34.5)
        quest["offer_items"] = {item(i): n for i, n in quest["offer_items"].items()}
    for st in quest["steps"]:
        st.pop("act", None)  # the act a step was built in — the save's bookkeeping
        for w in _facts(st["when"]) + _facts(st.get("needs", {})):
            for k in ("talk", "room", "arrive", "choice"):
                if k in w:
                    w[k] = ids.get(w[k], w[k])
            if "encounter" in w:
                room = w["encounter"].removesuffix("_enc")
                w["encounter"] = encounters.get(w["encounter"]) or (ids[room] + "_enc" if room in ids else w["encounter"])
            if "item" in w:
                w["item"] = item(w["item"])
            if "flag" in w:
                w["flag"] = _renamed(str(w["flag"]), qid, new_id)
            if "secret" in w:
                room, _, sid = w["secret"].partition(":")
                if sid == "q_" + qid or sid.startswith(f"q_{qid}_"):  # the hiding place of the quest's thing (by acts: q_<quest>_<key>)
                    found = gen.get("room_secrets", {}).get(room, []) + gen.get("rooms", {}).get(room, {}).get("secrets", [])
                    sec = next((dict(x) for x in found if x.get("id") == sid), None)
                    if sec is None:
                        return [f"✗ {qid}: в сейве нет тайника {w['secret']}"]
                    sec["id"] = "q_" + new_id + sid[len("q_" + qid):]
                    sec["loot"] = {"items": {item(i): n for i, n in sec.get("loot", {}).get("items", {}).items()}}
                    secrets = world["rooms"][ids.get(room, room)].setdefault("secrets", [])
                    secrets[:] = [x for x in secrets if x.get("id") != sid]  # a made room came with it under the old id
                    secrets.append(sec)
                    sid = sec["id"]
                w["secret"] = f"{ids.get(room, room)}:{sid}"
        for c in st.get("choices", []):  # the finale's choice (v0.7.39.6): its flag, the people, its thing
            if c.get("flag"):
                c["flag"] = _renamed(str(c["flag"]), qid, new_id)
            c["attitude"] = {ids.get(k, k): v for k, v in c.get("attitude", {}).items()}
            if not c["attitude"]:
                c.pop("attitude")
            if c.get("items"):
                c["items"] = {item(i): n for i, n in c["items"].items()}
        st["attitude"] = {ids.get(k, k): v for k, v in st.get("attitude", {}).items()}
        if not st["attitude"]:
            st.pop("attitude")
        if st.get("items"):
            st["items"] = {item(i): n for i, n in st["items"].items()}
    world["quests"][new_id] = quest
    return [f"✓ {qid} → {new_id} «{quest['title']}»"] + lines


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
        elif gid in gen.get("quests", {}):
            out = promote_quest(world, gen, save_items(known[save]), gid, new_id, ids)
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
