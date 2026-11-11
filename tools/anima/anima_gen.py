#!/usr/bin/env python3
"""Game icons drawn by Anima on a Forge (AUTOMATIC1111 API), self-contained: Python 3.9+ and Pillow, nothing of the
repo. Copy this folder to the machine with Forge and run it there under nohup or tmux; it draws only what is missing,
so a stopped run goes on from where it stopped, and after a `git pull` the same command redraws only the icons whose
subject (or settings) changed: each variant keeps the prompt it was drawn from beside it.

    python3 anima_gen.py jobs/icons.json                       # draw everything missing → out/
    python3 anima_gen.py jobs/icons.json --only items,spells   # some kinds
    python3 anima_gen.py jobs/icons.json --ids longsword,fireball --redraw
    python3 anima_gen.py jobs/icons.json --sheets              # only the contact sheets of what is drawn
    python3 anima_gen.py jobs/icons.json --pick longsword=2    # the 2nd variant becomes the icon

    nohup python3 anima_gen.py jobs/icons.json > anima.log 2>&1 &
    nohup python3 anima_gen.py jobs/portraits.json --steps 24 > portraits.log 2>&1 &   # people and monsters
    nohup python3 anima_gen.py jobs/icons.json --style painted --only items,spells > painted.log 2>&1 &   # → out_painted/, by families

A portrait job (`style: "portrait"`) is drawn as a bust and kept whole in raw/; its variant is the face cut out of it,
256 px WebP (variants/<id>__<n>.webp); it has its own seeds, and a person its own look per variant (`looks`).

The prompt follows the Anima card (huggingface.co/circlestone-labs/Anima): quality tags first, the object in tags,
then at least two plain sentences; ER SDE, CFG 4–5. The object is drawn on a flat background, which is cut out into a
transparent PNG: its colour is the median of the border and the cut is a flood fill from the border, so any flat
colour works. The background is dark; a dark object goes on grey (`key` of a job), so the cut keeps its edge.

What is written (per kind, e.g. out/items/):
    raw/<id>__<seed>.png      the frame as Forge drew it
    variants/<id>__<n>.png    cut out, ICON px, one per seed; <id>__<n>.txt — the prompt it was drawn from
    <id>.png                  the icon: variant 1, or the one picked by --pick
    sheet_<kind>_<page>.png   contact sheets: a row per icon, a column per variant, on a dark slot
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import shutil
import sys
import time
import urllib.error
import urllib.request
from collections import deque
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent

CHECKPOINT = "anima-aesthetic"  # a part of the checkpoint's title on Forge
MODULES = ("qwen_image_vae.safetensors", "qwen_3_06b_base.safetensors")  # what an Anima checkpoint needs on Forge
# The A/B of 2026-11-10 (one seed, one change at a time): a dark background with no tag of its own draws the object
# biggest and boldest; a solid green, grey or magenta one shrinks it and spoils abstract emblems, and «a dark outline»
# draws thick black contours. So the dark one by default, another only for a dark object the cut would eat.
HEAD = "masterpiece, best quality, safe, no humans, simple background, {tag}flat color, minimalism, icon, "
TAIL = ("It is a game icon from a fantasy RPG, drawn in a minimalist style as one bold flat silhouette with clean "
        "sharp edges, in a simple palette of two or three colors with no shading and no texture. The single object "
        "is centered and fills most of the square, on a plain {word} background.")
NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
            "chromatic aberration, text, letters, watermark, signature, border, frame, multiple objects, duplicate, "
            "human, person, face, hands, realistic, photo, 3d, detailed texture, gradient, noise")
KEYS = {  # a job's key → (a tag of the head, the word of the tail)
    "dark": ("", "dark"),
    "grey": ("grey background, ", "solid grey"),
    "white": ("white background, ", "solid white"),
    "green": ("green background, ", "solid green"),
}
# The painted style (the author, 2026-11-11: the flat minimalism no longer fits beside the portraits and the painted
# interface): the same subjects as a small soft painterly illustration, drawn into out_painted/ so the flat icons stay
# as they are until the painted ones are picked; the cut and the keys stay the same.
PAINTED_HEAD = "masterpiece, best quality, score_7, safe, no humans, simple background, {tag}"
PAINTED_TAIL = ("It is an icon for a fantasy role-playing game, painted as a small illustration in a soft painterly "
                "style with gentle shading, rich muted colors and light from the upper left. The single object is "
                "large and centered and fills almost the whole square, on a plain flat {word} background with no "
                "vignette.")  # the trial of 2026-11-11: «fills most» drew small things, a vignette spoiled the cut
PAINTED_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
                    "chromatic aberration, text, letters, watermark, signature, border, frame, multiple objects, "
                    "duplicate, human, person, face, hands, photo, 3d render, flat color, minimalism, vector art, "
                    "vignette, gradient background, small object")
STYLES = ("flat", "painted")  # flat: every icon as before; painted: each kind by its family (FAMILY)
# The painted style follows the families of BG3's icons (docs/design/ux/bg3-icons.md, the author 2026-11-11): a thing is
# a painted object cut out of its background; a spell, a feature or an act is a bright glowing emblem on a tile of
# cracked stone, which the model draws as a rounded tile on black, so the same cut leaves the tile with clear corners;
# a condition is that tile in a circle. The colour of the emblem is the subject's own (make_jobs.py: damage, then
# school), so the sentences of subjects.json serve both families.
GLYPH_HEAD = "masterpiece, best quality, score_7, safe, no humans, lineart, glowing, emblem, stone texture, "
GLYPH_TAIL = ("It is an ability icon for a fantasy role-playing game. The subject is drawn as one simple bold emblem "
              "of thin glowing lines with a white-hot core and a soft colored glow, like luminous chalk or molten "
              "metal inlaid in stone, with no solid fill. The emblem is large and centered on a square tile of dark "
              "brown rough cracked stone that fills the whole frame, a little darker toward its edges.")
# The A/B of 2026-11-11 on eight spells, picked by the author out of four: this first prompt, whose words the model does
# not quite follow — the tile floats on black with rounded corners and the emblem is a bright filled shape — and that
# reads best at 64 px. Rejected: glowing outlines on stone edge to edge (flatter), a sign engraved in a slab (darker),
# a dim subtle stone (the emblem shrank), a brick wall (busy).
GLYPH_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
                  "chromatic aberration, text, letters, watermark, signature, multiple objects, duplicate, human, "
                  "person, face, photo, 3d render, realistic, solid fill, flat color, plain background, "
                  "white background, scenery, landscape")
# The interface's buttons and the inventory's groups as BG3's skills: one embossed emblem of silver, no colour of its own,
# cut out like a thing (the trial of 2026-11-11).
RELIEF_HEAD = "masterpiece, best quality, score_7, safe, no humans, simple background, {tag}metallic, silver, emboss, "
RELIEF_TAIL = ("It is an interface icon for a fantasy role-playing game: the subject as one embossed emblem of polished "
               "silver metal, a raised relief with soft shading and bright highlights, light from the upper left, "
               "monochrome with no other colors. The single emblem is large and centered and fills almost the whole "
               "square, on a plain flat {word} background.")
RELIEF_NEGATIVE = PAINTED_NEGATIVE + ", colorful, gold, gem, glow"
FAMILIES = {  # a family → (head, tail, negative); the head's {tag} and the tail's {word} are the job's key
    "flat": (HEAD, TAIL, NEGATIVE),
    "object": (PAINTED_HEAD, PAINTED_TAIL, PAINTED_NEGATIVE),
    "glyph": (GLYPH_HEAD, GLYPH_TAIL, GLYPH_NEGATIVE),
    "medal": (GLYPH_HEAD, GLYPH_TAIL, GLYPH_NEGATIVE),
    "relief": (RELIEF_HEAD, RELIEF_TAIL, RELIEF_NEGATIVE),
}
FAMILY = {"spells": "glyph", "features": "glyph", "acts": "glyph", "traits": "glyph", "conditions": "medal",
          "ui": "relief", "groups": "relief", "marks": "flat"}  # a kind (or its head before «/») in the painted style
ICON = 128  # px of the final icon
NEAR, FAR = 38, 80  # colour distance from the background: cut below NEAR, kept above FAR, faded between
ROWS_PER_SHEET = 40

# Portraits (a job's `style: "portrait"`, v0.8.4.43.5): a bust on a dark muted background, kept whole in raw/; the
# game takes the face cut out of it (FACE of the frame's side), PORTRAIT px, WebP. The trial of 2026-11-11 with the
# author: the face fills the token's circle, the bust at 64 px is a speck. A job may carry its `seeds` and its
# `looks` (tags and a sentence per variant); a child's job drops «child» from the negative and adds `neg_add`.
P_HEAD = "masterpiece, best quality, score_7, safe, "
P_TAIL = ("It is a character portrait for a fantasy role-playing game: head and shoulders, the face centered and turned "
          "slightly to the side, looking at the viewer, soft painterly shading, on a plain dark muted background.")
P_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
              "chromatic aberration, text, letters, watermark, signature, border, frame, multiple people, 2girls, "
              "2boys, nsfw, nude, full body, cropped head, hands, weapon in front of face, blood, gore, "
              "loli, shota, child")  # the last three as in the event images' MINOR_NEG (llm_server images.py)
FACE = (0.14, 0.02, 0.86, 0.74)  # a fixed square over the head and a little of the shoulders (the author, 2026-11-11)
PORTRAIT = 256
TRIM = 0.03  # of a glyph's tile kept whole, each side
FLAT = 0.6  # a glyph's frame whose border is this flat (a share near its median) floats on a ground: cut out


# --- Forge ----------------------------------------------------------------------------------------------------------


def call(url: str, path: str, body: dict | None = None, timeout: int = 900):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def model_settings(url: str, checkpoint: str) -> dict:
    """The checkpoint's title and the module paths Forge wants, found by name; exits when one is missing."""
    titles = [str(m["title"]) for m in call(url, "/sdapi/v1/sd-models")]
    found = [t for t in titles if checkpoint.lower() in t.lower()]
    if not found:
        sys.exit(f"no checkpoint like «{checkpoint}» on {url}: {titles}")
    paths = {str(m["model_name"]): str(m["filename"]) for m in call(url, "/sdapi/v1/sd-modules")}
    missing = [m for m in MODULES if m not in paths]
    if missing:
        sys.exit(f"no modules {missing} on {url}")
    return {"sd_model_checkpoint": found[0], "forge_additional_modules": [paths[m] for m in MODULES]}


