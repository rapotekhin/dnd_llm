"""The OpenRouter balance of the server's key for the game's settings (0.113.0)."""

import asyncio

import httpx

from llm_server.llm.account import CREDITS_URL, KEY_URL, OpenRouterAccount


def _client(credits_status: int = 200, key_status: int = 200) -> tuple[httpx.AsyncClient, list[str]]:
    asked: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        asked.append(str(req.url))
        assert req.headers["Authorization"] == "Bearer sk-test"
        if str(req.url) == CREDITS_URL:
            return httpx.Response(credits_status, json={"data": {"total_credits": 10.0, "total_usage": 3.25}})
        if str(req.url) == KEY_URL:
            return httpx.Response(key_status, json={"data": {"limit_remaining": 4.5, "usage_daily": 0.0312}})
        return httpx.Response(404)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler)), asked


def test_the_balance_of_the_account_and_of_the_key() -> None:
    client, asked = _client()
    got = asyncio.run(OpenRouterAccount("sk-test").fetch(client))
    assert got == {"credits_left_usd": 6.75, "key_left_usd": 4.5}
    assert asked == [CREDITS_URL, KEY_URL]


def test_asked_once_a_minute() -> None:
    client, asked = _client()
    acc = OpenRouterAccount("sk-test")
    asyncio.run(acc.fetch(client))
    asyncio.run(acc.fetch(client))
    assert len(asked) == 2


def test_a_key_without_the_credits_right_keeps_its_own_numbers() -> None:
    client, _ = _client(credits_status=403)
    got = asyncio.run(OpenRouterAccount("sk-test").fetch(client))
    assert got is not None and got["credits_left_usd"] is None and got["key_left_usd"] == 4.5


def test_no_key_or_no_answer_is_none() -> None:
    assert asyncio.run(OpenRouterAccount("").fetch()) is None
    client, _ = _client(key_status=500)
    assert asyncio.run(OpenRouterAccount("sk-test").fetch(client)) is None
