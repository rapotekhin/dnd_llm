class_name TestUtils
extends RefCounted
## Shared helpers for gdUnit4 suites: game data without autoloads.


static func rules() -> Dictionary:
	return _json("res://data/rules.json")


static func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func session_with_chat() -> GameSession:
	var s := GameSession.create(42, "2026-10-18T12:00:00")
	s.append(GameSession.dm_entry("Таверна «Пьяный гусь».", s.next_turn_id()))
	s.append(GameSession.player_entry("осматриваюсь"))
	s.append(GameSession.check_entry({"skill": "perception"}, {"check_id": s.next_check_id(), "rolls": [12], "bonus": 0,
		"total": 12, "dc": 15, "success": false, "nat": 12, "blocked": false}))
	s.append(GameSession.dm_entry("Ничего необычного.", s.next_turn_id()))
	s.options = ["Подойти к стойке"]
	return s
