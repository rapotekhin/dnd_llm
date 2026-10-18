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


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def known() -> dict[str, set[str]]:
    races = load(DATA / "srd" / "races.json")
    classes = load(DATA / "srd" / "classes.json")
    return {
        "races": set(races["races"]), "subraces": set(races["subraces"]), "classes": set(classes["classes"]),
        "subclasses": set(classes["subclasses"]), "backgrounds": set(load(DATA / "srd" / "backgrounds.json")),
        "items": set(load(DATA / "items.json")["catalog"]),
    }


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
    items = ids["items"] - set(rules.get("items_exclude", []))

    rooms, npcs = world["rooms"], world["npcs"]
    if world["start_room"] not in rooms:
        errors.append(f"world.start_room: нет комнаты {world['start_room']}")
    placed: set[str] = set()
    for rid, room in rooms.items():
        if room["location_id"] not in world["locations"]:
            errors.append(f"комната {rid}: нет локации {room['location_id']}")
        errors += [f"комната {rid}: выход в несуществующую {x}" for x in room["exits"] if x not in rooms]
        secret_ids = [sec["id"] for sec in room.get("secrets", [])]
        if len(secret_ids) != len(set(secret_ids)):
            errors.append(f"комната {rid}: id секретов повторяются")
        for n in room["npcs"]:
            if n not in npcs:
                errors.append(f"комната {rid}: нет NPC {n}")
            elif n in placed:
                errors.append(f"NPC {n} стоит в двух комнатах")
            placed.add(n)
    for nid, npc in npcs.items():
        errors += [f"NPC {nid}: в каталоге нет предмета {x}" for x in npc.get("stock", []) if x not in items]

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
