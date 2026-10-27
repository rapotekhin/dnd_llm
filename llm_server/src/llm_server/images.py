"""The frame of an event (v0.7.35): a small agent writes the prompt by the model family's template, an image model
draws it. Image models are config (config.IMAGE_MODELS); a backend is how one is reached — OpenRouter, or an own
endpoint such as AUTOMATIC1111."""

import base64
import json
import logging
import struct
import threading
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

import httpx

from . import prompts
from .agents import build_image_agent
from .config import ImageModel
from .llm.catalog import REQUEST_COSTS
from .llm.providers import PINNED, pinned_for
from .protocol import ErrorCode, ImageModelInfo, ImageParams, ImageResult, Usage
from .session import RpcError

if TYPE_CHECKING:
    from .session import Session

log = logging.getLogger("llm_server.images")

OPENROUTER_IMAGES_URL = "https://openrouter.ai/api/v1/images"  # every image model; FLUX refuses chat/completions
PROMPT_CHARS = 700  # Recraft cuts its prompt at 1000 characters; the agent overshoots and the style goes in front
_SIZES = {"16:9": (1024, 576), "3:2": (960, 640), "4:3": (896, 672), "1:1": (768, 768)}  # an own endpoint's canvas


class ImageError(Exception):
    pass


@dataclass
class Drawn:
    mime: str
    data_b64: str
    cost_usd: float = 0.0


class ImagePrices:
    """What our images really cost, per model (the mean of the last bills), kept in a small JSON file."""

    KEEP = 20

    def __init__(self, path: Path | None):
        self.path = path
        self._lock = threading.Lock()
        self._bills: dict[str, list[float]] = {}
        try:
            self._bills = json.loads(path.read_text(encoding="utf-8")) if path else {}
        except (OSError, ValueError):
            pass

    def observe(self, model: str, usd: float) -> None:
        if usd <= 0:
            return
        with self._lock:
            self._bills[model] = (self._bills.get(model, []) + [round(usd, 6)])[-self.KEEP:]
            if self.path:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                self.path.write_text(json.dumps(self._bills), encoding="utf-8")

    def price(self, model: ImageModel) -> float:
        bills = self._bills.get(model.id)
        return round(sum(bills) / len(bills), 4) if bills else model.usd_per_image


class ImageCatalog:
    def __init__(self, models: tuple[ImageModel, ...], default: str, prices: ImagePrices):
        self.models = {m.id: m for m in models}
        self.default = default if default in self.models else next(iter(self.models), "")
        self.prices = prices

    def infos(self) -> list[ImageModelInfo]:
        return [ImageModelInfo(id=m.id, name=m.name, usd_per_image=self.prices.price(m)) for m in self.models.values()]

    def resolve(self, requested: str | None) -> ImageModel | None:
        return self.models.get(requested or self.default)


async def draw(spec: ImageModel, prompt: str, negative: str, aspect: str, api_key: str,
               client: httpx.AsyncClient | None = None) -> Drawn:
    if client is None:
        async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=20)) as c:
            return await draw(spec, prompt, negative, aspect, api_key, c)
    if spec.backend == "openrouter":
        return await _openrouter(client, spec, prompt, aspect, api_key)
    if spec.backend == "a1111":
        return await _a1111(client, spec, prompt, negative, aspect)
    raise ImageError(f"unknown image backend {spec.backend}")


async def _openrouter(c: httpx.AsyncClient, spec: ImageModel, prompt: str, aspect: str, api_key: str) -> Drawn:
    # No output_format: FLUX refuses it, Recraft ignores it (a 1.6 MB WebP); the client re-encodes what it keeps.
    body = {"model": spec.id, "prompt": prompt, "n": 1, "aspect_ratio": aspect}
    resp = await c.post(OPENROUTER_IMAGES_URL, json=body, headers={"Authorization": f"Bearer {api_key}"})
    if resp.status_code != 200:
        raise ImageError(f"OpenRouter HTTP {resp.status_code}: {resp.text[:200]}")
    data = resp.json()
    try:
        first = data["data"][0]
    except (KeyError, IndexError, TypeError):
        raise ImageError(f"no image in the answer: {json.dumps(data)[:300]}") from None
    cost = float((data.get("usage") or {}).get("cost") or 0)
    if first.get("b64_json"):
        return Drawn(str(first.get("media_type") or "image/png"), str(first["b64_json"]), cost)
    got = await c.get(str(first["url"]))  # a provider may answer with a link
    got.raise_for_status()
    return Drawn(got.headers.get("content-type", "image/png").split(";")[0], base64.b64encode(got.content).decode(), cost)


