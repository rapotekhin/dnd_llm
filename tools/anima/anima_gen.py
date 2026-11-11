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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

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
ICON = 128  # px of the final icon
NEAR, FAR = 38, 80  # colour distance from the background: cut below NEAR, kept above FAR, faded between
ROWS_PER_SHEET = 40


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


def prompt_of(job: dict, key: str) -> str:
    tag, word = KEYS[key]
    return HEAD.format(tag=tag) + job["tags"] + ".\n" + job["sentence"] + " " + TAIL.format(word=word)


def full_prompt(job: dict, a: argparse.Namespace) -> str:
    return prompt_of(job, job.get("key") if job.get("key") in KEYS else a.bg)


def stale(out: Path, job: dict, n: int, seed: int, prompt: str) -> bool:
    """Not drawn yet, or drawn from another prompt: its subject was edited after a `git pull`. A variant drawn
    before the stamps existed counts as current."""
    v = paths(out, job, n, seed)[1]
    if not v.exists():
        return True
    stamp = v.with_suffix(".txt")
    return stamp.exists() and stamp.read_text(encoding="utf-8") != prompt


def draw(url: str, settings: dict, job: dict, seed: int, a: argparse.Namespace) -> Image.Image:
    body = {"prompt": full_prompt(job, a), "negative_prompt": NEGATIVE, "steps": a.steps, "cfg_scale": a.cfg,
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


# --- files ----------------------------------------------------------------------------------------------------------


def paths(out: Path, job: dict, n: int, seed: int) -> tuple[Path, Path]:
    d = out / job["kind"]
    return d / "raw" / f"{job['id']}__{seed}.png", d / "variants" / f"{job['id']}__{n}.png"


def sheets(out: Path, jobs: list[dict], seeds: list[int]) -> None:
    font = ImageFont.load_default()
    by_kind: dict[str, list[dict]] = {}
    for j in jobs:
        by_kind.setdefault(j["kind"], []).append(j)
    cell, label = ICON + 8, 150
    for kind, js in by_kind.items():
        drawn = [j for j in js if any(paths(out, j, n, s)[1].exists() for n, s in enumerate(seeds, 1))]
        for page in range(0, len(drawn), ROWS_PER_SHEET):
            rows = drawn[page:page + ROWS_PER_SHEET]
            sheet = Image.new("RGB", (label + len(seeds) * cell + 8, len(rows) * cell + 8), (24, 20, 16))
            pen = ImageDraw.Draw(sheet)
            for r, j in enumerate(rows):
                y = 8 + r * cell
                pen.text((8, y + ICON // 2 - 12), j["id"][:24], fill=(220, 210, 190), font=font)
                pen.text((8, y + ICON // 2 + 2), j.get("name", "")[:24], fill=(150, 140, 120), font=font)
                for c, seed in enumerate(seeds):
                    n = c + 1
                    v = paths(out, j, n, seed)[1]
                    if not v.exists():
                        continue
                    slot = Image.new("RGBA", (ICON, ICON), (38, 36, 44, 255))
                    slot.alpha_composite(Image.open(v).convert("RGBA"))
                    x = label + c * cell
                    sheet.paste(slot.convert("RGB"), (x, y))
                    pen.text((x + 3, y + 2), str(n), fill=(255, 255, 255), font=font)
            name = out / kind / f"sheet_{kind.replace('/', '_')}_{page // ROWS_PER_SHEET + 1}.png"
            name.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(name)
            print("sheet", name, flush=True)


def pick(out: Path, jobs: list[dict], seeds: list[int], picks: str) -> None:
    by_id = {j["id"]: j for j in jobs}
    for one in filter(None, picks.split(",")):
        jid, _, n = one.partition("=")
        j = by_id.get(jid.strip())
        if j is None or not n.strip().isdigit() or not 1 <= int(n) <= len(seeds):
            sys.exit(f"--pick {one}: an id of the jobs and a variant 1…{len(seeds)}")
        v = paths(out, j, int(n), seeds[int(n) - 1])[1]
        if not v.exists():
            sys.exit(f"--pick {one}: {v} is not drawn")
        shutil.copyfile(v, out / j["kind"] / f"{j['id']}.png")
        print("picked", jid, n, flush=True)


# --- main -----------------------------------------------------------------------------------------------------------


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("jobs", type=Path, help="the jobs file: {jobs: [{id, kind, name, tags, sentence, key}]}")
    p.add_argument("--out", type=Path, default=HERE / "out")
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
    p.add_argument("--redraw", action="store_true", help="draw the chosen ones again")
    p.add_argument("--sheets", action="store_true", help="only the contact sheets")
    p.add_argument("--pick", default="", help="id=n,…: variant n becomes the icon")
    a = p.parse_args()

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

    todo = [(j, n, s) for j in jobs for n, s in enumerate(seeds, 1) if a.redraw or stale(a.out, j, n, s, full_prompt(j, a))]
    print(f"{len(jobs)} icons x {len(seeds)} variants: {len(todo)} to draw at {a.side}px, {a.steps} steps", flush=True)
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
        raw = draw(a.url, settings, job, seed, a)
        raw.save(raw_path)
        cut(raw).save(cut_path)
        cut_path.with_suffix(".txt").write_text(full_prompt(job, a), encoding="utf-8")  # the stamp: redrawn when it changes
        icon = a.out / job["kind"] / f"{job['id']}.png"
        if n == 1 or not icon.exists():
            shutil.copyfile(cut_path, icon)
        left = (time.time() - started) / i * (len(todo) - i)
        print(f"[{i}/{len(todo)}] {job['kind']}/{job['id']} #{n} {time.time() - t:.0f}s, "
              f"left ~{left / 3600:.1f} h", flush=True)
    sheets(a.out, jobs, seeds)


if __name__ == "__main__":
    main()
