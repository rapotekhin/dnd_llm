class_name TestUtils
extends RefCounted
## Shared helpers for gdUnit4 suites: game data without autoloads.

const INNKEEPER := "a1f3c7c2-6b1e-4e92-9e2a-111111111111"
const COOK := "c3f5e9e4-8d3a-4ab4-9c4c-333333333333"


static func rules() -> Dictionary:
	return _json("res://data/rules.json")


static var _data: Dictionary = {}


## All game data (a fresh deep copy: tests may change it).
static func data() -> Dictionary:
	if _data.is_empty():
		_data = preload("res://autoload/catalog.gd").load_all()
	return _data.duplicate(true)


## The start character (Айра, fighter 1) built from data/start/character.json.
static func character() -> Dictionary:
	var d := data()
	return CharacterBuilder.build(d["character"], d)


static func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func new_session(seed_value: int = 42) -> GameSession:
	var d := data()
	return GameSession.create(seed_value, "2026-10-18T12:00:00", str(d["world"]["start_room"]), CharacterBuilder.build(d["character"], d))


static func session_with_chat() -> GameSession:
	var s := new_session()
	s.append(GameSession.dm_entry("Таверна «Пьяный гусь».", s.next_turn_id()))
	s.append(GameSession.player_entry("осматриваюсь"))
	s.append(GameSession.check_entry({"skill": "perception"}, {"check_id": s.next_check_id(), "rolls": [12], "bonus": 0,
		"total": 12, "dc": 15, "success": false, "nat": 12, "blocked": false}))
	s.append(GameSession.dm_entry("Ничего необычного.", s.next_turn_id()))
	s.options = ["Подойти к стойке"]
	return s
