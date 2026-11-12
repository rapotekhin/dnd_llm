"""Our own geometry of a UI part for ControlNet: a depth map and a line map, white on black, one pair per family of
guides. Nothing of another game: plain shapes drawn by code (the trial of 2026-11-11, skill anima_art).

- heavy: a raised rim around an inset field, corner ornaments (the leather and wood trial);
- thin: a flat panel framed by two thin lines with a small curl in each corner (the «lines» style);
- book: a parchment page inside a narrow band of binding, a double ink line, pale circles in the corners (the «book»
  style); its button and cell are the thin ones, the prompt makes them paper;
- plate: a narrow bevelled rim with a rivet in each corner, the plates of our own icons (the «plates» style).

Only the corners carry ornaments: the game lays a part as nine pieces and stretches its edges, so an ornament in the
middle of an edge would smear.

    python tools/anima/ui/guides.py [out_dir]        # → tools/anima/out_ui/guides/<part>_<family>_{depth,lines}.png
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = {"window": (768, 768), "button": (1024, 320), "cell": (512, 512),  # every family
        "tab": (768, 256), "card": (768, 512), "field": (1024, 192),  # thin only: panels laid in nine pieces
        "crest": (768, 256), "divider": (1024, 128), "ring": (512, 512)}  # thin only: ornaments laid whole
BASE = ("window", "button", "cell")
ORNAMENTS = ("crest", "divider", "ring")
# heavy: rim width, the inner line's inset, the corner ornament's size, the field's depth
HEAVY = {
    "window": {"rim": 56, "inner": 76, "corner": 120, "field": 70},
    "button": {"rim": 34, "inner": 50, "corner": 64, "field": 110},
    "cell": {"rim": 40, "inner": 56, "corner": 70, "field": 50},
}
# thin: the outer and inner line (inset, width; no inner — one line), the corner's rounding, the curl's size (0 — none),
# a diamond on each corner (its half size), the side left open (a tab sits on its panel), the field's depth.
# The widths are what stays one or two screen pixels after the game's scale (mock.CUT).
THIN = {
    "window": {"outer": (22, 5), "inner": (34, 3), "round": 0, "curl": 60, "field": 45},
    "button": {"outer": (14, 10), "inner": (32, 5), "round": 56, "curl": 0, "field": 60},
    "cell": {"outer": (16, 12), "inner": (36, 5), "round": 0, "curl": 0, "field": 35},
    "tab": {"outer": (14, 8), "inner": (28, 4), "round": 48, "curl": 0, "field": 55, "open": "bottom"},
    "card": {"outer": (18, 5), "inner": None, "round": 0, "curl": 0, "dot": 14, "field": 50},
    "field": {"outer": (10, 8), "inner": None, "round": 0, "curl": 0, "field": 30},
}
# book: the binding band, the double ink line, the circles in the corners (centre inset, radius)
BOOK = {"band": 30, "outer": (46, 5), "inner": (58, 3), "circle": (112, 66)}
# plate: a narrow bevelled rim, a rivet in each corner (centre inset, radius), the field's depth (a button's face is
# a raised plate, a window's and a cell's field lies low)
PLATE = {
    "window": {"rim": 30, "rivet": (16, 10), "field": 60},
    "button": {"rim": 20, "rivet": (32, 12), "field": 190},
    "cell": {"rim": 36, "rivet": (20, 10), "field": 40},
}


def bevel(w: int, h: int, rim: int, field: int) -> Image.Image:
    """Depth: the rim rises from the outer edge to its top and falls to the field; the field is flat and low."""
    img = Image.new("L", (w, h), field)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)  # distance to the outer edge
            if d < rim:
                t = d / rim
                v = 150 + 105 * math.sin(math.pi * min(1.0, t * 1.15))  # a rounded ridge
                px[x, y] = int(max(field, v))
    return img


def corner_ornament(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, sx: int, sy: int, fill, width: int) -> None:
    """A plain ornament in a corner: a diamond stud, two curls along the edges, a small ring; (sx, sy) point inward."""
    d = r * 0.32
    draw.polygon([(cx, cy - d * sy), (cx + d * sx, cy), (cx, cy + d * sy), (cx - d * sx, cy)], outline=fill, width=width)
    draw.ellipse([cx - d * 0.35, cy - d * 0.35, cx + d * 0.35, cy + d * 0.35], outline=fill, width=width)
    for along in ("x", "y"):  # a curl running along each edge from the stud
        pts = []
        for i in range(40):
            t = i / 39
            a = t * math.pi * 1.4
            rad = r * 0.5 * (1 - t * 0.6)
            if along == "x":
                pts.append((cx + sx * (d + t * r * 0.9), cy + sy * (math.sin(a) * rad * 0.35)))
            else:
                pts.append((cx + sx * (math.sin(a) * rad * 0.35), cy + sy * (d + t * r * 0.9)))
        draw.line(pts, fill=fill, width=width, joint="curve")


def corners(w: int, h: int, at: float) -> list[tuple[float, float, int, int]]:
    """The four corners at `at` from the edges, each with the direction pointing inward."""
    return [(at, at, 1, 1), (w - 1 - at, at, -1, 1), (at, h - 1 - at, 1, -1), (w - 1 - at, h - 1 - at, -1, -1)]


def frame(dr: ImageDraw.ImageDraw, w: int, h: int, inset: int, width: int, rnd: int, fill: int,
          open_bottom: bool = False) -> None:
    box = [inset, inset, w - 1 - inset, h - 1 - inset + (rnd + inset + width if open_bottom else 0)]
    if rnd:
        dr.rounded_rectangle(box, radius=rnd, outline=fill, width=width)
    else:
        dr.rectangle(box, outline=fill, width=width)


def heavy(part: str) -> tuple[Image.Image, Image.Image]:
    w, h = SIZE[part]
    p = HEAVY[part]
    depth = bevel(w, h, p["rim"], p["field"]).filter(ImageFilter.GaussianBlur(1.5))
    ln = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(ln)
    wl = max(2, w // 256)
    frame(dr, w, h, p["rim"], wl, 0, 255)  # where the rim meets the field
    frame(dr, w, h, p["inner"], max(1, wl - 1), 0, 200)  # a thin inner line
    for cx, cy, sx, sy in corners(w, h, p["rim"] / 2):
        corner_ornament(dr, cx, cy, p["corner"], sx, sy, 255, wl)
    depth.paste(255, mask=ln.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MaxFilter(3)))
    return depth, ln


def thin_lines(part: str) -> Image.Image:
    w, h = SIZE[part]
    p = THIN[part]
    ln = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(ln)
    (o, ow) = p["outer"]
    shut = p.get("open") != "bottom"
    frame(dr, w, h, o, ow, p["round"], 255, not shut)
    if p["inner"]:
        i, iw = p["inner"]
        frame(dr, w, h, i, iw, max(0, p["round"] - (i - o)), 190, not shut)
    if p["curl"]:
        for cx, cy, sx, sy in corners(w, h, (o + p["inner"][0]) / 2):
            corner_ornament(dr, cx, cy, p["curl"], sx, sy, 255, p["inner"][1])
    if p.get("dot"):
        d = p["dot"]
        for cx, cy, _, _ in corners(w, h, o + ow / 2):
            dr.polygon([(cx, cy - d), (cx + d, cy), (cx, cy + d), (cx - d, cy)], fill=255)
    return ln


def thin(part: str) -> tuple[Image.Image, Image.Image]:
    """A flat panel: the lines barely raised above it, the field a little lower than the band between them."""
    w, h = SIZE[part]
    p = THIN[part]
    ln = thin_lines(part)
    depth = Image.new("L", (w, h), p["field"])
    o = p["outer"][0]
    ImageDraw.Draw(depth).rectangle([0, 0, w - 1, h - 1], outline=p["field"] + 25, width=o)  # the band outside the line
    depth.paste(p["field"] + 75, mask=ln.point(lambda v: 255 if v > 100 else 0))
    return depth.filter(ImageFilter.GaussianBlur(2)), ln


def diamond(dr: ImageDraw.ImageDraw, cx: float, cy: float, d: float, width: int) -> None:
    dr.polygon([(cx, cy - d), (cx + d, cy), (cx, cy + d), (cx - d, cy)], outline=255, width=width)
    dr.polygon([(cx, cy - d * 0.4), (cx + d * 0.4, cy), (cx, cy + d * 0.4), (cx - d * 0.4, cy)], fill=255)


def ornament(part: str) -> tuple[Image.Image, Image.Image]:
    """A piece laid whole over a panel: the crest over a window's title, a divider, the ring of a portrait. Thin lines
    on black; the game takes their brightness for alpha."""
    w, h = SIZE[part]
    ln = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(ln)
    cx, cy = w / 2, h / 2
    if part == "crest":  # a diamond with two waves running out to each side, a small curl at each end
        diamond(dr, cx, cy, 34, 5)
        for s in (-1, 1):
            for amp, wd in ((40, 5), (-22, 3)):
                pts = [(cx + s * (44 + t / 60 * 256), cy - math.sin(t / 60 * 2 * math.pi) * amp * (1 - t / 120))
                       for t in range(61)]
                dr.line(pts, fill=255, width=wd, joint="curve")
            ex = cx + s * 300
            dr.ellipse([ex - 9, cy - 9, ex + 9, cy + 9], outline=255, width=4)
    elif part == "divider":  # a line thinning toward both ends, a diamond and two dots in the middle
        for x in range(40, w - 40, 4):
            k = 1 - abs(x - cx) / (cx - 40)
            dr.line([(x, cy), (x + 4, cy)], fill=int(120 + 135 * k), width=max(1, round(1 + 5 * k)))
        diamond(dr, cx, cy, 18, 4)
        for s in (-1, 1):
            dr.ellipse([cx + s * 40 - 5, cy - 5, cx + s * 40 + 5, cy + 5], fill=255)
    elif part == "ring":  # two close circles, a diamond at the top and the bottom
        for r, wd in ((228, 8), (212, 3)):
            dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=wd)
        for y in (cy - 222, cy + 222):
            diamond(dr, cx, y, 16, 4)
    depth = Image.new("L", (w, h), 40)
    depth.paste(110, mask=ln.point(lambda v: 255 if v > 100 else 0))
    return depth.filter(ImageFilter.GaussianBlur(2)), ln


def book_window() -> tuple[Image.Image, Image.Image]:
    """A page: the binding raised at the edges, the page flat, a double ink line, rings and spokes in each corner."""
    w, h = SIZE["window"]
    b = BOOK
    ln = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(ln)
    frame(dr, w, h, b["band"], 4, 0, 255)  # where the binding meets the page
    frame(dr, w, h, b["outer"][0], b["outer"][1], 0, 230)
    frame(dr, w, h, b["inner"][0], b["inner"][1], 0, 170)
    at, r = b["circle"]
    for cx, cy, _, _ in corners(w, h, at):  # pale drawings: three rings, eight spokes
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=120, width=2)
        dr.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72], outline=100, width=2)
        for k in range(8):
            a = k * math.pi / 4
            dr.line([(cx + math.cos(a) * r * 0.25, cy + math.sin(a) * r * 0.25),
                     (cx + math.cos(a) * r * 0.72, cy + math.sin(a) * r * 0.72)], fill=90, width=2)
        dr.ellipse([cx - r * 0.2, cy - r * 0.2, cx + r * 0.2, cy + r * 0.2], outline=110, width=2)
    depth = Image.new("L", (w, h), 110)
    ddr = ImageDraw.Draw(depth)
    for k in range(b["band"]):  # the binding: a soft roll from the edge to the page
        ddr.rectangle([k, k, w - 1 - k, h - 1 - k], outline=int(150 + 60 * math.sin(math.pi * k / b["band"])))
    depth.paste(135, mask=ln.point(lambda v: 255 if v > 200 else 0))
    return depth.filter(ImageFilter.GaussianBlur(2)), ln


def plate(part: str) -> tuple[Image.Image, Image.Image]:
    """A bevelled rim with a rivet in each corner: the rivets stand highest, the rim meets the field in one line."""
    w, h = SIZE[part]
    p = PLATE[part]
    depth = bevel(w, h, p["rim"], p["field"])
    ln = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(ln)
    frame(dr, w, h, p["rim"], max(3, w // 200), 0, 255)
    at, r = p["rivet"]
    ddr = ImageDraw.Draw(depth)
    for cx, cy, _, _ in corners(w, h, at):
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=3)
        ddr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return depth.filter(ImageFilter.GaussianBlur(1.5)), ln


def make(part: str, family: str) -> tuple[Image.Image, Image.Image]:
    if family == "heavy":
        return heavy(part)
    if family == "plate":
        return plate(part)
    if family == "book" and part == "window":
        return book_window()
    if part in ORNAMENTS:
        return ornament(part)
    return thin(part)


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "out_ui" / "guides"
    out.mkdir(parents=True, exist_ok=True)
    for fam in ("heavy", "thin", "book", "plate"):
        for part in SIZE if fam == "thin" else BASE:
            depth, ln = make(part, fam)
            depth.convert("RGB").save(out / f"{part}_{fam}_depth.png")
            ln.convert("RGB").save(out / f"{part}_{fam}_lines.png")
            print(part, fam)
