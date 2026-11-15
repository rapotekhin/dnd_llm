"""Experiment: a map's grid as a flat colour mask (32 px a square) → image models repaint it as a top-down battle map.

    python tools/mask_maps/mask_maps.py masks
    python tools/mask_maps/mask_maps.py draw [--only model,room]
    python tools/mask_maps/mask_maps.py sheet
"""
from __future__ import annotations

import base64
import io
import json
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "mask_maps"  # masks, frames and sheets stay local (art is not on GitHub)
OUT.mkdir(parents=True, exist_ok=True)
MAPS = ROOT / "build" / "playtest" / "map_compare" / "maps.json"
sys.path.insert(0, str(ROOT / "tools" / "anima"))
import anima_gen  # noqa: E402

PX = 32
import os
NAT = os.environ.get("MASK_PALETTE") == "nat"
LOOSE = os.environ.get("MASK_LOOSE") == "1"
SMOOTH = os.environ.get("MASK_SMOOTH") == "1"
SUF = ("_nat" if NAT else "") + ("_loose" if LOOSE else "") + ("_smooth" if SMOOTH else "")
MODELS = {
    "flux-klein": "black-forest-labs/flux-3-image-klein",
    "flux": "black-forest-labs/flux-3-image",
    "gpt-image": "openai/gpt-image-2.6-sunburst",
    "krea-edit": "krea/k3-edit",
    "nano-banana": "google/gemini-nano-banana-2.1",
}
GROUND = {
    "grass": (110, 170, 70), "high_grass": (70, 130, 40), "dirt": (165, 120, 70), "cobble": (175, 175, 165),
    "water": (60, 120, 210), "deep_water": (20, 50, 140), "mud": (90, 65, 40), "farmland": (130, 85, 40),
    "planks": (200, 150, 90), "flagstone": (140, 140, 150), "wall": (40, 40, 40), "roof": (150, 50, 40),
    "cliff_top": (120, 110, 100), "": (0, 0, 0),
}
THING = {  # colour of a thing's footprint
    "table": (120, 60, 20), "bench": (230, 200, 60), "stool": (230, 200, 60), "barrel": (255, 120, 0), "crate": (255, 120, 0),
    "counter": (180, 0, 180), "hearth": (255, 0, 0), "stage": (0, 200, 200), "plant_pot": (0, 255, 0), "well": (0, 220, 255),
    "stall": (255, 0, 140), "standing_stone": (255, 255, 255),
}
DOOR = (255, 230, 0)
if NAT:  # near-natural tones: the model should texture them, not keep them
    GROUND = {
        "grass": (96, 138, 62), "high_grass": (72, 112, 46), "dirt": (138, 104, 70), "cobble": (148, 142, 132),
        "water": (56, 96, 128), "deep_water": (30, 58, 92), "mud": (86, 70, 50), "farmland": (102, 76, 50),
        "planks": (160, 118, 76), "flagstone": (122, 118, 112), "wall": (66, 62, 58), "roof": (128, 72, 52),
        "cliff_top": (112, 104, 94), "": (0, 0, 0),
    }
    THING = {
        "table": (98, 62, 36), "bench": (132, 92, 54), "stool": (132, 92, 54), "barrel": (118, 80, 46), "crate": (140, 108, 66),
        "counter": (110, 70, 42), "hearth": (150, 64, 36), "stage": (150, 112, 72), "plant_pot": (82, 128, 62), "well": (112, 112, 116),
        "stall": (168, 62, 52), "standing_stone": (150, 150, 144),
    }
    DOOR = (122, 82, 44)
    GROUND.update({"rock": (52, 48, 46), "cave": (118, 106, 92), "still_water": (48, 78, 88)})
    THING.update({"forge": (160, 70, 38), "workbench": (120, 86, 52), "anvil": (58, 58, 64), "shelf": (104, 74, 44),
                  "chest": (126, 86, 42), "altar": (196, 190, 176), "vein": (176, 146, 72), "timber": (112, 84, 54),
                  "campfire": (184, 92, 44), "stump": (108, 80, 50)})
