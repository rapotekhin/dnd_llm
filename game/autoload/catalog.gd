extends Node
## Game data from res://data/*.json, loaded and checked once at start. Fails loudly on a broken file.

const FILES: Array[String] = ["rules", "game"]

var data: Dictionary = {}


func _ready() -> void:
	for name in FILES:
		data[name] = load_json("res://data/%s.json" % name)


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
