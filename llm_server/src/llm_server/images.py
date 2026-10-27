"""The frame of an event (v0.7.35): a small agent writes the prompt by the model family's template, an image model
draws it. Image models are config (config.IMAGE_MODELS); a backend is how one is reached — OpenRouter, or an own
endpoint such as AUTOMATIC1111."""

import base64
import json
import logging
import struct
import threading
import zlib
from dataclasses import dataclass, replace
from pathlib import Path
from typing import TYPE_CHECKING

import httpx

from . import prompts
from .agents import build_image_agent
from .config import SD_MODELS, ImageModel
from .llm.catalog import REQUEST_COSTS
from .llm.providers import PINNED, pinned_for
from .protocol import ErrorCode, ImageModelInfo, ImageParams, ImageResult, Usage
from .session import RpcError

if TYPE_CHECKING:
    from .session import Session

log = logging.getLogger("llm_server.images")

OPENROUTER_IMAGES_URL = "https://openrouter.ai/api/v1/images"  # every image model; FLUX refuses chat/completions
PROMPT_CHARS = 700  # Recraft cuts its prompt at 1000 characters; the agent overshoots and the style goes in front


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
    """The models of the config, and those of an own server at `own_url` as it answers at the latest hello."""

    def __init__(self, models: tuple[ImageModel, ...], default: str, prices: ImagePrices, own_url: str = ""):
        self.base = models
        self.models = {m.id: m for m in models}
        self.wanted = default  # may be an own server's model, offered only while it answers
        self.default = default if default in self.models else next(iter(self.models), "")
        self.prices = prices
        self.own_url = own_url

    async def refresh(self) -> None:
        if self.own_url:
            own = await own_image_models(self.own_url)
            self.models = {m.id: m for m in (*self.base, *own)}
            self.default = self.wanted if self.wanted in self.models else next(iter(self.models), "")

    def infos(self) -> list[ImageModelInfo]:
        return [ImageModelInfo(id=m.id, name=m.name, usd_per_image=self.prices.price(m), prompt_add=m.prompt_add,
                               negative_add=m.negative_add, negative=m.negative) for m in self.models.values()]

    def resolve(self, requested: str | None) -> ImageModel | None:
        return self.models.get(requested or self.default)


async def own_image_models(url: str, client: httpx.AsyncClient | None = None) -> tuple[ImageModel, ...]:
    """The own server's models: its current checkpoint and the SD_MODELS it has; nothing when it does not answer."""
    try:
        if client is None:
            async with httpx.AsyncClient(timeout=httpx.Timeout(5, connect=2)) as c:
                return await own_image_models(url, c)
        resp = await client.get(url + "/sdapi/v1/sd-models")
        resp.raise_for_status()
        titles = [str(m.get("title", "")) for m in resp.json()]
    except (httpx.HTTPError, ValueError, AttributeError) as exc:
        log.info("no own image server at %s: %s", url, str(exc)[:120])
        return ()
    found = []
    paths = await _module_paths(url, client) if any(m.modules for m in SD_MODELS) else {}
    for m in SD_MODELS:
        # A title is "<folder>/<file> [hash]"; the folder and the hash differ from server to server.
        title = next((t for t in titles if t.split(" [")[0].replace("\\", "/").rsplit("/", 1)[-1] == m.checkpoint), "")
        if not title or not all(n in paths for n in m.modules):
            continue
        txt2img = m.txt2img
        if m.modules:
            settings = {**txt2img.get("override_settings", {}), "forge_additional_modules": [paths[n] for n in m.modules]}
            txt2img = {**txt2img, "override_settings": settings}
        found.append(replace(m, url=url, checkpoint=title, txt2img=txt2img))
    return (ImageModel("a1111", "Stable Diffusion (свой сервер)", "sd", 0.0, backend="a1111", url=url), *found)


