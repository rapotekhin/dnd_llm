"""Per-square agreement with the mask: each square's colour stats → nearest class centroid, share right."""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image
OUT = Path(__file__).resolve().parents[2] / "build" / "mask_maps"
ROOT = Path(__file__).resolve().parents[2]
maps = json.loads((ROOT / "build/playtest/map_compare/maps.json").read_text(encoding="utf-8"))
def score(room, path):
    m = maps[room]; w, h = int(m["w"]), len(m["rows"])
    lab = np.asarray(Image.open(OUT / f"mask_{room}.png").convert("RGB"))
    img = np.asarray(Image.open(path).convert("RGB").resize((w * 32, h * 32), Image.LANCZOS)).astype(float)
    X, y = [], []
    for j in range(h):
        for i in range(w):
            c = tuple(lab[j * 32 + 16, i * 32 + 16])
            if c == (0, 0, 0): continue
            cell = img[j * 32 + 4:j * 32 + 28, i * 32 + 4:i * 32 + 28].reshape(-1, 3)
            X.append(np.concatenate([cell.mean(0), cell.std(0)])); y.append(c)
    X = np.array(X); classes = sorted(set(y)); yi = np.array([classes.index(c) for c in y])
    cent = np.array([X[yi == k].mean(0) for k in range(len(classes))])
    pred = np.argmin(((X[:, None] - cent[None]) ** 2).sum(-1), 1)
    return round(100 * (pred == yi).mean())
for room in maps:
    row = {}
    for name, p in [("ours", ROOT / f"build/playtest/map_compare/ours_{room}.png"), ("klein", OUT / f"flux-klein_{room}.png"),
                    ("klein_nat7", OUT / f"flux-klein_{room}_nat.png"), ("klein_nat21", OUT / f"flux-klein_{room}_nat_s21.png"),
                    ("gpt", OUT / f"gpt-image_{room}.png")]:
        if p.exists(): row[name] = score(room, p)
    print(room, row)
