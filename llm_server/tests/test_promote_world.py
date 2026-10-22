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


QUEST_GEN = {
    "npcs": {"gen_npc_1": {"name": "Тимоша", "role": "посыльный", "gender": "male", "monster": "commoner", "tags": [], "generated": True,
                           "links": [], "quest_depth": 1}},
    "npc_rooms": {"gen_npc_1": "gen_room_1"},
    "rooms": {"gen_room_1": {"name": "Задний двор лавки", "location_id": "brod", "description": "Бочки и крапива.",
                             "exits": ["brod-square"], "npcs": ["gen_npc_1"], "hooks": [], "secrets": [], "generated": True,
                             "encounter": {"id": "gen_room_1_enc", "enemies": [{"monster": "wolf", "count": 1, "name": "Волк", "desc": "", "col": 3}],
                                           "loot": {"coins_cp": 0, "items": {}}}}},
    "edge_exits": {"brod-square": ["gen_room_1"]},
    "edges_used": ["brod-square:0"],
    "room_secrets": {"gen_room_1": [{"id": "q_gen_quest_1", "dc": 10, "text": "Под крыльцом блестит", "skill": "perception",
                                     "loot": {"items": {"gen_ab12": 1}}}]},
    "quests": {
        "gen_quest_1": {"title": "Пропавший задаток", "description": "", "giver": "npc_merchant", "offer_text": "Найди задаток.",
                        "generated": True, "scale": "ordinary", "depth": 0, "steps": [
                            {"text": "Расспросить посыльного", "when": {"talk": "gen_npc_1"}, "action": "Поговорить: Тимоша"},
                            {"text": "Найти задаток", "when": {"secret": "gen_room_1:q_gen_quest_1"}},
                            {"text": "Отогнать волка", "when": {"encounter": "gen_room_1_enc"}, "danger": True},
                            {"text": "Отдать задаток", "when": {"talk": "npc_merchant", "item": "gen_ab12"}, "reward_cp": 3500, "xp": 150,
                             "attitude": {"npc_merchant": 1}, "danger": True}]},
        "gen_quest_2": {"title": "Кто травит колодцы", "description": "Своё.", "giver": "", "own": True, "generated": True,
                        "steps": [{"text": "Осмотреть погреб", "when": {"room": "brod-tavern-cellar"}, "xp": 300}]},
    },
}
ITEMS = {"gen_ab12": {"name": "Кошель задатка", "item_type": "treasure", "rarity": "common", "value_cp": 500, "weight": 0.5,
                      "properties": [], "description": "Тугой кожаный кошель.", "generated": True}}


def _setup_quest(tmp_path: Path) -> tuple[Path, Path]:
    user, worlds = _setup(tmp_path)
    save = {"session": {"world_id": "frontier", "generated": QUEST_GEN, "items": ITEMS}}
    (user / "saves" / "autosave.json").write_text(json.dumps(save, ensure_ascii=False), encoding="utf-8")
    return user, worlds


def test_a_quest_comes_with_its_place_person_and_thing(tmp_path):
    user, worlds = _setup_quest(tmp_path)
    assert "gen_quest_1: задание «Пропавший задаток» — от npc_merchant" in "\n".join(promote_world.report(user))
    lines = promote_world.promote(["autosave:gen_quest_1=quest_deposit"], user, worlds)
    assert lines[0].startswith("✓ gen_quest_1 → quest_deposit"), lines
    assert not any(line.startswith("✗") for line in lines), lines
    w = _world(worlds)
    q = w["quests"]["quest_deposit"]
    yard = next(r for r, d in w["rooms"].items() if d["name"] == "Задний двор лавки")
    boy = next(n for n, d in w["npcs"].items() if d["name"] == "Тимоша")
    item = next(i for i, d in w["items"].items() if d["name"] == "Кошель задатка")
    assert q["steps"][0]["when"] == {"talk": boy}
    assert q["steps"][1]["when"] == {"secret": f"{yard}:q_quest_deposit"}
    assert q["steps"][2]["when"] == {"encounter": f"{yard}_enc"}
    assert q["steps"][3]["when"] == {"talk": "npc_merchant", "item": item}
    assert q["description"] == "Пропавший задаток" and "generated" not in q and "scale" not in q
    hiding = next(s for s in w["rooms"][yard]["secrets"] if s["id"] == "q_quest_deposit")
    assert hiding["loot"] == {"items": {item: 1}}


def test_an_own_deed_stays_in_its_game(tmp_path):
    user, worlds = _setup_quest(tmp_path)
    assert "своё дело" in promote_world.promote(["autosave:gen_quest_2"], user, worlds)[0]


def test_a_thing_with_mechanics_waits_for_the_catalog(tmp_path):
    user, worlds = _setup_quest(tmp_path)
    save = json.loads((user / "saves" / "autosave.json").read_text(encoding="utf-8"))
    save["session"]["items"]["gen_ab12"]["properties"] = ["magic_plus1"]
    (user / "saves" / "autosave.json").write_text(json.dumps(save, ensure_ascii=False), encoding="utf-8")
    before = (worlds / "frontier" / "world.json").read_bytes()
    assert "promote_items" in promote_world.promote(["autosave:gen_quest_1"], user, worlds)[0]
    assert (worlds / "frontier" / "world.json").read_bytes() == before
