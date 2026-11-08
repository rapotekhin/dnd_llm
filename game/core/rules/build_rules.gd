class_name BuildRules
extends RefCounted
## One's own place furnished by hand (v0.8.4.42, the author: «Имущество как в Sims»): on the map of its room the owner
## draws walls, puts windows and doors in them, sets things on squares and opens passages into new rooms of its own name.
## A row of the catalog (rules.property.furnish) is a `part` — a square of layouts.json `cells`; a `thing` — an upgrade
## of the place (PropertyRules.ups, the master's too) that stands on a square and works by its rules (a bed rests, a
## chest stores, a station crafts, a counter trades); or the `passage` — stairs inside a building, a new place under the
## sky at the edge of an open map, a new building in a wall of it. The squares are the generator's (LayoutGen): what the
## hands did is the room's `build` {cells: {"x,y": {c, was, part, way?}}, things: [{id, up, x, y, mark, …}]} on the grid,
## laid over the generated map by LayoutRules. Money — Ledger, the price — Price; `who` builds (the hero by default).

const PART := "part"
const THING := "thing"
const PASSAGE := "passage"


static func cfg(data: Dictionary) -> Dictionary:
	return PropertyRules.cfg(data)["furnish"]


# --- where -----------------------------------------------------------------------------------------------------------


## The place `who` furnishes: its own place it stands in, "" — none.
static func place_of(s: GameSession, data: Dictionary, who: String = Being.HERO) -> String:
	return PropertyRules.here(s, data, who) if data["rules"].has("property") else ""


## "" when `who` may build here now, else a localization key.
static func where_why(s: GameSession, data: Dictionary, who: String = Being.HERO) -> String:
	if place_of(s, data, who).is_empty():
		return "BUILD_NOT_HOME"
	return "BUILD_NOT_NOW" if CombatRules.active(s) else ""


# --- the catalog -----------------------------------------------------------------------------------------------------


## An upgrade that stands on a square: what it gives has a key of `furnish.things`.
static func is_thing(data: Dictionary, u: Dictionary) -> bool:
	var g: Dictionary = u.get("gives", {})
	return (cfg(data)["things"] as Array).any(func(k: Variant) -> bool: return g.has(str(k)))


## A thing of this kind is one to a place: a counter makes a shop of its own; an income or a staff place would add up.
static func _one_only(data: Dictionary, u: Dictionary) -> bool:
	var g: Dictionary = u.get("gives", {})
	return g.has("object") or g.keys().any(func(k: Variant) -> bool: return not (cfg(data)["things"] as Array).has(k) and str(k) != "capacity_lb")


## The group of a row for the filter: a part's own, a thing's by what it gives, the passage — "ways".
static func group_of(data: Dictionary, row: Dictionary) -> String:
	if row.has("group"):
		return str(row["group"])
	var g: Dictionary = row.get("gives", {})
	for gr: Dictionary in cfg(data)["groups"]:
		if (gr.get("gives", []) as Array).any(func(k: Variant) -> bool: return g.has(str(k))):
			return str(gr["id"])
	return "decor"


