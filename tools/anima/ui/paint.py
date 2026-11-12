"""Paint the UI parts by Anima over our own guides (ControlNet LLLite depth + lineart): <out>/<part>_<style>_<seed>.png.
Forge's LLLite breaks the model on the second ControlNet call («'NoneType' object is not callable» on any request
after it), so the checkpoint is unloaded after every frame; never run this beside another job on the same Forge.

A style says everything of its look: tags, a sentence for each part, the tail, what to keep out and the family of
guides (guides.py). leather and wood are the first trial (heavy frames); lines is a dark panel framed by thin gold
lines, book a parchment page with ink lines, plates our own icons' riveted steel around dark stone (the trial of
2026-11-12).

    python tools/anima/ui/guides.py
    python tools/anima/ui/paint.py [--parts window,button,cell] [--styles lines,book] [--seeds 11,22,33]
    python tools/anima/ui/paint.py --styles lines --parts accent,tab,card,field,crest,divider,ring   # lines only
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import anima_gen  # noqa: E402  (call, model_settings, CHECKPOINT)
from guides import ORNAMENTS  # noqa: E402

URL = "http://127.0.0.1:7860"
OUT = HERE.parent / "out_ui"
HEAD = "masterpiece, best quality, safe, no humans, simple background, game ui, "
PART = {
    "window": ("frame, border, empty center, panel, symmetrical",
               "A large flat panel of a fantasy role-playing game's interface, framed along its edges, its middle "
               "empty."),
    "button": ("button, rectangular plate, border, empty center, symmetrical",
               "A wide rectangular button of a fantasy role-playing game's interface with a flat empty face."),
    "cell": ("square frame, slot, border, empty center, symmetrical",
             "A square slot of a fantasy role-playing game's hotbar with an empty face."),
    "accent": ("button, rectangular plate, border, empty center, symmetrical",
               "A wide rectangular button of a fantasy role-playing game's interface, the one to press, with a flat "
               "empty face."),
    "tab": ("tab, rounded top, border, empty center, symmetrical",
            "A tab of a fantasy role-playing game's interface, open at the bottom where it sits on its panel, with "
            "a flat empty face."),
    "card": ("frame, border, empty center, small panel, symmetrical",
             "A small flat card of a fantasy role-playing game's interface for a description, its middle empty."),
    "field": ("text field, input box, border, empty center, symmetrical",
              "A long flat text field of a fantasy role-playing game's interface, empty."),
    "crest": ("ornament, flourish, symmetrical, isolated, black background",
              "A small symmetrical ornament for the top of a panel in a fantasy role-playing game's interface, alone."),
    "divider": ("divider, horizontal line, ornament, isolated, black background",
                "A thin horizontal divider of a fantasy role-playing game's interface, alone."),
    "ring": ("circle frame, ring, round frame, empty center, symmetrical, black background",
             "A round frame for a character portrait in a fantasy role-playing game's interface, its inside empty."),
}
GUIDE_PART = {"accent": "button"}  # a part drawn over another part's guides
HEAVY_TAIL = ("Soft painterly shading, muted dark colors, seen straight from the front, flat orthographic view, the "
              "frame fills the whole image edge to edge, no text.")
STYLE = {
    "leather": {
        "guide": "heavy", "tags": "ornate, raised border, corner ornaments, aged bronze, dark leather, rivets, worn metal",
        "say": {p: "A raised border of aged bronze with worn edges, small rivets and ornaments at the corners; the "
                   "panel inside is dark brown worn leather." for p in PART},
        "tail": HEAVY_TAIL, "not": ""},
    "wood": {
        "guide": "heavy", "tags": "ornate, raised border, corner ornaments, dark wood, carved wood, gold trim, filigree",
        "say": {p: "A raised border of dark carved wood with thin gold filigree trim and ornaments at the corners; the "
                   "panel inside is dark smooth wood." for p in PART},
        "tail": HEAVY_TAIL, "not": ""},
    "lines": {
        "guide": "thin", "tags": "minimalist, thin lines, gold lineart, dark, black, elegant, simple, flat",
        "say": {
            "window": "The border is only two thin lines of dull pale gold close together, with a small elegant curl "
                      "in each corner; the panel inside is plain flat near-black charcoal with a faint warm tint, "
                      "almost empty, a little darker toward the middle.",
            "button": "Its outline is two thin lines of dull pale gold close together with softly rounded corners; the "
                      "face inside is plain flat near-black charcoal with a faint warm tint, a little lighter at the "
                      "top.",
            "cell": "Its outline is two thin lines of dull bronze close together; the face inside is plain flat "
                    "near-black, a little darker toward the middle like a shallow hollow.",
            "accent": "Its outline is two thin lines of bright pale gold close together with softly rounded corners; "
                      "the face inside is a deep dark warm bronze-gold, softly lit toward the middle, plain.",
            "tab": "Its outline is two thin lines of dull pale gold along the top and the sides with softly rounded "
                   "top corners and no line along the bottom; the face inside is plain flat near-black charcoal with "
                   "a faint warm tint, a little lighter at the top.",
            "card": "The border is one thin line of dull pale gold with a tiny diamond on each corner; the panel "
                    "inside is plain flat very dark charcoal with a faint warm tint, a little lighter at the top.",
            "field": "Its outline is one thin line of dull bronze; the field inside is plain flat black, a little "
                     "sunken.",
            "crest": "It is drawn in thin lines of dull pale gold: a small diamond in the middle with two elegant "
                     "waving curls running out to each side, on a plain black background.",
            "divider": "It is a single thin line of dull pale gold fading out toward both ends, with a tiny diamond "
                       "and two dots in its middle, on a plain black background.",
            "ring": "It is a thin ring of two close lines of dull pale gold with a tiny diamond at its top and at its "
                    "bottom; inside and outside it is plain black.",
        },
        "tail": ("Clean flat shading, very dark muted colors with the thin gold lines as the only light, seen straight "
                 "from the front, flat orthographic view, the frame fills the whole image edge to edge, no text."),
        "alone": ("Clean flat lines, the thin gold lines as the only light on plain black, seen straight from the "
                  "front, flat orthographic view, centered with empty black space around it, no text."),
        "not": ", thick frame, heavy border, ornate, bronze plate, leather, wood, stone, rivets, bevel, embossed, "
               "relief, bright, colorful, glowing"},
    "book": {
        "guide": "book", "tags": "parchment, old paper, ink lines, brown ink, beige, faded, flat",
        "say": {
            "window": "It is one flat sheet of aged cream parchment seen straight from above, with soft brown stains "
                      "and a faint texture of paper fibres, framed by a thin double line of brown ink set in from its "
                      "edges and a narrow strip of dark worn leather along the very edges; in each corner a small pale "
                      "faded ink drawing of a magic circle; the middle of the sheet is plain and empty.",
            "button": "It is a strip of slightly darker aged parchment framed by a thin double line of dark brown ink "
                      "with softly rounded corners, its face plain and empty.",
            "cell": "It is a square slot drawn on an old page: a thin double border of dark brown ink around a field "
                    "of darker grey-brown worn paper, a little shadowed toward the middle, plain and empty.",
        },
        "tail": ("Soft painterly shading, warm muted colors of old paper and ink, seen straight from the front, flat "
                 "orthographic view, the paper fills the whole image edge to edge with no background around it, no "
                 "text."),
        "not": ", white background, white margin, handwriting, open book, book spine, two pages, scroll, rolled "
               "paper, torn edges, burnt, thick frame, metal, gold, wood, stone, pentagram, glowing, colorful"},
    "plates": {
        "guide": "plate", "tags": "hand-painted, metal texture, steel, rivets, stone texture, dark, clean, bold shapes",
        "say": {
            "window": "A narrow frame of brushed silver-grey steel with a cool blue tint, a round rivet in each corner "
                      "and a thin warm gold edge along its inner side, around a panel of dark brown smooth stone with "
                      "faint cracks near the edges; the middle of the panel is plain, dark and empty.",
            "button": "It is a plate of brushed silver-grey steel with a cool blue tint, softly bevelled edges and a "
                      "small round rivet in each corner, its face smooth, plain and empty, a little darker toward its "
                      "edges.",
            "cell": "A narrow rim of brushed silver-grey steel with a cool blue tint and a small rivet in each corner "
                    "around a deep dark hollow, plain and empty.",
        },
        "tail": ("Soft painterly shading in a clean hand-painted style like the icons of a fantasy role-playing game, "
                 "seen straight from the front, flat orthographic view, the frame fills the whole image edge to edge, "
                 "no text."),
        "not": ", ornate, filigree, leather, wood, parchment, glowing, emblem, symbol, rust"},
}
NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, blurry, jpeg artifacts, text, letters, words, "
            "watermark, signature, logo, title bar, close button, computer window, desktop, person, character, face, "
            "creature, animal, scenery, landscape, perspective, tilted, 3d render, photo")


def prompt(part: str, style: str) -> tuple[str, str]:
    s = STYLE[style]
    tags, said = PART[part]
    tail = s["alone"] if part in ORNAMENTS else s["tail"]  # an ornament is laid whole, not edge to edge
    return (HEAD + tags + ", " + s["tags"] + ".\n" + said + " " + s["say"][part] + " " + tail,
            NEGATIVE + s["not"])


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def unit(model: str, image: Path, weight: float, end: float) -> dict:
    return {"enabled": True, "module": "None", "model": model, "weight": weight, "image": b64(image),
            "resize_mode": "Just Resize", "guidance_start": 0.0, "guidance_end": end, "control_mode": "Balanced",
            "pixel_perfect": False, "processor_res": 512}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--guides", type=Path, default=OUT / "guides")
    p.add_argument("--out", type=Path, default=OUT / "raw")
    p.add_argument("--parts", default="window,button,cell")
    p.add_argument("--styles", default="lines,book")
    p.add_argument("--seeds", default="11,22,33")
    p.add_argument("--steps", type=int, default=24)
    p.add_argument("--depth", type=float, default=0.75)
    p.add_argument("--lines", type=float, default=0.55)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    settings = anima_gen.model_settings(URL, anima_gen.CHECKPOINT)
    for part in a.parts.split(","):
        for style in a.styles.split(","):
            guide = f"{GUIDE_PART.get(part, part)}_{STYLE[style]['guide']}"
            w, h = Image.open(a.guides / f"{guide}_depth.png").size
            pos, neg = prompt(part, style)
            for seed in [int(s) for s in a.seeds.split(",")]:
                dest = a.out / f"{part}_{style}_{seed}.png"
                if dest.exists():
                    continue
                body = {"prompt": pos, "negative_prompt": neg, "steps": a.steps, "cfg_scale": 4.5,
                        "sampler_name": "ER SDE", "width": w, "height": h, "seed": seed,
                        "override_settings": settings, "override_settings_restore_afterwards": False,
                        "alwayson_scripts": {"controlnet": {"args": [
                            unit("anima-lllite-depth-1", a.guides / f"{guide}_depth.png", a.depth, 0.8),
                            unit("anima-lllite-lineart-1", a.guides / f"{guide}_lines.png", a.lines, 0.6)]}}}
                t = time.time()
                for attempt in range(2):  # Forge's LLLite breaks the model on the second ControlNet call: unload after each
                    try:
                        r = anima_gen.call(URL, "/sdapi/v1/txt2img", body)
                        break
                    except Exception as exc:  # noqa: BLE001
                        print(f"  {exc}; unload and again", flush=True)
                        anima_gen.call(URL, "/sdapi/v1/unload-checkpoint", {})
                else:
                    raise RuntimeError("forge fails")
                Image.open(io.BytesIO(base64.b64decode(r["images"][0]))).convert("RGB").save(dest)
                anima_gen.call(URL, "/sdapi/v1/unload-checkpoint", {})
                print(f"{dest.name} {time.time() - t:.0f}s", flush=True)


if __name__ == "__main__":
    main()
