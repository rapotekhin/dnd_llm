import json

import pytest
from jinja2 import UndefinedError

from llm_server import REPO_ROOT, prompts
from llm_server.llm.budget import DailyBudget
from llm_server.llm.catalog import ModelCatalog
from llm_server.protocol import ItemProperty, Snapshot

from conftest import tavern_snapshot

INNKEEPER = "npc_innkeeper"


def snap() -> Snapshot:
    return Snapshot.model_validate(tavern_snapshot())


def test_exploration_prompt():
    text = prompts.system_prompt("exploration", snap(), None)
    assert "Таверна «Хромой олень» — общий зал [brod-tavern-hall]" in text
    assert "Кухня таверны [brod-tavern-kitchen]" in text  # exits with ids for `move`
    assert "10 зм" in text
    assert "женском роде" in text
    assert "Сил 16" in text and "athletics +5*" in text and "(* — владеет)" in text
    assert "Кольчуга, Щит, Длинный меч" in text
    assert "Заклинатель" not in text
    assert "## Мир: Сумеречная Марка" in text and "Пепельный Князь" in text
    assert "Забытые Королевства" in text  # the rule against other settings
    assert "Классический" in text and "Вуали" in text and "пытки" in text
    assert "История персонажа: Айра стояла" in text
    assert "\n\n\n" not in text


def test_caster_sheet_in_the_prompt():
    raw = tavern_snapshot()
    raw["character"].update({"class_name": "Волшебник", "spell_save_dc": 13, "cantrips": ["Огненный снаряд"],
                             "spells": ["Волшебная стрела", "Щит"], "spell_slots": [{"level": 1, "left": 1, "max": 2}]})
    text = prompts.system_prompt("exploration", Snapshot.model_validate(raw), None)
    assert "Заклинатель: Сл спасброска 13; ячейки: 1 круг 1/2." in text
    assert "Заговоры: Огненный снаряд." in text
    assert "Заклинания: Волшебная стрела, Щит." in text


def test_style_and_content_limits_in_the_prompt():
    raw = tavern_snapshot()
    raw["world"].update({"dm_style": "dry", "violence": "mild", "lines": ["пауки"], "veils": []})
    text = prompts.system_prompt("exploration", Snapshot.model_validate(raw), None)
    assert "Сухой: коротко и по делу" in text
    assert "мягко:" in text
    assert "Линии" in text and "пауки" in text and "Вуали" not in text
    assert "тёмное фэнтези с надеждой: серая мораль" in text  # the pack's tone replaces the default


def test_npc_prompts():
    s = snap()
    npc = next(n for n in s.scene.npcs if n.npc_id == INNKEEPER)
    social = prompts.system_prompt("social", s, npc)
    trade = prompts.system_prompt("trade", s, npc)
    assert social.startswith("# Ты — Бруно Хмель")
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