RUBBLE = (112, 106, 98)
FOAM = (206, 226, 232)
SAY_GROUND = {  # a ground's colour in words and what it is; the auto legend takes those on the map
    "grass": "green = grass", "high_grass": "darker green = tall grass", "dirt": "brown = bare earth and worn paths",
    "cobble": "light grey band = a cobbled road", "water": "blue = a river or a pond", "deep_water": "dark blue = deep water",
    "mud": "dark brown = mud", "farmland": "dark brown beds = vegetable beds",
    "planks": "light brown = a wooden plank floor or a bridge",
    "flagstone": "grey = a stone flagstone floor", "wall": "dark grey-brown = thick stone walls", "roof": "red-brown = a roof",
    "cliff_top": "grey-brown = a rocky cliff edge", "rock": "very dark grey = solid rock, the walls of the cave",
    "cave": "grey-brown = the cave floor of packed earth and stones", "still_water": "dark blue-grey = still underground water",
}
SAY_THING = {
    "table": "large dark-brown blocks = wooden tables", "bench": "lighter brown blocks = wooden benches (pews)",
    "stool": "small lighter brown blocks = stools", "barrel": "small brown blocks = barrels", "crate": "tan blocks = wooden crates",
    "counter": "a long brown block = a counter", "hearth": "a reddish block = a stone fireplace",
    "stage": "a light wooden block = a small stage", "plant_pot": "a small green block = a potted plant",
    "well": "a grey block = a stone well", "stall": "a red block = a market stall with a cloth awning",
    "standing_stone": "outlined grey squares = standing stones",
    "forge": "an orange-red block = a stone smithing forge with glowing coals",
    "workbench": "a brown block = a wooden workbench with tools", "anvil": "a small dark iron-grey block = an iron anvil",
    "shelf": "a dark brown block at a wall = a tall shelf with goods", "chest": "brown blocks = wooden chests with iron bands",
    "altar": "a pale stone block = a stone altar with candles",
    "vein": "ochre blocks at the rock = veins of ore glittering in the rock",
    "timber": "a brown block = wooden mine support timbers", "campfire": "an orange block = a campfire in a ring of stones",
    "stump": "small brown blocks = tree stumps",
}
SAY_PROP = {"door": "small brown squares in walls = wooden doors", "stairs": "small light-grey marks at the walls = stairs",
            "tree": "dark green discs = tree crowns (each disc one tree, large merged discs a grove)", "grove": None,
            "boulder": "grey discs = boulders", "fence": "a thin dark-brown line = a wattle fence",
            "rubble": "small grey heaps = rubble of fallen stones",
            "waterfall": "a pale foam strip = a waterfall falling off the cliff"}
TREE = (20, 80, 20)
BOULDER = (100, 100, 100)
FENCE = (90, 50, 20)

LEGEND = {
    "brod-tavern-hall": ("the common hall of a rustic medieval fantasy tavern with a small kitchen behind it",
        "warm wooden plank floor = tan; stone flagstone floor of the kitchen = grey; thick stone walls = dark charcoal grey; "
        "doors = yellow squares in the walls; long wooden tables = dark brown; benches and stools = mustard yellow; "
        "the bar counter = magenta; barrels and crates = orange; the fireplace hearth = red; a small bard's stage = cyan; "
        "a potted plant = bright green; stairs up and down = small light-grey marks at the walls"),
    "brod-square": ("the market square of a small medieval fantasy village seen from above, houses around it",
        "grass = green; cobblestone paths = light grey; bare dirt = brown; vegetable garden beds = dark brown; a small pond = blue; "
        "house roofs (thatch or wooden shingle) = red-brown, each block one house; stone house walls = dark charcoal grey; "
        "house doors = yellow; a wooden fence = dark brown thin line; boulders = grey; "
        "a stone well = cyan; a striped market stall = pink; a wooden stage = teal"),
    "pushcha-edge": ("the edge of a dark old forest by a river: meadow, a dirt road, a ring of standing stones",
        "grass meadow = green; tall grass = darker green; dirt = brown; mud = dark brown; the cobbled road across = light grey; "
        "river and pond = blue, deep water = dark blue; a wooden bridge = tan; trees = dark green discs (each disc one tree, "
        "large discs groves); boulders = grey discs; standing stones of a stone circle = white squares; "
        "a cliff edge = grey-brown"),
}


WHAT = {
    "brod-smithy": "a village blacksmith's smithy with a packed earth floor",
    "brod-temple": "a small stone temple of a harvest goddess with an altar and pews",
    "brod-tavern-cellar": "the stone cellar of a tavern full of stores",
    "mine-gallery": "a gallery of an old mine dug through rock, with a flooded pool",
    "outpost-crypt": "a small crypt under a ruined outpost",
    "pushcha-trail": "a trail through an old dark forest",
    "pushcha-glade": "a forest glade with a campfire by a stream",
    "outpost-road": "a cobbled road through a wooded valley with a river, a waterfall and a stone circle",
    "outpost-yard": "the yard of a ruined stone outpost: crumbling buildings, rubble, a well",
    "mine-entrance": "the entrance tunnels of a mine dug into a rocky hillside",
}


