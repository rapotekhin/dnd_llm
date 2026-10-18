import json

import pytest
from jinja2 import UndefinedError

from llm_server import REPO_ROOT, prompts
from llm_server.llm.budget import DailyBudget
from llm_server.llm.catalog import ModelCatalog
from llm_server.protocol import ItemProperty, Snapshot

from conftest import tavern_snapshot

INNKEEPER = "a1f3c7c2-6b1e-4e92-9e2a-111111111111"


def snap() -> Snapshot:
    return Snapshot.model_validate(tavern_snapshot())


def test_exploration_prompt():
    text = prompts.system_prompt("exploration", snap(), None)
    assert "Главный зал [tavern-room-001]" in text
    assert "Кухня [tavern-room-002]" in text  # exits with ids for `move`
    assert "15 зм" in text
    assert "женском роде" in text
    assert "\n\n\n" not in text


def test_npc_prompts():
    s = snap()
    npc = next(n for n in s.scene.npcs if n.npc_id == INNKEEPER)
    social = prompts.system_prompt("social", s, npc)
    trade = prompts.system_prompt("trade", s, npc)
    assert social.startswith("# Ты — Борик Каменный Бокал")
    assert "target_id = \"" + INNKEEPER in social
    assert "Сделка — только эффектами" in trade
    with pytest.raises(ValueError):
        prompts.system_prompt("social", s, None)


def test_prompt_without_character_or_scene_still_renders():
    text = prompts.system_prompt("exploration", Snapshot(), None)
    assert "Избегай родовых форм".lower() in text.lower()


def test_strict_templates_fail_on_missing_variables():
    with pytest.raises(UndefinedError):
        prompts.render("turn.md.j2", mode="exploration")


def test_turn_prompt_kinds():
    s = snap()
    assert "Опиши место" in prompts.turn_prompt("exploration", "enter", "", s, None)
    assert "вернулся в общую сцену" in prompts.turn_prompt("exploration", "resume", "", s, None)
    assert "Действие игрока: прыгаю" in prompts.turn_prompt("exploration", "action", "прыгаю", s, None)
    assert "Мастер: Таверна шумит." in prompts.turn_prompt("exploration", "action", "x", s, None)


def test_coins_format():
    assert prompts.coins(1537) == "15 зм 3 см 7 мм"
    assert prompts.coins(0) == "0 зм"


def test_budget_counts_and_resets(tmp_path, monkeypatch):
    b = DailyBudget(tmp_path / "budget.json", 1.0)
    b.add(0.4)
    b.add(0.7)
    assert b.exhausted()
    assert b.left() == 0
    monkeypatch.setattr(DailyBudget, "_today", staticmethod(lambda: "2099-01-01"))
    assert b.spent_today() == 0
    assert DailyBudget(tmp_path / "x.json", None).left() is None


def test_catalog_resolves_only_whitelisted_models():
    c = ModelCatalog(("a/x", "b/y"), "a/x")
    assert c.resolve(None) == "a/x"
    assert c.resolve("b/y") == "b/y"
    assert c.resolve("c/z") is None


def test_item_properties_match_the_godot_vocabulary():
    godot = json.loads((REPO_ROOT / "game" / "data" / "items.json").read_text(encoding="utf-8"))["properties"]
    assert set(godot) == set(ItemProperty.__args__)
