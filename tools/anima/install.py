"""Put the drawn icons and portraits into the game.

    icons:      out/<kind>/variants/<id>__<n>.png        → game/assets/icons/<kind>/<id>.png (the picked variant)
    portraits:  out/portraits/<sub>/variants/<id>__<n>.webp → game/assets/portraits/<sub>/<id>__<n>.webp (every one)

The variant of each icon is read from picks.json (absent — variant 1); an icon listed under `redo` is left out, so the
game shows its blank until the subject is fixed and drawn again. A portrait keeps all its variants (the game picks one
per person); a bad one is listed under `redo` as «portraits/<sub>/<id>__<n>» and the game shows the letter for it. An
icon under `overlay` gets a mark drawn by code over it (overlays.py: a symbol the model would spoil); an icon under
`same` («features/domain_spells_2»: «features/domain_spells_1») is laid from the other's picked variant, one under
`drawn` («ui/skills»: «d20») is a whole icon drawn by code (overlays.ICONS) where the model fills a geometry. A file already in
the game is replaced only when it differs. Run `"$GODOT" --headless --path game --import` afterwards.

    python tools/anima/install.py                 # every kind of the icon jobs
    python tools/anima/install.py --only spells   # one kind
    python tools/anima/install.py --jobs tools/anima/jobs/portraits.json   # the portraits
    python tools/anima/install.py --dry           # only say what would change
"""
from __future__ import annotations

import argparse
import filecmp
import json
import shutil
from pathlib import Path

import overlays

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent / "game" / "assets"


def files(j: dict, variant: dict, redo: set, out: Path, like: dict | None = None) -> list[tuple[Path, Path] | None]:
    """(drawn, in the game) of each file of a job; None for one left out by `redo`. An icon under `same` is the picked
    variant of the icon it names (the same feature at another level, one style of two classes)."""
    key = f"{j['kind']}/{j['id']}"
    if j.get("style") != "portrait":
        if key in redo:
            return [None]
        src = (like or {}).get(key, key)
        kind, _, iid = src.partition("/")
        return [(out / kind / "variants" / f"{iid}__{variant.get(src, 1)}.png", ASSETS / "icons" / j["kind"] / f"{j['id']}.png")]
    sub = j["kind"].removeprefix("portraits/")
    return [None if f"{key}__{n}" in redo else
            (out / j["kind"] / "variants" / f"{j['id']}__{n}.webp", ASSETS / "portraits" / sub / f"{j['id']}__{n}.webp")
            for n in range(1, len(j["seeds"]) + 1)]


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
    variant, redo, overlay = picks.get("variant", {}), set(picks.get("redo", [])), picks.get("overlay", {})
    like, drawn = picks.get("same", {}), picks.get("drawn", {})
    only = set(filter(None, a.only.split(",")))
    new = same = skipped = missing = 0
    for j in jobs:
        if only and j["kind"] not in only:
            continue
        for pair in files(j, variant, redo, a.out, like):
            if pair is None:
                skipped += 1
                continue
            src, dst = pair
            key = f"{j['kind']}/{j['id']}" if j.get("style") != "portrait" else ""
            if key in drawn:  # the whole icon drawn by code, the model's left aside
                body = overlays.icon(drawn[key])
            elif not src.exists():
                missing += 1
                print("not drawn:", src.relative_to(a.out))
                continue
            else:
                mark = overlay.get(key)
                body = overlays.apply(mark, src) if mark else None
            if dst.exists() and (dst.read_bytes() == body if body else filecmp.cmp(src, dst, shallow=False)):
                same += 1
                continue
            new += 1
            if not a.dry:
                dst.parent.mkdir(parents=True, exist_ok=True)
                if body:
                    dst.write_bytes(body)
                else:
                    shutil.copyfile(src, dst)
    print(f"put {new}, unchanged {same}, left out (redo) {skipped}, not drawn {missing}" + (" (dry)" if a.dry else ""))


if __name__ == "__main__":
    main()
