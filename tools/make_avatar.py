"""The project's avatar: a mosaic of game moments drawn by Anima on the own Forge, a big d20 in front.

    python tools/make_avatar.py                 # draw the missing frames, then compose → build/avatar/avatar.png
    python tools/make_avatar.py --compose-only  # only compose from the frames already drawn
    python tools/make_avatar.py --redraw 3,7    # draw these frames again
    python tools/make_avatar.py --compose-only --icon   # also the game's icon: game/icon.png and game/icon.ico

The frames are kept in build/avatar/frames/ and drawn once; a frame is redrawn only when asked.
"""
from __future__ import annotations

import argparse
import base64
import io
import itertools
import json
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "avatar"
FONT = ROOT / "game" / "assets" / "fonts" / "literata.ttf"

# The Ri-mix Anima settings of llm_server.config.SD_MODELS (v0.7.38.4).
CHECKPOINT = "riMixIllustriousAnima_riMixAnima.safetensors"
MODULES = ("qwen_image_vae.safetensors", "qwen_3_06b_base.safetensors")
QUALITY = ("masterwork, masterpiece, best quality, high quality, absurdres, highres, detailed, depth of field, "
           "high detail, very aesthetic, safe, adult, aged up, "
           "<lora:anima-base-1-masterpiece-v51:0.8> <lora:anima-highres-aesthetic-boost:0.8>")
NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, artist name, (lowres:1.2), (bad anatomy:1.4), "
            "bad hands, multiple views, jpeg artifacts, patreon logo, patreon username, web address, signature, "
            "watermark, text, nsfw, explicit, nude")

# Twenty moments of the game: adventure and the life beside it.
SCENES = (
    "1girl, 1boy, standing, counter, bar, talking, smile, indoors, tavern, barrel, fireplace, warm lighting, cowboy shot. "
    "A young woman in a travel cloak haggles with a stout bald innkeeper across the counter of a warm tavern.",
    "1boy, solo, wolf, animal, fighting, holding sword, snarling, outdoors, forest, path, dusk, dynamic angle, full body. "
    "A young warrior in leather armor swings a sword at a leaping grey wolf on a forest trail at dusk.",
    "1girl, solo, elf, pointy ears, silver hair, hooded robe, casting spell, fireball, outstretched hand, indoors, dungeon, "
    "stone wall, dark, glowing, full body, from below. An elf mage hurls a ball of fire down a dark stone corridor.",
    "1boy, solo, halfling, short, dark cloak, hood up, lockpicking, crouching, treasure chest, indoors, cellar, candle, "
    "dark, from side. A halfling thief picks the lock of an iron-bound chest by a single candle.",
    "1boy, solo, dwarf, long beard, braided beard, apron, muscular, hammering, anvil, sparks, indoors, forge, fire, "
    "glowing metal, cowboy shot. A dwarf smith strikes a glowing blade on an anvil, sparks flying.",
    "1girl, solo, blonde hair, white robe, holy symbol, kneeling, praying, altar, candles, indoors, church, stained glass, "
    "light rays, from side. A priestess kneels before a candlelit altar under a stained-glass window.",
    "1boy, solo, old man, wizard, grey beard, robe, reading, open book, glowing book, bookshelf, library, indoors, "
    "candlelight, upper body. An old wizard reads a glowing tome among tall dark bookshelves.",
    "crowd, festival, market, lantern, bunting, stalls, dancing, music, outdoors, town square, evening, wide shot. "
    "A harvest fair in a small town square, lanterns, stalls and dancing people in the evening.",
    "2boys, arena, fighting, sword, shield, crowd, cheering, outdoors, sand, sunlight, dynamic angle, wide shot. "
    "Two fighters clash with sword and shield on the sand of a wooden arena before a cheering crowd.",
    "1boy, solo, fishing, fishing rod, sitting, river, wooden pier, reeds, outdoors, sunrise, mist, from behind, wide shot. "
    "A lone traveler fishes from a wooden pier on a misty river at sunrise.",
    "1girl, solo, ranger, hooded cloak, holding bow, aiming, deer, animal, outdoors, forest, autumn, from side, wide shot. "
    "A hooded ranger aims a bow at a deer in an autumn forest.",
    "1boy, solo, tiefling, horns, tail, red skin, dark cloak, sneaking, rooftop, outdoors, town, night, full moon, "
    "from above. A tiefling rogue creeps over moonlit rooftops of a sleeping town.",
    "2girls, 1boy, campfire, sitting, night, stars, outdoors, forest clearing, bedroll, warm lighting, wide shot. "
    "Three adventurers rest by a campfire under the stars in a forest clearing.",
    "1boy, solo, monster, goblin, many goblins, ambush, holding axe, outdoors, ruins, forest, fog, dynamic angle. "
    "A half-orc warrior with an axe stands his ground as goblins leap from the fog of an old ruin.",
    "no humans, menhir, standing stone, glowing runes, outdoors, forest, fog, moonlight, night, wide shot. "
    "An ancient standing stone with glowing runes in a misty moonlit forest glade.",
    "1girl, 1boy, wedding, white dress, holding hands, smile, petals, outdoors, village, temple, daylight, cowboy shot. "
    "A village wedding before a small temple, petals falling on the happy couple.",
    "1boy, solo, merchant, shop, shelves, potions, scales, coins, smile, indoors, warm lighting, upper body. "
    "A cheerful merchant behind a counter full of potions, scales and coins.",
    "2boys, dice, playing, table, mugs, tavern, laughing, indoors, candlelight, night, from above. "
    "Two men throw dice on a tavern table, mugs of ale and coins between them.",
    "1girl, solo, horse, riding, cart, road, rain, mud, outdoors, hills, overcast, wide shot. "
    "A traveler drives a horse cart along a muddy road through rainy hills.",
    "1boy, solo, knight, armor, holding torch, dragon, monster, cave, treasure, gold, dark, from behind, wide shot. "
    "A knight with a torch faces a huge dragon sleeping on a hoard of gold in a dark cave.",
)


