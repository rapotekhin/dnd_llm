"""Moving generated items from the backend library into the game catalog (ADR-0008 §6, roadmap v0.7.18.3).

    python tools/promote_items.py                                   # the library: each item checked, how often given
    python tools/promote_items.py --promote gen_9b1ce7507b           # into the catalog with an id from its name
    python tools/promote_items.py --promote gen_9b1ce7507b=dark_ale  # … with the author's id

The master makes items within the engine's rules; the backend keeps the accepted ones in
llm_server/var/items/library.jsonl, shared by all games. The author picks which become part of the game: a promoted item
goes into tools/srd/promoted.json (the SRD build merges it into the catalog, so it survives `srd_import.py build`) and
into game/data/items.json at once, under a permanent id, and leaves the library (find_items then finds it in the
catalog). Saves keep the full description of a generated item, so old games are unaffected. The check mirrors
ItemRules.check_generated: known properties and base, rarity by points (properties and `use`), the value within it —
the library keeps the master's proposal, the engine's numbers are set again here.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "game" / "data" / "items.json"
SPELLS = ROOT / "game" / "data" / "srd" / "spells.json"
PROMOTED = ROOT / "tools" / "srd" / "promoted.json"
LIBRARY = ROOT / "llm_server" / "var" / "items" / "library.jsonl"
TRACES = ROOT / "llm_server" / "var" / "traces"

TRANSLIT = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f",
                     "kh", "ts", "ch", "sh", "shch", "", "y", "", "e", "yu", "ya"]))


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def library(path: Path = LIBRARY) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def slug(name: str) -> str:
    s = "".join(TRANSLIT.get(ch, ch) for ch in name.lower())
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")[:40] or "item"


def use_points(items: dict, spells: dict, item: dict) -> tuple[int, str]:
    """Points of the item's `use` and the reason it is wrong ("" — fine), as ItemRules._generated_use."""
    use = item.get("use") or {}
    if not use:
        return 0, ""
    cost = items["use_points"]
    charges = int(use.get("charges") or 0)
    if use.get("spell"):
        spell = spells.get(use["spell"])
        if spell is None:
            return 0, f"заклинания {use['spell']} нет в книге движка"
        level = max(int(spell.get("level", 0)), int(use.get("level") or 0))
        if level > 3:
            return 0, "заклинание в предмете — не выше 3 круга"
        if charges > int(cost["charges_max"]):
            return 0, f"зарядов не больше {cost['charges_max']}"
        return int(cost["wand" if charges else "scroll"][level]), ""
    if charges:
        return 0, "заряды — только у предмета с заклинанием"
    if use.get("heal"):
        heal = cost["heal"].get(use["heal"])
        return (int(heal["points"]), "") if heal else (0, "лечение: light, medium или strong")
    if use.get("resist"):
        return int(cost["resist"]), ""
    if use.get("check_adv"):
        return int(cost["check_adv"]), ""
    return 0, "use: spell, heal, resist или check_adv"


def rarity_of(items: dict, spells: dict, item: dict) -> str:
    """The rarity by points (properties and `use`), as the engine sets it."""
    points = sum(int(items["properties"].get(p, 0)) for p in item.get("properties", [])) + use_points(items, spells, item)[0]
    rarity = "common"
    for at, name in items["rarity_by_points"]:
        if points >= int(at):
            rarity = name
    return rarity


def check(items: dict, spells: dict, item: dict) -> str:
    """Why the item cannot enter the catalog ("" — it can); rarity and value are set by the engine's rules."""
    if not str(item.get("name", "")).strip():
        return "нет названия"
    unknown = [p for p in item.get("properties", []) if p not in items["properties"]]
    if unknown:
        return f"свойства движку неизвестны: {', '.join(unknown)}"
    if item.get("base") and item["base"] not in items["catalog"]:
        return f"базового предмета {item['base']} нет в каталоге"
    return use_points(items, spells, item)[1]


def times_given(item_id: str, traces: Path = TRACES) -> int:
    return sum(p.read_text(encoding="utf-8", errors="ignore").count(item_id) for p in traces.glob("*.jsonl")) if traces.exists() else 0


