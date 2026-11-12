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
    python3 anima_gen.py jobs/icons.json --style painted --only acts --backend openrouter   # → out_painted_flux/, FLUX

`--backend openrouter` draws the same prompts by a model of OpenRouter (`--model`, FLUX 3 Klein by default, ~$0.009 a
frame) instead of Forge, a few at a time (`--parallel`), on the key OPENROUTER_API_KEY of the environment or of the
repo's .env; into its own folder (out_<style>_<model>/), picked into its own picks file. It has no negative prompt, and
its seed is taken but not kept to: a variant drawn again comes out another picture. The cut is the same.

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
import math
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent

CHECKPOINT = "anima-aesthetic"  # a part of the checkpoint's title on Forge
OPENROUTER_IMAGES = "https://openrouter.ai/api/v1/images"
OPENROUTER_MODEL = "black-forest-labs/flux-3-image-klein"  # the acts by it read their gestures far better (2026-11-12)
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
# A combat ability on a plate of metal, a spell on stone (the author, 2026-11-12): the glyph's own words with the stone
# turned into worn steel with rivets, cut as a tile.
PLATE_HEAD = "masterpiece, best quality, score_7, safe, no humans, lineart, glowing, emblem, metal texture, steel, silver, "
PLATE_TAIL = ("It is an ability icon for a fantasy role-playing game. The subject is drawn as one simple bold emblem "
              "of thin glowing lines with a white-hot core and a soft colored glow, like luminous chalk or molten "
              "metal inlaid in steel, with no solid fill. The emblem is large and centered on a square plate of "
              "brushed silver-grey steel with a cool blue tint and a rivet in each corner that fills the whole frame, "
              "a little darker toward its edges.")  # dark worn steel (the first trial) melted into the brown stone
MEDAL_HEAD = "masterpiece, best quality, score_7, safe, no humans, flat color, simple, icon, symbol, emblem, circle, gold rim, "
MEDAL_TAIL = ("It is a status icon for a fantasy role-playing game. One round badge: a thin polished gold ring around "
              "a dark flat round field. Inside it the subject is drawn as one simple bold emblem in its own bright "
              "colours with a thick dark outline, with no shading, no texture and no small details, large and "
              "centered, so that it reads at a glance. The badge is large and centered and fills almost the whole "
              "square, on a plain flat dark background.")
MEDAL_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
                  "chromatic aberration, text, letters, watermark, signature, multiple objects, duplicate, photo, "
                  "3d render, realistic, painterly, detailed, relief, embossed, coin, glowing, neon, square, tile, "
                  "stone, scenery, landscape")
# a condition (the author, 2026-11-12): the glyph's tile in a circle was «не очень», a chased gold coin put the sign in
# gold on gold and too detailed — «простая эмблемка в золотом кружочке»
INK_HEAD = "masterpiece, best quality, score_7, safe, no humans, sketch, lineart, monochrome, thick lines, metal texture, steel, "
INK_TAIL = ("It is an action icon for a fantasy role-playing game. The subject is drawn large as a rough sketch of a few "
            "thick dark ink brush strokes with no fill, bold and simple like a quick chalk drawing, cropped by the frame "
            "where it comes in from the edge. It is drawn on a square plate of brushed silver-grey steel with a cool "
            "blue tint and a rivet in each corner that fills the whole frame, a little darker toward its edges.")
INK_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
                "chromatic aberration, text, letters, watermark, signature, multiple objects, duplicate, face, photo, "
                "3d render, realistic, colorful, glowing, neon, painterly, solid fill, scenery, landscape, nsfw")
# a basic act (the author, 2026-11-12): the glowing sign was not clear, a flat pictogram too bare, an illustration
# missed every gesture; BG3's acts (looked at) are hands in three-quarter view from the lower left in a few rough
# strokes with no fill — in dark ink on our steel the author took it over white chalk and over strokes on dark
BRONZE_HEAD = "masterpiece, best quality, score_7, safe, no humans, lineart, glowing, emblem, metal texture, bronze, "
BRONZE_TAIL = ("It is a trait icon for a fantasy role-playing game. The subject is drawn as one simple bold emblem of "
               "thin glowing lines with a white-hot core and a soft colored glow, like luminous chalk or molten metal "
               "inlaid in bronze, with no solid fill. The emblem is large and centered on a square plate of polished "
               "warm bronze with a little green patina in its recesses and a rivet in each corner that fills the whole "
               "frame, a little darker toward its edges.")  # a race's trait apart from the steel of features and acts
