"""The sheets of the third run: each map — its mask, a clean frame, two seeds with the game's grid and the mask's outlines.

    python tools/mask_maps/sheet_v3.py      → build/mask_maps/v3_indoor.jpg, v3_outdoor.jpg, grid_v3_<room>.jpg
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from overlay import OUT, S, overlay

NAMES = {"brod-smithy": "кузница 11×8", "brod-temple": "храм 11×10", "brod-tavern-cellar": "погреб 9×7",
         "mine-gallery": "галерея шахты 27×17", "outpost-crypt": "склеп 7×5", "pushcha-trail": "тропа Пущи 40×40",
         "pushcha-glade": "поляна 40×40", "outpost-road": "дорога к заставе 40×40", "outpost-yard": "двор заставы 28×28",
         "mine-entrance": "вход в шахту 27×17"}
SHEETS = {"indoor": ["brod-smithy", "brod-temple", "brod-tavern-cellar", "outpost-crypt", "mine-gallery"],
          "outdoor": ["pushcha-trail", "pushcha-glade", "outpost-road", "outpost-yard", "mine-entrance"]}
SUF = "_nat_loose_smooth"


def gridded(room: str, path: Path) -> Image.Image:
    """A frame with the mask's outlines in red and the game's squares in faint white."""
    im = overlay(room, path)
    w, h = im.size
    g = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    for x in range(0, w + 1, S):
        d.line([(x, 0), (x, h)], fill=(255, 255, 255, 70), width=1)
    for y in range(0, h + 1, S):
        d.line([(0, y), (w, y)], fill=(255, 255, 255, 70), width=1)
    return Image.alpha_composite(im.convert("RGBA"), g).convert("RGB")


def main() -> None:
    font = ImageFont.truetype("arial.ttf", 22)
    side = 560
    for name, rooms in SHEETS.items():
        sheet = Image.new("RGB", (4 * (side + 8), len(rooms) * (side + 40)), (22, 22, 22))
        d = ImageDraw.Draw(sheet)
        for r, room in enumerate(rooms):
            a, b = OUT / f"flux-klein_{room}{SUF}.png", OUT / f"flux-klein_{room}{SUF}_s21.png"
            cells = [("маска · " + NAMES[room], Image.open(OUT / f"mask_{room}{SUF}.png")), ("Klein, сид 7", Image.open(a)),
                     ("сид 7 + клетки и контуры", gridded(room, a)), ("сид 21 + клетки и контуры", gridded(room, b))]
            for c, (lab, pic) in enumerate(cells):
                pic = pic.convert("RGB")
                pic.thumbnail((side, side))
                x, y = c * (side + 8), r * (side + 40)
                sheet.paste(pic, (x + (side - pic.width) // 2, y + 36))
                d.text((x + 6, y + 6), lab, fill=(240, 240, 240), font=font)
            gridded(room, a).save(OUT / f"grid_v3_{room}.jpg", quality=88)
        sheet.save(OUT / f"v3_{name}.jpg", quality=86)
        print(OUT / f"v3_{name}.jpg")


if __name__ == "__main__":
    main()