def auto_legend(m: dict) -> str:
    parts = [SAY_GROUND[g] for g in dict.fromkeys(m["grounds"]) if g in SAY_GROUND]
    seen = set()
    for pr in m["props"]:
        k = next((k for k in SAY_PROP if pr["id"].startswith(k)), None)
        if k and SAY_PROP[k] and k not in seen:
            seen.add(k)
            parts.append(SAY_PROP[k])
    parts += [SAY_THING[b] for b in dict.fromkeys(t["body"] for t in m["things"]) if b in SAY_THING]
    return "; ".join(parts)


if NAT:
    LEGEND = {
        "brod-tavern-hall": (LEGEND["brod-tavern-hall"][0],
            "light brown = wooden plank floor; grey = stone flagstone floor of the kitchen; dark grey-brown = thick stone walls; "
            "brown squares in the walls = wooden doors; every block with a dark outline is one piece of furniture: "
            "the large dark-brown blocks are long wooden tables, the small lighter-brown blocks beside them are benches and stools, "
            "the long brown block is the bar counter, the reddish block in a wall is the stone fireplace with a fire, "
            "the light wooden block is a small bard's stage, the small tan blocks are barrels and crates, the green one a potted plant; "
            "small light-grey marks at the walls are stairs up and down"),
        "brod-square": (LEGEND["brod-square"][0],
            "green = grass; light grey = cobblestone paths; brown = bare dirt; dark brown = vegetable garden beds; blue = a small pond; "
            "red-brown blocks = house roofs (thatch or wooden shingle), each block one house; dark grey-brown = stone house walls; "
            "brown squares in walls = doors; a thin dark-brown line = a wooden fence; grey discs = boulders; "
            "outlined blocks are objects: the grey one a stone well, the red one a market stall with a cloth awning, "
            "the light wooden one a wooden stage, the tan ones crates"),
        "pushcha-edge": (LEGEND["pushcha-edge"][0],
            "green = grass meadow; darker green = tall grass; brown = dirt; dark brown = mud; light grey = the cobbled road across; "
            "blue = river and pond, darker blue = deep water; light brown = a wooden bridge; dark green discs = tree crowns (each disc one tree, "
            "large discs groves); grey discs = boulders; outlined grey squares = seven standing stones of an ancient stone circle "
            "around an empty grassy centre (nothing inside the ring); light brown only at the south river = a wooden footbridge; "
            "grey-brown = a cliff edge"),
    }


def maps() -> dict:
    old = OUT / "maps_v1.json"
    out = json.loads(old.read_text(encoding="utf-8")) if old.exists() else {}
    out.update(json.loads(MAPS.read_text(encoding="utf-8")))
    return out


HARD = ("wall", "roof", "flagstone", "planks", "farmland", "")


ROADS = {"=": "cobble", ",": "dirt"}  # a row's character that is a road, and its ground


def _field(rng, h: int, w: int, step: int, amp: float):
    import numpy as np
    g = rng.uniform(-1, 1, (h // step + 2, w // step + 2)).astype("float32")
    return np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC)) * amp


def _warp(a, dx, dy):
    import numpy as np
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    return a[np.clip((yy + dy).round().astype(int), 0, h - 1), np.clip((xx + dx).round().astype(int), 0, w - 1)]


