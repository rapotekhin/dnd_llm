"""Validates the world packs in game/data/worlds/ (and any folder given) for CI, where Godot does not run.

The same rules as WorldPack.validate in game/core/world/world_pack.gd: the shape by game/data/worlds/pack.schema.json,
then references — rule filters and renames name known SRD ids, rooms, exits, NPCs and trader stock exist, ready-made
characters use races, classes and backgrounds the pack allows. Whether a ready-made character passes every creation
step is checked by gdUnit (CharacterBuilder), not here.

    uv run --project llm_server python tools/validate_data.py            # the repo packs
    uv run --project llm_server python tools/validate_data.py <pack dir>  # a mod
"""

import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game" / "data"
WORLDS = DATA / "worlds"
SCHEMA = json.loads((WORLDS / "pack.schema.json").read_text(encoding="utf-8"))


def check_when(w: dict, where: str, rooms: dict, npcs: dict, items: set, top: bool) -> list[str]:
    """A quest or exit condition: one fact (encounter, secret, room, flag), a button (talk with an item, choice —
    only on a quest step), or all / any of facts."""
    errors: list[str] = []
    keys = set(w) - {"item"}
    if len(keys) != 1:
        return [f"{where}: в when ровно одно условие (item — только к talk)"]
    if ("talk" in w or "choice" in w) and not top:
        errors.append(f"{where}: talk и choice — только целым шагом задания")
    if "encounter" in w and w["encounter"] not in {r.get("encounter", {}).get("id") for r in rooms.values()}:
        errors.append(f"{where}: нет встречи {w['encounter']}")
    if "secret" in w:
        rid, sec = w["secret"].split(":")
        if sec not in [x["id"] for x in rooms.get(rid, {}).get("secrets", [])]:
            errors.append(f"{where}: нет секрета {w['secret']}")
    if "room" in w and w["room"] not in rooms:
        errors.append(f"{where}: нет комнаты {w['room']}")
    if "choice" in w and w["choice"] not in rooms:
        errors.append(f"{where}: нет комнаты выбора {w['choice']}")
    if "talk" in w and w["talk"] not in npcs:
        errors.append(f"{where}: нет NPC {w['talk']}")
    if "item" in w and ("talk" not in w or w["item"] not in items):
        errors.append(f"{where}: item — предмет каталога и только вместе с talk")
    for sub_w in w.get("all", []) + w.get("any", []):
        errors += check_when(sub_w, where, rooms, npcs, items, top=False)
    return errors


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def known() -> dict[str, set[str]]:
    races = load(DATA / "srd" / "races.json")
    classes = load(DATA / "srd" / "classes.json")
    return {
        "races": set(races["races"]), "subraces": set(races["subraces"]), "classes": set(classes["classes"]),
        "subclasses": set(classes["subclasses"]), "backgrounds": set(load(DATA / "srd" / "backgrounds.json")),
        "items": set(load(DATA / "items.json")["catalog"]),
        "monsters": set(load(DATA / "srd" / "monsters.json")),
        "languages": set(load(DATA / "srd" / "misc.json")["languages"]) | set(load(DATA / "rules.json")["languages"]["secret"]),
    }


ROOM_TAGS = {"temple", "stage"}  # v0.7.11: an acolyte's free rest, a show (rules.json backgrounds)
SERVICE_OPS = {"identify", "lift_curse", "enchant"}  # v0.7.16: the engine's operations a service runs (rules.json items.services)
NPC_TAGS = {"clergy", "underworld", "commoner", "military"}  # the people of the hero's past (rules.json backgrounds ties)


