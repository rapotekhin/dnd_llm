"""The interface's frames into the game: each part of the lines style as the author picked it (picks_lines.json, a seed
per part) cut out of its ground, changed into its looks (a button's hover, pressed and disabled, the main button's gold,
a tab on and off) and brought to the game's px — game/assets/ui/frames/<file>.png. What to make and how big is the
`frames` of game/data/icons.json, the same rows UiTheme.skin lays over the theme; the files stay out of git, as the
icons do, and the theme keeps its flat styles where a file is missing. Run the import afterwards.

    python tools/anima/ui/frames.py            # every file of `frames.files`
    python tools/anima/ui/frames.py --dry      # only say what would be made
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageEnhance

from mock import GAME, OUT, lit, outline, states, unground
from preview import PICKS, seeds_of

LOOKS = {"hover": "наведение", "pressed": "нажата", "disabled": "недоступна"}  # mock.states by its names


def warm(img: Image.Image) -> Image.Image:
    """The main button warmed to the theme's gold, as preview.Kit.accent lays it (the model paints its face dark)."""
    return ImageEnhance.Brightness(Image.blend(img, Image.new("RGB", img.size, (150, 112, 52)), 0.4)).enhance(1.1)


def look_of(img: Image.Image, look: str) -> Image.Image:
    """A part's picture changed into one of its looks (`look` of a file of `frames.files`)."""
    if look.startswith("warm"):
        img, look = warm(img), look.removeprefix("warm").lstrip("_")
    if look in LOOKS:
        return states(img)[LOOKS[look]]
    if look in ("on", "off"):
        return ImageEnhance.Brightness(img).enhance(1.25 if look == "on" else 0.8)
    return img


def ornament(img: Image.Image, look: str) -> Image.Image:
    """An ornament painted on black (divider, ring): its brightness is its alpha (mock.lit). `lit` keeps the
    whole square (the ring: its circles stand where the portrait's are counted); a divider is split into its stretched `line` — the left half up to the middle mark mirrored, so the mark is not
    stretched with it — and its `mark`, the diamond with its dots laid once in the middle."""
    orn = lit(img)
    if look == "lit":
        return orn
    box = orn.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, *orn.size)
    orn = orn.crop(box)
    w, h = orn.size
    alpha = orn.getchannel("A")
    tall = [x for x in range(w) if sum(1 for y in range(h) if alpha.getpixel((x, y)) > 60) > 3]  # the mark is taller than the line
    mid = (min(tall), max(tall) + 1) if tall else (w // 2, w // 2)
    gap = max(2, (mid[1] - mid[0]) // 3)  # the dots beside the mark go with it
    a, b = max(0, mid[0] - gap * 2), min(w, mid[1] + gap * 2)
    if look == "mark":  # the dots and the diamond alone: the stretched line runs on under them
        return orn.crop((max(0, mid[0] - 1), 0, min(w, mid[1] + 1), h))
    half = orn.crop((0, 0, a, h))
    line = Image.new("RGBA", (a * 2, h), (0, 0, 0, 0))
    line.paste(half, (0, 0))
    line.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (a, 0))
    return line


def make(raw: Path, seed: int, part: str, look: str, scale: float) -> Image.Image:
    """One file: the drawn part in its look, cut out of its ground by the part's own line (an ornament by its
    brightness), at the game's px."""
    plain = Image.open(raw / f"{part}_lines_{seed}.png").convert("RGB")
    if look in ("lit", "line", "mark"):
        cut = ornament(plain, look)
    else:
        shape = outline("button" if part == "accent" else part, "thin", plain.size)
        cut = unground(look_of(plain, look), shape)
        cut.putalpha(unground(plain, shape).getchannel("A"))  # a darkened look keeps the alpha of the plain picture
    w, h = cut.size
    return cut.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--raw", type=Path, default=OUT / "raw")
    p.add_argument("--dry", action="store_true")
    a = p.parse_args()
    frames = json.loads((GAME / "data/icons.json").read_text(encoding="utf-8"))["frames"]
    seed_of = seeds_of(PICKS)
    dst = GAME / frames["root"].removeprefix("res://")
    for name, f in frames["files"].items():
        part = frames["parts"][f["part"]]
        out = dst / f"{name}.png"
        img = make(a.raw, seed_of[f["part"]], f["part"], f.get("look", ""), f.get("scale", part["scale"]))  # a file's own scale first
        print(f"{name:16s} {f['part']}_lines_{seed_of[f['part']]} {f.get('look', ''):13s} {img.size[0]}×{img.size[1]}"
              f"  margin {round(part.get('cut', 0) * part['scale'])}")
        if not a.dry:
            dst.mkdir(parents=True, exist_ok=True)
            img.save(out)
    print(("would make" if a.dry else "made"), len(frames["files"]), "files in", dst)


if __name__ == "__main__":
    main()
