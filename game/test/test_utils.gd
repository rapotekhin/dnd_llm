class_name TestUtils
extends RefCounted
## Shared helpers for gdUnit4 suites: game data without autoloads.

## Ids of the start pack (data/worlds/frontier) that the tests rely on.
const INNKEEPER := "npc_innkeeper"
const SERVING := "npc_serving"
const COOK := "npc_cook"
const START_ROOM := "brod-tavern-hall"
const KITCHEN := "brod-tavern-kitchen"
const FAR_ROOM := "mine-deep"


static func rules() -> Dictionary:
	return _json("res://data/rules.json")


static var _data: Dictionary = {}


## All game data with the start pack applied (a fresh deep copy: tests may change it).
static func data() -> Dictionary:
	if _data.is_empty():
		var base: Dictionary = preload("res://autoload/catalog.gd").load_all()
		_data = WorldPack.apply_rules(base, WorldPack.load_bundle("res://data/worlds/frontier", "builtin"))
	return _data.duplicate(true)


static func base() -> Dictionary:
	return preload("res://autoload/catalog.gd").load_all()


## The start pack's first ready-made character (Айра, fighter 1).
static func preset_choices() -> Dictionary:
	return CharacterBuilder.preset_choices(data()["presets"][0])


static func character() -> Dictionary:
	var d := data()
	return CharacterBuilder.build_preset(d["presets"][0], d)


static func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func new_session(seed_value: int = 42) -> GameSession:
	var d := data()
	var s := GameSession.create(seed_value, "2026-10-18T12:00:00", str(d["world"]["start_room"]), CharacterBuilder.build_preset(d["presets"][0], d))
	s.world_id = "frontier"
	s.settings = WorldPack.default_settings(d["pack"])
	return s


static func session_with_chat() -> GameSession:
	var s := new_session()
	s.append(GameSession.dm_entry("Таверна «Пьяный гусь».", s.next_turn_id()))
	s.append(GameSession.player_entry("осматриваюсь"))
	s.append(GameSession.check_entry({"skill": "perception"}, {"check_id": s.next_check_id(), "rolls": [12], "bonus": 0,
		"total": 12, "dc": 15, "success": false, "nat": 12, "blocked": false}))
	s.append(GameSession.dm_entry("Ничего необычного.", s.next_turn_id()))
	s.options = ["Подойти к стойке"]
	return s