static func groups(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for gr: Dictionary in cfg(data)["groups"]:
		out.append(str(gr["id"]))
	return out


## The mark of the map a thing stands as: a station by layouts.json `mark_tags`, else `furnish.marks`; "" — none (a chest
## is a thing of the room, PropRules).
static func mark_of(data: Dictionary, u: Dictionary) -> String:
	var g: Dictionary = u.get("gives", {})
	var marks: Dictionary = cfg(data)["marks"]
	if g.has("station"):
		return str(data["layouts"]["mark_tags"].get(str(g["station"]), marks["station"]))
	for k: String in marks:
		if g.has(k):
			return str(marks[k])
	return ""


## What may be built at the place: [{id, kind, name, text, price_cp, group, cell?}]; the passage's price is its cheapest.
static func catalog(s: GameSession, data: Dictionary, pid: String, who: String = Being.HERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts: Dictionary = cfg(data)["parts"]
	for id: String in parts:
		var p: Dictionary = parts[id]
		out.append({"id": id, "kind": PART, "name": str(p["name"]), "text": str(p.get("text", "")), "price_cp": int(p["price_cp"]),
			"group": group_of(data, p), "cell": str(p["cell"])})
	var all_ups := PropertyRules.ups(data)
	for up: String in all_ups:
		var u: Dictionary = all_ups[up]
		if is_thing(data, u) and PropertyRules.fits(s, data, pid, up, who):
			out.append({"id": up, "kind": THING, "name": str(u["name"]), "text": str(u.get("text", "")), "price_cp": int(u["price_cp"]),
				"group": group_of(data, u)})
	var pg: Dictionary = cfg(data)["passage"]
	var least := 1 << 30
	for k: String in pg["kinds"]:
		least = mini(least, int(pg["kinds"][k]["price_cp"]))
	out.append({"id": PASSAGE, "kind": PASSAGE, "name": str(pg["name"]), "text": str(pg.get("text", "")), "price_cp": least, "group": str(pg["group"])})
	return out


## The rows of a group ("" — all) whose name holds `query`.
static func view(rows: Array[Dictionary], query: String, group: String) -> Array[Dictionary]:
	var q := query.strip_edges().to_lower()
	var out: Array[Dictionary] = rows.filter(func(r: Dictionary) -> bool:
		return (group.is_empty() or str(r["group"]) == group) and (q.is_empty() or str(r["name"]).to_lower().contains(q)))
	return out


static func row(s: GameSession, data: Dictionary, pid: String, id: String, who: String = Being.HERO) -> Dictionary:
	for r: Dictionary in catalog(s, data, pid, who):
		if str(r["id"]) == id:
			return r
	return {}


## One price of a row (Price): the passage's by the kind its square makes.
static func quote(data: Dictionary, r: Dictionary, passage_kind: String = "") -> Dictionary:
	if str(r.get("kind", "")) == PASSAGE and not passage_kind.is_empty():
		return Price.start(int(cfg(data)["passage"]["kinds"][passage_kind]["price_cp"]))
	return Price.start(int(r.get("price_cp", 0)))


# --- the room's record -----------------------------------------------------------------------------------------------


static func record(v: WorldView, room: String) -> Dictionary:
	return v.room(room).get("build", {})


## The records of the rooms of a map: a part of its key, so the map is laid again when the hands change it.
static func records(v: WorldView, rooms: Array[String]) -> Array:
	var out: Array = []
	for r: String in rooms:
		out.append(record(v, r))
	return out


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _cell(key: String) -> Vector2i:
	return Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))


## Lays what the hands built over a map just generated: the squares, then the marks of the things before the others.
static func lay(map: Dictionary, v: WorldView) -> void:
	var ids: Array = map["ids"]
	for i: int in ids.size():
		var rec := record(v, str(ids[i]))
		for key: String in rec.get("cells", {}):
			_put_cell(map, LayoutGen.off_grid(map, _cell(key)), str(rec["cells"][key]["c"]))
		for t: Dictionary in rec.get("things", []):
			if not str(t.get("mark", "")).is_empty():
				var at := LayoutGen.off_grid(map, Vector2i(int(t["x"]), int(t["y"])))
				(map["marks"] as Array).push_front({"name": str(t["mark"]), "x": at.x, "y": at.y, "room": i})


static func _put_cell(map: Dictionary, at: Vector2i, c: String) -> void:
	if at.x < 0 or at.y < 0 or at.x >= int(map["w"]) or at.y >= int(map["h"]):
		return
	var rows: Array = map["rows"]
	rows[at.y] = str(rows[at.y]).substr(0, at.x) + c + str(rows[at.y]).substr(at.x + 1)