async def _module_paths(url: str, client: httpx.AsyncClient) -> dict[str, str]:
    """Forge's VAE and text encoder files: their name → the path its `forge_additional_modules` wants."""
    try:
        resp = await client.get(url + "/sdapi/v1/sd-modules")
        resp.raise_for_status()
        return {str(m["model_name"]): str(m["filename"]) for m in resp.json()}
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        log.info("no modules at %s: %s", url, str(exc)[:120])
        return {}


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
    w, h = canvas(aspect, spec.side)
    body = {"prompt": prompt, "negative_prompt": negative, "width": w, "height": h, "steps": 25, **spec.txt2img}
    if spec.checkpoint:
        body["override_settings"] = {**body.get("override_settings", {}), "sd_model_checkpoint": spec.checkpoint}
        body["override_settings_restore_afterwards"] = False  # restoring reloads a checkpoint on every frame
    resp = await c.post(spec.url.rstrip("/") + "/sdapi/v1/txt2img", json=body, timeout=httpx.Timeout(300, connect=20))
    if resp.status_code != 200:
        raise ImageError(f"{spec.url} HTTP {resp.status_code}")
    images = resp.json().get("images") or []
    if not images:
        raise ImageError("no image in the answer")
    return Drawn("image/png", str(images[0]))


def compose(spec: ImageModel, params: ImageParams, prompt: str, negative: str) -> tuple[str, str]:
    """The player's additions (v0.7.37): after the scene (v0.7.38.2, as booru prompts go), and the negative — with
    the agent's tags or alone."""
    add = spec.prompt_add if params.prompt_add is None else params.prompt_add
    neg = spec.negative_add if params.negative_add is None else params.negative_add
    joined = ", ".join(x for x in (_tags(prompt), _tags(add)) if x)
    if not spec.negative:
        return joined, ""
    return joined, ", ".join(x for x in (_tags(neg), "" if params.negative_only else _tags(negative)) if x)


def booru_scene(scene: str) -> str:
    """`solo` beside a beast makes Illustrious grow them into one werewolf: the agent writes it anyway (v0.7.38.2)."""
    tags = [t.strip() for t in scene.split(",") if t.strip()]
    beast = any(t in ("animal", "monster") or "feral" in t for t in tags)
    return ", ".join(t for t in tags if not (beast and t == "solo"))


def _tags(text: str) -> str:
    return text.strip().strip(",").strip()


def canvas(aspect: str, side: int) -> tuple[int, int]:
    """The own server's width and height: the area of side², the aspect kept, multiples of 64."""
    try:
        a, b = (float(x) for x in aspect.split(":"))
    except ValueError:
        a, b = 16.0, 9.0
    r = (a / b) ** 0.5
    return max(64, round(side * r / 64) * 64), max(64, round(side / r / 64) * 64)


# --- handlers -------------------------------------------------------------------


async def stub_image(session: "Session", params: ImageParams) -> ImageResult:
    spec = _spec(session, params)
    prompt, _ = compose(spec, params, prompts.image_prompt(spec.template, params.event[:200], params.style), "")
    return ImageResult(mime="image/png", data_b64=base64.b64encode(_png(16, 9, (92, 74, 56))).decode(),
                       prompt=prompt, usage=Usage(model="stub"))


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
    scene = booru_scene(result.output.scene) if spec.template in ("illustrious", "anima") else result.output.scene
    prompt, negative = compose(spec, params, prompts.image_prompt(spec.template, scene, params.style),
                               result.output.negative)
    try:
        drawn = await draw(spec, prompt, negative, params.aspect, services.settings.openrouter_api_key)
    except (ImageError, httpx.HTTPError) as exc:
        log.warning("image %s failed: %s", spec.id, str(exc)[:300])
        raise RpcError(ErrorCode.LLM_UNAVAILABLE, f"image: {str(exc)[:160]}") from None
    services.budget.add(drawn.cost_usd)
    services.images.prices.observe(spec.id, drawn.cost_usd)
    usage = text_usage.model_copy(update={"cost_usd": round(text_usage.cost_usd + drawn.cost_usd, 6), "model": f"{model} + {spec.id}"})
    if services.trace:
        services.trace.write({"what": "image", "image_model": spec.id, "frame": frame, "prompt": prompt,
                              "negative": negative, "image_usd": drawn.cost_usd, "mime": drawn.mime,
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