def smooth(im: Image.Image, hard: Image.Image, roads: dict, seed: int = 3) -> Image.Image:
    """Nature warped by a wide and a fine noise and rounded; each road bent by the wide one only and blurred to a smooth band;
    the hard grounds (walls, roofs, floors, a bridge) kept as they are."""
    import numpy as np
    from PIL import ImageFilter
    a = np.asarray(im).copy()
    h, w = a.shape[:2]
    rng = np.random.default_rng(seed)
    bx, by = _field(rng, h, w, 112, 18), _field(rng, h, w, 112, 18)
    fx, fy = _field(rng, h, w, 40, 6), _field(rng, h, w, 40, 6)
    soft = a.copy()
    flat = a.reshape(-1, 3)
    hm0 = (np.asarray(hard) == 0).reshape(-1)
    cols, counts = np.unique(flat[hm0], axis=0, return_counts=True)
    under = cols[counts.argmax()] if len(cols) else np.array(GROUND["grass"], dtype=a.dtype)
    for rm in roads.values():  # a road's square is grass under it; the road is laid again on top
        soft[np.asarray(rm) > 0] = under
    soft[np.asarray(hard) > 0] = under  # so a wall never runs out into the grass
    out = np.asarray(Image.fromarray(_warp(soft, bx + fx, by + fy)).filter(ImageFilter.ModeFilter(15))).copy()
    for g, rm in roads.items():
        r = Image.fromarray(_warp(np.asarray(rm), bx * 0.7, by * 0.7)).filter(ImageFilter.GaussianBlur(7))
        out[np.asarray(r) > 110] = GROUND[g]
    hm = np.asarray(hard) > 0
    out[hm] = a[hm]
    return Image.fromarray(out)


def mask(m: dict) -> Image.Image:
    w, h = int(m["w"]), len(m["rows"])
    im = Image.new("RGB", (w * PX, h * PX), (0, 0, 0))
    d = ImageDraw.Draw(im)
    hard = Image.new("L", im.size, 0)
    hd = ImageDraw.Draw(hard)
    roads = {g: Image.new("L", im.size, 0) for g in set(ROADS.values())}
    for i, g in enumerate(m["grounds"]):
        x, y = i % w, i // w
        ch = m["rows"][y][x] if x < len(m["rows"][y]) else " "
        if g == "":
            continue
        d.rectangle([x * PX, y * PX, x * PX + PX - 1, y * PX + PX - 1], fill=GROUND.get(g, (255, 0, 255)))
        if g in HARD:
            hd.rectangle([x * PX, y * PX, x * PX + PX - 1, y * PX + PX - 1], fill=255)
        if ROADS.get(ch) == g:
            ImageDraw.Draw(roads[g]).rectangle([x * PX, y * PX, x * PX + PX - 1, y * PX + PX - 1], fill=255)
    if SMOOTH:
        im = smooth(im, hard, roads)
        d = ImageDraw.Draw(im)
    for p in m["props"]:
        x, y = p["i"] % w, p["i"] // w
        pid = p["id"]
        box = [x * PX, y * PX, x * PX + PX - 1, y * PX + PX - 1]
        if pid == "door":
            d.rectangle(box, fill=DOOR)
        elif pid.startswith("stairs"):
            d.rectangle([box[0] + 6, box[1] + 6, box[2] - 6, box[3] - 6], fill=(220, 220, 220))
        elif pid.startswith("rubble"):
            import math
            import random
            rnd = random.Random(p["i"])
            pts = [(box[0] + 16 + rnd.uniform(8, 14) * math.cos(a / 7 * 6.283),
                    box[1] + 16 + rnd.uniform(8, 14) * math.sin(a / 7 * 6.283)) for a in range(7)]
            d.polygon(pts, fill=RUBBLE)
        elif pid.startswith("waterfall"):
            d.rectangle(box, fill=FOAM)
        elif pid == "fence":
            d.rectangle([box[0], box[1] + 13, box[2], box[1] + 18], fill=FENCE)
        elif pid.startswith(("tree", "grove", "boulder")):
            n = 2 if ("pair" in pid or "grove" in pid or "ridge" in pid) else 1
            hh = 2 if ("grove" in pid or "ridge" in pid) else 1
            col = TREE if pid.startswith(("tree", "grove")) else BOULDER
            if SMOOTH:  # a crown of its own size, off the centre a little; a boulder a little uneven
                import random
                rnd = random.Random(p["i"])
                cx, cy = x * PX + n * PX / 2 + rnd.uniform(-5, 5), y * PX + hh * PX / 2 + rnd.uniform(-5, 5)
                rx = (n * PX / 2) * (rnd.uniform(1.0, 1.55) if col == TREE else rnd.uniform(0.7, 0.95))
                ry = (hh * PX / 2) * (rnd.uniform(1.0, 1.55) if col == TREE else rnd.uniform(0.6, 0.9))
                if col == TREE and n == hh:
                    ry = rx * rnd.uniform(0.9, 1.1)
                d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=col)
            else:
                d.ellipse([box[0] + 3, box[1] + 3, x * PX + n * PX - 4, y * PX + hh * PX - 4], fill=col)
    bodies = json.loads((ROOT / "game" / "data" / "rules.json").read_text(encoding="utf-8"))["things"]["bodies"]
    for t in m["things"]:
        sw, sh = bodies.get(t["body"], {}).get("size", [1, 1])
        x, y = int(t["x"]), int(t["y"])
        d.rectangle([x * PX + 2, y * PX + 2, (x + sw) * PX - 3, (y + sh) * PX - 3], fill=THING.get(t["body"], (255, 0, 255)),
                    outline=(28, 20, 14) if NAT else None, width=2 if NAT else 0)
    return im


