"""tools/validate_data.py — the CI check of world packs (the game checks the same rules in WorldPack)."""

import importlib.util
import json
import shutil

from llm_server import REPO_ROOT

spec = importlib.util.spec_from_file_location("validate_data", REPO_ROOT / "tools" / "validate_data.py")
validate_data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate_data)

FRONTIER = REPO_ROOT / "game" / "data" / "worlds" / "frontier"


def test_repo_packs_are_valid():
    assert validate_data.main([]) == 0


def _broken(tmp_path, edit) -> list[str]:
    d = tmp_path / "mod"
    shutil.copytree(FRONTIER, d)
    for name in ("pack", "world", "characters"):
        path = d / f"{name}.json"
        doc = json.loads(path.read_text(encoding="utf-8"))
        edit(name, doc)
        path.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
    return validate_data.validate_pack(d, validate_data.known())


def test_broken_packs_are_reported(tmp_path):
    def edit(name, doc):
        if name == "pack":
            doc["rules"]["races"] = ["human", "ent"]
        elif name == "world":
            doc["rooms"]["brod-square"]["exits"].append("nowhere")
            doc["npcs"]["npc_smith"]["stock"]["lightsaber"] = 1
            doc["rooms"]["brod-gate"]["secrets"].append(dict(doc["rooms"]["brod-gate"]["secrets"][0]))
        else:
            doc["presets"][1]["choices"]["class"] = "jedi"
    errors = " | ".join(_broken(tmp_path, edit))
    for needle in ("ent", "nowhere", "lightsaber", "jedi", "id секретов"):
        assert needle in errors, needle


def test_schema_catches_shape(tmp_path):
    def edit(name, doc):
        if name == "pack":
            doc["dm_style"] = "epic"
            del doc["lore"]
    errors = " | ".join(_broken(tmp_path, edit))
    assert "dm_style" in errors and "lore" in errors
