"""The trial in the game's look: each painted part cut into nine pieces and laid as the game would lay a StyleBoxTexture
(corners as they are, edges and the middle stretched), the button's hover / pressed / disabled made from one picture.

    python tools/anima/ui/mock.py [--seed 11] [--mats leather,wood]      # out_ui/raw → out_ui/mock/
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[2] / "game"
OUT = HERE.parent / "out_ui"
FONT = GAME / "assets/fonts/literata.ttf"
UI_FONT = GAME / "assets/fonts/inter.ttf"
BG = (23, 19, 15)  # the theme's darkest panel
GOLD = (201, 164, 92)  # the theme's border colour
TEXT = (226, 214, 190)
ICONS = ["items/longsword", "items/shortbow", "spells/fire_bolt", "spells/cure_wounds", "items/healing_potion",
         "acts/dash", "ui/rest_short", "ui/sneak"]
# a part: the margin of its nine pieces in raw px, and the scale from raw px to screen px
CUT = {"window": (84, 0.28), "button": (52, 0.14), "cell": (0, 0.115)}


def nine(img: Image.Image, margin: int, scale: float, size: tuple[int, int]) -> Image.Image:
    """Lay img at `size` screen px: its margin (raw px) drawn at `scale`, the edges and the middle stretched."""
    w, h = img.size
    m = margin
    tex = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    tm = max(1, round(m * scale))
    tw, th = tex.size
    W, H = size
    out = Image.new("RGB", size)
    xs = [(0, tm, 0, tm), (tm, tw - tm, tm, W - tm), (tw - tm, tw, W - tm, W)]
    ys = [(0, tm, 0, tm), (tm, th - tm, tm, H - tm), (th - tm, th, H - tm, H)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            piece = tex.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
            out.paste(piece, (dx0, dy0))
    return out


def states(btn: Image.Image) -> dict[str, Image.Image]:
    """Hover a little brighter with a warm glow, pressed darker, disabled grey and dim: one picture, four looks."""
    hover = ImageEnhance.Brightness(btn).enhance(1.25)
    glow = Image.new("RGB", btn.size, (255, 200, 120))
    hover = Image.blend(hover, glow, 0.08)
    pressed = ImageEnhance.Brightness(btn).enhance(0.75)
    disabled = ImageEnhance.Brightness(ImageEnhance.Color(btn).enhance(0.15)).enhance(0.6)
    return {"обычная": btn, "наведение": hover, "нажата": pressed, "недоступна": disabled}


def text(d: ImageDraw.ImageDraw, xy, s: str, size: int, fill=TEXT, font=FONT, anchor="la") -> None:
    d.text(xy, s, fill=fill, font=ImageFont.truetype(str(font), size), anchor=anchor)


def icon(path: str, side: int) -> Image.Image | None:
    f = GAME / "assets/icons" / f"{path}.png"
    return Image.open(f).convert("RGBA").resize((side, side), Image.LANCZOS) if f.exists() else None


def mock(raw: Path, mat: str, seed: int) -> Image.Image:
    W, H = 1200, 640
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    win = Image.open(raw / f"window_{mat}_{seed}.png").convert("RGB")
    btn = Image.open(raw / f"button_{mat}_{seed}.png").convert("RGB")
    cell = Image.open(raw / f"cell_{mat}_{seed}.png").convert("RGB")
    # a window with a title, a body and its buttons
    canvas.paste(nine(win, *CUT["window"], (640, 400)), (40, 40))
    text(d, (74, 74), "Лист персонажа", 26, GOLD)
    for i, line in enumerate(["Тарас · Монах, уровень 1", "Хиты 10/10 · КД 15 · Скорость 40 футов",
                              "Сила 10  Ловкость 16  Телосложение 12", "Мудрость 15  Интеллект 10  Харизма 8"]):
        text(d, (74, 124 + i * 30), line, 17, font=UI_FONT)
    for i, (name, look) in enumerate(states(btn).items()):
        x = 74 + i * 146
        canvas.paste(nine(look, *CUT["button"], (136, 40)), (x, 370))
        text(d, (x + 68, 390), ["Принять", "Принять", "Принять", "Принять"][i], 15,
             TEXT if name != "недоступна" else (120, 112, 100), UI_FONT, "mm")
        text(d, (x + 68, 418), name, 11, (150, 140, 120), UI_FONT, "mm")
    # a row of hotbar cells with the game's icons
    side = 60
    for i, ref in enumerate(ICONS):
        x, y = 40 + i * (side + 4), 500
        c = cell.resize((side, side), Image.LANCZOS)
        canvas.paste(c, (x, y))
        ic = icon(ref, side - 14)
        if ic is not None:
            canvas.paste(ic, (x + 7, y + 7), ic)
    text(d, (40, 470), "Ячейки панели действий с иконками игры", 13, (150, 140, 120), UI_FONT)
    # the raw paints at the right
    t = win.copy(); t.thumbnail((220, 220)); canvas.paste(t, (720, 40))
    t = cell.copy(); t.thumbnail((200, 200)); canvas.paste(t, (960, 40))
    t = btn.copy(); t.thumbnail((440, 140)); canvas.paste(t, (720, 290))
    text(d, (720, 20), "как нарисовано (до нарезки)", 13, (150, 140, 120), UI_FONT)
    return canvas


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--raw", type=Path, default=OUT / "raw")
    p.add_argument("--out", type=Path, default=OUT / "mock")
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--mats", default="leather,wood")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    for mat in a.mats.split(","):
        try:
            img = mock(a.raw, mat, a.seed)
        except FileNotFoundError as e:
            print("missing", e)
            continue
        dest = a.out / f"mock_{mat}_{a.seed}.png"
        img.save(dest)
        print(dest)


if __name__ == "__main__":
    main()
