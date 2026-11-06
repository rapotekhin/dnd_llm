"""The OpenRouter account of the server's key for the game's settings (0.113.0): what is left on the account
(`/api/v1/credits`: bought − used) and what is left under the key's own limit (`/api/v1/key`).
Asked at most once a `ttl`; a failure is a None of its own, never an error of the status. The key never reaches a log."""

import logging
import time

import httpx

log = logging.getLogger(__name__)

CREDITS_URL = "https://openrouter.ai/api/v1/credits"
KEY_URL = "https://openrouter.ai/api/v1/key"


def _num(v: object) -> float | None:
    try:
        return None if v is None else round(float(v), 4)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


class OpenRouterAccount:
    def __init__(self, api_key: str, ttl: float = 60.0):
        self._key = api_key
        self.ttl = ttl
        self._at = -1e9
        self._last: dict[str, float | None] | None = None

    async def fetch(self, client: httpx.AsyncClient | None = None) -> dict[str, float | None] | None:
        """{credits_left_usd, key_left_usd}; None without a key or when OpenRouter did not answer."""
        if not self._key:
            return None
        if time.monotonic() - self._at < self.ttl:
            return self._last
        self._at = time.monotonic()  # one try per ttl, a failed one too
        headers = {"Authorization": f"Bearer {self._key}"}
        try:
            if client is None:
                async with httpx.AsyncClient(timeout=8) as c:
                    credits, key = await self._get(c, headers)
            else:
                credits, key = await self._get(client, headers)
        except (httpx.HTTPError, ValueError, TypeError, KeyError) as exc:
            log.warning("cannot read the OpenRouter balance: %s", type(exc).__name__)
            return self._last
        total, used = _num(credits.get("total_credits")), _num(credits.get("total_usage"))
        self._last = {
            "credits_left_usd": None if total is None or used is None else round(total - used, 4),
            "key_left_usd": _num(key.get("limit_remaining")),
        }
        return self._last

    @staticmethod
    async def _get(c: httpx.AsyncClient, headers: dict[str, str]) -> tuple[dict, dict]:
        credits: dict = {}
        r = await c.get(CREDITS_URL, headers=headers)
        if r.status_code == 200:  # a key without the right to the account's credits answers 403: the key's own numbers stay
            credits = r.json().get("data") or {}
        k = await c.get(KEY_URL, headers=headers)
        k.raise_for_status()
        return credits, k.json().get("data") or {}