def portrait(job: dict) -> bool:
    return job.get("style") == "portrait"


def seeds_of(job: dict, seeds: list[int]) -> list[int]:
    return list(job.get("seeds") or seeds)


def family(job: dict, style: str = "flat") -> str:
    """How an icon is drawn and cut: flat, object (cut out), glyph (a tile cut out of black), medal (the tile in a
    circle), relief (silver, cut out), portrait."""
    if portrait(job):
        return "portrait"
    if style == "flat":
        return "flat"
    return FAMILY.get(job["kind"], FAMILY.get(job["kind"].split("/")[0], "object"))


def prompt_of(job: dict, key: str, style: str = "flat") -> str:
    tag, word = KEYS[key]
    head, tail, _ = FAMILIES[family(job, style)]
    return head.format(tag=tag) + job["tags"] + ".\n" + job["sentence"] + " " + tail.format(word=word)


def full_prompt(job: dict, n: int, a: argparse.Namespace) -> str:
    look = job["looks"][n - 1] if job.get("looks") else job
    if portrait(job):
        return P_HEAD + look["tags"] + ".\n" + look["sentence"] + " " + P_TAIL
    return prompt_of({**look, "kind": job["kind"]}, job.get("key") if job.get("key") in KEYS else a.bg,
                     getattr(a, "style", "flat"))


