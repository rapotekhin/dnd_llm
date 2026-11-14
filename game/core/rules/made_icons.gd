class_name MadeIcons
extends RefCounted
## The icons of what the master made (v0.8.4.44.1): a thing, a spell, an ability, a status or a trait is drawn once by
## the icon model (`icon.request`, one frame on a chroma ground by the same seed), cut by IconCut and kept in the
## profile's folder by its ref. A made thing's id is its own (ItemRules.generated_id, the ids of MakeRules), so one
## picture serves it in every game it comes in again. IconRules.own reads the folder after the art of the game; what
## has a picture of its own is not drawn. The rows are rules.made_icons.

const DIR := "made_icons/"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["made_icons"]


## The folder of a profile's made icons ("user:/" is the profile of no name: user://made_icons/).
static func root(profile_dir: String) -> String:
	var base := profile_dir.trim_suffix("/")
	return ("user://" if base == "user:" else base + "/") + DIR


## The file of a ref in the folder.
static func path_of(folder: String, r: String) -> String:
	return folder + r + ".png"


## What the master made in this game and has no picture yet: [{ref, kind, name, text, ground}], things first, then the
## made acts and statuses in the order they were made.
static func wanted(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cf := cfg(data)
	for id: String in s.items:
		var def: Dictionary = s.items[id]
		if drawn(data, id, def):
			_add(out, data, IconRules.ref("items", id), "item", str(def.get("name", "")), str(def.get("description", "")))
	var made: Dictionary = WorldGen.generated(s).get("made", {})
	for id: String in made:
		var def: Dictionary = made[id]
		var row: Variant = (cf["kinds"] as Dictionary).get(str(def.get("what", "")))
		if row is Array:
			_add(out, data, IconRules.ref(str(row[0]), id), str(row[1]), str(def.get("name", "")), str(def.get("text", "")))
	return out


## Whether a thing of the session is the master's own invention, drawn as itself: a made thing with none of the fields
## that make it a copy of another (a quality, a book or a recipe, a pact's weapon) and no use a group's picture tells
## (a scroll).
static func drawn(data: Dictionary, id: String, def: Dictionary) -> bool:
	var skip: Dictionary = cfg(data)["skip"]
	if not id.begins_with(MakeRules.PREFIX) or not bool(def.get("generated", false)):
		return false
	if (skip["fields"] as Array).any(func(f: String) -> bool: return def.has(f)):
		return false
	var use: Variant = def.get("use")
	return not (use is Dictionary and (skip["uses"] as Array).any(func(u: String) -> bool: return bool((use as Dictionary).get(u, false))))


## The chroma ground of a subject: magenta when its words speak of green (rules.made_icons.magenta), else green.
static func ground(data: Dictionary, name: String, text: String) -> String:
	var words := (name + " " + text + " ").to_lower()
	return "magenta" if (cfg(data)["magenta"] as Array).any(func(w: String) -> bool: return words.contains(w)) else "green"


## The params of `icon.request` for one wanted icon.
static func params(data: Dictionary, want: Dictionary) -> Dictionary:
	return {"kind": want["kind"], "name": str(want["name"]).left(80), "text": str(want["text"]).left(600),
		"ground": want["ground"], "seed": int(cfg(data)["seed"])}


static func _add(out: Array[Dictionary], data: Dictionary, r: String, kind: String, name: String, text: String) -> void:
	if name.strip_edges().is_empty() or not IconRules.own(data, r).is_empty():
		return
	out.append({"ref": r, "kind": kind, "name": name, "text": text, "ground": ground(data, name, text)})