GOLD_HEAD = "masterpiece, best quality, score_7, safe, no humans, lineart, monochrome, gold, simple, icon, symbol, black background, "
GOLD_TAIL = ("It is an interface icon for a fantasy role-playing game. The subject is drawn as one simple elegant line "
             "drawing in pale warm gold on a plain black background: clean even lines of a bold medium thickness, only "
             "outlines with the inside of every shape left black, no fill and no shading, only a few lines, like a "
             "fine engraving, large and centered, filling most of the frame, so that it reads at a small size.")
GOLD_NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, blurry, jpeg artifacts, "
                 "chromatic aberration, text, letters, watermark, signature, multiple objects, duplicate, frame, "
                 "border, circle frame, square frame, tile, plate, photo, 3d render, realistic, painterly, colorful, "
                 "solid fill, filled shape, white fill, solid color, shading, gradient, glow, neon, scenery, landscape, "
                 "nsfw")
# the interface's buttons in the author's style of the interface, thin gold lines on a dark panel (2026-11-12): a line
# drawing on black, its brightness the alpha, recoloured to one gold and fitted to the square (`gold`). The subjects
# were written for painted things: their colours are dropped from the prompt (a «pale compass rose» came filled)
COLOURS = re.compile(r"\b(white|black|grey|gray|slate|blue|red|green|yellow|brown|gold|golden|silver|cream|orange|"
                     r"purple|violet|pale|dark|bright|tan|beige|amber|crimson|teal|pink)\b[ -]?", re.I)
FAMILIES = {  # a family → (head, tail, negative); the head's {tag} and the tail's {word} are the job's key
    "flat": (HEAD, TAIL, NEGATIVE),
    "object": (PAINTED_HEAD, PAINTED_TAIL, PAINTED_NEGATIVE),
    "glyph": (GLYPH_HEAD, GLYPH_TAIL, GLYPH_NEGATIVE),
    "plate": (PLATE_HEAD, PLATE_TAIL, GLYPH_NEGATIVE),
    "bronze": (BRONZE_HEAD, BRONZE_TAIL, GLYPH_NEGATIVE),
    "ink": (INK_HEAD, INK_TAIL, INK_NEGATIVE),
    "medal": (MEDAL_HEAD, MEDAL_TAIL, MEDAL_NEGATIVE),
    "gold": (GOLD_HEAD, GOLD_TAIL, GOLD_NEGATIVE),
}
TILED = ("glyph", "plate", "bronze", "ink")  # the families cut as a tile by its shape
# A kind (or its head before «/») in the painted style; the rest — items, groups — is an object. The interface's
# buttons and the inventory's groups were tried as a silver relief like BG3's skills (2026-11-11): the model drew a
# painted thing with a silver detail, and the author took painted things; the buttons go with the interface's thin
# gold lines since (2026-11-12).
FAMILY = {"spells": "glyph", "features": "plate", "acts": "ink", "traits": "bronze", "conditions": "medal",
          "marks": "flat", "ui": "gold"}  # stone spells, steel abilities, ink acts on steel, bronze traits (2026-11-12)
