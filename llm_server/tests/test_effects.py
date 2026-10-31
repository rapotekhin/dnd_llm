"""v0.7.69: 31 kinds of effects, one name for each, one table in the engine."""

import re
from pathlib import Path

from llm_server import agents, prompts
from llm_server.protocol import class_tag, effect_classes, effect_tag

ENGINE = Path(__file__).parents[2] / "game" / "core" / "rules" / "effect_engine.gd"


def _rows() -> set[str]:
    return set(re.findall(r'^\t\t"([a-z_:>]+)": \{', ENGINE.read_text(encoding="utf-8"), re.M))


def test_the_kinds_are_few_and_each_effect_has_its_own_name():
    classes = effect_classes()
    assert len({cls.model_fields["kind"].default for cls in classes}) == 31
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
    assert "create(what: " in text and "поля — в теме rules" in text
    assert "teach_kind" not in text  # a course's fields wait for its topic
    assert len(text) < 7000
