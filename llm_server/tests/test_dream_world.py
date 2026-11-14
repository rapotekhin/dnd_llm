"""The tutorial's dream (v0.8.4.44.2, protocol 0.131.0): a closed world tells the master what it may not make there, and
a dream borrows nothing from the item library and keeps nothing in it."""

from pathlib import Path

from llm_server import prompts
from llm_server.protocol import Snapshot

from conftest import tavern_snapshot


def _dream_snapshot(closed: list[str]) -> Snapshot:
    raw = tavern_snapshot()
    raw["world"].update({"name": "Сон в пещере", "closed": closed, "dream": True})
    return Snapshot.model_validate(raw)


def test_a_closed_world_tells_the_master_what_it_may_not_make():
    text = prompts.system_prompt("exploration", _dream_snapshot(["create:npc", "create:place", "create:quest"]), None)
    assert "Этот мир закрыт" in text and "create:npc, create:place, create:quest" in text
    assert "Этот мир закрыт" not in prompts.system_prompt("exploration", Snapshot.model_validate(tavern_snapshot()), None)


def test_the_prompts_name_no_place_of_the_mark_in_their_rules():
    for name in ("topics/people.md.j2", "topics/property.md.j2", "topics/quests.md.j2", "topics/craft.md.j2", "topics/bank.md.j2"):
        text = (Path(prompts.__file__).parent / name).read_text(encoding="utf-8")
        for word in ("Брод", "Марк", "Пущ", "Горм"):
            assert word not in text, (name, word)
