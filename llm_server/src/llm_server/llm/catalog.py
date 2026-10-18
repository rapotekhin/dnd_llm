"""Models the player may pick: names and prices from the OpenRouter catalog, fetched once at start."""

import logging
from collections.abc import Callable

import httpx
from pydantic_ai.models import Model

from ..protocol import ModelInfo

log = logging.getLogger("llm_server.models")

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
OPENROUTER_CREDITS_URL = "https://openrouter.ai/api/v1/credits"

ModelFactory = Callable[[str], Model]


class ModelCatalog:
    def __init__(self, allowed: tuple[str, ...], default: str):
        self.allowed = allowed
        self.default = default
        self._info: dict[str, ModelInfo] = {m: ModelInfo(id=m, name=m) for m in allowed}

    def infos(self) -> list[ModelInfo]:
        return [self._info[m] for m in self.allowed]

    def resolve(self, requested: str | None) -> str | None:
        """The model id to use, or None when the player asked for one outside the whitelist."""
        if not requested:
            return self.default
        return requested if requested in self.allowed else None

    def cost_usd(self, model: str, input_tokens: int, output_tokens: int) -> float:
        info = self._info.get(model)
        if info is None:
            return 0.0
        return (input_tokens * info.input_usd_per_mtok + output_tokens * info.output_usd_per_mtok) / 1_000_000

    async def load_prices(self, client: httpx.AsyncClient | None = None) -> None:
        """Names and prices from OpenRouter; on failure the ids stay as names and prices 0 (logged)."""
        try:
            async with client or httpx.AsyncClient(timeout=10) as c:
                resp = await c.get(OPENROUTER_MODELS_URL)
                resp.raise_for_status()
                data = resp.json()["data"]
        except (httpx.HTTPError, KeyError, ValueError) as exc:
            log.warning("cannot load OpenRouter model prices: %s", exc)
            return
        by_id = {m["id"]: m for m in data}
        for model_id in self.allowed:
            m = by_id.get(model_id)
            if m is None:
                log.warning("model %s is not in the OpenRouter catalog", model_id)
                continue
            pricing = m.get("pricing", {})
            self._info[model_id] = ModelInfo(
                id=model_id,
                name=str(m.get("name", model_id)),
                input_usd_per_mtok=float(pricing.get("prompt", 0)) * 1_000_000,
                output_usd_per_mtok=float(pricing.get("completion", 0)) * 1_000_000,
            )


def openrouter_factory(api_key: str) -> ModelFactory:
    from pydantic_ai.models.openrouter import OpenRouterModel
    from pydantic_ai.providers.openrouter import OpenRouterProvider

    provider = OpenRouterProvider(api_key=api_key)
    cache: dict[str, Model] = {}

    def make(model_id: str) -> Model:
        if model_id not in cache:
            cache[model_id] = OpenRouterModel(model_id, provider=provider)
        return cache[model_id]

    return make


async def check_openrouter_key(api_key: str) -> float | None:
    """Remaining OpenRouter credits in USD, or None if the key is rejected. Never logs the key."""
    try:
        async with httpx.AsyncClient(timeout=10) as c:
            resp = await c.get(OPENROUTER_CREDITS_URL, headers={"Authorization": f"Bearer {api_key}"})
        if resp.status_code != 200:
            return None
        data = resp.json()["data"]
        return float(data.get("total_credits", 0)) - float(data.get("total_usage", 0))
    except (httpx.HTTPError, KeyError, ValueError):
        return None