def forge(url: str, path: str, body: dict | None = None, timeout: float = 600) -> dict | list:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url.rstrip("/") + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def module_paths(url: str) -> list[str]:
    found = {}
    for m in forge(url, "/sdapi/v1/sd-modules", timeout=30):
        found[Path(str(m.get("filename", ""))).name] = m["filename"]
    missing = [n for n in MODULES if n not in found]
    if missing:
        sys.exit(f"Forge has no {', '.join(missing)}")
    return [found[n] for n in MODULES]


def draw_frames(url: str, redraw: set[int], seed: int) -> None:
    frames = OUT / "frames"
    frames.mkdir(parents=True, exist_ok=True)
    todo = [i for i in range(len(SCENES)) if i in redraw or not (frames / f"{i:02d}.png").exists()]
    if not todo:
        return
    modules = module_paths(url)
    for i in todo:
        body = {
            "prompt": f"{SCENES[i]}, {QUALITY}", "negative_prompt": NEGATIVE,
            "sampler_name": "Euler a", "steps": 20, "cfg_scale": 6, "distilled_cfg_scale": 3.5,
            "width": 832, "height": 1024, "seed": seed + i,
            "override_settings": {"sd_model_checkpoint": CHECKPOINT, "forge_additional_modules": modules},
            "override_settings_restore_afterwards": False,
        }
        print(f"frame {i + 1}/{len(SCENES)}…", flush=True)
        img = base64.b64decode(forge(url, "/sdapi/v1/txt2img", body)["images"][0].split(",", 1)[-1])
        (frames / f"{i:02d}.png").write_bytes(img)


# --- the mosaic -------------------------------------------------------------------

