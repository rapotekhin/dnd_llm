#!/usr/bin/env python3
"""The map's tiles by FLUX over OpenRouter: grounds as seamless textures, props cut out of their frames.

    python tools/tiles/gen_tiles.py draw                     # every job of tiles.json × --variants (~$0.009 a frame)
    python tools/tiles/gen_tiles.py draw --only grass,tree   # some of them again
    tools/anima/.venv-matte/Scripts/python.exe tools/tiles/gen_tiles.py matte   # props cut by BiRefNet (tools/anima/matte.py)
    python tools/tiles/gen_tiles.py sheet                    # build/tiles/sheet_ground.png, sheet_props.png to pick from
    python tools/tiles/gen_tiles.py install                  # tools/tiles/picks.json → game/assets/tiles/{ground,props}/

A ground comes out of FLUX nearly even but not seamless: it is made so by blending it with itself rolled by half
(`seamless`), so a texture repeats under the dual grid with no seam. The key is OPENROUTER_API_KEY of the environment
or of the repo's .env, never printed (anima_gen.openrouter_key).
"""
from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / "anima"))
import anima_gen  # noqa: E402

OUT = ROOT / "build" / "tiles"
GAME = ROOT / "game" / "assets" / "tiles"
GROUND_PX = 512  # a ground texture's side in the game: it spans `repeat` squares of the map
PROP_PX = 256
SEEDS = (11, 22, 33, 44)


def jobs(only: str) -> list[tuple[str, str, str]]:
    """(group, id, prompt) of tiles.json, `only` some ids."""
    spec = json.loads((HERE / "tiles.json").read_text(encoding="utf-8"))
    want = {s for s in only.split(",") if s}
    out = []
    for group, style in (("ground", "ground"), ("props", "prop")):
        for tid, subject in spec[group].items():
            if not want or tid in want:
                out.append((group, tid, spec["style"][style].replace("{subject}", subject)))
    return out


def seamless(img: Image.Image) -> Image.Image:
    """The frame blended with itself rolled by half: the rolled one wraps at the edges, the frame itself has no seam in
    the middle, so the frame is kept in the middle and the rolled one at the edges."""
    side = min(img.size)
    img = img.crop(((img.width - side) // 2, (img.height - side) // 2, (img.width + side) // 2, (img.height + side) // 2))
    rolled = ImageChops.offset(img, side // 2, side // 2)
    mask = Image.new("L", (side, side))
    px = mask.load()
    for y in range(side):
        for x in range(side):
            dx = 1.0 - abs(2.0 * x / (side - 1) - 1.0)  # 0 at the edges, 1 in the middle
            dy = 1.0 - abs(2.0 * y / (side - 1) - 1.0)
            w = min(1.0, min(dx, dy) * 2.2)
            px[x, y] = int(255 * w * w * (3 - 2 * w))
    return Image.composite(img, rolled, mask)


def draw(a: argparse.Namespace) -> None:
    key = anima_gen.openrouter_key()
    (OUT / "raw").mkdir(parents=True, exist_ok=True)
    todo = [(g, t, p, n) for g, t, p in jobs(a.only) for n in range(a.variants)
            if a.force or not (OUT / "raw" / f"{t}__{n}.png").exists()]
    spent = 0.0
    with ThreadPoolExecutor(4) as pool:
        futures = {pool.submit(anima_gen.openrouter_frame, p, SEEDS[n % len(SEEDS)] + n, key, a.model): (g, t, n)
                   for g, t, p, n in todo}
        for f in as_completed(futures):
            g, t, n = futures[f]
            img, cost = f.result()
            spent += cost
            img.save(OUT / "raw" / f"{t}__{n}.png")
            if g == "ground":
                seamless(img).resize((GROUND_PX, GROUND_PX), Image.LANCZOS).save(OUT / f"{t}__{n}.png")
            print(f"{t}__{n}  ${cost:.4f}", flush=True)
    print(f"{len(todo)} frames, ${spent:.3f}")


def matte(a: argparse.Namespace) -> None:
    """Props cut out of their frames by BiRefNet, in the env of tools/anima/matte.py (torch)."""
    import matte as m

    model, device = m.load(m.MODEL_DIR)
    for g, t, _ in jobs(a.only):
        if g != "props":
            continue
        for raw in sorted((OUT / "raw").glob(f"{t}__*.png")):
            rgb = Image.open(raw).convert("RGB")
            m.matte(rgb, m.mask_of(model, device, rgb)).resize((PROP_PX, PROP_PX), Image.LANCZOS).save(OUT / raw.name)
            print(raw.name, flush=True)


def sheet(a: argparse.Namespace) -> None:
    """A sheet per group: each ground as 2×2 of itself (a seam shows), each prop on a checker."""
    for group in ("ground", "props"):
        rows = [(t, sorted(OUT.glob(f"{t}__*.png"))) for g, t, _ in jobs(a.only) if g == group]
        rows = [r for r in rows if r[1]]
        if not rows:
            continue
        cell, label = 256, 110
        cols = max(len(r[1]) for r in rows)
        out = Image.new("RGB", (label + cols * (cell + 8), len(rows) * (cell + 8)), (24, 20, 16))
        d = ImageDraw.Draw(out)
        for i, (t, files) in enumerate(rows):
            d.text((6, i * (cell + 8) + cell // 2), t, fill=(230, 210, 160))
            for j, f in enumerate(files):
                img = Image.open(f).convert("RGBA")
                at = (label + j * (cell + 8), i * (cell + 8))
                if group == "ground":
                    half = img.resize((cell // 2, cell // 2), Image.LANCZOS)
                    for k in range(4):
                        out.paste(half, (at[0] + (k % 2) * cell // 2, at[1] + (k // 2) * cell // 2))
                else:
                    back = Image.new("RGBA", (cell, cell), (120, 110, 90, 255))
                    back.alpha_composite(img.resize((cell, cell), Image.LANCZOS))
                    out.paste(back.convert("RGB"), at)
                d.text((at[0] + 4, at[1] + 4), str(j), fill=(255, 255, 255))
        path = OUT / f"sheet_{group}.png"
        out.save(path)
        print(path)


def install(a: argparse.Namespace) -> None:
    picks = json.loads((HERE / "picks.json").read_text(encoding="utf-8"))
    for g, t, _ in jobs(a.only):
        if t not in picks:
            continue
        src = OUT / f"{t}__{int(picks[t])}.png"
        dst = GAME / g / f"{t}.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        Image.open(src).save(dst)
        print(dst.relative_to(ROOT))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("step", choices=("draw", "matte", "sheet", "install"))
    p.add_argument("--only", default="", help="ids, comma-separated")
    p.add_argument("--variants", type=int, default=3)
    p.add_argument("--model", default=anima_gen.OPENROUTER_MODEL)
    p.add_argument("--force", action="store_true", help="draw again what is drawn")
    a = p.parse_args()
    {"draw": draw, "matte": matte, "sheet": sheet, "install": install}[a.step](a)


if __name__ == "__main__":
    main()
