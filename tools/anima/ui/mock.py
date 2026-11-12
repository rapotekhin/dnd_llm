"""The trial in the game's look: each painted part cut into nine pieces and laid as the game would lay a StyleBoxTexture
(corners as they are, edges and the middle stretched), the button's hover / pressed / disabled made from one picture.

    python tools/anima/ui/mock.py [--seeds 11,22,33] [--styles lines,book]      # out_ui/raw → out_ui/mock/
    python tools/anima/ui/mock.py --screen all                                 # the lines style as a game screen
    python tools/anima/ui/mock.py --screen window=22,button=11 --seeds 33      # each part from its own seed
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

import guides

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
# a part of a family of guides (guides.py): the margin of its nine pieces in raw px, the scale from raw px to screen px
CUT = {("window", "heavy"): (84, 0.28), ("button", "heavy"): (52, 0.14),
       ("window", "thin"): (120, 0.3), ("button", "thin"): (76, 0.125),
       ("window", "book"): (184, 0.3), ("button", "book"): (76, 0.125),
       ("window", "plate"): (110, 0.3), ("button", "plate"): (50, 0.125)}  # the painted rim is wider than its guide
INK = (52, 38, 26)
# a style's guides and its text: the title, the body, a button's caption
LOOK = {"leather": ("heavy", GOLD, TEXT, TEXT), "wood": ("heavy", GOLD, TEXT, TEXT),
        "lines": ("thin", GOLD, TEXT, TEXT), "book": ("book", (128, 36, 24), INK, INK),
        "plates": ("plate", GOLD, TEXT, INK)}


def nine(img: Image.Image, margin: int, scale: float, size: tuple[int, int]) -> Image.Image:
    """Lay img at `size` screen px: its margin (raw px) drawn at `scale`, the edges and the middle stretched."""
    w, h = img.size
    m = margin
    tex = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    tm = max(1, round(m * scale))
    tw, th = tex.size
    W, H = size
    out = Image.new(img.mode, size)
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


def outline(part: str, guide: str, size: tuple[int, int]) -> Image.Image:
    """What of a painted part the game shows: a rounded button only inside its outer line (the model paints the
    corners outside it any colour), every other part whole."""
    w, h = size
    if part not in ("button", "tab") or guide not in ("thin", "book"):
        return Image.new("L", size, 255)
    p = guides.THIN[part]
    o = p["outer"][0]
    m = Image.new("L", size, 0)
    bottom = h + p["round"] if p.get("open") == "bottom" else h - 1 - o
    ImageDraw.Draw(m).rounded_rectangle([o, o, w - 1 - o, bottom], radius=p["round"], fill=255)
    return m.filter(ImageFilter.GaussianBlur(1.5))


def unground(img: Image.Image, shape: Image.Image) -> Image.Image:
    """The part with alpha: the white ground the model sometimes leaves around a frame flooded away from the corners,
    and `shape` (outline) on top; a ground of another colour is part of the panel and stays. A button's looks take the
    alpha of its plain picture: darkened, its ground is no longer white."""
    rgb = img.convert("RGB")
    w, h = rgb.size
    mark = rgb.copy()
    for xy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if min(rgb.getpixel(xy)) >= 225:
            ImageDraw.floodfill(mark, xy, (255, 0, 255), thresh=40)
    flooded = Image.eval(Image.merge("RGB", [Image.eval(c, lambda v, t=t: 255 if v == t else 0)
                                             for c, t in zip(mark.split(), (255, 0, 255))]).convert("L"),
                         lambda v: 0 if v == 255 else 255)
    alpha = Image.composite(shape, Image.new("L", rgb.size, 0), flooded).filter(ImageFilter.GaussianBlur(1))
    out = rgb.copy()
    out.putalpha(alpha)
    return out


def text(d: ImageDraw.ImageDraw, xy, s: str, size: int, fill=TEXT, font=FONT, anchor="la") -> None:
    d.text(xy, s, fill=fill, font=ImageFont.truetype(str(font), size), anchor=anchor)


def icon(path: str, side: int) -> Image.Image | None:
    f = GAME / "assets/icons" / f"{path}.png"
    return Image.open(f).convert("RGBA").resize((side, side), Image.LANCZOS) if f.exists() else None


def mock(raw: Path, mat: str, seed: int) -> Image.Image:
    guide, title, body, caption = LOOK[mat]
    W, H = 1200, 640
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    win = Image.open(raw / f"window_{mat}_{seed}.png").convert("RGB")
    btn = Image.open(raw / f"button_{mat}_{seed}.png").convert("RGB")
    cell = Image.open(raw / f"cell_{mat}_{seed}.png").convert("RGB")
    # a window with a title, a body and its buttons, the text inside the corners' margin
    margin, scale = CUT[("window", guide)]
    pad = max(34, round(margin * scale) + 10)
    x0, y0 = 40 + pad + 6, 40 + pad
    piece = nine(unground(win, outline("window", guide, win.size)), margin, scale, (640, 400))
    canvas.paste(piece, (40, 40), piece)
    text(d, (x0, y0), "Лист персонажа", 26, title)
    for i, line in enumerate(["Тарас · Монах, уровень 1", "Хиты 10/10 · КД 15 · Скорость 40 футов",
                              "Сила 10  Ловкость 16  Телосложение 12", "Мудрость 15  Интеллект 10  Харизма 8"]):
        text(d, (x0, y0 + 50 + i * 30), line, 17, body, UI_FONT)
    alpha = unground(btn, outline("button", guide, btn.size)).getchannel("A")
    for i, (name, look) in enumerate(states(btn).items()):
        x = x0 + i * 136
        look = look.copy()
        look.putalpha(alpha)
        piece = nine(look, *CUT[("button", guide)], (126, 40))
        canvas.paste(piece, (x, 320), piece)
        text(d, (x + 63, 340), "Принять", 15, caption if name != "недоступна" else (120, 112, 100), UI_FONT, "mm")
        text(d, (x + 63, 368), name, 11, (150, 140, 120) if guide != "book" else INK, UI_FONT, "mm")
    # a row of hotbar cells with the game's icons
    side = 60
    for i, ref in enumerate(ICONS):
        x, y = 40 + i * (side + 4), 500
        c = unground(cell, outline("cell", guide, cell.size)).resize((side, side), Image.LANCZOS)
        canvas.paste(c, (x, y), c)
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


SCREEN_CUT = {"window": (120, 0.3), "button": (76, 0.125), "accent": (76, 0.125), "tab": (66, 0.133),
              "card": (40, 0.33), "field": (24, 0.177)}  # the lines style's parts (guides.THIN)
PARTS = ("window", "button", "accent", "tab", "card", "field", "cell", "crest", "divider", "ring")
DIM = (150, 140, 120)


def lit(img: Image.Image, lo: int = 20, hi: int = 110) -> Image.Image:
    """An ornament painted on black laid over a panel: its brightness is its alpha."""
    rgb = img.convert("RGB")
    rgb.putalpha(rgb.convert("L").point(lambda v: 0 if v <= lo else 255 if v >= hi else (v - lo) * 255 // (hi - lo)))
    return rgb


def portraits(n: int) -> list[Image.Image]:
    found = sorted((GAME / "assets/portraits/people").glob("*/*/*.webp"))
    return [Image.open(found[i * len(found) // n]).convert("RGB") for i in range(n)] if found else []


def screen(raw: Path, seed_of: dict[str, int]) -> Image.Image:
    """The lines style as a game screen: the sheet with its crest, divider, tabs, a field and two buttons, a card of a
    spell, the hotbar with the party's rings. Each part from its own seed."""
    img = {p: Image.open(raw / f"{p}_lines_{seed_of[p]}.png").convert("RGB") for p in PARTS}
    W, H = 1280, 720
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)

    def lay(part: str, xy: tuple[int, int], size: tuple[int, int], look: Image.Image | None = None) -> None:
        pic = look if look is not None else img[part]
        pic = unground(pic, outline("button" if part == "accent" else part, "thin", pic.size))
        piece = nine(pic, *SCREEN_CUT[part], size)
        canvas.paste(piece, xy, piece)

    def whole(part: str, box: tuple[int, int, int, int]) -> None:
        orn = lit(img[part]).resize((box[2], box[3]), Image.LANCZOS)
        canvas.paste(orn, (box[0], box[1]), orn)

    # the sheet
    lay("window", (40, 50), (640, 480))
    whole("crest", (360 - 120, 22, 240, 80))
    text(d, (360, 112), "Тарас", 28, GOLD, anchor="mm")
    text(d, (360, 140), "Монах, уровень 1 · Человек", 14, DIM, UI_FONT, "mm")
    whole("divider", (360 - 230, 150, 460, 58))
    tab = img["tab"]
    for i, name in enumerate(["Персонаж", "Снаряжение", "Заклинания"]):
        look = ImageEnhance.Brightness(tab).enhance(1.25 if i == 0 else 0.8)
        lay("tab", (88 + i * 150, 200), (142, 34), look)
        text(d, (88 + i * 150 + 71, 218), name, 14, TEXT if i == 0 else DIM, UI_FONT, "mm")
    d.line([(80, 234), (640, 234)], fill=(120, 98, 60), width=1)
    for i, line in enumerate(["Хиты 10/10 · КД 15 · Скорость 40 футов", "Сила 10   Ловкость 16   Телосложение 12",
                              "Мудрость 15   Интеллект 10   Харизма 8", "Владение: короткие мечи, простое оружие"]):
        text(d, (96, 256 + i * 30), line, 16, TEXT, UI_FONT)
    lay("field", (96, 392), (300, 34))
    text(d, (110, 409), "Поиск по снаряжению…", 14, (110, 102, 90), UI_FONT, "lm")
    # the model paints the accent's face nearly as dark as a plain button's: the warm gold of the theme's accent on it
    warm = Image.blend(img["accent"], Image.new("RGB", img["accent"].size, (150, 112, 52)), 0.4)
    lay("accent", (330, 452), (150, 40), ImageEnhance.Brightness(warm).enhance(1.1))
    text(d, (405, 472), "Принять", 15, (245, 232, 205), UI_FONT, "mm")
    lay("button", (494, 452), (150, 40))
    text(d, (569, 472), "Отмена", 15, TEXT, UI_FONT, "mm")
    # a spell's card
    lay("card", (720, 80), (320, 210))
    ic = icon("spells/fire_bolt", 44)
    if ic is not None:
        canvas.paste(ic, (740, 100), ic)
    text(d, (796, 108), "Огненный снаряд", 20, GOLD)
    text(d, (796, 134), "Заговор воплощения", 13, DIM, UI_FONT)
    whole("divider", (740, 152, 280, 34))
    for i, line in enumerate(["Дальность 120 футов · 1 действие", "Урон 1d10 огнём, при попадании",
                              "Горючий предмет вспыхивает"]):
        text(d, (742, 196 + i * 24), line, 14, TEXT, UI_FONT)
    # the hotbar: the party's rings, then the cells
    faces = portraits(3)
    for i, face in enumerate(faces):
        x, y, s = 40 + i * 84, 600, 76
        inner = round(s * 0.83)
        f = face.resize((inner, inner), Image.LANCZOS)
        m = Image.new("L", (inner, inner), 0)
        ImageDraw.Draw(m).ellipse([0, 0, inner - 1, inner - 1], fill=255)
        canvas.paste(f, (x + (s - inner) // 2, y + (s - inner) // 2), m)
        whole("ring", (x, y, s, s))
    side = 56
    cell = unground(img["cell"], outline("cell", "thin", img["cell"].size)).resize((side, side), Image.LANCZOS)
    for i, ref in enumerate(ICONS + ["spells/fire_bolt", "items/longsword"]):
        x, y = 310 + i * (side + 4), 610
        canvas.paste(cell, (x, y), cell)
        ic = icon(ref, side - 12)
        if ic is not None:
            canvas.paste(ic, (x + 6, y + 6), ic)
    label = " · ".join(f"{p} {seed_of[p]}" for p in PARTS)
    text(d, (W - 20, H - 14), label, 11, (110, 102, 90), UI_FONT, "rm")
    return canvas


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--raw", type=Path, default=OUT / "raw")
    p.add_argument("--out", type=Path, default=OUT / "mock")
    p.add_argument("--seeds", default="11,22,33")
    p.add_argument("--styles", default="lines,book,plates")
    p.add_argument("--screen", default="", help="the lines screen: a seed for every part, or part=seed,… over --seeds")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    if a.screen:
        picks = dict(x.split("=") for x in a.screen.split(",") if "=" in x)
        for seed in (int(x) for x in a.seeds.split(",")):
            seed_of = {part: int(picks.get(part, seed)) for part in PARTS}
            name = "screen_lines_" + ("_".join(str(seed_of[q]) for q in PARTS) if picks else str(seed)) + ".png"
            screen(a.raw, seed_of).save(a.out / name)
            print(a.out / name)
        return
    for mat in a.styles.split(","):
        for seed in (int(x) for x in a.seeds.split(",")):
            try:
                img = mock(a.raw, mat, seed)
            except FileNotFoundError as e:
                print("missing", e)
                continue
            dest = a.out / f"mock_{mat}_{seed}.png"
            img.save(dest)
            print(dest)


if __name__ == "__main__":
    main()
