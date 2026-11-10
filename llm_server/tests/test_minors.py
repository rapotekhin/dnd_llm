"""Children is never intimate (v0.7.38.7, taken out in 1838cd48, back in v0.8.4.42.22): the master's rule names
them whatever the 18+ toggle says, a frame with one of them is drawn with the safety tags, and the negative always holds
the tags against children."""

from llm_server import prompts
from llm_server.config import SD_MODELS
from llm_server.images import MINOR_NEG, NSFW_NEG, adult_frame, compose
from llm_server.protocol import ImageParams, WorldInfo

ANIMA = next(m for m in SD_MODELS if m.template == "anima")


def test_the_master_is_told_the_18_plus_rule_and_the_children():
    off = prompts.intimacy_rule(WorldInfo())
    assert "за кадр" in off and "Дети — никогда" in off
    on = prompts.intimacy_rule(WorldInfo(adult=True))
    assert "Дети — никогда" in on


def test_18_plus_lifts_the_safety_tags_only_without_children():
    adult = ImageParams(event="x", adult=True, hero="Айра, человек, женщина, молодая")
    assert adult_frame(adult)
    for p in (ImageParams(event="x"),
              ImageParams(event="x", adult=True, minors=["Урга"]),
              ImageParams(event="x", adult=True, people=["Лёшка — человек, мужчина, ребёнок; сын мельника"])):
        assert not adult_frame(p), p


def test_the_negative_always_holds_the_tags_against_children():
    for p in (ImageParams(event="x"), ImageParams(event="x", adult=True)):
        _, neg = compose(ANIMA, p, "2girls", "crowd")
        tags = {t.strip() for t in neg.split(",")}
        assert set(MINOR_NEG) <= tags, neg
    _, neg = compose(ANIMA, ImageParams(event="x"), "2girls", "crowd")
    assert set(NSFW_NEG) <= {t.strip() for t in neg.split(",")}, neg
    _, neg = compose(ANIMA, ImageParams(event="x", negative_add="", negative_only=True), "2girls", "")
    assert set(MINOR_NEG) <= {t.strip() for t in neg.split(",")}, neg  # the player's own negative cannot drop them