def negative_of(job: dict, style: str = "flat") -> str:
    if not portrait(job):
        return FAMILIES[family(job, style)][2]
    drop = set(job.get("neg_drop", []))
    tags = [t.strip() for t in P_NEGATIVE.split(",") if t.strip() not in drop]
    return ", ".join(tags + [t.strip() for t in job.get("neg_add", "").split(",") if t.strip()])


def stamp_of(job: dict, n: int, a: argparse.Namespace) -> str:
    """What a variant was drawn from: the prompt, and the negative of a portrait (a child's differs) or a painted one."""
    text = full_prompt(job, n, a)
    style = getattr(a, "style", "flat")
    return text + "\n\nNEGATIVE: " + negative_of(job, style) if portrait(job) or style != "flat" else text


def stale(out: Path, job: dict, n: int, seed: int, stamp_text: str) -> bool:
    """Not drawn yet, drawn from another prompt (its subject was edited after a `git pull`) or from another seed (a
    variant reseeded in picks.json: no raw frame of the new seed). A variant drawn before the stamps existed counts as
    current."""
    raw, v = paths(out, job, n, seed)
    if not v.exists() or not raw.exists():
        return True
    stamp = v.with_suffix(".txt")
    return stamp.exists() and stamp.read_text(encoding="utf-8") != stamp_text


