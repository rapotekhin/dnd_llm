#!/usr/bin/env python3
"""The map's tiles by FLUX over OpenRouter: grounds as seamless textures, props cut out of their frames.

    python tools/tiles/gen_tiles.py draw                     # every job of tiles.json × --variants (~$0.009 a frame)
    python tools/tiles/gen_tiles.py draw --only grass,tree   # some of them again
    tools/anima/.venv-matte/Scripts/python.exe tools/tiles/gen_tiles.py matte   # props cut by BiRefNet (tools/anima/matte.py)
    python tools/tiles/gen_tiles.py sheet                    # build/tiles/sheet_ground.png, sheet_props.png to pick from
    python tools/tiles/gen_tiles.py install                  # tools/tiles/picks.json → game/assets/tiles/{ground,props,edges}/
                                                             # and the sharp set {ground,props}_hi/ the map takes close up

A ground comes out of FLUX nearly even but not seamless: it is made so by blending it with itself rolled by half
(`seamless`), so a texture repeats under the dual grid with no seam. An edge (`grounds.edges`: two grounds whose meeting
is drawn) is ONE frame of the sixteen dual-grid tiles: FLUX repaints a mask of the pair laid on `grounds.edge_layout`
(5×5 corners, each 2×2 window a case once, so the sheet is a small continuous map), the line crossing every tile's side
at its middle; the sheet keeps the line in its alpha (0.5 on the line), and the shader takes only a band of it round
the line over the grounds' own textures. The key is OPENROUTER_API_KEY of the environment
or of the repo's .env, never printed (anima_gen.openrouter_key).
"""
from __future__ import annotations

import argparse
import json
import math
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
HI = 2  # the sharp set the map takes close up (MapGround.HI): grounds from the raw frame, props cut twice the size
EDGE_PX = 1024  # a sheet of 4 × 4 tiles
FIELD_PX = 256  # the line is worked out at this size and smoothed up
LOW, HIGH = (40, 105, 200), (70, 150, 60)  # the mask's colours: the lower ground blue, the higher green
SEEDS = (11, 22, 33, 44)


def grounds_lib() -> dict:
    return json.loads((ROOT / "game" / "data" / "layouts.json").read_text(encoding="utf-8"))["grounds"]


def bodies() -> dict:
    """The things of the map with their squares (rules.things.bodies): a prop of that id is drawn and cut to its size."""
    return json.loads((ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))["things"]["bodies"]


def size_of(tid: str) -> tuple[int, int]:
    w, h = bodies().get(tid, {}).get("size", [1, 1])
    return int(w), int(h)


def aspect(tid: str) -> str:
    """The frame FLUX draws a thing in: the long side of its squares across."""
    w, h = size_of(tid)
    frames = {"1:1": 1.0, "3:2": 1.5, "16:9": 16 / 9, "21:9": 21 / 9}
    return min(frames, key=lambda k: abs(frames[k] - w / h))


def keyed(rgb: Image.Image, mask: Image.Image) -> Image.Image:
    """The cut's mask with what plainly differs from the frame's flat grey background kept too: BiRefNet takes a flat
    tabletop seen from above for the background and keeps only what lies on it; a soft shadow stays out."""
    from PIL import ImageFilter
    border = [rgb.getpixel((x, y)) for x in range(0, rgb.width, 16) for y in (0, rgb.height - 1)]         + [rgb.getpixel((x, y)) for y in range(0, rgb.height, 16) for x in (0, rgb.width - 1)]
    back = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))
    flat = Image.new("RGB", rgb.size, back)
    diff = ImageChops.difference(rgb, flat).convert("L")
    strong = diff.point(lambda v: 0 if v < 34 else 255 if v > 56 else int((v - 34) * 255 / 22))
    strong = strong.filter(ImageFilter.MedianFilter(5))
    out = ImageChops.lighter(mask.convert("L").resize(rgb.size), strong)
    return out