def mosaic(size: int, cols: int, rows: int, gap: int) -> Image.Image:
    canvas = Image.new("RGB", (size, size), (12, 10, 14))
    paths = sorted((OUT / "frames").glob("*.png"))[: cols * rows]
    for k, p in enumerate(paths):
        c, r = k % cols, k // cols
        x0, x1 = round(c * size / cols), round((c + 1) * size / cols)
        y0, y1 = round(r * size / rows), round((r + 1) * size / rows)
        w, h = x1 - x0 - gap, y1 - y0 - gap
        im = Image.open(p).convert("RGB")
        scale = max(w / im.width, h / im.height)
        im = im.resize((math.ceil(im.width * scale), math.ceil(im.height * scale)), Image.LANCZOS)
        left, top = (im.width - w) // 2, (im.height - h) // 2
        canvas.paste(im.crop((left, top, left + w, top + h)), (x0 + gap // 2, y0 + gap // 2))
    # Darker and a little muted, a vignette to the edges: the die stays the subject.
    canvas = ImageEnhance.Color(canvas).enhance(0.8)
    canvas = ImageEnhance.Brightness(canvas).enhance(0.62)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.hypot(xx - size / 2, yy - size / 2) / (size / 2)
    vignette = np.clip(1.05 - 0.45 * d ** 2, 0.35, 1.0)[..., None]
    return Image.fromarray((np.asarray(canvas, np.float32) * vignette).clip(0, 255).astype(np.uint8))


# --- the d20 ----------------------------------------------------------------------

PHI = (1 + 5 ** 0.5) / 2
BASE = np.array((150, 18, 32), np.float32)  # deep red resin
GOLD = (236, 190, 92)
EDGE = (250, 214, 130)


def icosahedron() -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    v = []
    for a, b in itertools.product((-1, 1), repeat=2):
        v += [(0, a, b * PHI), (a, b * PHI, 0), (b * PHI, 0, a)]
    v = np.array(v, np.float64)
    faces = [f for f in itertools.combinations(range(12), 3)
             if all(abs(np.linalg.norm(v[i] - v[j]) - 2) < 1e-6 for i, j in itertools.combinations(f, 2))]
    return v, faces


def rotation_to(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """The rotation that turns unit vector a onto unit vector b."""
    v, c = np.cross(a, b), float(np.dot(a, b))
    k = np.array(((0, -v[2], v[1]), (v[2], 0, -v[0]), (-v[1], v[0], 0)))
    return np.eye(3) + k + k @ k / (1 + c)


def rot(axis: str, deg: float) -> np.ndarray:
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    return {"x": np.array(((1, 0, 0), (0, c, -s), (0, s, c))),
            "y": np.array(((c, 0, s), (0, 1, 0), (-s, 0, c))),
            "z": np.array(((c, -s, 0), (s, c, 0), (0, 0, 1)))}[axis]


def face_numbers(v: np.ndarray, faces: list, front: int) -> dict[int, int]:
    """20 in front; opposite faces sum to 21, as on a real d20."""
    centers = np.array([v[list(f)].mean(0) for f in faces])
    normals = centers / np.linalg.norm(centers, axis=1)[:, None]
    near = normals @ normals[front]
    order = sorted(range(len(faces)), key=lambda i: -near[i])
    visible = order[:10]
    nums = dict(zip(visible, (20, 2, 8, 14, 18, 4, 16, 6, 12, 10)))
    for i in visible:
        opposite = int(np.argmin(normals @ normals[i]))
        nums[opposite] = 21 - nums[i]
    return nums


def number_texture(n: int, side: int) -> tuple[Image.Image, list[tuple[float, float]]]:
    """An equilateral triangle's texture with the number at its centroid; its corners: the apex, then the base."""
    h = side * math.sqrt(3) / 2
    tri = [(side / 2, 0.0), (0.0, h), (float(side), h)]
    tex = Image.new("RGBA", (side, math.ceil(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(tex)
    font = ImageFont.truetype(str(FONT), int(side * (0.30 if n < 10 else 0.27)))
    try:
        font.set_variation_by_axes([800])
    except (OSError, AttributeError):
        pass
    cx, cy = side / 2, h * 2 / 3 - side * 0.02
    d.text((cx, cy), str(n), font=font, fill=GOLD + (255,), anchor="mm",
           stroke_width=max(2, side // 90), stroke_fill=(70, 20, 10, 255))
    if n in (6, 9):  # the dot that tells 6 from 9
        bb = d.textbbox((cx, cy), str(n), font=font, anchor="mm")
        r = side * 0.018
        d.ellipse((bb[2] + r, bb[3] - 2 * r, bb[2] + 3 * r, bb[3]), fill=GOLD + (255,))
    return tex, tri


def affine_from(dst: list, src: list) -> tuple:
    """PIL's AFFINE coefficients: for a pixel of the output (dst) — where to read it in the texture (src)."""
    a = np.array([[x, y, 1] for x, y in dst], np.float64)
    sx = np.linalg.solve(a, [p[0] for p in src])
    sy = np.linalg.solve(a, [p[1] for p in src])
    return (*sx, *sy)


def draw_die(size: int, radius: float, tilt: tuple[float, float, float]) -> Image.Image:
    v, faces = icosahedron()
    centers = np.array([v[list(f)].mean(0) for f in faces])
    front = 0
    r = rotation_to(centers[front] / np.linalg.norm(centers[front]), np.array((0.0, 0.0, 1.0)))
    vr = v @ r.T
    # turn the front face so its apex points up
    apex = max(faces[front], key=lambda i: vr[i][1])
    a = math.degrees(math.atan2(vr[apex][0], vr[apex][1]))
    r = rot("x", tilt[0]) @ rot("y", tilt[1]) @ rot("z", a + tilt[2]) @ r
    nums = face_numbers(v, faces, front)
    p = v @ r.T
    scale = radius / np.linalg.norm(p, axis=1).max()
    c = size / 2

    def screen(pt: np.ndarray) -> tuple[float, float]:
        return c + pt[0] * scale, c - pt[1] * scale

    light = np.array((-0.35, 0.45, 0.82))
    light /= np.linalg.norm(light)
    half = light + np.array((0, 0, 1.0))
    half /= np.linalg.norm(half)
    die = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    drawn = []
    for i, f in enumerate(faces):
        pts = p[list(f)]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        n /= np.linalg.norm(n)
        if np.dot(n, pts.mean(0)) < 0:
            n = -n
        if n[2] <= 0.02:
            continue
        drawn.append((pts.mean(0)[2], i, n))
    tex_side = 512
    for _, i, n in sorted(drawn):
        f = faces[i]
        pts2 = [screen(p[j]) for j in f]
        diff = max(0.0, float(n @ light))
        spec = max(0.0, float(n @ half)) ** 40
        col = BASE * (0.32 + 0.78 * diff) + 255 * 0.55 * spec
        face = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        fd = ImageDraw.Draw(face)
        fd.polygon(pts2, fill=tuple(int(x) for x in col.clip(0, 255)) + (255,))
        # the number: its top toward the die's top for the front face, outward for the rest
        if i == 0:
            up = min(range(3), key=lambda k: pts2[k][1])
        else:
            up = max(range(3), key=lambda k: np.hypot(pts2[k][0] - c, pts2[k][1] - c))
        others = [k for k in range(3) if k != up]
        ax, ay = pts2[up]
        b0, b1 = pts2[others[0]], pts2[others[1]]
        if (b0[0] - ax) * (b1[1] - ay) - (b0[1] - ay) * (b1[0] - ax) > 0:
            others.reverse()
        dst = [pts2[up], pts2[others[0]], pts2[others[1]]]
        tex, tri = number_texture(nums[i], tex_side)
        # fade the numbers on faces seen at a slant, as paint does
        alpha = min(1.0, 0.25 + n[2] * 1.1)
        tex.putalpha(tex.getchannel("A").point(lambda x: int(x * alpha)))
        warped = tex.transform((size, size), Image.AFFINE, affine_from(dst, tri), resample=Image.BICUBIC)
        face.alpha_composite(warped)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).polygon(pts2, fill=255)
        die.paste(face, (0, 0), mask)
    # gold edges over all the visible faces, the silhouette darker
    ed = ImageDraw.Draw(die)
    w = max(2, int(radius * 0.012))
    for _, i, _n in sorted(drawn):
        pts2 = [screen(p[j]) for j in faces[i]]
        ed.line(pts2 + [pts2[0]], fill=EDGE + (255,), width=w, joint="curve")
    return die


def compose(size: int) -> Image.Image:
    bg = mosaic(size, cols=5, rows=4, gap=max(4, size // 300))
    ss = 2  # draw the die twice as large and scale it down: smooth edges
    die = draw_die(size * ss, radius=size * ss * 0.40, tilt=(-14, 10, 0)).resize((size, size), Image.LANCZOS)
    alpha = die.getchannel("A")
    # a warm glow behind and a soft shadow under the die
    glow = Image.new("RGBA", (size, size), (255, 170, 60, 0))
    glow.putalpha(alpha.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(size * 0.04)).point(lambda x: int(x * 0.75)))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(size * 0.02)).point(lambda x: int(x * 0.8)))
    out = bg.convert("RGBA")
    out.alpha_composite(glow)
    out.alpha_composite(shadow, (int(size * 0.012), int(size * 0.02)))
    out.alpha_composite(die)
    return out.convert("RGB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="http://127.0.0.1:7860", help="the own Forge")
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--seed", type=int, default=20261030)
    ap.add_argument("--compose-only", action="store_true")
    ap.add_argument("--redraw", default="", help="frame numbers from 1, comma-separated")
    ap.add_argument("--icon", action="store_true", help="also write the game's icon (game/icon.png, game/icon.ico)")
    args = ap.parse_args()
    if not args.compose_only:
        redraw = {int(x) - 1 for x in args.redraw.split(",") if x.strip()}
        draw_frames(args.url, redraw, args.seed)
    OUT.mkdir(parents=True, exist_ok=True)
    img = compose(args.size)
    img.save(OUT / "avatar.png")
    img.resize((512, 512), Image.LANCZOS).save(OUT / "avatar_512.png")
    print(OUT / "avatar.png")
    if args.icon:
        game = ROOT / "game"
        img.resize((512, 512), Image.LANCZOS).save(game / "icon.png")
        img.save(game / "icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        print(game / "icon.png")


if __name__ == "__main__":
    main()
