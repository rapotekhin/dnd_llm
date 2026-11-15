from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
OUT = Path(__file__).resolve().parents[2] / "build" / "mask_maps"
font = ImageFont.truetype("arial.ttf", 26)
models = [("flux-klein", "Klein $0.009"), ("flux", "FLUX 3 $0.048"), ("gpt-image", "GPT $0.06"), ("krea-edit", "Krea $0.08"), ("nano-banana", "Banana $0.04")]
side = 560
for room in ("brod-square", "pushcha-edge"):
    rows = [("строгий промпт", "_nat"), ("свободный промпт", "_nat_loose"), ("свободный + сглаженная маска", "_nat_loose_smooth")]
    sheet = Image.new("RGB", (6 * (side + 10), 3 * (side + 46)), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    for r, (rname, suf) in enumerate(rows):
        y = r * (side + 46)
        cells = [("маска: " + rname, OUT / f"mask_{room}{suf}.png")] + [(lab, OUT / f"{m}_{room}{suf}.png") for m, lab in models]
        for c, (lab, p) in enumerate(cells):
            x = c * (side + 10)
            if p.exists():
                pic = Image.open(p).convert("RGB"); pic.thumbnail((side, side))
                sheet.paste(pic, (x, y + 42))
            d.text((x + 6, y + 8), lab, fill=(240, 240, 240), font=font)
    sheet.save(OUT / f"loose_{room}.jpg", quality=88)
    print(OUT / f"loose_{room}.jpg")