def fit(cut: Image.Image, tid: str, side: int) -> Image.Image:
    """A cut thing laid in its square texture as the map draws it: its own picture cropped to what is drawn, stretched to
    its squares' w:h and centred in a square of the long side (MapGround reads a thing of w × h squares so)."""
    box = cut.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, cut.width, cut.height)
    w, h = size_of(tid)
    long = max(w, h)
    pad = 0.92  # a little air round it, for its shadow
    body = cut.crop(box)
    if w != h and (body.width > body.height) != (w > h):  # drawn across its squares (a bed standing up): laid along them
        body = body.transpose(Image.Transpose.ROTATE_90)
    body = body.resize((max(1, round(side * pad * w / long)), max(1, round(side * pad * h / long))), Image.LANCZOS)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.paste(body, ((side - body.width) // 2, (side - body.height) // 2), body)
    return out


def jobs(only: str) -> list[tuple[str, str, str]]:
    """(group, id, prompt) of tiles.json, `only` some ids."""
    spec = json.loads((HERE / "tiles.json").read_text(encoding="utf-8"))
    want = {s for s in only.split(",") if s}
    out = []
    for group, style in (("ground", "ground"), ("props", "prop")):
        for tid, subject in spec[group].items():
            if not want or tid in want:
                out.append((group, tid, spec["style"][style].replace("{subject}", subject)))
    for pair in grounds_lib().get("edges", []):
        low, high = str(pair["low"]), str(pair["high"])
        tid = f"{low}__{high}"
        if not want or tid in want:
            same = grounds_lib().get("same", {})  # a ground with the texture of another: its words too
            words = lambda g: spec["ground"][same.get(g, g)]
            meet = spec["edges"].get(tid, spec["edges"]["*"])
            style = "edge"
            if isinstance(meet, dict):  # a pair of its own style: land and land, the mask's colours not kept (a cliff)
                style, meet = meet.get("style", style), meet["meet"]
            text = spec["style"][style].replace("{low}", words(low)).replace("{high}", words(high))
            out.append(("edges", tid, text.replace("{meet}", meet)))
    return out


def _hash(x: float, y: float) -> float:
    v = math.sin(x * 127.1 + y * 311.7) * 43758.5453
    return v - math.floor(v)


def _noise(x: float, y: float) -> float:
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = _hash(ix, iy), _hash(ix + 1, iy), _hash(ix, iy + 1), _hash(ix + 1, iy + 1)
    return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy


def gain_of(tid: str) -> float:
    """How steeply an edge sheet's alpha leaves its line (`gain` of its `grounds.edges` row): 2 — saturated a quarter of a
    tile off the line (a shore), 1 — half a tile (a cliff's face and shadow, painted wider)."""
    for pair in grounds_lib().get("edges", []):
        if f"{pair['low']}__{pair['high']}" == tid:
            return float(pair.get("gain", 2.0))
    return 2.0


def edge_field(gain: float = 2.0) -> Image.Image:
    """The line of an edge sheet as a grey picture, EDGE_PX: 128 on the line, the higher ground above it. Each tile's
    corners of `edge_layout` mixed over the tile, a rough line on top that dies out on the tile's sides, so the line
    crosses every side at its middle and any two tiles meet."""
    rows = [str(r) for r in grounds_lib()["edge_layout"]]
    tile = FIELD_PX / 4
    img = Image.new("L", (FIELD_PX, FIELD_PX))
    px = img.load()
    for y in range(FIELD_PX):
        for x in range(FIELD_PX):
            sx, sy = (x + 0.5) / tile, (y + 0.5) / tile
            ix, iy = min(3, int(sx)), min(3, int(sy))
            fx, fy = sx - ix, sy - iy
            c = [int(rows[iy][ix]), int(rows[iy][ix + 1]), int(rows[iy + 1][ix]), int(rows[iy + 1][ix + 1])]
            cov = (c[0] * (1 - fx) + c[1] * fx) * (1 - fy) + (c[2] * (1 - fx) + c[3] * fx) * fy
            damp = math.sin(math.pi * fx) * math.sin(math.pi * fy)
            v = cov + (_noise(sx * 1.6, sy * 1.6) - 0.5) * 0.35 * damp
            px[x, y] = max(0, min(255, round((0.5 + (v - 0.5) * gain) * 255)))
    return img.resize((EDGE_PX, EDGE_PX), Image.BICUBIC)


def edge_mask(field: Image.Image) -> Image.Image:
    """The two flat colours FLUX repaints: the higher ground where the field is above the line."""
    hi = field.point(lambda v: 255 if v >= 128 else 0)
    return Image.composite(Image.new("RGB", field.size, HIGH), Image.new("RGB", field.size, LOW), hi)


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
    field = edge_field() if any(g == "edges" for g, *_ in todo) else None
    refs = [edge_mask(field)] if field else None
    with ThreadPoolExecutor(4) as pool:
        futures = {pool.submit(anima_gen.openrouter_frame, p, SEEDS[n % len(SEEDS)] + n, key, a.model,
                               aspect(t) if g == "props" else "1:1", refs if g == "edges" else None): (g, t, n) for g, t, p, n in todo}
        for f in as_completed(futures):
            g, t, n = futures[f]
            img, cost = f.result()
            spent += cost
            img.save(OUT / "raw" / f"{t}__{n}.png")
            if g == "ground":
                seamless(img).resize((GROUND_PX, GROUND_PX), Image.LANCZOS).save(OUT / f"{t}__{n}.png")
            elif g == "edges":  # the painting, the line in its alpha
                sheet_rgba = img.resize((EDGE_PX, EDGE_PX), Image.LANCZOS).convert("RGBA")
                sheet_rgba.putalpha(field if gain_of(t) == 2.0 else edge_field(gain_of(t)))  # a wide edge: a gentler line
                sheet_rgba.save(OUT / f"{t}__{n}.png")
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
            cut = rgb.convert("RGBA")  # the whole frame with its mask: `fit` crops it, no size lost on the way
            cut.putalpha(keyed(rgb, m.mask_of(model, device, rgb)))
            fit(cut, t, PROP_PX).save(OUT / raw.name)
            (OUT / "hi").mkdir(exist_ok=True)
            fit(cut, t, PROP_PX * HI).save(OUT / "hi" / raw.name)
            print(raw.name, flush=True)


def sheet(a: argparse.Namespace) -> None:
    """A sheet per group: each ground as 2×2 of itself (a seam shows), each prop on a checker."""
    for group in ("ground", "props", "edges"):
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
                if group == "edges":  # the painting with its tile grid
                    rgb = img.convert("RGB").resize((cell, cell), Image.LANCZOS)
                    dd = ImageDraw.Draw(rgb)
                    for k in range(1, 4):
                        dd.line([k * cell // 4, 0, k * cell // 4, cell], fill=(255, 210, 60))
                        dd.line([0, k * cell // 4, cell, k * cell // 4], fill=(255, 210, 60))
                    out.paste(rgb, at)
                elif group == "ground":
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
        sharp = sharp_of(g, f"{t}__{int(picks[t])}.png")
        if sharp is not None:
            hi = GAME / f"{g}_hi" / f"{t}.png"
            hi.parent.mkdir(parents=True, exist_ok=True)
            sharp.save(hi)
            print(hi.relative_to(ROOT))


def sharp_of(group: str, name: str) -> Image.Image | None:
    """The sharp picture of a pick: a ground made seamless from its raw frame as the plain one is, a prop as `matte` cut it
    twice the size; an edge sheet has none (FLUX's frame is its size already)."""
    if group == "ground" and (OUT / "raw" / name).exists():
        side = GROUND_PX * HI
        return seamless(Image.open(OUT / "raw" / name).convert("RGB")).resize((side, side), Image.LANCZOS)
    if group == "props" and (OUT / "hi" / name).exists():
        return Image.open(OUT / "hi" / name)
    return None


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