def catalog_def(items: dict, spells: dict, item: dict) -> dict:
    """The catalog shape of a library item: the rarity by points, the value within it (as ItemRules.check_generated)."""
    out = {k: item[k] for k in ("name", "item_type", "properties", "description") if k in item}
    out["rarity"] = rarity_of(items, spells, item)
    out["value_cp"] = min(int(item.get("value_cp", 0)), int(items["rarity_max_value_cp"][out["rarity"]]))
    for k in ("base", "text"):
        if item.get(k):
            out[k] = item[k]
    if item.get("use"):  # the shapes the engine resolves (ItemRules._generated_use)
        use = {k: v for k, v in item["use"].items() if v is not None}
        charges = int(use.pop("charges", 0) or 0)
        if "heal" in use:
            out["use"] = {"heal": {"light": [2, 4, 2], "medium": [4, 4, 4], "strong": [8, 4, 8]}[use["heal"]]}
        elif "spell" in use:
            out["use"] = {"spell": use["spell"], "level": int(use.get("level") or 0)} | ({} if charges else {"scroll": True})
            if charges:
                out["charges"] = {"max": charges, "regain": f"1d{max(1, charges - 1)}", "crumble": True}
        else:
            out["use"] = use | {"duration": "hour"}
    if out.get("item_type") == "consumable":
        out["stack"] = True
    return out


def promote(picks: list[str], items_path: Path = ITEMS, promoted_path: Path = PROMOTED, library_path: Path = LIBRARY) -> list[str]:
    """Moves the picked library items («gen_id» or «gen_id=new_id») into the catalog. Lines of what happened."""
    items = load_json(items_path)
    spells = load_json(SPELLS)
    promoted = load_json(promoted_path)
    lib = library(library_path)
    by_id = {i["item_id"]: i for i in lib}
    lines, moved = [], set()
    for pick in picks:
        gen_id, _, new_id = pick.partition("=")
        item = by_id.get(gen_id)
        if item is None:
            lines.append(f"✗ {gen_id}: нет в библиотеке")
            continue
        why = check(items, spells, item)
        if why:
            lines.append(f"✗ {gen_id} «{item['name']}»: {why}")
            continue
        new_id = new_id or slug(item["name"])
        if new_id in items["catalog"]:
            lines.append(f"✗ {gen_id}: id {new_id} уже занят в каталоге — задай свой: {gen_id}=другой_id")
            continue
        d = catalog_def(items, spells, item)
        items["catalog"][new_id] = d
        promoted[new_id] = d
        moved.add(gen_id)
        lines.append(f"✓ {gen_id} «{item['name']}» → каталог: {new_id}")
    if moved:
        items["catalog"] = dict(sorted(items["catalog"].items()))
        items_path.write_text(json.dumps(items, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
        promoted_path.write_text(json.dumps(dict(sorted(promoted.items())), ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
        library_path.write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in lib if i["item_id"] not in moved), encoding="utf-8")
    return lines


def report(items_path: Path = ITEMS, library_path: Path = LIBRARY) -> list[str]:
    items = load_json(items_path)
    spells = load_json(SPELLS)
    names = {str(d.get("name", "")).lower(): k for k, d in items["catalog"].items()}
    out = []
    for item in library(library_path):
        why = check(items, spells, item)
        twin = names.get(str(item["name"]).lower())
        mark = "✗ " + why if why else ("≈ в каталоге уже есть " + twin if twin else "✓")
        out.append(f"{item['item_id']}  «{item['name']}» — {item['item_type']}, {rarity_of(items, spells, item) if not why else '?'}, {item.get('value_cp', 0)} мм, "
                   f"выдавали {times_given(item['item_id'])} — {mark}")
    return out or ["библиотека пуста"]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--promote", default="", help="comma-separated library ids, each optionally =new_catalog_id")
    opts = parser.parse_args()
    if opts.promote:
        lines = promote([p.strip() for p in opts.promote.split(",") if p.strip()])
        print("\n".join(lines))
        return 1 if any(line.startswith("✗") for line in lines) else 0
    print("\n".join(report()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
