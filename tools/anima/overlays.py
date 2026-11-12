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


def strike(size: int, ink: tuple = (214, 52, 40, 255)) -> Image.Image:
    """A red bar across the whole icon from its upper left to its lower right over a dark outline, its ends round:
    a sense taken away (the author's «перечёркнутый глаз», «перечёркнутый колокольчик», 2026-11-12). It stays inside
    the gold ring of a condition's medal."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    a, b, w = size * 0.25, size * 0.75, size * 0.075
    for col, r in ((DARK, w / 2 + 5), (ink, w / 2)):
        d.line([(a, a), (b, b)], fill=col, width=int(r * 2))
        for x in (a, b):
            d.ellipse([x - r, x - r, x + r, x + r], fill=col)
    return im


LINE = 0.022  # a line's width to the icon's side: the gold line icons' own (ui/sheet: 2–4 px of 128)


def _lines(d: ImageDraw.ImageDraw, segs: list, w: float, col: tuple) -> None:
    """Segments of an even width with round ends, so the joints close."""
    for a, b in segs:
        d.line([a, b], fill=col, width=round(w))
        for x, y in (a, b):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=col)


def d20(size: int) -> Image.Image:
    """A twenty-sided die seen face on in thin gold lines, every face hollow (the author, 2026-11-12: the model filled
    it): the hexagon of its silhouette, the face in the middle and the nine around it — the gold line icons' look."""
    big = size * 4
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    c, r, ri = big / 2, big * 0.43, big * 0.43 * 0.52
    hexa = [(c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in (-90, -30, 30, 90, 150, 210)]
    top, ur, lr, bot, ll, ul = hexa
    tri = [(c + ri * math.cos(math.radians(a)), c + ri * math.sin(math.radians(a))) for a in (-90, 30, 150)]
    apex, br, bl = tri
    edges = list(zip(hexa, hexa[1:] + hexa[:1])) + list(zip(tri, tri[1:] + tri[:1]))
    edges += [(apex, top), (apex, ul), (apex, ur), (bl, ul), (bl, ll), (bl, bot), (br, ur), (br, lr), (br, bot)]
    _lines(ImageDraw.Draw(im), edges, big * LINE, GOLD)
    return im.resize((size, size), Image.LANCZOS)


def sheet_lines(size: int) -> Image.Image:
    """A sheet with a folded corner and four lines of writing in the same thin gold lines, hollow (the tab «Подробно»
    of the character's sheet beside the helmet and the d20)."""
    big = size * 4
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    x0, y0, x1, y1, fold = big * 0.25, big * 0.1, big * 0.75, big * 0.9, big * 0.15
    w = big * LINE
    edge = [(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1), (x0, y0)]
    segs = list(zip(edge, edge[1:])) + [((x1 - fold, y0), (x1 - fold, y0 + fold)), ((x1 - fold, y0 + fold), (x1, y0 + fold))]
    for i, end in enumerate((0.7, 0.8, 0.8, 0.5)):  # the lines of writing, a share of the sheet's width, the last short
        y = y0 + big * (0.3 + i * 0.12)
        segs.append(((x0 + big * 0.07, y), (x0 + big * 0.07 + (x1 - x0 - big * 0.14) * end, y)))
    _lines(ImageDraw.Draw(im), segs, w, GOLD)
    return im.resize((size, size), Image.LANCZOS)


MARKS = {"peace": peace, "peace_gold": lambda side: peace(side, DARK, GOLD)}  # gold on a dark disc: over the line icons (ui)
WHOLE = {"strike": strike}  # marks laid over the whole icon, not in its corner
ICONS = {"d20": d20, "sheet_lines": sheet_lines}  # whole icons drawn by code where the model fills or bends a geometry


def icon(name: str, side: int = 128) -> bytes:
    """A whole icon drawn by code (`drawn` of the picks: «ui/skills»: «d20»), as PNG bytes."""
    buf = io.BytesIO()
    ICONS[name](side).save(buf, "PNG")
    return buf.getvalue()


def apply(name: str, src: Path) -> bytes:
    """The icon at src with the overlay `name` (in its lower right corner, or over all of it for `WHOLE`), as PNG
    bytes."""
    base = Image.open(src).convert("RGBA")
    big = base.resize((WORK, WORK), Image.LANCZOS)
    if name in WHOLE:
        big.alpha_composite(WHOLE[name](WORK))
    else:
        side = int(WORK * 0.45)
        big.alpha_composite(MARKS[name](side), (WORK - side - 8, WORK - side - 8))
    buf = io.BytesIO()
    big.resize(base.size, Image.LANCZOS).save(buf, "PNG")
    return buf.getvalue()