GOLD = (222, 196, 140)  # the gold of a line icon, its brightest lines toward GOLD_LIT
GOLD_LIT = (250, 238, 205)
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
TILE_WORK, TILE_FAR = 256, 24  # a glyph's tile is found at this side, by this distance from the ground
TILT_MIN, TILT_MAX = 1.5, 30  # degrees: a tile askew by this much is turned straight
FLAT = 0.6  # a glyph's frame whose border is this flat (a share near its ground) floats on a ground: cut out
GROUND_FITS = 3  # the ground's surface fitted again and again to the border near the last one
OUTSIDE = 0.03  # a frame with more of its outside-the-tile this far from the ground is stone all over: kept whole


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
    circle), portrait."""
    if portrait(job):
        return "portrait"
    if style == "flat":
        return "flat"
    return FAMILY.get(job["kind"], FAMILY.get(job["kind"].split("/")[0], "object"))


def uncolour(text: str) -> str:
    """A subject without its colours, for a family that draws in one colour."""
    text = COLOURS.sub("", text)
    text = re.sub(r"\s*,(\s*,)+", ",", text)
    return re.sub(r"\s{2,}", " ", text).strip(" ,")


def prompt_of(job: dict, key: str, style: str = "flat") -> str:
    tag, word = KEYS[key]
    fam = family(job, style)
    head, tail, _ = FAMILIES[fam]
    tags, sentence = (uncolour(job["tags"]), uncolour(job["sentence"])) if fam == "gold" else (job["tags"],
                                                                                              job["sentence"])
    return head.format(tag=tag) + tags + ".\n" + sentence + " " + tail.format(word=word)


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
    """What a variant was drawn from: the prompt, and the negative of a portrait (a child's differs) or a painted one;
    a model of OpenRouter by its name (it takes no negative)."""
    text = full_prompt(job, n, a)
    if getattr(a, "backend", "forge") == "openrouter":
        return text + "\n\nMODEL: " + a.model
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


def openrouter_key() -> str:
    """OPENROUTER_API_KEY of the environment, or of the repo's .env when this folder sits in the repo; never printed."""
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    env = HERE.parents[1] / ".env"
    if not key and env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            name, _, value = line.strip().partition("=")
            if name == "OPENROUTER_API_KEY" and value.strip():
                key = value.strip().strip('"').strip("'")
    if not key:
        sys.exit("--backend openrouter: no OPENROUTER_API_KEY in the environment or in .env")
    return key


def draw_openrouter(job: dict, n: int, seed: int, a: argparse.Namespace) -> tuple[Image.Image, float]:
    """A frame by a model of OpenRouter and its cost in USD; the prompt is the same as Forge's, with no negative."""
    body = json.dumps({"model": a.model, "prompt": full_prompt(job, n, a), "n": 1, "aspect_ratio": "1:1",
                       "seed": seed}).encode()
    for attempt in range(5):
        req = urllib.request.Request(OPENROUTER_IMAGES, data=body, headers={
            "Authorization": f"Bearer {a.key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                data = json.loads(r.read())
            first = data["data"][0]
            if first.get("b64_json"):
                raw = base64.b64decode(first["b64_json"])
            else:
                with urllib.request.urlopen(first["url"], timeout=120) as r:
                    raw = r.read()
            cost = float((data.get("usage") or {}).get("cost") or 0)
            return Image.open(io.BytesIO(raw)).convert("RGB"), cost
        except urllib.error.HTTPError as exc:
            if exc.code in (400, 401, 402, 403, 404):  # a wrong model, no key, no money: nothing to wait for
                raise RuntimeError(f"openrouter: HTTP {exc.code} {exc.read()[:200]!r}") from None
            print(f"  openrouter: HTTP {exc.code}; again in {20 * (attempt + 1)} s", flush=True)
        except (urllib.error.URLError, TimeoutError, ConnectionError, KeyError, IndexError, ValueError) as exc:
            print(f"  openrouter: {exc}; again in {20 * (attempt + 1)} s", flush=True)
        time.sleep(20 * (attempt + 1))
    raise RuntimeError("openrouter does not answer")


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


def _terms(u: float, t: float) -> tuple[float, ...]:
    return (1.0, u, t, u * u, t * t, u * t)


def _fit(rows: list[tuple[float, ...]], ys: list[float]) -> list[float]:
    """Least squares by the normal equations, solved by Gaussian elimination (no numpy on the Forge machine)."""
    n = len(rows[0])
    a = [[sum(r[i] * r[j] for r in rows) + (1e-6 if i == j else 0.0) for j in range(n)]
         + [sum(r[i] * y for r, y in zip(rows, ys))] for i in range(n)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(a[r][c]))
        a[c], a[p] = a[p], a[c]
        for r in range(n):
            if r != c and a[c][c]:
                f = a[r][c] / a[c][c]
                a[r] = [x - f * y for x, y in zip(a[r], a[c])]
    return [a[i][n] / a[i][i] if a[i][i] else 0.0 for i in range(n)]


def _at(coef: list[list[float]], terms: tuple[float, ...]) -> tuple[float, float, float]:
    return tuple(sum(c * t for c, t in zip(ch, terms)) for ch in coef)


def _ground(rgb: Image.Image) -> tuple[tuple, float]:
    """The ground of a frame: a smooth surface of colour fitted to its border, and the share of the border near it
    (1.0 is a ground with no texture). A painted ground is often a gradient or a vignette — the steel plates of
    2026-11-12 lay on a dark blue sliding into teal, and a ground of one colour kept it as the plate's own. The surface
    is a quadratic in the place per channel, fitted only to the border that is ground: it starts from the border's
    median, and each fit takes the border within FAR of the last one — a plate touching the frame's edge stays out.
    Inside the frame the surface keeps to the colours of that border: a quadratic bulging brighter in the middle took
    the dark stone at a tile's edge for ground. The ground is (the surface, its lowest and its highest colour)."""
    w, h = rgb.size
    px = rgb.load()
    pts = [(x, y) for x in range(0, w, 4) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 4) for x in (0, w - 1)]
    cols = [px[p] for p in pts]
    terms = [_terms(x / (w - 1), y / (h - 1)) for x, y in pts]
    coef = [[float(median(c[ch] for c in cols)), 0.0, 0.0, 0.0, 0.0, 0.0] for ch in range(3)]
    ground = list(range(len(pts)))
    for _ in range(GROUND_FITS):
        dist = [math.dist(cols[i], _at(coef, terms[i])) for i in range(len(pts))]
        near = [i for i in range(len(pts)) if dist[i] <= FAR]
        if len(near) < len(pts) // 10:
            break
        ground = near
        coef = [_fit([terms[i] for i in ground], [cols[i][ch] for i in ground]) for ch in range(3)]
    dist = [math.dist(cols[i], _at(coef, terms[i])) for i in range(len(pts))]
    lo = tuple(min(cols[i][ch] for i in ground) for ch in range(3))
    hi = tuple(max(cols[i][ch] for i in ground) for ch in range(3))
    return (coef, lo, hi), sum(1 for d in dist if d <= NEAR) / len(pts)


def _off_ground(rgb: Image.Image, ground: tuple) -> Image.Image:
    """How far each place of a frame stands from its ground (`_ground`), TILE_WORK px, grey."""
    coef, lo, hi = ground
    k = 64  # the surface is smooth: drawn small, stretched
    surface = Image.new("RGB", (k, k))
    surface.putdata([tuple(max(lo[ch], min(hi[ch], int(v))) for ch, v in
                           enumerate(_at(coef, _terms(x / (k - 1), y / (k - 1))))) for y in range(k) for x in range(k)])
    small = rgb.resize((TILE_WORK, TILE_WORK), Image.LANCZOS)
    return ImageChops.difference(small, surface.resize(small.size, Image.BILINEAR)).convert("L")


def _hull(points: list[tuple[int, int]]) -> list[tuple[float, float]]:
    """The convex hull of points, counter-clockwise (Andrew's monotone chain)."""
    pts = sorted(set(points))
    if len(pts) < 3:
        return [(float(x), float(y)) for x, y in pts]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return [(float(x), float(y)) for x, y in lower[:-1] + upper[:-1]]


def _tilt(hull: list[tuple[float, float]]) -> float:
    """The angle in degrees (−45…45) of the smallest rectangle around a hull: how far a tile lies askew."""
    best, angle = None, 0.0
    for (x0, y0), (x1, y1) in zip(hull, hull[1:] + hull[:1]):
        t = math.atan2(y1 - y0, x1 - x0)
        c, s = math.cos(t), math.sin(t)
        xs = [x * c + y * s for x, y in hull]
        ys = [-x * s + y * c for x, y in hull]
        area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        if best is None or area < best:
            best, angle = area, math.degrees(t)
    return (angle + 45) % 90 - 45


def _tile_hull(diff: Image.Image, side: int) -> list[tuple[float, float]]:
    """The hull of the tile in a frame of `side` px, by its distance from the ground (`_off_ground`): what is far from
    the ground, its cracks closed, the biggest piece of it."""
    fg = diff.point(lambda v: 255 if v > TILE_FAR else 0).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    n = TILE_WORK
    on = [v > 0 for v in fg.tobytes()]
    seen = [False] * (n * n)
    biggest: list[int] = []
    for start in range(n * n):  # the biggest piece: the tile, not a spark of its glow
        if not on[start] or seen[start]:
            continue
        piece, stack = [], [start]
        seen[start] = True
        while stack:
            i = stack.pop()
            piece.append(i)
            x, y = i % n, i // n
            for j in (i - 1 if x else -1, i + 1 if x < n - 1 else -1, i - n if y else -1, i + n if y < n - 1 else -1):
                if j >= 0 and on[j] and not seen[j]:
                    seen[j] = True
                    stack.append(j)
        if len(piece) > len(biggest):
            biggest = piece
    rows: dict[int, list[int]] = {}
    for i in biggest:
        rows.setdefault(i // n, []).append(i % n)
    edge = [(min(xs), y) for y, xs in rows.items()] + [(max(xs) + 1, y) for y, xs in rows.items()]
    k = side / n
    return [(x * k, y * k) for x, y in _hull(edge)]


def _outside(diff: Image.Image, hull: list[tuple[float, float]], side: int) -> float:
    """The share of a frame outside the tile's hull that is far from the ground: about none when the tile floats on a
    ground; the cracks and edges of slabs around the glyph when the stone fills the frame (thaumaturgy, major image of
    2026-11-12: a border of smooth slabs passed for a ground)."""
    k = diff.size[0] / side
    inside = Image.new("L", diff.size)
    ImageDraw.Draw(inside).polygon([(x * k, y * k) for x, y in hull], fill=255)
    far, ins = diff.point(lambda v: 255 if v > TILE_FAR else 0).tobytes(), inside.tobytes()
    out = sum(1 for i in ins if not i)
    return sum(1 for f, i in zip(far, ins) if f and not i) / max(1, out)


def _whole(rgb: Image.Image) -> Image.Image:
    """A frame of stone all over, kept whole, a thin smeared edge trimmed."""
    w, h = rgb.size
    m = int(w * TRIM)
    return rgb.convert("RGBA").crop((m, m, w - m, h - m)).resize((ICON, ICON), Image.LANCZOS)


def tile(raw: Image.Image) -> Image.Image:
    """A glyph's tile cut out by its shape, not by colour: the cracks of its stone are as dark as the ground around it,
    so a colour cut ate holes in it (the night run of 2026-11-11). The tile is the convex hull of what stands out from
    the ground; a tile lying askew is turned straight; every tile is cropped to its own square, so all are one size.
    When the stone fills the frame (its border is not flat, or the outside of the tile is textured) the frame is
    kept whole."""
    rgb = raw.convert("RGB")
    w, h = rgb.size
    ground, flat = _ground(rgb)
    if flat < FLAT:
        return _whole(rgb)
    diff = _off_ground(rgb, ground)
    hull = _tile_hull(diff, w)
    if len(hull) < 3:
        return cut(raw)
    if _outside(diff, hull, w) > OUTSIDE:  # slabs of stone smooth at the edge: the frame is stone, not a ground
        return _whole(rgb)
    tilt = _tilt(hull)
    if TILT_MIN <= abs(tilt) <= TILT_MAX:
        rgb = rgb.rotate(tilt, resample=Image.BICUBIC)
        hull = _tile_hull(diff.rotate(tilt, resample=Image.BILINEAR), w)  # what the turn brings in is no tile
    mask = Image.new("L", rgb.size)
    ImageDraw.Draw(mask).polygon(hull, fill=255)
    mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.2))  # no dark fringe, a soft edge
    x0, y0, x1, y1 = mask.getbbox() or (0, 0, w, h)
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out.crop(box).resize((ICON, ICON), Image.LANCZOS)


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


def gold(raw: Image.Image) -> Image.Image:
    """A line icon on black: its brightness over the ground is the alpha, its colour one gold (whatever the model
    tinted it), the drawing fitted to the square with the same margin for every icon."""
    im = raw.convert("RGB").resize((256, 256), Image.LANCZOS)
    lum = im.convert("L")
    w, h = lum.size
    border = [lum.getpixel((x, y)) for x in range(w) for y in (0, h - 1)] + \
             [lum.getpixel((x, y)) for y in range(h) for x in (0, w - 1)]
    lo = median(border) + 14
    hi = lo + 80
    alpha = lum.point(lambda v: 0 if v <= lo else 255 if v >= hi else int((v - lo) * 255 / (hi - lo)))
    lit = lum.point(lambda v: 0 if v <= hi else min(255, int((v - hi) * 255 / max(1, 255 - hi))))
    out = Image.composite(Image.new("RGB", (w, h), GOLD_LIT), Image.new("RGB", (w, h), GOLD), lit).convert("RGBA")
    out.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 24 else 0).getbbox()
    if box:
        out = out.crop(box)
    side = round(max(out.size) / 0.84)  # 8% of margin each side
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(out, ((side - out.width) // 2, (side - out.height) // 2))
    return square.resize((ICON, ICON), Image.LANCZOS)


def save_variant(raw: Image.Image, job: dict, path: Path, style: str = "flat") -> None:
    how = family(job, style)
    if how == "portrait":
        face(raw).save(path, "WEBP", quality=88, method=6)
    elif how in TILED:
        tile(raw).save(path)
    elif how == "medal":
        medal(raw).save(path)
    elif how == "gold":
        gold(raw).save(path)
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
    p.add_argument("--family", default="", help="kind=family,…: a trial of another family for a kind (painted)")
    p.add_argument("--backend", default="forge", choices=("forge", "openrouter"), help="who draws")
    p.add_argument("--model", default=OPENROUTER_MODEL, help="the model of OpenRouter (--backend openrouter)")
    p.add_argument("--parallel", type=int, default=0, help="frames at a time: 1 on Forge, 4 on OpenRouter")
    a = p.parse_args()
    by_model = "_" + a.model.split("/")[-1].split("-")[0] if a.backend == "openrouter" else ""  # out_painted_flux/
    a.out = a.out or HERE / (("out" if a.style == "flat" else f"out_{a.style}") + by_model)
    a.parallel = a.parallel or (4 if a.backend == "openrouter" else 1)
    for one in filter(None, a.family.split(",")):
        kind, _, fam = one.partition("=")
        if fam not in FAMILIES:
            sys.exit(f"--family {one}: a family of {sorted(FAMILIES)}")
        FAMILY[kind] = fam

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
    how = f"by {a.model}" if a.backend == "openrouter" else f"at {a.side}px, {a.steps} steps"
    print(f"{len(jobs)} jobs, {frames} frames: {len(todo)} to draw {how} → {a.out}", flush=True)
    if not todo:
        return sheets(a.out, jobs, seeds)
    if a.backend == "openrouter":
        a.key = openrouter_key()

        def render(job: dict, n: int, seed: int) -> tuple[Image.Image, float]:
            return draw_openrouter(job, n, seed, a)
    else:
        settings = model_settings(a.url, a.checkpoint)
        print("model", settings["sd_model_checkpoint"], flush=True)

        def render(job: dict, n: int, seed: int) -> tuple[Image.Image, float]:
            return draw(a.url, settings, job, n, seed, a), 0.0

    def one(job: dict, n: int, seed: int) -> tuple[float, float]:
        raw_path, cut_path = paths(a.out, job, n, seed)
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        cut_path.parent.mkdir(parents=True, exist_ok=True)
        t = time.time()
        raw, cost = render(job, n, seed)
        raw.save(raw_path)
        save_variant(raw, job, cut_path, a.style)
        cut_path.with_suffix(".txt").write_text(stamp_of(job, n, a), encoding="utf-8")  # the stamp: redrawn when it changes
        icon = a.out / job["kind"] / f"{job['id']}.png"
        if not portrait(job) and (n == 1 or not icon.exists()):
            shutil.copyfile(cut_path, icon)
        return time.time() - t, cost

    started, spent = time.time(), 0.0
    with ThreadPoolExecutor(max_workers=a.parallel) as pool:
        running = {pool.submit(one, *t): t for t in todo}
        for i, done in enumerate(as_completed(running), 1):
            job, n, _ = running[done]
            took, cost = done.result()
            spent += cost
            left = (time.time() - started) / i * (len(todo) - i)
            paid = f", ${spent:.3f} so far" if a.backend == "openrouter" else ""
            print(f"[{i}/{len(todo)}] {job['kind']}/{job['id']} #{n} {took:.0f}s, left ~{left / 3600:.1f} h{paid}",
                  flush=True)
    sheets(a.out, jobs, seeds)


if __name__ == "__main__":
    main()
