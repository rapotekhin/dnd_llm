"""The mask's outlines (things, doors, walls, water, roads) drawn over a render, and the comparison sheets of the natural run."""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
OUT = Path(__file__).resolve().parents[2] / "build" / "mask_maps"
ROOT = Path(__file__).resolve().parents[2]
maps = json.loads((ROOT / "build/playtest/map_compare/maps.json").read_text(encoding="utf-8"))
S = 40  # px a square in the overlay

def edges(room):
    m = maps[room]; w, h = int(m["w"]), len(m["rows"])
    lab = np.asarray(Image.open(OUT / f"mask_{room}.png").convert("RGB"))
    cls = [[tuple(lab[j * 32 + 16, i * 32 + 16]) for i in range(w)] for j in range(h)]
    segs = []
    for j in range(h):
        for i in range(w):
            for di, dj in ((1, 0), (0, 1)):
                a, b = i + di, j + dj
                if a < w and b < h and cls[j][i] != cls[b][a]:
                    if di: segs.append(((a * S, j * S), (a * S, (j + 1) * S)))
                    else: segs.append(((i * S, b * S), ((i + 1) * S, b * S)))
    return w, h, segs

def overlay(room, path):
    w, h, segs = edges(room)
    im = Image.open(path).convert("RGB").resize((w * S, h * S), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    for a, b in segs: d.line([a, b], fill=(255, 40, 40), width=2)
    return im

if __name__ == "__main__":  # the sheets of the second run (v2)
    font = ImageFont.truetype("arial.ttf", 24)
    for room in maps:
        cols = [("маска", OUT / f"mask_{room}_nat.png", False), ("наш рендер", ROOT / f"build/playtest/map_compare/ours_{room}.png", False),
                ("Klein, старая маска", OUT / f"flux-klein_{room}.png", False),
                ("Klein, естественная, сид 7", OUT / f"flux-klein_{room}_nat.png", False),
                ("Klein, естественная, сид 21", OUT / f"flux-klein_{room}_nat_s21.png", False),
                ("сид 7 + контуры маски", OUT / f"flux-klein_{room}_nat.png", True),
                ("сид 21 + контуры маски", OUT / f"flux-klein_{room}_nat_s21.png", True),
                ("GPT + контуры маски", OUT / f"gpt-image_{room}.png", True)]
        side = 620
        sheet = Image.new("RGB", (4 * (side + 10), 2 * (side + 44)), (24, 24, 24))
        d = ImageDraw.Draw(sheet)
        for k, (name, p, ov) in enumerate(cols):
            x, y = (k % 4) * (side + 10), (k // 4) * (side + 44)
            pic = overlay(room, p) if ov else Image.open(p).convert("RGB")
            if ov: overlay(room, p).save(OUT / f"overlay_{p.stem}.png")
            pic.thumbnail((side, side))
            sheet.paste(pic, (x + (side - pic.width) // 2, y + 40))
            d.text((x + 6, y + 8), name, fill=(240, 240, 240), font=font)
        sheet.save(OUT / f"nat_{room}.png")
        print(OUT / f"nat_{room}.png")
