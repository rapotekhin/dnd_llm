class_name IconRules
extends RefCounted
## The one place an icon is chosen (v0.8.4.43). A ref is "<kind>/<id>" (items/longsword, spells/fireball, ui/map); the
## answer says what to draw, a window only shows it: {ref, path, real, tint, frame, framed, marks [{what, id, color, path}]}.
## `path` — the picture: a file by id (or `shared`) → for a made or magic thing its plain base's file
## (ItemRules.plain_of) → its group's file → the blank of the kind → _blank/default.png. `real` — the picture shows this
## very thing or its base (a blank does not, and the window adds the name over it). Marks are a damage type, a material,
## a spell's area; `frame` is the colour of an item's rarity; `tint` is a spell's school for a spell with no file.
## Everything is a row of data/icons.json: a new kind of mark needs no code.

const BLANK := "_blank/"
const EMPTY_HAND := "ui/empty_hand"  # a hand that holds nothing: the hotbar's hand, an attack with no weapon (an open palm)

static var _exists := {}  # path → bool: a file is looked for once a run


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("icons", {})


static func root(data: Dictionary) -> String:
	return str(cfg(data).get("root", "res://assets/icons/"))


static func ref(kind: String, id: String) -> String:
	return "%s/%s" % [kind, id]


static func of(data: Dictionary, session_items: Dictionary, r: String) -> Dictionary:
	var kind := r.get_slice("/", 0)
	var id := r.get_slice("/", 1) if r.contains("/") else ""
	var out := {"ref": r, "path": "", "real": false, "tint": "", "frame": "", "marks": []}
	if kind == "items":
		id = ItemRules.real_id(id)
		_item(data, session_items, id, out)
	elif kind == "spells":
		_spell(data, id, out)
	if out["path"] == "":
		out["path"] = own(data, ref(kind, id))
		out["real"] = out["path"] != ""
	if out["path"] == "":
		out["path"] = blank(data, kind)
	out["framed"] = out["real"] and (cfg(data).get("framed", []) as Array).has(kind)  # its own frame drawn in: laid edge to edge (v0.8.4.43.33)
	return out


## The file of a ref itself or of the ref it shares; "" — none.
static func own(data: Dictionary, r: String) -> String:
	var shared: Dictionary = cfg(data).get("shared", {})
	for at: String in [r, str(shared.get(r, ""))]:
		if at.is_empty():
			continue
		var path := root(data) + at + ".png"
		if has_file(path):
			return path
	return ""


static func blank(data: Dictionary, kind: String) -> String:
	var path := root(data) + BLANK + kind + ".png"
	return path if has_file(path) else root(data) + BLANK + "default.png"


static func has_file(path: String) -> bool:
	if not _exists.has(path):
		_exists[path] = ResourceLoader.exists(path)
	return _exists[path]


## The icon of a button of the interface by its node name (`buttons` of icons.json, a key «X_*» for every «X_…»):
## "ui/<id>", or "ui/default" for a name the table does not know.
static func button(data: Dictionary, node_name: String) -> String:
	var table: Dictionary = cfg(data).get("buttons", {})
	var row := ""
	if table.has(node_name):
		row = str(table[node_name])
	else:
		for k: String in table:
			if k.ends_with("*") and node_name.begins_with(k.trim_suffix("*")):
				row = str(table[k])
				break
	if row.is_empty():
		return "ui/default"
	return row if row.contains("/") else "ui/" + row  # a whole ref: a gathering spot by its thing (v0.8.4.43.14)


## The colour of a school of magic, "#hex" or "" for none.
static func school_color(data: Dictionary, school_id: String) -> String:
	return "" if school_id.begins_with("_") else str(cfg(data).get("schools", {}).get(school_id, ""))


## A file put in while the game runs (the build screen, a test) is seen again.
static func forget() -> void:
	_exists.clear()


static func _item(data: Dictionary, session_items: Dictionary, id: String, out: Dictionary) -> void:
	var def := ItemRules.def_of(data["items"], session_items, id)
	var c := cfg(data)
	out["frame"] = str(c.get("rarity", {}).get(str(def.get("rarity", "")), ""))
	var props: Array = def.get("properties", [])
	for t: String in (c.get("elements", {}) as Dictionary).keys():
		if not t.begins_with("_") and props.has(t + "_damage"):
			out["marks"].append(_mark(data, "elements", t))
	for m: String in (c.get("materials", {}) as Dictionary).keys():
		if not m.begins_with("_") and (props.has(m) or str(def.get("material", "")) == m or id.begins_with(m + "_")):
			out["marks"].append(_mark(data, "materials", m))
	var path := own(data, ref("items", id))
	if path == "":
		path = own(data, ref("items", ItemRules.plain_of(data["items"], session_items, id)))
	out["real"] = path != ""
	if path == "" and not def.is_empty():
		path = own(data, ref("groups", ItemGroups.of(data, session_items, id)))
	out["path"] = path


static func _spell(data: Dictionary, id: String, out: Dictionary) -> void:
	var sp: Dictionary = data.get("spells", {}).get(id, {})
	var c := cfg(data)
	if sp.has("damage_type") and c.get("elements", {}).has(str(sp["damage_type"])):
		out["marks"].append(_mark(data, "elements", str(sp["damage_type"])))
	var area: Variant = sp.get("area", {})
	if area is Dictionary and c.get("shapes", {}).has(str((area as Dictionary).get("type", ""))):
		out["marks"].append(_mark(data, "shapes", str(area["type"])))
	out["path"] = own(data, ref("spells", id))
	out["real"] = out["path"] != ""
	if out["path"] == "":
		out["tint"] = school_color(data, str(sp.get("school_id", "")))
		out["path"] = blank(data, "spells")


## A mark: its colour, and its own picture when assets/icons/marks/<what>/<id>.png is there.
static func _mark(data: Dictionary, what: String, id: String) -> Dictionary:
	var path := root(data) + "marks/%s/%s.png" % [what, id]
	return {"what": what, "id": id, "color": str(cfg(data)[what][id]), "path": path if has_file(path) else ""}