## The things placed on a map, as tokens of the build screen: {ref, kind, id, name, mark, x, y}.
static func tokens(data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := WorldView.new(data["world"])
	for room: Variant in map["ids"]:
		for t: Dictionary in record(v, str(room)).get("things", []):
			var at := LayoutGen.off_grid(map, Vector2i(int(t["x"]), int(t["y"])))
			var name := str(PropertyRules.ups(data).get(str(t["up"]), {}).get("name", t["up"]))
			out.append({"ref": "build:" + str(t["id"]), "kind": "prop", "id": str(t["id"]), "name": name, "mark": name.left(1), "x": at.x, "y": at.y, "attitude": 0})
	return out


static func _thing_at(v: WorldView, map: Dictionary, cell: Vector2i) -> Dictionary:
	var g := LayoutGen.on_grid(map, cell)
	for room: Variant in map["ids"]:
		for t: Dictionary in record(v, str(room)).get("things", []):
			if int(t["x"]) == g.x and int(t["y"]) == g.y:
				return {"room": str(room), "thing": t}
	return {}


static func _edit_at(v: WorldView, map: Dictionary, cell: Vector2i) -> Dictionary:
	var key := _key(LayoutGen.on_grid(map, cell))
	for room: Variant in map["ids"]:
		var cells: Dictionary = record(v, str(room)).get("cells", {})
		if cells.has(key):
			return {"room": str(room), "key": key, "edit": cells[key]}
	return {}


static func _save(s: GameSession, data: Dictionary, room: String, rec: Dictionary) -> void:
	Overlay.put(s, data, EntityRef.room(room), "build", rec)


static func _rec(data: Dictionary, room: String) -> Dictionary:
	var rec: Dictionary = record(WorldView.new(data["world"]), room).duplicate(true)
	for k: String in ["cells", "things"]:
		if not rec.has(k):
			rec[k] = {} if k == "cells" else []
	return rec


# --- the squares -----------------------------------------------------------------------------------------------------


static func _map(s: GameSession, data: Dictionary, who: String) -> Dictionary:
	return LayoutRules.map_of(s, data, Life.room(s, data, who))


static func _char(map: Dictionary, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(map["w"]) or cell.y >= int(map["h"]):
		return LayoutGen.BLANK
	return str(map["rows"][cell.y])[cell.x]


static func _floor_free(data: Dictionary, map: Dictionary, cell: Vector2i) -> bool:
	var c := _char(map, cell)
	return not LayoutGen.solid(data["layouts"], c) and not bool(data["layouts"]["cells"].get(c, {}).get("keep_free", false))


## The squares nothing is built on: the ways and the squares before them, doors between rooms, the marks, placed things,
## things put on a square, the hero.
static func _taken(s: GameSession, data: Dictionary, map: Dictionary, who: String) -> Dictionary:
	var out := {}
	for e: Dictionary in map["exits"]:
		out[Vector2i(int(e["x"]), int(e["y"]))] = true
		out[Vector2i(int(e["ax"]), int(e["ay"]))] = true
	for d: Dictionary in map["doors"]:
		out[Vector2i(int(d["x"]), int(d["y"]))] = true
	for m: Dictionary in map["marks"]:
		out[Vector2i(int(m["x"]), int(m["y"]))] = true
	for room: Variant in map["ids"]:
		for p: Dictionary in s.props.get(str(room), []):
			if p.get("at") is Array:
				out[LayoutGen.off_grid(map, Vector2i(int(p["at"][0]), int(p["at"][1])))] = true
	if who == Being.HERO and str(map["id"]) == LayoutRules.map_id(s, data, s.room_id):
		out[WalkRules.settle(s, data, map)] = true
	return out


## The squares a change must keep joined: the ways in and out, the doors between rooms, the hero.
static func _anchors(s: GameSession, data: Dictionary, map: Dictionary, who: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e: Dictionary in map["exits"]:
		out.append(Vector2i(int(e["ax"]), int(e["ay"])))
	for d: Dictionary in map["doors"]:
		out.append(Vector2i(int(d["x"]), int(d["y"])))
	if who == Being.HERO and str(map["id"]) == LayoutRules.map_id(s, data, s.room_id):
		out.append(WalkRules.settle(s, data, map))
	return out


## The square changed to `c` cuts none of the anchors joined now from another (the map was checked so, LayoutGen.faults).
static func _sound(data: Dictionary, map: Dictionary, anchors: Array[Vector2i], cell: Vector2i, c: String) -> bool:
	var lib: Dictionary = data["layouts"]
	var before := _parts(map, lib, anchors)
	var after_map := map.duplicate()
	after_map["rows"] = (map["rows"] as Array).duplicate()
	_put_cell(after_map, cell, c)
	var after := _parts(after_map, lib, anchors)
	for i: int in anchors.size():
		for j: int in anchors.size():
			if before[i] == before[j] and after[i] != after[j]:
				return false
	return true


## Which part of the map each anchor is in: the index of the first anchor it reaches.
static func _parts(map: Dictionary, lib: Dictionary, anchors: Array[Vector2i]) -> Array[int]:
	var out: Array[int] = []
	out.resize(anchors.size())
	out.fill(-1)
	for i: int in anchors.size():
		if out[i] >= 0:
			continue
		var seen := LayoutGen.reached(map, lib, anchors[i])
		for j: int in anchors.size():
			if out[j] < 0 and seen.has(anchors[j]):
				out[j] = i
	return out


## Of the place `pid`: a square of a room it owns.
static func _room_at(s: GameSession, data: Dictionary, map: Dictionary, pid: String, cell: Vector2i) -> String:
	var room := WalkRules.room_of(map, cell)
	return room if not room.is_empty() and PropertyRules.at(s, data, room) == pid else ""


# --- building --------------------------------------------------------------------------------------------------------


## The kind of passage a square makes: inside a building — stairs; on an open map — a new place under the sky at its
## edge, a new building in a wall elsewhere.
static func passage_kind(s: GameSession, data: Dictionary, map: Dictionary, room: String, cell: Vector2i) -> String:
	if not LayoutRules.is_open(s, data, room):
		return "stairs"
	var edge := cell.x == 0 or cell.y == 0 or cell.x == int(map["w"]) - 1 or cell.y == int(map["h"]) - 1
	return "edge" if edge else "door"


## The price of `id` on `cell` of the map `who` stands on: 0 — nothing to build there.
static func price(s: GameSession, data: Dictionary, id: String, cell: Vector2i, who: String = Being.HERO) -> int:
	var pid := place_of(s, data, who)
	var r := row(s, data, pid, id, who)
	if r.is_empty():
		return 0
	var map := _map(s, data, who)
	var kind := passage_kind(s, data, map, WalkRules.room_of(map, cell), cell) if str(r["kind"]) == PASSAGE else ""
	return Price.rounded(quote(data, r, kind))


## "" when `who` may build `id` (a row of the catalog) on `cell` of the map it stands on, else a localization key.
## `name` — the new room's for a passage.
static func build_why(s: GameSession, data: Dictionary, id: String, cell: Vector2i, name: String = "", who: String = Being.HERO) -> String:
	var why := where_why(s, data, who)
	if not why.is_empty():
		return why
	var pid := place_of(s, data, who)
	var r := row(s, data, pid, id, who)
	if r.is_empty():
		return "BUILD_UNKNOWN"
	var map := _map(s, data, who)
	var room := _room_at(s, data, map, pid, cell)
	if room.is_empty():
		return "BUILD_NOT_YOURS"
	var taken := _taken(s, data, map, who)
	match str(r["kind"]):
		PART:
			why = _part_why(s, data, map, cell, cfg(data)["parts"][id], taken, who)
		THING:
			why = _thing_why(s, data, map, room, cell, PropertyRules.ups(data)[id], pid, id, taken, who)
		_:
			why = _passage_why(s, data, map, room, cell, name, taken, who)
	if not why.is_empty():
		return why
	return "PROPERTY_NO_MONEY" if Ledger.balance(s, who) < price(s, data, id, cell, who) else ""


static func _part_why(s: GameSession, data: Dictionary, map: Dictionary, cell: Vector2i, p: Dictionary, taken: Dictionary, who: String) -> String:
	if taken.has(cell):
		return "BUILD_TAKEN"
	var c := str(p["cell"])
	if _char(map, cell) == c:
		return "BUILD_SAME"
	if str(p.get("on", "floor")) == "wall":
		if _char(map, cell) != LayoutGen.WALL:
			return "BUILD_ON_WALL"
	elif not _floor_free(data, map, cell):
		return "BUILD_ON_FLOOR"
	if c == LayoutGen.DOOR and not _through(data, map, cell):
		return "BUILD_DOOR_NOWHERE"
	if not _sound(data, map, _anchors(s, data, map, who), cell, c):
		return "BUILD_CUTS"
	return ""


## A door joins two squares of floor across it.
static func _through(data: Dictionary, map: Dictionary, cell: Vector2i) -> bool:
	var lib: Dictionary = data["layouts"]
	var walk := func(d: Vector2i) -> bool: return not LayoutGen.solid(lib, _char(map, cell + d))
	return (walk.call(Vector2i.LEFT) and walk.call(Vector2i.RIGHT)) or (walk.call(Vector2i.UP) and walk.call(Vector2i.DOWN))


static func _thing_why(s: GameSession, data: Dictionary, map: Dictionary, room: String, cell: Vector2i, u: Dictionary, pid: String, up: String,
		taken: Dictionary, who: String) -> String:
	if taken.has(cell) or not _thing_at(WorldView.new(data["world"]), map, cell).is_empty():
		return "BUILD_TAKEN"
	if not _floor_free(data, map, cell):
		return "BUILD_ON_FLOOR"
	if bool(u.get("indoor", false)) and not SceneRules.indoor(s, data["world"], room):
		return "PROPERTY_NEEDS_ROOF"
	if _one_only(data, u) and PropertyRules.has_upgrade(Life.of(s, who, data), pid, up):
		return "PROPERTY_UPGRADE_HAS"
	return ""


static func _passage_why(s: GameSession, data: Dictionary, map: Dictionary, room: String, cell: Vector2i, name: String, taken: Dictionary, who: String) -> String:
	var n := name.strip_edges()
	if n.is_empty() or n.length() > int(cfg(data)["name_max"]):
		return "BUILD_NAME"
	if taken.has(cell):
		return "BUILD_TAKEN"
	var kind := passage_kind(s, data, map, room, cell)
	match kind:
		"stairs":
			if not _floor_free(data, map, cell) or not _thing_at(WorldView.new(data["world"]), map, cell).is_empty():
				return "BUILD_ON_FLOOR"
		"door":  # a new building: in a wall the hands drew on the open map
			var own: Dictionary = _edit_at(WorldView.new(data["world"]), map, cell).get("edit", {})
			if _char(map, cell) != LayoutGen.WALL or str(own.get("c", "")) != LayoutGen.WALL or _front(data, map, cell, _reach(s, data, map, who)).x < 0:
				return "BUILD_PASSAGE_WALL"
		_:
			if not _floor_free(data, map, _inward(map, cell)) or taken.has(_inward(map, cell)):
				return "BUILD_PASSAGE_EDGE"
	if LayoutRules.is_open(s, data, room):
		var no := LayoutRules.no_way(s, data, room, kind == "edge")
		if not no.is_empty():
			return "BUILD_NO_WAY"
	return ""


## The square of floor before a door in a wall of an open map, the side the walker comes from first; (-1, -1) — none.
static func _front(data: Dictionary, map: Dictionary, cell: Vector2i, reach: Dictionary) -> Vector2i:
	var any := Vector2i(-1, -1)
	for side: String in LayoutGen.SIDES:
		var at: Vector2i = cell + LayoutGen.STEP[side]
		if _floor_free(data, map, at):
			if reach.has(at):
				return at
			any = at if any.x < 0 else any
	return any


## The squares reached from the hero (from the first way in for another builder).
static func _reach(s: GameSession, data: Dictionary, map: Dictionary, who: String) -> Dictionary:
	var anchors := _anchors(s, data, map, who)
	return LayoutGen.reached(map, data["layouts"], anchors[-1]) if not anchors.is_empty() else {}


static func _border_side(map: Dictionary, cell: Vector2i) -> String:
	if cell.y == 0:
		return "n"
	if cell.y == int(map["h"]) - 1:
		return "s"
	return "w" if cell.x == 0 else "e"


static func _inward(map: Dictionary, cell: Vector2i) -> Vector2i:
	return cell + LayoutGen.STEP[LayoutGen.OPPOSITE[_border_side(map, cell)]]


## Builds `id` on `cell` (build_why first). Lines.
static func build(s: GameSession, data: Dictionary, id: String, cell: Vector2i, name: String = "", who: String = Being.HERO) -> Array[String]:
	var pid := place_of(s, data, who)
	var r := row(s, data, pid, id, who)
	var map := _map(s, data, who)
	var room := WalkRules.room_of(map, cell)
	var cost := price(s, data, id, cell, who)
	Ledger.add(s, -cost, "property:furnish", who)
	match str(r["kind"]):
		PART:
			var rec := _rec(data, room)
			var key := _key(LayoutGen.on_grid(map, cell))
			var was: Dictionary = rec["cells"].get(key, {})
			rec["cells"][key] = {"c": str(r["cell"]), "was": str(was.get("was", _char(map, cell))), "part": id}
			_save(s, data, room, rec)
			return ["%s: %s — %s" % [PropertyRules.name_of(s, data, pid), str(r["name"]).to_lower(), Money.format(cost)]]
		THING:
			var g := LayoutGen.on_grid(map, cell)
			var gen := WorldGen.generated(s)
			gen["build_n"] = int(gen.get("build_n", 0)) + 1
			var thing := {"id": "b%d" % int(gen["build_n"]), "up": id, "x": g.x, "y": g.y, "mark": mark_of(data, PropertyRules.ups(data)[id])}
			var lines := PropertyRules.apply_upgrade(s, data, pid, id, who, room, thing)
			var rec := _rec(data, room)
			(rec["things"] as Array).append(thing)
			_save(s, data, room, rec)
			return lines
	return _passage(s, data, pid, map, room, cell, name.strip_edges(), cost, who)


static func _passage(s: GameSession, data: Dictionary, pid: String, map: Dictionary, room: String, cell: Vector2i, name: String, cost: int,
		who: String) -> Array[String]:
	var v := WorldView.new(data["world"])
	var kind := passage_kind(s, data, map, room, cell)
	var k: Dictionary = cfg(data)["passage"]["kinds"][kind]
	var mid := LayoutRules.map_id(s, data, room)
	var floor_now := int(LayoutRules.fields(v.room(room)).get("floor", 0))
	var layout := {"shape": "open" if kind == "edge" else ("building" if kind == "door" else LayoutRules.shape_of(v, data, room)),
		"floor": floor_now + 1 if kind == "stairs" else 0, "rows": _rows(kind, k["size"])}
	var rid := PropertyRules.add_room(s, data, room, {"name": name, "description": str(k.get("description", "")), "indoor": kind != "edge",
		"layout": layout}, v.site_id(room))
	var side := "n"
	var front := cell
	if kind == "door":
		front = _front(data, map, cell, _reach(s, data, map, who))
		for sd: String in LayoutGen.SIDES:
			if front + LayoutGen.STEP[sd] == cell:
				side = sd
	elif kind == "edge":
		side = _border_side(map, cell)
		front = _inward(map, cell)
	var at := LayoutGen.on_grid(map, cell)
	var ahead := LayoutGen.on_grid(map, front)
	var way := {"to": rid, "room": room, "x": at.x, "y": at.y, "ax": ahead.x, "ay": ahead.y, "side": side, "kind": kind}
	var picks: Dictionary = s.layouts.get_or_add("picks", {}).get_or_add(mid, {})
	var own: Dictionary = picks if LayoutRules.is_open(s, data, room) else picks.get_or_add(room, {})
	own.get_or_add("ways", {})[rid] = way  # the way stands where the hands put it, LayoutGen keeps it so
	if kind == "door":
		var rec := _rec(data, room)
		rec["cells"][_key(at)] = {"c": LayoutGen.DOOR, "was": _char(map, cell), "part": "door", "way": rid}
		_save(s, data, room, rec)
	ObjectRules.note(s, v.site_id(room), "пристроено: %s" % name)
	return ["%s: %s — «%s», %s" % [PropertyRules.name_of(s, data, pid), kind_words(kind), name, Money.format(cost)]]


## The words of a passage's kind for the lines.
static func kind_words(kind: String) -> String:
	return {"stairs": "лестница в новую комнату", "door": "дверь в новое здание", "edge": "проход на новый участок"}.get(kind, kind)


## The rows of a new room: an empty box with a socket on each side (a building), an open plot (a place under the sky).
static func _rows(kind: String, size: Array) -> Array[String]:
	var w := int(size[0])
	var h := int(size[1])
	var out: Array[String] = []
	for y: int in h:
		if kind == "edge":
			out.append(".".repeat(w))
		elif y == 0 or y == h - 1:
			out.append("#".repeat(w / 2) + LayoutGen.SOCKET + "#".repeat(w - w / 2 - 1))
		else:
			var side := LayoutGen.SOCKET if y == h / 2 else LayoutGen.WALL
			out.append(side + ".".repeat(w - 2) + side)
	return out


# --- taking away -----------------------------------------------------------------------------------------------------


## "" when what the hands built on `cell` may be taken away, else a localization key.
static func remove_why(s: GameSession, data: Dictionary, cell: Vector2i, who: String = Being.HERO) -> String:
	var why := where_why(s, data, who)
	if not why.is_empty():
		return why
	var map := _map(s, data, who)
	var v := WorldView.new(data["world"])
	if _room_at(s, data, map, place_of(s, data, who), cell).is_empty():
		return "BUILD_NOT_YOURS"
	var at := _thing_at(v, map, cell)
	if not at.is_empty():
		var t: Dictionary = at["thing"]
		if t.has("object"):
			return "BUILD_KEEP_OBJECT"
		for p: Dictionary in s.props.get(str(at["room"]), []):
			if str(p.get("id", "")) == str(t.get("prop", "")) and not (p.get("contents", {}) as Dictionary).is_empty():
				return "BUILD_CHEST_FULL"
		return ""
	var e := _edit_at(v, map, cell)
	if e.is_empty():
		return "BUILD_NOTHING"
	if e["edit"].has("way"):
		return "BUILD_KEEP_WAY"
	return "" if _sound(data, map, _anchors(s, data, map, who), cell, str(e["edit"]["was"])) else "BUILD_CUTS"


## Takes away what the hands built on `cell`: `refund_pct` of its price back. Lines.
static func remove(s: GameSession, data: Dictionary, cell: Vector2i, who: String = Being.HERO) -> Array[String]:
	var pid := place_of(s, data, who)
	var map := _map(s, data, who)
	var v := WorldView.new(data["world"])
	var at := _thing_at(v, map, cell)
	var name := ""
	var paid := 0
	if not at.is_empty():
		var room := str(at["room"])
		var rec := _rec(data, room)
		var t: Dictionary = at["thing"]
		var others: Array = (rec["things"] as Array).filter(func(o: Dictionary) -> bool: return str(o["id"]) != str(t["id"]))
		PropertyRules.remove_upgrade(s, data, pid, t, room, others, who)
		rec["things"] = others
		_save(s, data, room, rec)
		var u: Dictionary = PropertyRules.ups(data).get(str(t["up"]), {})
		name = str(u.get("name", t["up"]))
		paid = int(u.get("price_cp", 0))
	else:
		var e := _edit_at(v, map, cell)
		var rec := _rec(data, str(e["room"]))
		(rec["cells"] as Dictionary).erase(str(e["key"]))
		_save(s, data, str(e["room"]), rec)
		var p: Dictionary = cfg(data)["parts"].get(str(e["edit"]["part"]), {})
		name = str(p.get("name", ""))
		paid = int(p.get("price_cp", 0))
	var back := Price.share(paid, float(cfg(data)["refund_pct"]))
	Ledger.add(s, back, "property:furnish", who)
	return ["%s: убрано — %s, назад %s" % [PropertyRules.name_of(s, data, pid), name.to_lower(), Money.format(back)]]
