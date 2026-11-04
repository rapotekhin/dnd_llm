class_name SightRules
extends RefCounted
## What is seen on a map (v0.8.3). A square is seen when nothing opaque stands in the way and it is in reach: in the light
## that is `sight.day` squares, in the dark as far as the hero's light or darkvision goes, by the SRD. The map itself is
## open from the start (v0.8.4): the view says who stands in it and what is dimmed. The numbers are `rules.sight`.

const OCTANTS: Array[Array] = [[1, 0, 0, 1], [0, 1, 1, 0], [0, 1, -1, 0], [-1, 0, 0, 1], [-1, 0, 0, -1], [0, -1, -1, 0], [0, -1, 1, 0], [1, 0, 0, -1]]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["sight"]


static func opaque(lib: Dictionary, c: String) -> bool:
	return c == LayoutGen.BLANK or bool(lib["cells"].get(c, {}).get("opaque", false))


## Squares of darkvision of anybody (v0.8.4.12, ADR-0016), 0 — none: Devil's Sight, a race's or a template's darkvision,
## a thing worn or the spell; the longest of them.
static func dark_sight(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> int:
	if Sheet.has_trait(s, data, who, "eldritch_invocation_devils_sight"):
		return int(cfg(data)["devils_sight"])
	var own := int(Sheet.template(data, who).get("darkvision", 0)) / int(FightGrid.cfg(data)["ft"])
	var h := Sheet.holder(s, who)
	if Sheet.has_trait(s, data, who, "darkvision") or Sheet.prop(s, data, who, "darkvision") or _spell(h, "darkvision"):
		return maxi(own, int(cfg(data)["darkvision"]))
	return own


## Squares the light it carries reaches, 0 — none: a status's `light` (the Light spell — `true`, its squares by
## `rules.sight.lights`; a creature's own glow — a number of squares, v0.8.4.27.6) or the best light source on its belt
## (v0.8.4.24: one in the pack is not lit).
static func light(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> int:
	var lights: Dictionary = cfg(data)["lights"]
	var best := 0
	for e: Dictionary in ItemRules.born_effects(data, Sheet.holder(s, who)):
		if e.has("light"):
			best = maxi(best, int(lights["light"]) if e["light"] is bool else int(e["light"]))
	for id: String in ItemRules.belt(Sheet.things(s, data, who), data, s.items):
		if not id.is_empty() and (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("light_source"):
			best = maxi(best, int(lights.get(id, lights["light"])))
	return best


static func _spell(h: Dictionary, key: String) -> bool:
	return (h.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return e.has(key))


## It carries a light in the dark and needs it, or it glows by itself whatever it sees by (an azer, a magmin, v0.8.4.27.6):
## it shows from afar.
static func lit(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> bool:
	return TimeRules.unlit(s, data) and light(s, data, who) > 0 and (dark_sight(s, data, who) == 0 or glows(s, data, who))


## It glows by its own trait (a number of `light`), not by a thing or a spell it may put out.
static func glows(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> bool:
	return ItemRules.born_effects(data, Sheet.holder(s, who)).any(func(e: Dictionary) -> bool:
		return e.has("light") and not e["light"] is bool and str(e.get("source", {}).get("kind", "")) == ItemRules.BORN)


## Why it stands in the dark: no light of the place and none shown. "" — lit. A darkvision does not light anyone.
static func in_dark(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> String:
	return "темнота" if TimeRules.unlit(s, data) and not lit(s, data, who) else ""


## How many squares it sees here now: the day's view, else its darkvision or its light; blinded — only beside.
static func reach(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> int:
	if ConditionRules.has(Sheet.holder(s, who), "blinded"):
		return int(cfg(data)["blind"])
	if not TimeRules.unlit(s, data):
		return int(cfg(data)["obscured" if WeatherRules.passive(s, data) > 0 else "day"])
	return maxi(maxi(dark_sight(s, data, who), light(s, data, who)), int(cfg(data)["blind"]))


## The squares seen from `from` within `radius`, walls that close the view among them: shadow casting by eight octants.
## `round` — the hero's view: a `thin` cell (a tree) does not close it, a watcher's it does.
static func view(map: Dictionary, lib: Dictionary, from: Vector2i, radius: int, round: bool = false) -> Dictionary:
	var out: Dictionary = {from: true}
	for o: Array in OCTANTS:
		_cast(map, lib, from, radius, 1, 1.0, 0.0, o, out, round)
	return out


static func _cast(map: Dictionary, lib: Dictionary, from: Vector2i, radius: int, row: int, top: float, bottom: float, o: Array, out: Dictionary, round: bool) -> void:
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
			var wall := not inside or (opaque(lib, rows[y][x]) and not (round and bool(lib["cells"].get(rows[y][x], {}).get("thin", false))))
			if blocked:
				if wall:
					next = right
					continue
				blocked = false
				start = next
			elif wall and j < radius:
				blocked = true
				_cast(map, lib, from, radius, j + 1, start, left, o, out, round)
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


## What the hero sees from `cell` now. A Fog Cloud or Darkness of a fight closes the view like a wall, and from inside it
## nothing is seen past the next square.
static func look(s: GameSession, data: Dictionary, map: Dictionary, cell: Vector2i) -> Dictionary:
	var veil := _veils(s, data)
	if veil.is_empty():
		return view(map, data["layouts"], cell, reach(s, data), true)
	var shut := map.duplicate()
	var rows: Array[String] = []
	rows.assign((map["rows"] as Array).duplicate())
	for at: Vector2i in veil:
		if at.x >= 0 and at.y >= 0 and at.y < rows.size() and at.x < rows[at.y].length():
			rows[at.y][at.x] = LayoutGen.BLANK
	shut["rows"] = rows
	var far := int(cfg(data)["blind"]) if veil.has(cell) else reach(s, data)
	var out := view(shut, data["layouts"], cell, far, true)
	for at: Vector2i in veil:
		if WalkRules.distance(at, cell) > int(cfg(data)["blind"]):
			out.erase(at)
	return out


## The squares under a veil the hero does not see through.
static func _veils(s: GameSession, data: Dictionary) -> Dictionary:
	var out := {}
	if not CombatRules.active(s):
		return out
	for z: Dictionary in SpellEffects.zones(s):
		if bool(z.get("obscure", false)) and not FightGrid.pierces(s, data, CombatRules.player(s), z, 1):
			for at: Vector2i in FightGrid.zone_cells(s, data, z):
				out[at] = true
	return out
