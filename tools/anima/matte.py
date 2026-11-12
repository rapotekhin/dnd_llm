#!/usr/bin/env python3
"""Things cut out of their painted frames by BiRefNet on the GPU, at home, from the raw frames anima_gen drew.

The night run of 2026-11-11: a painted ground is not flat — a dark gradient and a soft shadow under the thing — so the
colour cut of anima_gen ate the dark parts of a thing (a chain mail, a sword's grip) and kept its shadow. A matting
model tells a thing from its ground by what it is, not by its colour. Every variant of the object family
(anima_gen.family: items, ui, groups in the painted style) is cut again from its raw frame: the mask as alpha, the
thing cropped to its own square with a margin, so every thing fills its cell alike, ICON px. A glyph's tile, a medal
and a portrait stay anima_gen's. The stamps are kept: a matted variant is still current for anima_gen.

It runs in its own env with torch (CUDA), apart from the repo's venv:

    venv/Scripts/uv.exe venv --python <a Python 3.10> tools/anima/.venv-matte
    venv/Scripts/uv.exe pip install --python tools/anima/.venv-matte/Scripts/python.exe torch torchvision \
        --index-url https://download.pytorch.org/whl/cu128
    venv/Scripts/uv.exe pip install --python tools/anima/.venv-matte/Scripts/python.exe "transformers<5" timm kornia \
        einops pillow huggingface_hub
    tools/anima/.venv-matte/Scripts/python.exe tools/anima/matte.py tools/anima/jobs/icons.json --only items
    python tools/anima/anima_gen.py tools/anima/jobs/icons.json --style painted --only items --sheets

The model (ZhengPeng7/BiRefNet, 444 MB, its own code — read before it first ran: no network, no commands) is fetched
once into tools/anima/.venv-matte/birefnet and loaded from there. On an RTX 3050 Ti (4 GB) in half precision a frame
takes a fraction of a second.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import anima_gen as gen  # noqa: E402

MODEL_DIR = HERE / ".venv-matte" / "birefnet"
REPO = "ZhengPeng7/BiRefNet"
SIDE = 1024  # BiRefNet's own input
MARGIN = 0.05  # of the thing's square, each side
KEEP = 16  # alpha above this counts for the thing's box
MEAN, STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)


def load(model_dir: Path):
    import torch
    from transformers import AutoModelForImageSegmentation

    if not (model_dir / "model.safetensors").exists():
        from huggingface_hub import snapshot_download

        snapshot_download(REPO, local_dir=str(model_dir), allow_patterns=["*.safetensors", "*.json", "*.py"])
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = AutoModelForImageSegmentation.from_pretrained(str(model_dir), trust_remote_code=True)
    model.to(device).eval()
    if device == "cuda":
        model.half()
    return model, device


def mask_of(model, device: str, rgb: Image.Image) -> Image.Image:
    import torch
    import torchvision.transforms.functional as tf

    x = tf.normalize(tf.to_tensor(rgb.resize((SIDE, SIDE), Image.BILINEAR)), MEAN, STD).unsqueeze(0).to(device)
    if device == "cuda":
        x = x.half()
    with torch.no_grad():
        pred = model(x)[-1].sigmoid()[0, 0].float().cpu()
    return tf.to_pil_image(pred).resize(rgb.size, Image.BILINEAR)


def matte(raw: Image.Image, mask: Image.Image) -> Image.Image:
    """The thing with its mask as alpha, cropped to its own square with a margin, ICON px."""
    rgba = raw.convert("RGBA")
    rgba.putalpha(mask)
    box = mask.point(lambda v: 255 if v > KEEP else 0).getbbox()
    if box is None:
        return rgba.resize((gen.ICON, gen.ICON), Image.LANCZOS)
    x0, y0, x1, y1 = box
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * MARGIN))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    square = Image.new("RGBA", (side, side))
    square.alpha_composite(rgba, (side // 2 - cx, side // 2 - cy))  # what falls outside the frame stays clear
    return square.resize((gen.ICON, gen.ICON), Image.LANCZOS)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("jobs", type=Path, help="the jobs file of anima_gen")
    p.add_argument("--style", default="painted", choices=sorted(gen.STYLES))
    p.add_argument("--out", type=Path, default=None, help="out_<style>/ by default, as anima_gen")
    p.add_argument("--only", default="", help="kinds, comma-separated")
    p.add_argument("--ids", default="", help="ids, comma-separated")
    p.add_argument("--seeds", default="11,22", help="the seeds anima_gen drew with")
    p.add_argument("--model", type=Path, default=MODEL_DIR)
    a = p.parse_args()
    out = a.out or HERE / ("out" if a.style == "flat" else f"out_{a.style}")

    jobs = json.loads(a.jobs.read_text(encoding="utf-8"))["jobs"]
    jobs = [j for j in jobs if gen.family(j, a.style) == "object"]
    if a.only:
        jobs = [j for j in jobs if j["kind"] in a.only.split(",")]
    if a.ids:
        jobs = [j for j in jobs if j["id"] in a.ids.split(",")]
    seeds = [int(s) for s in a.seeds.split(",")]
    todo = [(j, n, s) for j in jobs for n, s in enumerate(gen.seeds_of(j, seeds), 1) if gen.paths(out, j, n, s)[0].exists()]
    print(f"{len(todo)} frames to matte", flush=True)
    if not todo:
        return
    model, device = load(a.model)
    print("model on", device, flush=True)
    started = time.time()
    for i, (job, n, seed) in enumerate(todo, 1):
        raw_path, cut_path = gen.paths(out, job, n, seed)
        rgb = Image.open(raw_path).convert("RGB")
        matte(rgb, mask_of(model, device, rgb)).save(cut_path)
        if i % 50 == 0 or i == len(todo):
            print(f"[{i}/{len(todo)}] {(time.time() - started) / i:.2f} s a frame", flush=True)


if __name__ == "__main__":
    main()