def draw(url: str, settings: dict, job: dict, n: int, seed: int, a: argparse.Namespace) -> Image.Image:
    body = {"prompt": full_prompt(job, n, a), "negative_prompt": negative_of(job, getattr(a, "style", "flat")), "steps": a.steps, "cfg_scale": a.cfg,
            "sampler_name": a.sampler, "width": a.side, "height": a.side, "seed": seed,
            "override_settings": settings, "override_settings_restore_afterwards": False}
    for attempt in range(5):  # Forge restarted or busy: wait and try again
        try:
            img = call(url, "/sdapi/v1/txt2img", body)["images"][0]
            return Image.open(io.BytesIO(base64.b64decode(img))).convert("RGB")
        except (urllib.error.URLError, TimeoutError, ConnectionError, KeyError) as exc:
            print(f"  forge: {exc}; again in {30 * (attempt + 1)} s", flush=True)
            time.sleep(30 * (attempt + 1))
    raise RuntimeError("forge does not answer")


# --- the cut --------------------------------------------------------------------------------------------------------


def cut(raw: Image.Image) -> Image.Image:
    """The flat background → transparent: its colour is the border's median, a pixel near it and joined to the border
    is background, the edge fades by the distance; then shrunk to ICON."""
    im = raw.convert("RGB").resize((256, 256), Image.LANCZOS)
    w, h = im.size
    px = im.load()
    border = [px[x, y] for x in range(w) for y in (0, h - 1)] + [px[x, y] for y in range(h) for x in (0, w - 1)]
    bg = tuple(median(c[i] for c in border) for i in range(3))
    alpha = [[255] * w for _ in range(h)]
    seen = [[False] * w for _ in range(h)]
    q = deque((x, y) for x in range(w) for y in (0, h - 1))
    q.extend((x, y) for y in range(h) for x in (0, w - 1))
    while q:
        x, y = q.popleft()
        if seen[y][x]:
            continue
        seen[y][x] = True
        c = px[x, y]
        d = ((c[0] - bg[0]) ** 2 + (c[1] - bg[1]) ** 2 + (c[2] - bg[2]) ** 2) ** 0.5
        if d >= FAR:
            continue
        alpha[y][x] = 0 if d <= NEAR else int(255 * (d - NEAR) / (FAR - NEAR))
        if d <= NEAR:
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx]:
                    q.append((nx, ny))
    a = Image.new("L", (w, h))
    a.putdata([v for row in alpha for v in row])
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))  # eat the fringe, soften the edge
    out = im.convert("RGBA")
    out.putalpha(a)
    return out.resize((ICON, ICON), Image.LANCZOS)


def face(raw: Image.Image) -> Image.Image:
    """A portrait's face cut out of the bust, PORTRAIT px square."""
    w, h = raw.size
    box = (int(w * FACE[0]), int(h * FACE[1]), int(w * FACE[2]), int(h * FACE[3]))
    return raw.convert("RGB").crop(box).resize((PORTRAIT, PORTRAIT), Image.LANCZOS)


def tile(raw: Image.Image) -> Image.Image:
    """A glyph's tile: mostly it floats on a flat ground (black, at times white) and is cut out like a thing; when the
    stone fills the frame (a few frames do) the border is textured, and the tile is kept whole, a thin smeared edge
    trimmed, so the cut does not eat the stone."""
    w, h = raw.size
    rgb = raw.convert("RGB")
    px = rgb.load()
    border = [px[x, y] for x in range(0, w, 4) for y in (0, h - 1)] + [px[x, y] for y in range(0, h, 4) for x in (0, w - 1)]
    bg = [median(c[i] for c in border) for i in range(3)]
    flat = sum(1 for c in border if sum((c[i] - bg[i]) ** 2 for i in range(3)) ** 0.5 <= NEAR) / len(border)
    if flat >= FLAT:
        return cut(raw)
    m = int(w * TRIM)
    return rgb.convert("RGBA").crop((m, m, w - m, h - m)).resize((ICON, ICON), Image.LANCZOS)


