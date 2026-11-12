"""Marks drawn by code over a drawn icon where the model would spoil a symbol (install.py, `overlay` of picks.json):
«<kind>/<id>»: "<name>" puts the overlay of that name over the icon on its way into the game."""
from __future__ import annotations

import io
import math
from pathlib import Path

from PIL import Image, ImageDraw

INK, DARK = (250, 246, 236, 255), (30, 22, 16, 255)
GOLD = (232, 210, 160, 255)  # the gold of the line icons (anima_gen.GOLD toward GOLD_LIT)
WORK = 512  # the icon is drawn over at this side, then brought back to its own


def peace(size: int, badge: tuple | None = (86, 160, 92, 255), ink: tuple = INK) -> Image.Image:
    """A peace symbol ☮ on a round badge with a dark rim (the author's «Не убивать», 2026-11-11), green by default;
    its lines in `ink` over a dark outline, the badge left out when None."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    o = 6
    if badge:
        d.ellipse([0, 0, size - 1, size - 1], fill=DARK)
        d.ellipse([o, o, size - 1 - o, size - 1 - o], fill=badge)
    c = size / 2
    r = size / 2 - (o * 2.6 if badge else o * 1.5)
    w = int(size * 0.075)
    for col, extra in ((DARK, 8), (ink, 0)):  # a dark outline under the light lines
        d.ellipse([c - r, c - r, c + r, c + r], outline=col, width=int(size * 0.1) + extra)
        d.line([(c, c - r), (c, c + r)], fill=col, width=w + extra)
        for ang in (45, 135):  # from the centre down-right and down-left (y grows down)
            a = math.radians(ang)
            d.line([(c, c), (c + r * math.cos(a), c + r * math.sin(a))], fill=col, width=w + extra)
    return im


MARKS = {"peace": peace, "peace_gold": lambda side: peace(side, DARK, GOLD)}  # gold on a dark disc: over the line icons (ui)


def apply(name: str, src: Path) -> bytes:
    """The icon at src with the overlay `name` in its lower right corner, as PNG bytes."""
    base = Image.open(src).convert("RGBA")
    big = base.resize((WORK, WORK), Image.LANCZOS)
    side = int(WORK * 0.45)
    big.alpha_composite(MARKS[name](side), (WORK - side - 8, WORK - side - 8))
    buf = io.BytesIO()
    big.resize(base.size, Image.LANCZOS).save(buf, "PNG")
    return buf.getvalue()
