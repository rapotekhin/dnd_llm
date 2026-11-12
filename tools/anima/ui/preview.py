"""Screens of the game in the lines style from the author's picks: the frames of `out_ui/raw/<part>_lines_<seed>.png`
(a seed per part) and the icons as picked (`icon_of`), laid out as the game lays them at 1600×900 — the screen out of a
fight, a fight, the character's gear, the spell book, the sheet with a card. Not the game itself: a mock to judge the
look before the theme is made (pick.py «Превью», mock.py --screen).

    python tools/anima/ui/preview.py                       # every screen with the seeds of picks_lines.json
    python tools/anima/ui/preview.py --only fight,gear
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageEnhance

from mock import (BG, DIM, FONT, GAME, GOLD, OUT, PARTS, SCREEN_CUT, TEXT, UI_FONT, lit, nine, outline, states,
                  text, unground)

HERE = Path(__file__).resolve().parent
SEEDS = [11, 22, 33]  # the seeds the frames were drawn with (paint.py --seeds); a pick n is SEEDS[n - 1]
PICKS = HERE / "picks_lines.json"
W, H = 1600, 900
SCREENS = {"game": "Экран", "fight": "Бой", "gear": "Снаряжение", "book": "Книга заклинаний", "sheet": "Лист и карточка"}
NAMES = {"window": "Окно", "button": "Кнопка", "accent": "Главная кнопка", "tab": "Вкладка", "card": "Карточка",
         "field": "Поле ввода", "cell": "Ячейка", "crest": "Герб над окном", "divider": "Разделитель",
         "ring": "Кольцо портрета"}  # the parts as the picker names them
FAINT = (110, 102, 90)
RED = (190, 70, 60)
GREEN = (120, 170, 90)
# what the hotbar holds, section by section (the game's own order); a ref is «<kind>/<id>», a cell left empty is ""
BAR = {"Общие": ["ui/place", "ui/board", "ui/sneak", "ui/look"],
       "Боевые": ["acts/dash", "acts/disengage", "acts/dodge", "acts/help", "acts/hide", "acts/shove"],
       "Класс": ["spells/sacred_flame", "spells/guiding_bolt", "spells/bless", "spells/cure_wounds",
                 "spells/healing_word", "features/channel_divinity"],
       "Вещи": ["items/healing_potion", "items/torch", "acts/throw", "acts/use_item"],
       "Дела": ["ui/gather", "ui/wilds"],
       "Пассивные": ["ui/nonlethal"]}
BUTTONS = ["ui/rest_short", "ui/sheet", "ui/map", "ui/camp", "ui/journal", "ui/menu"]
PACK = ["items/longsword", "items/dagger", "items/shortbow", "items/arrows", "items/healing_potion", "items/rations",
        "items/bread", "items/waterskin", "items/torch", "items/tinderbox", "items/rope", "items/bedroll",
        "items/backpack", "items/crowbar", "items/lantern", "items/amulet", "items/spell_scroll_acid_arrow",
        "items/potion_of_climbing", "items/greataxe", "items/leather_armor"]
COUNT = {"items/healing_potion": "2", "items/arrows": "20", "items/torch": "10", "items/rations": "5"}
CIRCLES = [("Заговоры", ["spells/sacred_flame", "spells/fire_bolt", "spells/thunderwave"]),
           ("1 круг", ["spells/bless", "spells/cure_wounds", "spells/guiding_bolt", "spells/healing_word",
                       "spells/shield", "spells/sleep", "spells/magic_missile"]),
           ("2 круг", ["spells/misty_step", "spells/web", "spells/spiritual_weapon"]),
           ("3 круг", ["spells/fireball", "spells/haste"])]


FACES = ["human/female", "human/male", "elf/female"]  # Aira, Bruno, Mira


def game_icon(ref: str) -> Path | None:
    f = GAME / "assets/icons" / f"{ref}.png"
    return f if f.exists() else None


class Kit:
    """The parts of one pick and the icons, laid on a canvas."""

    def __init__(self, raw: Path, seed_of: dict[str, int], icon_of: Callable[[str], Path | None] = game_icon):
        self.img = {p: Image.open(raw / f"{p}_lines_{seed_of[p]}.png").convert("RGB") for p in PARTS}
        self.seed_of = seed_of
        self.icon_of = icon_of
        self.cell_pic = unground(self.img["cell"], outline("cell", "thin", self.img["cell"].size))
        people = GAME / "assets/portraits/people"
        self.faces = [f for f in (next(iter(sorted((people / who).glob("adult__*.webp"))), None)
                                  for who in FACES) if f is not None]
        wolf = sorted((GAME / "assets/portraits/monsters").glob("wolf__*.webp"))
        self.wolf = wolf[0] if wolf else None

    # -- the parts
    def lay(self, c: Image.Image, part: str, xy: tuple[int, int], size: tuple[int, int],
            look: Image.Image | None = None) -> None:
        """A framed part (window, button, accent, tab, card, field) in nine pieces at `size`."""
        pic = look if look is not None else self.img[part]
        pic = unground(pic, outline("button" if part == "accent" else part, "thin", pic.size))
        piece = nine(pic, *SCREEN_CUT[part], size)
        c.paste(piece, xy, piece)

    def accent(self, c: Image.Image, xy: tuple[int, int], size: tuple[int, int], label: str) -> None:
        """The main button: the accent part warmed to the theme's gold (the model paints its face nearly as dark)."""
        warm = Image.blend(self.img["accent"], Image.new("RGB", self.img["accent"].size, (150, 112, 52)), 0.4)
        self.lay(c, "accent", xy, size, ImageEnhance.Brightness(warm).enhance(1.1))
        text(ImageDraw.Draw(c), (xy[0] + size[0] // 2, xy[1] + size[1] // 2), label, 16, (245, 232, 205), UI_FONT, "mm")

    def button(self, c: Image.Image, xy: tuple[int, int], size: tuple[int, int], label: str) -> None:
        self.lay(c, "button", xy, size)
        text(ImageDraw.Draw(c), (xy[0] + size[0] // 2, xy[1] + size[1] // 2), label, 15, TEXT, UI_FONT, "mm")

    def tab(self, c: Image.Image, xy: tuple[int, int], size: tuple[int, int], label: str, on: bool) -> None:
        look = ImageEnhance.Brightness(self.img["tab"]).enhance(1.25 if on else 0.8)
        self.lay(c, "tab", xy, size, look)
        text(ImageDraw.Draw(c), (xy[0] + size[0] // 2, xy[1] + size[1] // 2 + 1), label, 13 if size[1] < 30 else 15,
             TEXT if on else DIM, UI_FONT, "mm")

    def whole(self, c: Image.Image, part: str, box: tuple[int, int, int, int]) -> None:
        """An ornament (crest, divider, ring) painted on black: its brightness is its alpha."""
        orn = lit(self.img[part]).resize((box[2], box[3]), Image.LANCZOS)
        c.paste(orn, (box[0], box[1]), orn)

    def icon(self, ref: str, side: int) -> Image.Image | None:
        f = self.icon_of(ref) if ref else None
        return Image.open(f).convert("RGBA").resize((side, side), Image.LANCZOS) if f else None

    def cell(self, c: Image.Image, xy: tuple[int, int], side: int, ref: str = "", badge: str = "",
             grey: bool = False, picked: bool = False) -> None:
        frame = self.cell_pic.resize((side, side), Image.LANCZOS)
        if picked:
            frame = ImageEnhance.Brightness(frame).enhance(1.5)
        c.paste(frame, xy, frame)
        ic = self.icon(ref, side - round(side * 0.2))
        if ic is not None:
            if grey:
                ic = ImageEnhance.Brightness(ImageEnhance.Color(ic).enhance(0.1)).enhance(0.45)
            o = round(side * 0.1)
            c.paste(ic, (xy[0] + o, xy[1] + o), ic)
        if badge:
            text(ImageDraw.Draw(c), (xy[0] + side - 5, xy[1] + side - 4), badge, 11, TEXT, UI_FONT, "rd")

    def ring(self, c: Image.Image, xy: tuple[int, int], side: int, face: Path | None, badge: str = "") -> None:
        """A portrait in the ring ornament, a level or a number on its badge."""
        if face is not None:
            inner = round(side * 0.83)
            f = Image.open(face).convert("RGB").resize((inner, inner), Image.LANCZOS)
            m = Image.new("L", (inner, inner), 0)
            ImageDraw.Draw(m).ellipse([0, 0, inner - 1, inner - 1], fill=255)
            c.paste(f, (xy[0] + (side - inner) // 2, xy[1] + (side - inner) // 2), m)
        self.whole(c, "ring", (xy[0], xy[1], side, side))
        if badge:
            d = ImageDraw.Draw(c)
            bx, by = xy[0] + side - 22, xy[1] + side - 24
            d.ellipse([bx, by, bx + 24, by + 24], fill=BG, outline=GOLD)
            text(d, (bx + 12, by + 12), badge, 12, TEXT, UI_FONT, "mm")

    def sample(self, part: str, side: int = 256) -> Image.Image:
        """One part alone as the picker shows it: laid at a size the game would give it, on the theme's dark."""
        c = Image.new("RGB", (side, side), BG)
        if part == "window":
            self.lay(c, part, (8, 30), (240, 196))
        elif part in ("button", "field"):
            self.lay(c, part, (18, 104), (220, 48))
        elif part == "accent":
            self.accent(c, (18, 104), (220, 48), "Действовать")
        elif part == "tab":
            self.tab(c, (8, 108), (118, 40), "Вещи", True)
            self.tab(c, (130, 108), (118, 40), "Книга", False)
        elif part == "card":
            self.lay(c, part, (10, 46), (236, 164))
        elif part == "cell":
            for i, ref in enumerate(["items/longsword", "spells/bless", "acts/dash", "ui/map"]):
                self.cell(c, (24 + (i % 2) * 108, 24 + (i // 2) * 108), 100, ref)
        elif part == "crest":
            self.whole(c, part, (8, 92, 240, 72))
        elif part == "divider":
            self.whole(c, part, (8, 108, 240, 40))
        elif part == "ring":
            self.ring(c, (38, 38), 180, self.faces[0] if self.faces else None)
        return c

    # -- the screen's own blocks
    def party(self, c: Image.Image, fight: bool) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "window", (8, 8), (290, 150))
        self.ring(c, (26, 26), 86, self.faces[0] if self.faces else None, "19")
        text(d, (124, 44), "Айра", 30, GOLD, FONT)
        d.rounded_rectangle([124, 84, 278, 92], 3, fill=(60, 50, 40))
        d.rounded_rectangle([124, 84, 124 + (62 if fight else 154), 92], 3, fill=RED if fight else GREEN)
        for i, ref in enumerate(["ui/food", "ui/water", "ui/sleep"]):
            self.cell(c, (124 + i * 42, 102), 38, ref)
        self.lay(c, "window", (8, 166), (290, 518))
        text(d, (30, 196), "Рядом", 15, DIM, UI_FONT)
        for i, (name, face) in enumerate(zip(["Бруно, трактирщик", "Мира, травница"], self.faces[1:3])):
            self.ring(c, (28, 220 + i * 70), 56, face)
            text(d, (96, 248 + i * 70), name, 15, TEXT, UI_FONT, "lm")

    def map_panel(self, c: Image.Image, fight: bool) -> None:
        d = ImageDraw.Draw(c)
        top = 92 if fight else 72
        self.lay(c, "window", (304, top), (800, 684 - top))
        x0, y0, x1, y1 = 330, top + 26, 1078, 658
        d.rectangle([x0, y0, x1, y1], fill=(38, 34, 28))
        step = 34
        for x in range(x0, x1, step):
            d.line([(x, y0), (x, y1)], fill=(46, 41, 34))
        for y in range(y0, y1, step):
            d.line([(x0, y), (x1, y)], fill=(46, 41, 34))
        d.rectangle([x0, 380, x1, 410], fill=(70, 64, 54))  # the road
        if fight:
            self.ring(c, (680, 372), 46, self.faces[0] if self.faces else None)
            self.ring(c, (728, 372), 46, self.wolf)
            self.ring(c, (840, 300), 46, self.wolf)
        else:
            self.ring(c, (690, 372), 46, self.faces[0] if self.faces else None)
            self.ring(c, (560, 250), 46, self.faces[1] if len(self.faces) > 1 else None)

    def header(self, c: Image.Image) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "window", (304, 8), (800, 60))
        text(d, (330, 38), "Сумеречная Пуща › Опушка Пущи", 17, TEXT, UI_FONT, "lm")
        text(d, (870, 38), "утро 10:00", 14, DIM, UI_FONT, "rm")
        text(d, (1080, 38), "Выходы (2) ▾", 17, GOLD, UI_FONT, "rm")

    def queue(self, c: Image.Image) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "card", (304, 8), (800, 80))
        text(d, (330, 48), "Раунд 2", 16, DIM, UI_FONT, "lm")
        for i, face in enumerate([self.faces[0] if self.faces else None, self.wolf, self.wolf]):
            self.ring(c, (420 + i * 66, 16), 62 if i == 0 else 54, face)
        text(d, (630, 48), "Ход Айры", 17, GOLD, FONT, "lm")

    def chat(self, c: Image.Image, lines: list[tuple[str, bool]], hint: str) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "window", (1110, 8), (482, 884))
        y = 44
        for line, story in lines:
            if story:
                for part in wrap(line, 40):
                    text(d, (1138, y), part, 18, TEXT, FONT)
                    y += 30
            else:
                for part in wrap(line, 56):
                    text(d, (1138, y), part, 13, FAINT, UI_FONT)
                    y += 20
            y += 6
        self.whole(c, "divider", (1150, 744, 400, 30))
        d.rectangle([1138, 784, 1148, 794], fill=GREEN)
        text(d, (1158, 789), "Мастер на связи", 14, DIM, UI_FONT, "lm")
        self.lay(c, "field", (1138, 818), (250, 50))
        text(d, (1152, 843), hint, 15, FAINT, UI_FONT, "lm")
        self.accent(c, (1396, 818), (172, 50), "Действовать")

    def hotbar(self, c: Image.Image, fight: bool) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "window", (8, 690), (1096, 202))
        self.ring(c, (22, 742), 96, self.faces[0] if self.faces else None, "19")
        side, gap = 44, 4
        self.cell(c, (126, 740), side, "items/mace")
        self.cell(c, (174, 740), side, "items/shield")
        self.cell(c, (126, 790), side, "ui/weapon_set", picked=True)
        self.cell(c, (174, 790), side, "ui/weapon_set")
        x = 232
        names = []
        for name, refs in BAR.items():
            cols = (len(refs) + 1) // 2
            names.append((name, x, cols))
            for i, ref in enumerate(refs):
                grey = (name == "Боевые" and not fight) or (name == "Дела" and fight)
                self.cell(c, (x + (i // 2) * (side + gap), 740 + (i % 2) * (side + 6)), side, ref,
                          COUNT.get(ref, ""), grey)
            x += cols * (side + gap) + 8
            d.line([(x - 6, 742), (x - 6, 832)], fill=(150, 112, 60), width=2)
        if fight:
            self.ring(c, (x + 4, 746), 84, None)
            text(d, (x + 46, 779), "Конец", 15, GOLD, UI_FONT, "mm")
            text(d, (x + 46, 799), "хода", 15, GOLD, UI_FONT, "mm")
        else:
            self.cell(c, (x + 10, 752), 72, "ui/wait")
        bx = x + 96
        for i, ref in enumerate(BUTTONS):
            self.cell(c, (bx + (i % 3) * 48, 744 + (i // 3) * 50), 44, ref)
        tx = 232
        for i, (name, _x, _cols) in enumerate([("Всё", 0, 0)] + names):
            w = 64 if i == 0 else max(64, len(name) * 9 + 20)
            self.tab(c, (tx, 846), (w, 28), name, i == 0)
            tx += w + 4
        if fight:
            for i, col in enumerate([GREEN, (220, 170, 60), (170, 120, 220)]):
                d.ellipse([240 + i * 24, 712, 254 + i * 24, 726], fill=col)
            text(d, (318, 719), "→ 6", 15, TEXT, UI_FONT, "lm")

    def card(self, c: Image.Image, xy: tuple[int, int], ref: str, name: str, sub: str, lines: list[str]) -> None:
        d = ImageDraw.Draw(c)
        x, y = xy
        self.lay(c, "card", (x, y), (340, 124 + 26 * len(lines)))
        ic = self.icon(ref, 48)
        if ic is not None:
            c.paste(ic, (x + 22, y + 20), ic)
        text(d, (x + 82, y + 26), name, 20, GOLD, FONT)
        text(d, (x + 82, y + 52), sub, 13, DIM, UI_FONT)
        self.whole(c, "divider", (x + 30, y + 70, 280, 26))
        for i, line in enumerate(lines):
            text(d, (x + 24, y + 104 + i * 26), line, 14, TEXT, UI_FONT)

    def window(self, c: Image.Image, title: str, tab: int) -> tuple[int, int, int, int]:
        """The character window over a dimmed screen: its frame, crest, title, the three tabs as icons."""
        dim = Image.new("RGBA", c.size, (10, 8, 6, 150))
        c.paste(dim, (0, 0), dim)
        box = (180, 20, 1240, 690)
        self.lay(c, "window", box[:2], box[2:])
        self.whole(c, "crest", (box[0] + box[2] // 2 - 140, 2, 280, 70))
        d = ImageDraw.Draw(c)
        text(d, (box[0] + 40, 80), title, 32, GOLD, FONT)
        for i, ref in enumerate(["ui/inventory", "ui/spellbook", "ui/sheet"]):
            self.cell(c, (box[0] + box[2] // 2 - 80 + i * 56, 70), 50, ref, picked=i == tab)
        text(d, (box[0] + box[2] // 2, 136), "Уровень 3 · опыт 900 из 2700", 14, DIM, UI_FONT, "mm")
        text(d, (box[0] + box[2] - 50, 82), "×", 30, DIM, UI_FONT, "mm")
        self.whole(c, "divider", (box[0] + box[2] // 2 - 220, 146, 440, 34))
        return box

    def stats(self, c: Image.Image, x: int, y: int) -> None:
        d = ImageDraw.Draw(c)
        self.lay(c, "card", (x, y), (300, 470))
        text(d, (x + 24, y + 26), "Жрица, уровень 3", 22, GOLD, FONT)
        text(d, (x + 24, y + 58), "человек · молодая, высокая", 13, DIM, UI_FONT)
        for i, (ab, v) in enumerate([("СИЛ", 12), ("ЛОВ", 10), ("ТЕЛ", 14), ("ИНТ", 9), ("МДР", 16), ("ХАР", 13)]):
            text(d, (x + 36 + i * 44, y + 98), ab, 11, DIM, UI_FONT, "mm")
            text(d, (x + 36 + i * 44, y + 124), str(v), 22, TEXT, UI_FONT, "mm")
        self.whole(c, "divider", (x + 20, y + 150, 260, 26))
        text(d, (x + 24, y + 186), "Умения и черты", 14, GOLD, UI_FONT)
        for i, (ref, name) in enumerate([("features/channel_divinity", "Божественный канал"),
                                         ("features/disciple_of_life", "Ученик жизни"),
                                         ("traits/darkvision", "Тёмное зрение")]):
            self.cell(c, (x + 22, y + 210 + i * 50), 42, ref)
            text(d, (x + 74, y + 231 + i * 50), name, 15, TEXT, UI_FONT, "lm")
        text(d, (x + 24, y + 380), "Защиты: яд — сопротивление", 13, DIM, UI_FONT)
        text(d, (x + 24, y + 404), "Нужды: еда 80 · вода 65 · сон 90", 13, DIM, UI_FONT)


def wrap(s: str, width: int) -> list[str]:
    out, line = [], ""
    for word in s.split():
        if line and len(line) + 1 + len(word) > width:
            out.append(line)
            line = word
        else:
            line = f"{line} {word}".strip()
    return out + ([line] if line else [])


STORY = [("Опушка дышит сыростью: туман лежит в низинах, и где-то за ольхами перекликаются сойки.", True),
         ("Бруно машет вам с телеги: «Дорога на мельницу свободна, но волки опять вышли к тропе».", True)]
FIGHT = [("Из подлеска бесшумно выходят два серых волка.", True),
         ("Бой! Инициатива: Айра 17, Серый волк 12, Серый волк 9", False),
         ("▸ Броски раунда (3)", False),
         ("Айра — Священное пламя по Серому волку: спасбросок ЛОВ 8 против Сл 13 — 7 урона излучением", False),
         ("Серый волк — Укус по Айре: 15 против КД 18 — промах", False)]


def render(name: str, k: Kit) -> Image.Image:
    c = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(c)
    fight = name == "fight"
    k.party(c, fight)
    if name == "sheet":
        return sheet(c, k)
    if fight:
        k.queue(c)
    else:
        k.header(c)
    k.map_panel(c, fight)
    k.hotbar(c, fight)
    k.chat(c, FIGHT if fight else STORY,
           "Импровизация: что вы делаете?" if fight else "Что вы делаете?")
    if fight:
        text(d, (346, 640), "Ваш ход · Shift + клик — встать на клетку с вещью", 14, DIM, UI_FONT, "lm")
        k.card(c, (760, 430), "spells/sacred_flame", "Священное пламя", "Заговор воплощения · 1 действие",
               ["Цель — спасбросок Ловкости, Сл 13", "1d8 излучением, укрытие не спасает", "Шанс: 60%"])
    if name == "gear":
        gear(c, k)
    if name == "book":
        book(c, k)
    return c


def gear(c: Image.Image, k: Kit) -> None:
    x0, y0, w, h = k.window(c, "Айра", 0)
    d = ImageDraw.Draw(c)
    k.stats(c, x0 + 30, 196)
    # the doll: the worn slots around the figure, the sets, the AC, the belt
    dx = x0 + 360
    for i, ref in enumerate(["", "", "items/chain_mail", "", ""]):
        k.cell(c, (dx, 200 + i * 54), 48, ref)
    for i, ref in enumerate(["items/amulet", "", "", "", ""]):
        k.cell(c, (dx + 250, 200 + i * 54), 48, ref)
    d.ellipse([dx + 130, 210, dx + 170, 250], outline=(120, 98, 60), width=2)
    d.line([(dx + 150, 250), (dx + 150, 380)], fill=(120, 98, 60), width=2)
    d.line([(dx + 110, 270), (dx + 190, 270)], fill=(120, 98, 60), width=2)
    d.line([(dx + 150, 380), (dx + 125, 450)], fill=(120, 98, 60), width=2)
    d.line([(dx + 150, 380), (dx + 175, 450)], fill=(120, 98, 60), width=2)
    text(d, (dx + 40, 478), "В руках", 13, DIM, UI_FONT, "mm")
    k.cell(c, (dx, 492), 50, "items/mace", picked=True)
    k.cell(c, (dx + 52, 492), 50, "items/shield", picked=True)
    k.ring(c, (dx + 118, 484), 64, None)
    text(d, (dx + 150, 512), "18", 22, TEXT, UI_FONT, "mm")
    text(d, (dx + 150, 532), "КД", 10, DIM, UI_FONT, "mm")
    text(d, (dx + 248, 478), "Запасной", 13, DIM, UI_FONT, "mm")
    k.cell(c, (dx + 196, 492), 50, "items/shortbow")
    k.cell(c, (dx + 248, 492), 50, "")
    text(d, (dx + 150, 566), "Пояс", 13, DIM, UI_FONT, "mm")
    for i, ref in enumerate(["items/torch", "items/healing_potion", "", "items/spell_scroll_acid_arrow", ""]):
        k.cell(c, (dx + 22 + i * 52, 580), 48, ref, COUNT.get(ref, ""))
    # the things: the groups, the search, the grid
    gx = x0 + 690
    for i, ref in enumerate(["ui/all", "groups/weapon", "groups/armor", "groups/potion", "groups/food", "groups/tool"]):
        k.cell(c, (gx + i * 46, 196), 42, ref, picked=i == 0)
    k.lay(c, "field", (gx + 282, 194), (170, 46))
    text(d, (gx + 296, 217), "Поиск по имени", 14, FAINT, UI_FONT, "lm")
    for i in range(36):
        ref = PACK[i] if i < len(PACK) else ""
        k.cell(c, (gx + (i % 7) * 52, 256 + (i // 7) * 52), 50, ref, COUNT.get(ref, ""), picked=i == 4)
    d.rounded_rectangle([gx, 584, gx + 360, 592], 3, fill=(60, 50, 40))
    d.rounded_rectangle([gx, 584, gx + 200, 592], 3, fill=GREEN)
    text(d, (gx, 612), "Вес: 96 из 180 фнт.   Настроено: 1 из 3", 14, DIM, UI_FONT)
    k.card(c, (gx + 30, 380), "items/healing_potion", "Зелье лечения", "Зелье · обычное · 50 зм",
           ["Восстанавливает 2d4 + 2 хита", "Бонусное действие"])


def book(c: Image.Image, k: Kit) -> None:
    x0, y0, w, h = k.window(c, "Айра", 1)
    d = ImageDraw.Draw(c)
    k.stats(c, x0 + 30, 196)
    tx = x0 + 360
    for i, name in enumerate(["Жрица", "Общие", "Реакции"]):
        k.tab(c, (tx + i * 160, 196), (152, 38), name, i == 0)
    text(d, (tx, 254), "Ячейки:  1 круг ●●●○   2 круг ●●", 14, DIM, UI_FONT)
    y = 282
    for title, refs in CIRCLES:
        text(d, (tx, y + 10), title, 16, GOLD, FONT)
        k.whole(c, "divider", (tx + 110, y, 200, 26))
        y += 34
        for i, ref in enumerate(refs):
            k.cell(c, (tx + i * 56, y), 52, ref, picked=ref == "spells/bless")
        y += 66
    k.card(c, (x0 + 700, 260), "spells/bless", "Благословение", "1 круг · очарование · концентрация",
           ["До трёх существ: +1d4 к атакам", "и спасброскам, 1 минута", "Дальность 30 футов"])


def sheet(c: Image.Image, k: Kit) -> Image.Image:
    """The old trial screen: a window with its crest, tabs, field and buttons, a card, the states of a button."""
    d = ImageDraw.Draw(c)
    k.lay(c, "window", (330, 60), (700, 520))
    k.whole(c, "crest", (680 - 140, 34, 280, 80))
    text(d, (680, 128), "Айра", 30, GOLD, anchor="mm")
    text(d, (680, 158), "Жрица, уровень 3 · Человек", 14, DIM, UI_FONT, "mm")
    k.whole(c, "divider", (680 - 240, 170, 480, 54))
    for i, name in enumerate(["Персонаж", "Снаряжение", "Заклинания"]):
        k.tab(c, (400 + i * 156, 222), (148, 36), name, i == 0)
    for i, line in enumerate(["Хиты 24/24 · КД 18 · Скорость 30 футов", "Сила 12   Ловкость 10   Телосложение 14",
                              "Мудрость 16   Интеллект 9   Харизма 13"]):
        text(d, (400, 286 + i * 30), line, 16, TEXT, UI_FONT)
    k.lay(c, "field", (400, 390), (320, 44))
    text(d, (416, 412), "Поиск по снаряжению…", 14, FAINT, UI_FONT, "lm")
    for i, (name, look) in enumerate(states(k.img["button"]).items()):
        k.lay(c, "button", (400 + i * 150, 470), (140, 42), look)
        text(d, (470 + i * 150, 491), "Принять", 15, TEXT if name != "недоступна" else (120, 112, 100), UI_FONT, "mm")
        text(d, (470 + i * 150, 524), name, 11, FAINT, UI_FONT, "mm")
    k.accent(c, (850, 400), (150, 42), "Принять")
    k.card(c, (1080, 80), "spells/fire_bolt", "Огненный снаряд", "Заговор воплощения",
           ["Дальность 120 футов · 1 действие", "Урон 1d10 огнём, при попадании", "Горючий предмет вспыхивает"])
    k.hotbar(c, False)
    return c


def seeds_of(picks: Path = PICKS) -> dict[str, int]:
    """A part's seed by the author's pick (absent — the first seed)."""
    v = json.loads(picks.read_text(encoding="utf-8")).get("variant", {}) if picks.exists() else {}
    return {p: SEEDS[int(v.get(f"frames/{p}", 1)) - 1] for p in PARTS}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--raw", type=Path, default=OUT / "raw")
    p.add_argument("--out", type=Path, default=OUT / "preview")
    p.add_argument("--only", default="", help="screens, comma-separated: " + ",".join(SCREENS))
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    k = Kit(a.raw, seeds_of())
    for name in (a.only.split(",") if a.only else SCREENS):
        dest = a.out / f"{name}.png"
        render(name, k).save(dest)
        print(dest)


if __name__ == "__main__":
    main()
