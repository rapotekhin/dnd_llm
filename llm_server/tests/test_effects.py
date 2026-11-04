"""v0.7.69: 31 kinds of effects, one name for each, one table in the engine."""

import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from llm_server import agents, prompts
from llm_server.protocol import MOVE_PAIRS, MoveItemEffect, class_tag, effect_classes, effect_tag

ITEM = {"name": "Письмо", "item_type": "gear", "rarity": "common", "value_cp": 0}

ENGINE = Path(__file__).parents[2] / "game" / "core" / "rules" / "effect_engine.gd"


def _rows() -> set[str]:
    return set(re.findall(r'^\t\t"([a-z_:>]+)": \{', ENGINE.read_text(encoding="utf-8"), re.M))


def test_the_kinds_are_few_and_each_effect_has_its_own_name():
    classes = effect_classes()
    assert len({cls.model_fields["kind"].default for cls in classes}) == 32
    tags = [class_tag(cls) for cls in classes]
    assert len(tags) == len(set(tags))


def test_a_name_reads_the_same_from_a_model_and_from_a_dict():
    assert effect_tag({"kind": "create", "what": "npc"}) == "create:npc"
    assert effect_tag({"kind": "move_item", "source": "world", "target": "hero"}) == "move_item:world>hero"
    assert effect_tag({"kind": "coins", "delta_cp": 5}) == "coins"
    assert effect_tag({"kind": "make", "what": "status"}) == "make"  # `make` has a `what` of its own


def test_every_effect_has_a_row_in_the_engine_and_every_row_an_effect():
    rows = _rows()
    moves = {r for r in rows if r.startswith("move_item:")}
    tags = {class_tag(cls) for cls in effect_classes()} - {"move_item"}
    assert rows - moves == tags
    assert len(moves) == 10


def test_every_name_of_a_topic_is_an_effect():
    rows = _rows()
    for key, (_, tags) in prompts.TOPICS.items():
        assert set(tags) <= rows, key


def test_a_topics_fields_come_with_its_rules_not_in_every_turn():
    assert "item_id" in prompts.topic_text("containers") and "prop_id" in prompts.topic_text("containers")
    text = agents._effect_kinds()
    assert "create(what→тема: " in text and "bank→bank" in text and "поля — в теме " in text
    assert "teach_kind" not in text  # a course's fields wait for its topic
    assert len(text) < 7000


def test_a_thing_moves_only_by_a_real_way() -> None:
    for bad, why in (({"source": "container", "target": "npc", "prop_id": "p1", "item_id": "torch"}, "пути"),
                     ({"source": "container", "target": "hero", "prop_id": "p1", "item": ITEM}, "`item`"),
                     ({"source": "room", "target": "hero"}, "prop_id"),
                     ({"source": "container", "target": "hero", "prop_id": "p1"}, "item_id")):
        with pytest.raises(ValidationError, match=why):
            MoveItemEffect.model_validate({"kind": "move_item", **bad})
    MoveItemEffect.model_validate({"kind": "move_item", "source": "world", "target": "hero", "item": ITEM})
    MoveItemEffect.model_validate({"kind": "move_item", "source": "room", "target": "hero", "prop_id": "p1"})


def test_the_ways_of_a_thing_are_the_engine_s_rows() -> None:
    assert {f"move_item:{p}" for p in MOVE_PAIRS} == {r for r in _rows() if r.startswith("move_item:")}


def test_a_made_thing_carries_what_it_lays_while_worn_and_what_it_calls():
    """0.110.0: `wear` in the engine's words, `use.summon` in the shape of its summons; the engine prices both."""
    e = MoveItemEffect.model_validate({"source": "world", "target": "hero", "item": {**ITEM, "item_type": "wondrous", "rarity": "uncommon",
                                       "wear": {"fly_speed": "walk", "see_invisible": True},
                                       "use": {"summon": {"monster": "wolf", "count": 2, "minutes": 60}, "charges": 2}}})
    dumped = e.model_dump(mode="json")["item"]
    assert dumped["wear"] == {"fly_speed": "walk", "see_invisible": True}
    assert dumped["use"]["summon"]["monster"] == "wolf" and dumped["use"]["summon"]["count"] == 2
    with pytest.raises(ValidationError):
        MoveItemEffect.model_validate({"source": "world", "target": "hero", "item": {**ITEM, "use": {"summon": {"monster": "wolf", "count": 30}}}})
    topic = (Path(prompts.__file__).parent / "topics" / "items.md.j2").read_text(encoding="utf-8")
    assert "`summon`" in topic and "`wear`" in topic
