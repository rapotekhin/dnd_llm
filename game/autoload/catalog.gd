extends Node
## Game data from res://data/*.json, loaded once at start. Fails loudly on a broken file.

const FILES: Dictionary[String, String] = {
	"rules": "res://data/rules.json",
	"game": "res://data/game.json",
	"items": "res://data/items.json",
	"world": "res://data/start/world.json",
	## The ready-made start character as creation choices (CharacterBuilder); packs bring theirs from v0.5.1.
	"character": "res://data/start/character.json",
	"races": "res://data/srd/races.json",
	"classes": "res://data/srd/classes.json",
	"spells": "res://data/srd/spells.json",
	"backgrounds": "res://data/srd/backgrounds.json",
	"misc": "res://data/srd/misc.json",
}

var data: Dictionary = {}


func _ready() -> void:
	data = load_all()


## Every data file by key; also used by tests without the autoload.
static func load_all() -> Dictionary:
	var out := {}
	for key: String in FILES:
		out[key] = load_json(FILES[key])
	return out


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