async def _a1111(c: httpx.AsyncClient, spec: ImageModel, prompt: str, negative: str, aspect: str) -> Drawn:
    w, h = _SIZES.get(aspect, _SIZES["16:9"])
    resp = await c.post(spec.url.rstrip("/") + "/sdapi/v1/txt2img",
                        json={"prompt": prompt, "negative_prompt": negative, "width": w, "height": h, "steps": 25})
    if resp.status_code != 200:
        raise ImageError(f"{spec.url} HTTP {resp.status_code}")
    images = resp.json().get("images") or []
    if not images:
        raise ImageError("no image in the answer")
    return Drawn("image/png", str(images[0]))


# --- handlers -------------------------------------------------------------------


async def stub_image(session: "Session", params: ImageParams) -> ImageResult:
    spec = _spec(session, params)
    return ImageResult(mime="image/png", data_b64=base64.b64encode(_png(16, 9, (92, 74, 56))).decode(),
                       prompt=prompts.image_prompt(spec.template, params.event[:200], params.style), usage=Usage(model="stub"))


async def agent_image(session: "Session", params: ImageParams) -> ImageResult:
    from .turns import _model_id

    token = PINNED.set(pinned_for(_model_id(session, params.model), params.provider))
    try:
        return await _agent_image(session, params)
    finally:
        PINNED.reset(token)


async def _agent_image(session: "Session", params: ImageParams) -> ImageResult:
    from .turns import _model_id, _pick_providers, _usage, _with_retries

    services = session.services
    assert services.model_factory is not None
    spec = _spec(session, params)
    model = _model_id(session, params.model)  # also refuses when the day's budget is spent
    await _pick_providers(services.model_factory(model))
    agent = build_image_agent(services.model_factory(model), prompts.image_instructions(spec.template, PROMPT_CHARS))
    frame = prompts.image_frame(params.event, params.place, params.time, params.hero, params.people)
    billed: list[float] = []
    token = REQUEST_COSTS.set(billed)
    try:
        result = await _with_retries(lambda: agent.run(frame), services.settings.llm_retries, lambda: True)
    except Exception:
        services.budget.add(sum(billed))
        raise
    finally:
        REQUEST_COSTS.reset(token)
    text_usage = _usage(session, model, result.usage, billed)
    prompt = prompts.image_prompt(spec.template, result.output.scene, params.style)
    try:
        drawn = await draw(spec, prompt, result.output.negative, params.aspect, services.settings.openrouter_api_key)
    except (ImageError, httpx.HTTPError) as exc:
        log.warning("image %s failed: %s", spec.id, str(exc)[:300])
        raise RpcError(ErrorCode.LLM_UNAVAILABLE, f"image: {str(exc)[:160]}") from None
    services.budget.add(drawn.cost_usd)
    services.images.prices.observe(spec.id, drawn.cost_usd)
    usage = text_usage.model_copy(update={"cost_usd": round(text_usage.cost_usd + drawn.cost_usd, 6), "model": f"{model} + {spec.id}"})
    if services.trace:
        services.trace.write({"what": "image", "image_model": spec.id, "frame": frame, "prompt": prompt,
                              "negative": result.output.negative, "image_usd": drawn.cost_usd, "mime": drawn.mime,
                              "bytes": len(drawn.data_b64) * 3 // 4, "usage": usage.model_dump(mode="json")})
    return ImageResult(mime=drawn.mime, data_b64=drawn.data_b64, prompt=prompt, usage=usage)


def _spec(session: "Session", params: ImageParams) -> ImageModel:
    spec = session.services.images.resolve(params.image_model)
    if spec is None:
        raise RpcError(ErrorCode.INVALID_PARAMS, f"image model {params.image_model or '(default)'} is not offered by this server")
    return spec


def _png(w: int, h: int, rgb: tuple[int, int, int]) -> bytes:
    """A flat PNG for the stub: the client's path from the bytes to the card is the same."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    rows = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
