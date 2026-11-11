"""Paint the UI parts by Anima over our own guides (ControlNet LLLite depth + lineart): <out>/<part>_<mat>_<seed>.png.
Forge's LLLite breaks the model on the second ControlNet call («'NoneType' object is not callable» on any request
after it), so the checkpoint is unloaded after every frame; never run this beside another job on the same Forge.

    python tools/anima/ui/paint.py [--parts window,button,cell] [--mats leather,wood] [--seeds 11,22,33]
"""
from __future__ import annotations

import argparse
import base64
import io
import sys
import time
from pathlib import Path

from PIL import Image

sys.path.insert(0, r"C:\Code\dnd_llm\tools\anima")
import anima_gen  # noqa: E402  (call, model_settings, CHECKPOINT)

URL = "http://127.0.0.1:7860"
HEAD = "masterpiece, best quality, safe, no humans, simple background, game ui, "
PART = {
    "window": ("ornate frame, border, empty center, panel, corner ornaments, symmetrical",
               "An ornate rectangular frame of a window in a fantasy role-playing game's interface: a raised border "
               "with ornaments at the four corners around a large empty flat panel."),
    "button": ("button, rectangular plate, border, empty center, symmetrical",
               "A wide rectangular button of a fantasy role-playing game's interface: a raised border with small "
               "ornaments at the corners around a flat empty face."),
    "cell": ("square frame, slot, border, empty center, inset, symmetrical",
             "A square slot of a fantasy role-playing game's hotbar: a raised border with small studs at the corners "
             "around an empty dark inset."),
}
MAT = {
    "leather": ("aged bronze, dark leather, rivets, worn metal",
                "The border is aged bronze with worn edges and small rivets, the panel dark brown worn leather."),
    "wood": ("dark wood, carved wood, gold trim, filigree",
             "The border is dark carved wood with thin gold filigree trim, the panel dark smooth wood."),
}
TAIL = ("Soft painterly shading, muted dark colors, seen straight from the front, flat orthographic view, the frame "
        "fills the whole image edge to edge, no text.")
NEGATIVE = ("worst quality, low quality, score_1, score_2, score_3, blurry, jpeg artifacts, text, letters, words, "
            "watermark, signature, logo, person, character, face, creature, animal, scenery, landscape, perspective, "
            "tilted, 3d render, photo")


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
    p.add_argument("--mats", default="leather,wood")
    p.add_argument("--seeds", default="11,22,33")
    p.add_argument("--steps", type=int, default=24)
    p.add_argument("--depth", type=float, default=0.75)
    p.add_argument("--lines", type=float, default=0.55)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    settings = anima_gen.model_settings(URL, anima_gen.CHECKPOINT)
    for part in a.parts.split(","):
        w, h = Image.open(a.guides / f"{part}_depth.png").size
        for mat in a.mats.split(","):
            prompt = HEAD + PART[part][0] + ", " + MAT[mat][0] + ".\n" + PART[part][1] + " " + MAT[mat][1] + " " + TAIL
            for seed in [int(s) for s in a.seeds.split(",")]:
                dest = a.out / f"{part}_{mat}_{seed}.png"
                if dest.exists():
                    continue
                body = {"prompt": prompt, "negative_prompt": NEGATIVE, "steps": a.steps, "cfg_scale": 4.5,
                        "sampler_name": "ER SDE", "width": w, "height": h, "seed": seed,
                        "override_settings": settings, "override_settings_restore_afterwards": False,
                        "alwayson_scripts": {"controlnet": {"args": [
                            unit("anima-lllite-depth-1", a.guides / f"{part}_depth.png", a.depth, 0.8),
                            unit("anima-lllite-lineart-1", a.guides / f"{part}_lines.png", a.lines, 0.6)]}}}
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