SHAPE_WORDS = {
    "open": "Nature never follows the square grid: draw winding river banks with eroded earthen edges and exposed roots, "
            "meandering worn dirt paths with soft frayed edges, irregular patches of grass, mud and tall grass blending into "
            "each other, big round tree canopies overlapping their neighbours with soft cast shadows, scattered rocks, grass "
            "tufts, fallen leaves and twigs. Only buildings, walls and furniture stay straight.",
    "building": "An interior seen from above with the roof removed: the walls stay straight and thick, every piece of furniture "
                "stays on its own squares at its own size; the floor is worn and lived in — cracks, scuffs, dust, straw, small "
                "clutter (tools, sacks, candles, cobwebs in the corners) only where the plan leaves the floor empty.",
    "tunnels": "Natural cave and mine tunnels never follow the square grid: rough rock walls with jagged irregular edges, "
               "fallen stones and gravel along them, uneven floor of packed earth and rubble, wooden support beams, puddles; "
               "keep every passage and chamber where the plan has it, as wide as the plan has it.",
}


def prompt(room: str, m: dict) -> str:
    what, legend = LEGEND[room] if room in LEGEND else (WHAT[room], auto_legend(m))
    w, h = int(m["w"]), len(m["rows"])
    if LOOSE:
        return (f"Paint a finished top-down battle map for a fantasy tabletop RPG: {what}. The attached colour-coded image is "
                f"only a rough plan of {w}×{h} squares of 5 feet: keep where each area, building, road, body of water and object is, "
                "but do NOT copy its blocky outlines. " + SHAPE_WORDS.get(str(m.get("shape")), SHAPE_WORDS["open"]) + " "
                f"Colour legend of the plan: {legend}. "
                "Style: hand-illustrated fantasy battle map as sold by indie map makers — clean dark ink outlines, rich painterly "
                "shading, warm natural light, soft shadows, seen straight down, no perspective, no grid lines, no text, no labels, "
                "no watermark, no frame.")
    return (f"Repaint this colour-coded layout into a finished top-down orthographic battle map for a fantasy tabletop RPG: {what}. "
            f"The layout is a grid of {w}×{h} squares of 5 feet; keep every shape exactly where it is, with the same size "
            f"and outline — walls, doors, paths, water and every object stay in their squares. Colour legend: {legend}. "
            "Black outside the walls is empty void, keep it black. "
            + ("The flat colours only mark materials: replace every one with a real texture, keep none of them flat. " if NAT else "")
            + "Style: hand-painted, detailed, realistic textures, "
            "soft daylight from above, seen straight down, no perspective, no grid lines, no text, no labels, no frame.")


ASPECTS = {"1:1": 1.0, "3:4": 0.75, "4:5": 0.8, "2:3": 2 / 3, "4:3": 4 / 3, "5:4": 1.25, "3:2": 1.5, "16:9": 16 / 9}


def aspect(m: dict) -> str:
    r = int(m["w"]) / len(m["rows"])
    return min(ASPECTS, key=lambda k: abs(ASPECTS[k] - r))


def _b64(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def _post(url: str, body: dict, key: str) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json",
        "X-Title": "Between the Rolls mask maps"})
    with urllib.request.urlopen(req, timeout=400) as r:
        return json.loads(r.read())


import threading
_TL = threading.local()


def by_images(model: str, text: str, ref: Image.Image, asp: str, key: str) -> tuple[Image.Image, float, dict]:
    data = _post(anima_gen.OPENROUTER_IMAGES, {"model": model, "prompt": text, "n": 1, "aspect_ratio": ("3:4" if asp == "4:5" and "gpt" in model else asp),
        **({} if model == "black-forest-labs/flux-3-image" else {"seed": getattr(_TL, "seed", 7)}),
        "input_references": [{"type": "image_url", "image_url": {"url": _b64(ref)}}]}, key)
    first = data["data"][0]
    raw = base64.b64decode(first["b64_json"]) if first.get("b64_json") else urllib.request.urlopen(first["url"], timeout=120).read()
    return Image.open(io.BytesIO(raw)).convert("RGB"), float((data.get("usage") or {}).get("cost") or 0), data.get("usage") or {}


