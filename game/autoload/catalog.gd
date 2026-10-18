extends Node
## Game data from res://data/*.json, loaded once at start. Fails loudly on a broken file.

const FILES: Dictionary[String, String] = {
	"rules": "res://data/rules.json",
	"game": "res://data/game.json",
	"items": "res://data/items.json",
	"world": "res://data/start/world.json",
	"character": "res://data/start/character.json",
}

var data: Dictionary = {}


func _ready() -> void:
	for key: String in FILES:
		data[key] = load_json(FILES[key])


static func load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("Catalog: cannot parse %s" % path)
		return {}
	return parsed


func rules() -> Dictionary:
	return data["rules"]


func game() -> Dictionary:
	return data["game"]
