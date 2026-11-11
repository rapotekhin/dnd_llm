"""Our own geometry of a UI part for ControlNet: a depth map (a raised rim, an inset field) and a line map (where the
rim meets the field, an inner line, corner ornaments), white on black. Nothing of another game: plain shapes drawn by
code (the trial of 2026-11-11, skill anima_art).

    python tools/anima/ui/guides.py [out_dir]        # → tools/anima/out_ui/guides/
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# a part: canvas w×h, rim width, the inner line's inset, the corner ornament's size, the field's depth
PARTS = {
    "window": {"size": (768, 768), "rim": 56, "inner": 76, "corner": 120, "field": 70},
    "button": {"size": (1024, 320), "rim": 34, "inner": 50, "corner": 64, "field": 110},
    "cell": {"size": (512, 512), "rim": 40, "inner": 56, "corner": 70, "field": 50},
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


def lines(w: int, h: int, rim: int, inner: int, corner: int) -> Image.Image:
    img = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(img)
    wl = max(2, w // 256)
    dr.rectangle([rim, rim, w - 1 - rim, h - 1 - rim], outline=255, width=wl)  # where the rim meets the field
    dr.rectangle([inner, inner, w - 1 - inner, h - 1 - inner], outline=200, width=max(1, wl - 1))  # a thin inner line
    c = rim / 2
    for (cx, cy, sx, sy) in ((c, c, 1, 1), (w - 1 - c, c, -1, 1), (c, h - 1 - c, 1, -1), (w - 1 - c, h - 1 - c, -1, -1)):
        corner_ornament(dr, cx, cy, corner, sx, sy, 255, wl)
    return img


def make(name: str, out: Path) -> None:
    p = PARTS[name]
    w, h = p["size"]
    depth = bevel(w, h, p["rim"], p["field"]).filter(ImageFilter.GaussianBlur(1.5))
    ln = lines(w, h, p["rim"], p["inner"], p["corner"])
    depth_l = depth.copy()
    depth_l.paste(255, mask=ln.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MaxFilter(3)))
    depth.convert("RGB").save(out / f"{name}_depth.png")
    ln.convert("RGB").save(out / f"{name}_lines.png")


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "out_ui" / "guides"
    out.mkdir(parents=True, exist_ok=True)
    for n in PARTS:
        make(n, out)
        print(n)