def by_chat(model: str, text: str, ref: Image.Image, asp: str, key: str) -> tuple[Image.Image, float, dict]:
    data = _post("https://openrouter.ai/api/v1/chat/completions", {"model": model, "modalities": ["image", "text"],
        "image_config": {"aspect_ratio": asp},
        "messages": [{"role": "user", "content": [{"type": "text", "text": text},
                                                  {"type": "image_url", "image_url": {"url": _b64(ref)}}]}]}, key)
    msg = data["choices"][0]["message"]
    url = msg["images"][0]["image_url"]["url"]
    raw = base64.b64decode(url.split(",", 1)[1])
    return Image.open(io.BytesIO(raw)).convert("RGB"), float((data.get("usage") or {}).get("cost") or 0), data.get("usage") or {}


def one(name: str, room: str, key: str, seed: int = 7) -> dict:
    tag = "" if seed == 7 else f"_s{seed}"
    m = maps()[room]
    ref = Image.open(OUT / f"mask_{room}{SUF}.png")
    k = -(-512 // min(ref.size))  # a frame smaller than the model takes grows by a whole factor
    if k > 1:
        ref = ref.resize((ref.width * k, ref.height * k), Image.NEAREST)
    text, asp = prompt(room, m), aspect(m)
    _TL.seed = seed
    t = time.time()
    errors = []
    for how in (by_images, by_chat):
        try:
            img, cost, usage = how(MODELS[name], text, ref, asp, key)
            img.save(OUT / f"{name}_{room}{SUF}{tag}.png")
            return {"model": name, "room": room, "palette": "nat" if NAT else "mask", "seed": seed, "cost": cost, "secs": round(time.time() - t, 1), "size": img.size,
                    "via": how.__name__, "usage": usage}
        except urllib.error.HTTPError as exc:
            errors.append(f"{how.__name__}: HTTP {exc.code} {exc.read()[:300]!r}")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{how.__name__}: {exc!r}"[:300])
    return {"model": name, "room": room, "error": errors}


def draw(only: str) -> None:
    key = anima_gen.openrouter_key()
    pick = [p for p in only.split(",") if p] if only else []
    seeds = [int(x) for x in os.environ.get("MASK_SEEDS", "7").split(",")]
    pm = [x for x in pick if x in MODELS] or list(MODELS)
    pr = [x for x in pick if x in maps()] or list(LEGEND)
    jobs = [(n, r, sd) for n in pm for r in pr for sd in seeds]
    log = OUT / "costs.jsonl"
    with ThreadPoolExecutor(6) as pool:
        for res in pool.map(lambda j: one(j[0], j[1], key, j[2]), jobs):
            print(json.dumps(res, ensure_ascii=False), flush=True)
            with log.open("a", encoding="utf-8") as f:
                f.write(json.dumps(res, ensure_ascii=False) + "\n")


def masks() -> None:
    for room, m in maps().items():
        mask(m).save(OUT / f"mask_{room}{SUF}.png")
        (OUT / f"prompt_{room}{SUF}.txt").write_text(prompt(room, m), encoding="utf-8")
        print(room, aspect(m))


def sheet() -> None:
    cols = ["mask", "ours", *MODELS]
    side = 512
    font = ImageFont.truetype("arial.ttf", 22)
    for room in LEGEND:
        im = Image.new("RGB", (len(cols) * (side + 8), side + 40), (25, 25, 25))
        d = ImageDraw.Draw(im)
        for c, name in enumerate(cols):
            path = (ROOT / "build/playtest/map_compare" / f"ours_{room}.png") if name == "ours" else OUT / f"{name}_{room}.png"
            if name == "mask":
                path = OUT / f"mask_{room}{SUF}.png"
            if path.exists():
                pic = Image.open(path).convert("RGB")
                pic.thumbnail((side, side))
                im.paste(pic, (c * (side + 8) + (side - pic.width) // 2, 40))
            d.text((c * (side + 8) + 6, 8), name, fill=(240, 240, 240), font=font)
        im.save(OUT / f"sheet_{room}.png")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "masks"
    {"masks": masks, "draw": lambda: draw(sys.argv[2] if len(sys.argv) > 2 else ""), "sheet": sheet}[cmd]()
