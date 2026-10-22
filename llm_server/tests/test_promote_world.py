"""tools/promote_world.py — the master's people and places into the world pack by the author's pick (v0.7.20.2)."""

import importlib.util
import json
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("promote_world", REPO_ROOT / "tools" / "promote_world.py")
promote_world = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promote_world)

GEN = {
    "npcs": {
        "gen_npc_1": {"name": "Ждан", "role": "паромщик", "gender": "male", "monster": "commoner", "tags": [], "generated": True,
                      "links": [{"npc_id": "npc_innkeeper", "kind": "friend"}, {"npc_id": "gen_npc_2", "kind": "kin"}]},
        "gen_npc_2": {"name": "Огнеда", "role": "травница", "gender": "female", "monster": "commoner", "tags": [], "generated": True,
                      "links": []},
    },
    "npc_rooms": {"gen_npc_1": "brod-square", "gen_npc_2": "gen_room_2"},
    "rooms": {
        "gen_room_1": {"name": "Курган у дороги", "location_id": "gen_loc_1", "description": "Старый курган.", "exits": ["gen_room_2", "brod-gate"],
                       "npcs": [], "hooks": [], "secrets": [{"id": "s1", "dc": 15, "text": "Под камнем — лаз.", "skill": "perception"}],
                       "generated": True},
        "gen_room_2": {"name": "Хижина травницы", "location_id": "gen_loc_1", "description": "Дым и травы.", "exits": ["gen_room_1"],
                       "npcs": ["gen_npc_2"], "hooks": [], "secrets": [], "indoor": True, "generated": True,
                       "encounter": {"id": "gen_room_2_enc", "enemies": [{"monster": "wolf", "count": 1, "name": "Волк", "desc": "", "col": 3}],
                                     "loot": {"coins_cp": 0, "items": {}}}},
    },
    "locations": {"gen_loc_1": {"name": "Курганы", "description": "Холмы за воротами.", "terrain": "hills"}},
    "edge_exits": {"brod-gate": ["gen_room_1"]},
    "edges_used": ["brod-gate:0"],
}


def _setup(tmp_path: Path) -> tuple[Path, Path]:
    worlds = tmp_path / "worlds"
    shutil.copytree(REPO_ROOT / "game" / "data" / "worlds" / "frontier", worlds / "frontier")
    shutil.copy(REPO_ROOT / "game" / "data" / "worlds" / "pack.schema.json", worlds / "pack.schema.json")
    user = tmp_path / "user"
    (user / "saves").mkdir(parents=True)
    save = {"session": {"world_id": "frontier", "generated": GEN}}
    (user / "saves" / "autosave.json").write_text(json.dumps(save, ensure_ascii=False), encoding="utf-8")
    return user, worlds


def _world(worlds: Path) -> dict:
    return json.loads((worlds / "frontier" / "world.json").read_text(encoding="utf-8"))


def test_the_report_lists_people_and_whole_places(tmp_path):
    user, _ = _setup(tmp_path)
    text = "\n".join(promote_world.report(user))
    assert "gen_npc_1: Ждан — паромщик" in text
    assert "место: gen_room_1 «Курган у дороги», gen_room_2 «Хижина травницы» — новая локация «Курганы»" in text


def test_a_person_enters_the_pack_in_their_room(tmp_path):
    user, worlds = _setup(tmp_path)
    raw = (worlds / "frontier" / "world.json").read_bytes()
    lines = promote_world.promote(["autosave:gen_npc_1=npc_ferryman"], user, worlds)
    assert lines[0].startswith("✓"), lines
    w = _world(worlds)
    npc = w["npcs"]["npc_ferryman"]
    assert "generated" not in npc and npc["links"] == [{"npc_id": "npc_innkeeper", "kind": "friend"}]  # the made kin stays out
    assert "npc_ferryman" in w["rooms"]["brod-square"]["npcs"]
    assert b"\r\n" in (worlds / "frontier" / "world.json").read_bytes() and b"\r\n" in raw  # the file keeps its line ends
    assert promote_world.promote(["autosave:gen_npc_1"], user, worlds)[0].startswith("✗")  # already in the pack


def test_a_person_of_a_made_place_waits_for_the_place(tmp_path):
    user, worlds = _setup(tmp_path)
    assert "перенесите место" in promote_world.promote(["autosave:gen_npc_2"], user, worlds)[0]


def test_a_place_comes_whole_with_its_location_people_and_the_way_in(tmp_path):
    user, worlds = _setup(tmp_path)
    lines = promote_world.promote(["autosave:gen_room_2=kurgany"], user, worlds)  # any room of the place takes it all
    assert lines[0].startswith("✓"), lines
    w = _world(worlds)
    assert w["rooms"]["kurgany"]["name"] == "Курган у дороги"  # the entry gets the author's id
    hut = w["rooms"]["kurgany-2"]
    assert hut["location_id"] == "kurgany" and hut["exits"] == ["kurgany"] and hut["encounter"]["id"] == "kurgany-2_enc"
    assert w["locations"]["kurgany"]["name"] == "Курганы"
    assert w["rooms"]["kurgany"]["exits"] == ["kurgany-2", "brod-gate"]
    assert "kurgany" in w["rooms"]["brod-gate"]["exits"] and "open_edges" not in w["rooms"]["brod-gate"]  # the edge is used
    herb = next(i for i, n in w["npcs"].items() if n["name"] == "Огнеда")
    assert w["rooms"]["kurgany-2"]["npcs"] == [herb]


def test_a_bad_pack_is_left_as_it_was(tmp_path):
    user, worlds = _setup(tmp_path)
    bad = json.loads((user / "saves" / "autosave.json").read_text(encoding="utf-8"))
    bad["session"]["generated"]["npcs"]["gen_npc_1"]["monster"] = "no_such_monster"
    (user / "saves" / "autosave.json").write_text(json.dumps(bad, ensure_ascii=False), encoding="utf-8")
    before = (worlds / "frontier" / "world.json").read_bytes()
    lines = promote_world.promote(["autosave:gen_npc_1"], user, worlds)
    assert any("не прошёл проверку" in line for line in lines) and any("no_such_monster" in line for line in lines), lines
    assert (worlds / "frontier" / "world.json").read_bytes() == before