def validate_pack(pack_dir: Path, ids: dict[str, set[str]]) -> list[str]:
    errors: list[str] = []
    try:
        pack = load(pack_dir / "pack.json")
        world = load(pack_dir / pack.get("world", "world.json"))
        chars = load(pack_dir / pack.get("characters", "characters.json"))
    except (OSError, ValueError) as exc:
        return [f"не читается: {exc}"]
    for name, doc in (("pack", pack), ("world", world), ("characters", chars)):
        validator = jsonschema.Draft202012Validator({**SCHEMA, "$ref": f"#/$defs/{name}"})
        for e in sorted(validator.iter_errors(doc), key=lambda e: list(e.path)):
            errors.append(f"{name}.{'.'.join(str(p) for p in e.path)}: {e.message}")
    if errors:
        return errors

    rules = pack.get("rules", {})
    for kind in ("races", "classes", "backgrounds"):
        errors += [f"pack.rules.{kind}: неизвестный id {x}" for x in rules.get(kind, []) if x not in ids[kind]]
    errors += [f"pack.rules.items_exclude: неизвестный предмет {x}" for x in rules.get("items_exclude", []) if x not in ids["items"]]
    for kind, entries in rules.get("rename", {}).items():
        errors += [f"pack.rules.rename.{kind}: неизвестный id {x}" for x in entries if x not in ids[kind]]
    allowed = {k: set(rules.get(k) or ids[k]) for k in ("races", "classes", "backgrounds")}
    items = (ids["items"] - set(rules.get("items_exclude", []))) | set(world.get("items", {}))

    rooms, npcs = world["rooms"], world["npcs"]
    services = {**json.loads((ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))["item_rules"]["services"], **world.get("services", {})}
    services.pop("_doc", None)
    for sid, sv in world.get("services", {}).items():  # v0.7.16: a pack's own services — data over the engine's operations
        if sv.get("op") not in SERVICE_OPS or not isinstance(sv.get("cost_cp"), int) or not sv.get("name"):
            errors.append(f"услуга {sid}: нужны op из {sorted(SERVICE_OPS)}, cost_cp, name")
        if sv.get("op") == "enchant" and not (sv.get("property") and sv.get("suffix")):
            errors.append(f"услуга {sid}: enchant — нужны property и suffix")
    if world["start_room"] not in rooms:
        errors.append(f"world.start_room: нет комнаты {world['start_room']}")
    placed: set[str] = set()
    for rid, room in rooms.items():
        if room["location_id"] not in world["locations"]:
            errors.append(f"комната {rid}: нет локации {room['location_id']}")
        errors += [f"комната {rid}: выход в несуществующую {x}" for x in room["exits"] if x not in rooms]
        enc = room.get("encounter")
        if enc:
            foes = enc["enemies"] + [e for w in enc.get("waves", []) for e in w["enemies"]] + enc.get("help", {}).get("enemies", [])
            errors += [f"комната {rid}: встреча {enc['id']} — нет монстра {e['monster']}" for e in foes if e["monster"] not in ids["monsters"]]
            errors += [f"комната {rid}: в добыче нет предмета {x}" for x in enc.get("loot", {}).get("items", {}) if x not in items]
        for sec in room.get("secrets", []):
            errors += [f"комната {rid}: в тайнике {sec['id']} нет предмета {x}" for x in sec.get("loot", {}).get("items", {}) if x not in items]
            if "trap" in sec and sec["trap"]["guards"] not in room["exits"]:
                errors.append(f"комната {rid}: ловушка {sec['id']} стережёт не выход комнаты ({sec['trap']['guards']})")
        for to, lock in room.get("closed_exits", {}).items():
            if to not in room["exits"]:
                errors.append(f"комната {rid}: closed_exits {to} — не выход комнаты")
            errors += check_when(lock["when"], f"комната {rid}, выход {to}", rooms, npcs, items, top=False)
        secret_ids = [sec["id"] for sec in room.get("secrets", [])]
        if len(secret_ids) != len(set(secret_ids)):
            errors.append(f"комната {rid}: id секретов повторяются")
        errors += [f"комната {rid}: неизвестная метка {t}" for t in room.get("tags", []) if t not in ROOM_TAGS]
        for v in room.get("variants", []):  # v0.7.14.1: the room by the world's flags
            keys = {"if_flag", "if_not_flag", "description", "npcs", "hooks", "encounter", "safe"}
            if not ("if_flag" in v or "if_not_flag" in v) or set(v) - keys:
                errors.append(f"комната {rid}: вариант — if_flag или if_not_flag и только {', '.join(sorted(keys))}")
            errors += [f"комната {rid}: в варианте нет NPC {n}" for n in v.get("npcs", []) if n not in npcs]
            errors += [f"комната {rid}: в варианте нет монстра {f.get('monster')}" for f in v.get("encounter", {}).get("enemies", [])
                       if f.get("monster") not in ids["monsters"]]
        for n in room["npcs"]:
            if n not in npcs:
                errors.append(f"комната {rid}: нет NPC {n}")
            elif n in placed:
                errors.append(f"NPC {n} стоит в двух комнатах")
            placed.add(n)
    for nid, npc in npcs.items():
        errors += [f"NPC {nid}: в каталоге нет предмета {x}" for x in npc.get("stock", []) if x not in items]
        errors += [f"NPC {nid}: неизвестный язык {x}" for x in npc.get("languages", []) if x not in ids["languages"]]
        errors += [f"NPC {nid}: неизвестная метка {x}" for x in npc.get("tags", []) if x not in NPC_TAGS]
        errors += [f"NPC {nid}: неизвестная услуга {x}" for x in npc.get("services", []) if x not in services]
        if npc.get("services") and not npc.get("trader"):
            errors.append(f"NPC {nid}: услуги только у торговца (trader)")
        if npc.get("monster") and npc["monster"] not in ids["monsters"]:
            errors.append(f"NPC {nid}: нет монстра-шаблона {npc['monster']}")
        if npc.get("stock") and not npc.get("trader"):
            errors.append(f"NPC {nid}: есть stock, но нет trader: true")
        for sc in npc.get("schedule", []):  # v0.7.14.2: hours and a room ("" — away)
            if not all(isinstance(sc.get(k), int) and 0 <= sc[k] <= 23 for k in ("from", "to")) or (sc.get("room") and sc["room"] not in rooms):
                errors.append(f"NPC {nid}: schedule — from/to часы 0–23, room — комната пакета или пусто")
        if npc.get("heir") and (npc["heir"] not in npcs or npc["heir"] == nid):
            errors.append(f"NPC {nid}: наследник heir — другой NPC пакета")
        for sec in npc.get("secrets", []):  # v0.7.15.3: knowledge behind a check or attitude
            where = f"NPC {nid}, тайна {sec.get('id')}"
            if not all(sec.get(k) for k in ("id", "hint", "text")):
                errors.append(f"{where}: нужны id, hint, text")
            if not isinstance(sec.get("dc", 0), int) or not isinstance(sec.get("attitude", 0), int):
                errors.append(f"{where}: dc и attitude — целые")
            rv = sec.get("reveals", "")
            if rv and (":" not in rv or rv.split(":")[1] not in [x["id"] for x in rooms.get(rv.split(":")[0], {}).get("secrets", [])]):
                errors.append(f"{where}: reveals «комната:тайна» — нет такой тайны комнаты {rv}")
    for lid, loc in world["locations"].items():  # v0.7.17: a settlement keeps the hero's reputation
        if "settlement" in loc and not isinstance(loc["settlement"], bool):
            errors.append(f"локация {lid}: settlement — true / false")
    for lid, loc in world["locations"].items():  # v0.7.14: the law of a location
        law = loc.get("law")
        if law is None:
            continue
        errors += [f"локация {lid}: страж law.guards {g} — нет NPC" for g in law.get("guards", []) if g not in npcs]
        if law.get("guard_monster", "guard") not in ids["monsters"]:
            errors.append(f"локация {lid}: нет монстра стражи {law.get('guard_monster')}")

    for qid, q in world.get("quests", {}).items():
        if "steps" not in q:
            missing = [k for k in ("room", "action", "xp", "done_text") if k not in q]
            if missing:
                errors.append(f"задание {qid}: без шагов нужны {', '.join(missing)}")
            elif q["room"] not in rooms:
                errors.append(f"задание {qid}: нет комнаты {q['room']}")
            continue
        errors += [f"задание {qid}: в offer_items нет предмета {x}" for x in q.get("offer_items", {}) if x not in items]
        if q.get("giver") not in npcs:
            errors.append(f"задание {qid}: нет NPC-заказчика {q.get('giver')}")
        for i, st in enumerate(q["steps"]):
            w = st["when"]
            where = f"задание {qid}, шаг {i + 1}"
            errors += check_when(w, where, rooms, npcs, items, top=True)
            if "parts" in st and ("all" not in w or len(st["parts"]) != len(w["all"])):
                errors.append(f"{where}: parts — по одному названию на каждое условие all")
            if ("choice" in w) != ("choices" in st):
                errors.append(f"{where}: when.choice и choices — только вместе")
            for r in [st] + st.get("choices", []):
                errors += [f"{where}: в награде нет предмета {x}" for x in r.get("items", {}) if x not in items]
                errors += [f"{where}: нет NPC {x}" for x in r.get("attitude", {}) if x not in npcs]

    seen: set[str] = set()
    for p in chars["presets"]:
        ch, pid = p["choices"], p["id"]
        if pid in seen:
            errors.append(f"готовый персонаж: id повторяется ({pid})")
        seen.add(pid)
        for kind, key in (("races", "race"), ("classes", "class"), ("backgrounds", "background")):
            if ch[key] not in allowed[kind]:
                errors.append(f"готовый персонаж {pid}: {key} {ch[key]} недоступен в пакете")
        if ch.get("subrace") and ch["subrace"] not in ids["subraces"]:
            errors.append(f"готовый персонаж {pid}: нет подрасы {ch['subrace']}")
        if ch.get("subclass") and ch["subclass"] not in ids["subclasses"]:
            errors.append(f"готовый персонаж {pid}: нет подкласса {ch['subclass']}")
    return errors


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    dirs = [Path(a) for a in argv] or sorted(d for d in WORLDS.iterdir() if d.is_dir())
    ids = known()
    failed = 0
    for d in dirs:
        errors = validate_pack(d, ids)
        print(f"{'OK  ' if not errors else 'FAIL'} {d.name}")
        for e in errors:
            print(f"     {e}")
        failed += bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
