class_name SightRules
extends RefCounted
## What is seen on a map (v0.8.3). A square is seen when nothing opaque stands in the way and it is in reach: in the light
## that is `sight.day` squares, in the dark as far as the hero's light or darkvision goes, by the SRD. What was seen once
## stays known in the save as rows of the map's grid, the rest is fog. The numbers are `rules.sight`.

const OCTANTS: Array[Array] = [[1, 0, 0, 1], [0, 1, 1, 0], [0, 1, -1, 0], [-1, 0, 0, 1], [-1, 0, 0, -1], [0, -1, -1, 0], [0, -1, 1, 0], [1, 0, 0, -1]]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["sight"]


static func opaque(lib: Dictionary, c: String) -> bool:
	return c == LayoutGen.BLANK or bool(lib["cells"].get(c, {}).get("opaque", false))


## Squares of darkvision the hero has, 0 — none.
static func dark_sight(s: GameSession, data: Dictionary) -> int:
	var c := s.character
	if CharacterRules.has_feature(c, "eldritch_invocation_devils_sight"):
		return int(cfg(data)["devils_sight"])
	if CharacterRules.has_trait(c, "darkvision") or CharacterRules.item_prop(c, "darkvision") or SpellEffects.has(c, "darkvision"):
		return int(cfg(data)["darkvision"])
	return 0


## Squares the hero's own light reaches, 0 — none: the Light spell or the best light source in the pack.
static func light(s: GameSession, data: Dictionary) -> int:
	var c := s.character
	var lights: Dictionary = cfg(data)["lights"]
	var best := int(lights["light"]) if SpellEffects.has(c, "light") else 0
	for id: String in c.get("inventory", {}):
		if (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("light_source"):
			best = maxi(best, int(lights.get(id, lights["light"])))
	return best


## The hero carries a light in the dark and needs it: it shows from afar.
static func lit(s: GameSession, data: Dictionary) -> bool:
	return TimeRules.unlit(s, data) and dark_sight(s, data) == 0 and light(s, data) > 0


## How many squares the hero sees here now.
static func reach(s: GameSession, data: Dictionary) -> int:
	if not TimeRules.unlit(s, data):
		return int(cfg(data)["obscured" if WeatherRules.passive(s, data) > 0 else "day"])
	return maxi(maxi(dark_sight(s, data), light(s, data)), int(cfg(data)["blind"]))


## The squares seen from `from` within `radius`, walls that close the view among them: shadow casting by eight octants.
static func view(map: Dictionary, lib: Dictionary, from: Vector2i, radius: int) -> Dictionary:
	var out: Dictionary = {from: true}
	for o: Array in OCTANTS:
		_cast(map, lib, from, radius, 1, 1.0, 0.0, o, out)
	return out


static func _cast(map: Dictionary, lib: Dictionary, from: Vector2i, radius: int, row: int, top: float, bottom: float, o: Array, out: Dictionary) -> void:
	if top < bottom:
		return
	var rows: Array[String] = map["rows"]
	var w := int(map["w"])
	var h := int(map["h"])
	var far := radius * radius + radius
	var blocked := false
	var start := top
	var next := top
	for j: int in range(row, radius + 1):
		if blocked:
			return
		var dy := -j
		for dx: int in range(-j, 1):
			var right := (dx + 0.5) / (dy - 0.5)
			var left := (dx - 0.5) / (dy + 0.5)
			if start < right:
				continue
			if bottom > left:
				break
			var x: int = from.x + dx * int(o[0]) + dy * int(o[1])
			var y: int = from.y + dx * int(o[2]) + dy * int(o[3])
			var inside := x >= 0 and y >= 0 and x < w and y < h
			if inside and dx * dx + dy * dy <= far:
				out[Vector2i(x, y)] = true
			var wall := not inside or opaque(lib, rows[y][x])
			if blocked:
				if wall:
					next = right
					continue
				blocked = false
				start = next
			elif wall and j < radius:
				blocked = true
				_cast(map, lib, from, radius, j + 1, start, left, o, out)
				next = right


## Nothing opaque between two squares: a straight line either way counts.
static func line(map: Dictionary, lib: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return _clear(map, lib, a, b) or _clear(map, lib, b, a)


static func _clear(map: Dictionary, lib: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var rows: Array[String] = map["rows"]
	var d := (b - a).abs()
	var step := (b - a).sign()
	var err := d.x - d.y
	var at := a
	while at != b:
		var twice := err * 2
		if twice > -d.y:
			err -= d.y
			at.x += step.x
		if twice < d.x:
			err += d.x
			at.y += step.y
		if at != b and opaque(lib, rows[at.y][at.x]):
			return false
	return true


## What the hero sees from `cell` now; it stays known.
static func look(s: GameSession, data: Dictionary, map: Dictionary, cell: Vector2i) -> Dictionary:
	var cells := view(map, data["layouts"], cell, reach(s, data))
	remember(s, map, cells)
	return cells


static func remember(s: GameSession, map: Dictionary, cells: Dictionary) -> void:
	var all: Dictionary = s.layouts.get_or_add("seen", {})
	var id := str(map["id"])
	var mem := _fit(all.get(id, {}), LayoutGen.on_grid(map, Vector2i.ZERO), int(map["w"]), int(map["h"]))
	all[id] = mem
	var rows: Array = mem["rows"]
	for cell: Vector2i in cells:
		var row: String = rows[cell.y]
		if row[cell.x] != "1":
			row[cell.x] = "1"
			rows[cell.y] = row


## The rows of a map's memory at its corner on the grid now: a map that grew keeps what was seen.
static func _fit(mem: Dictionary, corner: Vector2i, w: int, h: int) -> Dictionary:
	var old: Array = mem.get("rows", [])
	if int(mem.get("x", corner.x)) == corner.x and int(mem.get("y", corner.y)) == corner.y and old.size() == h and (old.is_empty() or str(old[0]).length() == w):
		if not old.is_empty():
			return mem
	var rows: Array = []
	for y: int in h:
		rows.append("0".repeat(w))
	var shift := Vector2i(int(mem.get("x", corner.x)), int(mem.get("y", corner.y))) - corner
	for y: int in old.size():
		var was: String = old[y]
		for x: int in was.length():
			var at := Vector2i(x, y) + shift
			if was[x] == "1" and at.x >= 0 and at.y >= 0 and at.x < w and at.y < h:
				var row: String = rows[at.y]
				row[at.x] = "1"
				rows[at.y] = row
	return {"x": corner.x, "y": corner.y, "rows": rows}


## The squares of this map the hero has seen.
static func known(s: GameSession, map: Dictionary) -> Dictionary:
	var mem: Dictionary = (s.layouts.get("seen", {}) as Dictionary).get(str(map["id"]), {})
	var out := {}
	if mem.is_empty():
		return out
	mem = _fit(mem, LayoutGen.on_grid(map, Vector2i.ZERO), int(map["w"]), int(map["h"]))
	var rows: Array = mem["rows"]
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == "1":
				out[Vector2i(x, y)] = true
	return out
