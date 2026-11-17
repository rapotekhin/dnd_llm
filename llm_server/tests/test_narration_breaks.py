"""A story with its line breaks escaped twice reaches the chat with real ones (v0.8.4.44.11, the author: «\\n\\n вёрстка не
прочиталась в чате»)."""

from llm_server.protocol import TurnResult, Usage


def _turn(text: str) -> TurnResult:
    return TurnResult(turn_id="t1", narration=text, usage=Usage(model="stub"))


def test_escaped_breaks_become_real() -> None:
    assert _turn("Дверь скрипит.\\n\\nЗа ней темно.").narration == "Дверь скрипит.\n\nЗа ней темно."
    assert _turn("Раз.\\r\\nДва.").narration == "Раз.\nДва."


def test_real_breaks_stay() -> None:
    assert _turn("Раз.\n\nДва.").narration == "Раз.\n\nДва."
