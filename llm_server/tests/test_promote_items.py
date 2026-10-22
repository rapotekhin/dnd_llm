"""tools/promote_items.py — the master's items into the game catalog by the author's pick (v0.7.18.3)."""

import importlib.util
import json
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("promote_items", REPO_ROOT / "tools" / "promote_items.py")
promote_items = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promote_items)


def _setup(tmp_path: Path, lib: list[dict]) -> tuple[Path, Path, Path]:
    items = tmp_path / "items.json"
    shutil.copy(REPO_ROOT / "game" / "data" / "items.json", items)
    library = tmp_path / "library.jsonl"
    library.write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in lib), encoding="utf-8")
    return items, tmp_path / "promoted.json", library


def test_a_picked_item_enters_the_catalog_with_the_engines_numbers(tmp_path):
    lib = [{"item_id": "gen_a", "name": "Кинжал инея", "item_type": "weapon", "base": "dagger", "rarity": "common", "value_cp": 900000,
            "properties": ["finesse", "cold_damage"], "description": "Клинок в изморози."},
           {"item_id": "gen_b", "name": "Настой Веданы", "item_type": "consumable", "rarity": "common", "value_cp": 3000,
            "properties": [], "use": {"heal": "light", "spell": None, "charges": None}}]
    items, promoted, library = _setup(tmp_path, lib)
    lines = promote_items.promote(["gen_a=frost_dagger", "gen_b"], items, promoted, library)
    assert all(line.startswith("✓") for line in lines), lines
    catalog = json.loads(items.read_text(encoding="utf-8"))["catalog"]
    assert catalog["frost_dagger"]["rarity"] == "uncommon"  # by points, not as the master said
    assert catalog["frost_dagger"]["value_cp"] == 50000  # within the rarity
    assert catalog["nastoy_vedany"]["use"] == {"heal": [2, 4, 2]} and catalog["nastoy_vedany"]["stack"]
    assert set(json.loads(promoted.read_text(encoding="utf-8"))) == {"frost_dagger", "nastoy_vedany"}
    assert library.read_text(encoding="utf-8") == ""  # they left the library


def test_a_bad_or_taken_item_stays_in_the_library(tmp_path):
    lib = [{"item_id": "gen_c", "name": "Меч", "item_type": "weapon", "rarity": "common", "value_cp": 1, "properties": ["laser"]},
           {"item_id": "gen_d", "name": "Кружка эля", "item_type": "consumable", "rarity": "common", "value_cp": 4, "properties": []}]
    items, promoted, library = _setup(tmp_path, lib)
    lines = promote_items.promote(["gen_c", "gen_d=ale", "gen_x"], items, promoted, library)
    assert "неизвестны: laser" in lines[0] and "уже занят" in lines[1] and "нет в библиотеке" in lines[2]
    assert len(library.read_text(encoding="utf-8").splitlines()) == 2
    assert not promoted.exists()
