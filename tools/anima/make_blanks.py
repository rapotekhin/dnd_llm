"""Blank icons, one per kind, until Anima's are drawn: game/assets/icons/_blank/<kind>.png. A transparent 128 px
square with a plain outline shape of its kind, so a window built on icons already has something to show; an icon of an
id (game/assets/icons/<kind>/<id>.png) is taken over the blank when it exists.

    python tools/anima/make_blanks.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "icons" / "_blank"
S = 128
W = 7  # the line's width
# kind → (a shape, its colour): what tells one kind from another at a glance
KINDS = {
    "items": ("square", (196, 170, 120)),
    "spells": ("circle", (120, 160, 230)),
    "features": ("diamond", (220, 150, 90)),
    "traits": ("triangle", (150, 200, 140)),
    "conditions": ("hexagon", (200, 120, 170)),
    "acts": ("arrow", (230, 210, 140)),
    "groups": ("stack", (180, 180, 190)),
    "default": ("dot", (160, 160, 160)),
}


def blank(shape: str, col: tuple) -> Image.Image:
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c, m = S // 2, 30
    line = col + (255,)
    if shape == "square":
        d.rounded_rectangle((m, m, S - m, S - m), radius=10, outline=line, width=W)
    elif shape == "circle":
        d.ellipse((m, m, S - m, S - m), outline=line, width=W)
    elif shape == "diamond":
        d.polygon([(c, m - 6), (S - m + 6, c), (c, S - m + 6), (m - 6, c)], outline=line, width=W)
    elif shape == "triangle":
        d.polygon([(c, m - 4), (S - m + 6, S - m + 2), (m - 6, S - m + 2)], outline=line, width=W)
    elif shape == "hexagon":
        r = c - m + 4
        d.regular_polygon((c, c, r), 6, outline=line, width=W)
    elif shape == "arrow":
        d.line([(m, c), (S - m, c)], fill=line, width=W)
        d.line([(S - m - 22, c - 22), (S - m, c), (S - m - 22, c + 22)], fill=line, width=W, joint="curve")
    elif shape == "stack":
        for i in range(3):
            y = m + 6 + i * 20
            d.rounded_rectangle((m, y, S - m, y + 14), radius=4, outline=line, width=W - 2)
    else:
        d.ellipse((c - 14, c - 14, c + 14, c + 14), fill=line)
    return im


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, (shape, col) in KINDS.items():
        blank(shape, col).save(OUT / f"{kind}.png")
    print(f"{len(KINDS)} blanks -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
