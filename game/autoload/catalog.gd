extends Node
## Game data, loaded once at start: the base (rules, game settings, items, SRD) and the world packs
## (WorldPack). `data` is the base with the active pack applied — every system reads it.
## A broken base file fails loudly; a broken pack is listed with its errors and cannot be picked.

const FILES: Dictionary[String, String] = {
	"rules": "res://data/rules.json",
	"game": "res://data/game.json",
	"items": "res://data/items.json",
	"races": "res://data/srd/races.json",
	"classes": "res://data/srd/classes.json",
	"spells": "res://data/srd/spells.json",
	"backgrounds": "res://data/srd/backgrounds.json",
	"misc": "res://data/srd/misc.json",
}

var base: Dictionary = {}
## Every pack found (valid or not), built-in first.
var bundles: Array[Dictionary] = []
## base + the active pack (WorldPack.apply_rules).
var data: Dictionary = {}
var active_world: String = ""


func _ready() -> void:
	base = load_all()
	rescan()
	activate(str(base["game"].get("default_world", "")))


## Base data by key; also used by tests without the autoload.
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


func rescan() -> void:
	DirAccess.make_dir_recursive_absolute(WorldPack.MODS_DIR)
	bundles = WorldPack.scan([WorldPack.BUILTIN_DIR, WorldPack.MODS_DIR], base)
	for b: Dictionary in bundles:
		if not b["errors"].is_empty():
			push_warning("world pack %s (%s): %s" % [b["id"], b["dir"], "; ".join(b["errors"])])


func playable() -> Array[Dictionary]:
	return bundles.filter(func(b: Dictionary) -> bool: return b["errors"].is_empty())


func bundle(id: String) -> Dictionary:
	for b: Dictionary in playable():
		if b["id"] == id:
			return b
	return {}


## Makes `id` the active world; false if there is no playable pack with that id (the old one stays).
func activate(id: String) -> bool:
	var b := bundle(id)
	if b.is_empty():
		var any := playable()
		if not data.is_empty() or any.is_empty():
			return false
		b = any[0]
	data = WorldPack.apply_rules(base, b)
	active_world = str(b["id"])
	return active_world == id


func rules() -> Dictionary:
	return data["rules"]


func game() -> Dictionary:
	return data["game"]