def medal(raw: Image.Image) -> Image.Image:
    """A condition's medal: the glyph's tile in a circle inscribed in the tile itself (it floats smaller than the
    frame), with a soft edge, transparent outside."""
    im = tile(raw)
    alpha = im.getchannel("A")
    x0, y0, x1, y1 = alpha.getbbox() or (0, 0, ICON, ICON)
    side = min(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    k = 4  # drawn 4× larger and shrunk: a smooth edge
    mask = Image.new("L", (ICON * k, ICON * k))
    r = side / 2 * k - 2
    ImageDraw.Draw(mask).ellipse((cx * k - r, cy * k - r, cx * k + r, cy * k + r), fill=255)
    im.putalpha(ImageChops.multiply(alpha, mask.resize((ICON, ICON), Image.LANCZOS)))
    return im


def save_variant(raw: Image.Image, job: dict, path: Path, style: str = "flat") -> None:
    how = family(job, style)
    if how == "portrait":
        face(raw).save(path, "WEBP", quality=88, method=6)
    elif how == "glyph":
        tile(raw).save(path)
    elif how == "medal":
        medal(raw).save(path)
    else:
        cut(raw).save(path)


# --- files ----------------------------------------------------------------------------------------------------------


def paths(out: Path, job: dict, n: int, seed: int) -> tuple[Path, Path]:
    """The raw frame and the variant; a portrait's id may be a path itself (people/<race>/<sex>/<age>)."""
    d = out / job["kind"]
    ext = "webp" if portrait(job) else "png"
    return d / "raw" / f"{job['id']}__{seed}.png", d / "variants" / f"{job['id']}__{n}.{ext}"


def sheets(out: Path, jobs: list[dict], seeds: list[int]) -> None:
    font = ImageFont.load_default()
    by_kind: dict[str, list[dict]] = {}
    for j in jobs:
        by_kind.setdefault(j["kind"], []).append(j)
    cell, label = ICON + 8, 150
    for kind, js in by_kind.items():
        drawn = [j for j in js if any(paths(out, j, n, s)[1].exists() for n, s in enumerate(seeds_of(j, seeds), 1))]
        cols = max((len(seeds_of(j, seeds)) for j in drawn), default=0)
        for page in range(0, len(drawn), ROWS_PER_SHEET):
            rows = drawn[page:page + ROWS_PER_SHEET]
            sheet = Image.new("RGB", (label + cols * cell + 8, len(rows) * cell + 8), (24, 20, 16))
            pen = ImageDraw.Draw(sheet)
            for r, j in enumerate(rows):
                y = 8 + r * cell
                pen.text((8, y + ICON // 2 - 12), j["id"][:24], fill=(220, 210, 190), font=font)
                pen.text((8, y + ICON // 2 + 2), j.get("name", "")[:24], fill=(150, 140, 120), font=font)
                for c, seed in enumerate(seeds_of(j, seeds)):
                    n = c + 1
                    v = paths(out, j, n, seed)[1]
                    if not v.exists():
                        continue
                    slot = Image.new("RGBA", (ICON, ICON), (38, 36, 44, 255))
                    slot.alpha_composite(Image.open(v).convert("RGBA").resize((ICON, ICON), Image.LANCZOS))
                    x = label + c * cell
                    sheet.paste(slot.convert("RGB"), (x, y))
                    pen.text((x + 3, y + 2), str(n), fill=(255, 255, 255), font=font)
            name = out / kind / f"sheet_{kind.replace('/', '_')}_{page // ROWS_PER_SHEET + 1}.png"
            name.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(name)
            print("sheet", name, flush=True)


def recut(out: Path, jobs: list[dict], seeds: list[int], style: str = "flat") -> None:
    """Every variant cut again from its raw frame (a changed FACE or cut), the stamps kept: nothing is drawn."""
    done = 0
    for j in jobs:
        for n, seed in enumerate(seeds_of(j, seeds), 1):
            raw_path, cut_path = paths(out, j, n, seed)
            if raw_path.exists():
                save_variant(Image.open(raw_path), j, cut_path, style)
                done += 1
    print(f"{done} variants cut again", flush=True)


def pick(out: Path, jobs: list[dict], seeds: list[int], picks: str) -> None:
    by_id = {j["id"]: j for j in jobs}
    for one in filter(None, picks.split(",")):
        jid, _, n = one.partition("=")
        j = by_id.get(jid.strip())
        own = seeds_of(j, seeds) if j else seeds
        if j is None or portrait(j) or not n.strip().isdigit() or not 1 <= int(n) <= len(own):
            sys.exit(f"--pick {one}: an id of the icon jobs and a variant 1…{len(own)} (a portrait keeps all)")
        v = paths(out, j, int(n), own[int(n) - 1])[1]
        if not v.exists():
            sys.exit(f"--pick {one}: {v} is not drawn")
        shutil.copyfile(v, out / j["kind"] / f"{j['id']}.png")
        print("picked", jid, n, flush=True)


# --- main -----------------------------------------------------------------------------------------------------------


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("jobs", type=Path, help="the jobs file: {jobs: [{id, kind, name, tags, sentence, key}]}")
    p.add_argument("--out", type=Path, default=None, help="out/, or out_<style>/ for an icon style but flat")
    p.add_argument("--style", default="flat", choices=sorted(STYLES), help="an icon's style; a portrait has its own")
    p.add_argument("--url", default="http://127.0.0.1:7860", help="Forge with --api")
    p.add_argument("--checkpoint", default=CHECKPOINT, help="a part of the checkpoint's title")
    p.add_argument("--side", type=int, default=768)
    p.add_argument("--steps", type=int, default=20)
    p.add_argument("--cfg", type=float, default=4.5)
    p.add_argument("--sampler", default="ER SDE")
    p.add_argument("--seeds", default="11,22", help="one variant per seed")
    p.add_argument("--bg", default="dark", choices=sorted(KEYS), help="the background where a job names none")
    p.add_argument("--only", default="", help="kinds, comma-separated")
    p.add_argument("--ids", default="", help="ids, comma-separated")
    p.add_argument("--first", type=int, default=0, help="only the first N variants of each job (a trial)")
    p.add_argument("--redraw", action="store_true", help="draw the chosen ones again")
    p.add_argument("--sheets", action="store_true", help="only the contact sheets")
    p.add_argument("--recut", action="store_true", help="cut the variants again from the raw frames, nothing drawn")
    p.add_argument("--pick", default="", help="id=n,…: variant n becomes the icon")
    a = p.parse_args()
    a.out = a.out or HERE / ("out" if a.style == "flat" else f"out_{a.style}")

    jobs: list[dict] = json.loads(a.jobs.read_text(encoding="utf-8"))["jobs"]
    if a.only:
        jobs = [j for j in jobs if j["kind"] in a.only.split(",")]
    if a.ids:
        jobs = [j for j in jobs if j["id"] in a.ids.split(",")]
    seeds = [int(s) for s in a.seeds.split(",")]
    if a.pick:
        return pick(a.out, jobs, seeds, a.pick)
    if a.sheets:
        return sheets(a.out, jobs, seeds)
    if a.recut:
        return recut(a.out, jobs, seeds, a.style)

    todo = [(j, n, s) for j in jobs for n, s in enumerate(seeds_of(j, seeds), 1)
            if (not a.first or n <= a.first) and (a.redraw or stale(a.out, j, n, s, stamp_of(j, n, a)))]
    frames = sum(len(seeds_of(j, seeds)) for j in jobs)
    print(f"{len(jobs)} jobs, {frames} frames: {len(todo)} to draw at {a.side}px, {a.steps} steps", flush=True)
    if not todo:
        return sheets(a.out, jobs, seeds)
    settings = model_settings(a.url, a.checkpoint)
    print("model", settings["sd_model_checkpoint"], flush=True)
    started = time.time()
    for i, (job, n, seed) in enumerate(todo, 1):
        raw_path, cut_path = paths(a.out, job, n, seed)
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        cut_path.parent.mkdir(parents=True, exist_ok=True)
        t = time.time()
        raw = draw(a.url, settings, job, n, seed, a)
        raw.save(raw_path)
        save_variant(raw, job, cut_path, a.style)
        cut_path.with_suffix(".txt").write_text(stamp_of(job, n, a), encoding="utf-8")  # the stamp: redrawn when it changes
        icon = a.out / job["kind"] / f"{job['id']}.png"
        if not portrait(job) and (n == 1 or not icon.exists()):
            shutil.copyfile(cut_path, icon)
        left = (time.time() - started) / i * (len(todo) - i)
        print(f"[{i}/{len(todo)}] {job['kind']}/{job['id']} #{n} {time.time() - t:.0f}s, "
              f"left ~{left / 3600:.1f} h", flush=True)
    sheets(a.out, jobs, seeds)


if __name__ == "__main__":
    main()
