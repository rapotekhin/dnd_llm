"""Put the drawn icons into the game: out/<kind>/variants/<id>__<n>.png → game/assets/icons/<kind>/<id>.png.

The variant of each icon is read from picks.json (absent — variant 1); an icon listed under `redo` is left out, so the
game shows its blank until the subject is fixed and drawn again. An icon already in the game is replaced only when the
picked variant differs from it. Run `"$GODOT" --headless --path game --import` afterwards.

    python tools/anima/install.py                 # every kind of the jobs
    python tools/anima/install.py --only spells   # one kind
    python tools/anima/install.py --dry           # only say what would change
"""
from __future__ import annotations

import argparse
import filecmp
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
ICONS = HERE.parent.parent / "game" / "assets" / "icons"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--jobs", type=Path, default=HERE / "jobs" / "icons.json")
    p.add_argument("--out", type=Path, default=HERE / "out")
    p.add_argument("--picks", type=Path, default=HERE / "picks.json")
    p.add_argument("--only", default="", help="kinds, comma-separated")
    p.add_argument("--dry", action="store_true")
    a = p.parse_args()
    jobs = json.loads(a.jobs.read_text(encoding="utf-8"))
    jobs = jobs["jobs"] if isinstance(jobs, dict) else jobs
    picks = json.loads(a.picks.read_text(encoding="utf-8")) if a.picks.exists() else {}
    variant, redo = picks.get("variant", {}), set(picks.get("redo", []))
    only = set(filter(None, a.only.split(",")))
    new = same = skipped = missing = 0
    for j in jobs:
        key = f"{j['kind']}/{j['id']}"
        if only and j["kind"] not in only:
            continue
        if key in redo:
            skipped += 1
            continue
        src = a.out / j["kind"] / "variants" / f"{j['id']}__{variant.get(key, 1)}.png"
        if not src.exists():
            missing += 1
            print("not drawn:", src.relative_to(a.out))
            continue
        dst = ICONS / j["kind"] / f"{j['id']}.png"
        if dst.exists() and filecmp.cmp(src, dst, shallow=False):
            same += 1
            continue
        new += 1
        if not a.dry:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
    print(f"put {new}, unchanged {same}, left blank (redo) {skipped}, not drawn {missing}" + (" (dry)" if a.dry else ""))


if __name__ == "__main__":
    main()
