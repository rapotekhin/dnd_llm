class_name FightGrid
extends RefCounted
## The field of a fight (v0.8.4): the map of the place on squares of 5 ft, a fighter stands on a square by `x`, `y` and
## takes `span` × `span` of them by its SRD size. A diagonal is a plain step. This class knows the geometry and only it:
## who stands where, how far, what a line crosses, what cover it gives, where a walk can go, what an area covers. What a
## step or a hit does is CombatRules; which door is shut and what burns is kept in `s.combat`, read here.
## A fight on no map (`s.combat["field"]` {w, h}) is an open square: tests and the balance of open fights.

const NONE := Vector2i(-1, -1)
const SOLID := 1
const OPAQUE := 2
const LOW := 4  ## stands in the way of a shot, not of the eye: half cover
const PIT := 8  ## no floor: a walker falls, a flyer passes
const WET := 16  ## water: a slow step, a flyer passes
const DOOR := 32
const FULL_COVER := 99
const FLAG_NAMES := {"solid": SOLID, "pit": PIT, "wet": WET, "low": LOW}
const CORNERS: Array[Vector2] = [Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]
const CIRCLE: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]

static var _key := ""
static var _grid: Dictionary = {}
static var _flow_key := ""
static var _flows: Dictionary = {}


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["combat"]["grid"]


static func squares_of(data: Dictionary, feet: int) -> int:
	return int(ceil(feet / float(cfg(data)["ft"]))) if feet > 0 else 0


## The squares a walk of `speed` ft covers. Speed 0 — grappled, restrained, exhaustion 5.
static func steps_of(data: Dictionary, speed: int) -> int:
	return maxi(0, speed) / int(cfg(data)["ft"])


static func span_of(data: Dictionary, size: String) -> int:
	return int(cfg(data)["spans"].get(size, 1))


# --- where a fighter stands ------------------------------------------------------------------------------------


static func cell(f: Dictionary) -> Vector2i:
	return Vector2i(int(f.get("x", 0)), int(f.get("y", 0)))


static func put(f: Dictionary, at: Vector2i) -> void:
	f["x"] = at.x
	f["y"] = at.y


static func body_at(at: Vector2i, span: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in span:
		for x: int in span:
			out.append(at + Vector2i(x, y))
	return out


static func body(f: Dictionary) -> Array[Vector2i]:
	return body_at(cell(f), int(f.get("span", 1)))


static func _gap(a: Vector2i, a_span: int, b: Vector2i, b_span: int) -> int:
	var dx := maxi(0, maxi(b.x - (a.x + a_span - 1), a.x - (b.x + b_span - 1)))
	var dy := maxi(0, maxi(b.y - (a.y + a_span - 1), a.y - (b.y + b_span - 1)))
	return maxi(dx, dy)


## Squares between the bodies of two fighters: side by side is 1, a diagonal counts as one.
static func dist(a: Dictionary, b: Dictionary) -> int:
	return _gap(cell(a), int(a.get("span", 1)), cell(b), int(b.get("span", 1)))


static func dist_to(f: Dictionary, at: Vector2i) -> int:
	return _gap(cell(f), int(f.get("span", 1)), at, 1)


static func feet(data: Dictionary, a: Dictionary, b: Dictionary) -> int:
	return dist(a, b) * int(cfg(data)["ft"])


## Side by side: 5 ft.
static func touching(a: Dictionary, b: Dictionary) -> bool:
	return dist(a, b) <= 1


## Where a target is aimed at: an invisible foe stands where it was last seen until it strikes.
static func shown(f: Dictionary) -> Vector2i:
	if (f.get("conditions", []) as Array).has("invisible") and f.has("seen_x"):
		return Vector2i(int(f["seen_x"]), int(f["seen_y"]))
	return cell(f)


static func shown_dist(a: Dictionary, f: Dictionary) -> int:
	return _gap(cell(a), int(a.get("span", 1)), shown(f), int(f.get("span", 1)))


static func keep_seen(f: Dictionary) -> void:
	f["seen_x"] = int(f.get("x", 0))
	f["seen_y"] = int(f.get("y", 0))


static func tag(at: Vector2i) -> String:
	return "%d,%d" % [at.x, at.y]


## An aim at a square travels as a target id: "@x,y".
static func aim_id(at: Vector2i) -> String:
	return "@" + tag(at)


static func is_aim(target: String) -> bool:
	return target.begins_with("@")


static func aim_of(target: String) -> Vector2i:
	var t := target.trim_prefix("@")
	return Vector2i(int(t.get_slice(",", 0)), int(t.get_slice(",", 1)))


# --- the grid --------------------------------------------------------------------------------------------------


## The map of the fight: the whole floor, doors and rooms the hero has not seen too; those who heard come from there.
static func map(s: GameSession, data: Dictionary) -> Dictionary:
	return grid(s, data)["map"]


static func grid(s: GameSession, data: Dictionary) -> Dictionary:
	var key := "%d|%s|%s|%d|%s" % [s.get_instance_id(), str(s.combat.get("map", "")), str(s.combat.get("field", "")), int(s.combat.get("rev", 0)), str(s.layouts.get("rev", ""))]
	if key != _key or _grid.is_empty():
		_grid = _build(s, data)
		_key = key
	return _grid


static func changed(s: GameSession) -> void:
	s.combat["rev"] = int(s.combat.get("rev", 0)) + 1


static func _open_map(field: Dictionary) -> Dictionary:
	var w := int(field["w"])
	var h := int(field["h"])
	var rows: Array[String] = []
	for y: int in h:
		rows.append(".".repeat(w))
	return {"id": "field", "w": w, "h": h, "rows": rows, "ids": ["field"], "exits": [], "doors": [], "marks": []}


static func _build(s: GameSession, data: Dictionary) -> Dictionary:
	var field: Dictionary = s.combat.get("field", {})
	var m: Dictionary = _open_map(field) if not field.is_empty() else LayoutRules.map_of(s, data, str(s.combat.get("map", s.room_id)))
	var lib: Dictionary = data["layouts"]
	var w := int(m["w"])
	var h := int(m["h"])
	var flags := PackedByteArray()
	var cost := PackedByteArray()
	flags.resize(w * h)
	cost.resize(w * h)
	var kinds := {}
	var rows: Array = m["rows"]
	for y: int in h:
		var row: String = rows[y]
		for x: int in w:
			var c := row[x]
			if not kinds.has(c):
				kinds[c] = _kind(lib, c)
			var k: Array = kinds[c]
			flags[y * w + x] = int(k[0])
			cost[y * w + x] = int(k[1])
	for key: String in s.combat.get("doors", {}):
		var d: Dictionary = s.combat["doors"][key]
		var at := y_x(key)
		if at.x >= 0 and at.y >= 0 and at.x < w and at.y < h:
			var i := at.y * w + at.x
			if bool(d.get("open", false)):
				flags[i] = flags[i] & ~OPAQUE
			if bool(d.get("gone", false)):
				flags[i] = flags[i] & ~(OPAQUE | DOOR)
	for key: String in s.combat.get("cleared", {}):  # a thing of the map that was moved or smashed
		var at := y_x(key)
		if at.x >= 0 and at.y >= 0 and at.x < w and at.y < h:
			flags[at.y * w + at.x] = flags[at.y * w + at.x] & ~(SOLID | LOW | OPAQUE)
			cost[at.y * w + at.x] = 1
	for key: String in s.combat.get("blocks", {}):  # things of the field: pushed about, of the room by their bodies
		var at := y_x(key)
		if at.x >= 0 and at.y >= 0 and at.x < w and at.y < h:
			flags[at.y * w + at.x] = flags[at.y * w + at.x] | int(s.combat["blocks"][key].get("flags", SOLID | LOW))
	return {"map": m, "w": w, "h": h, "flags": flags, "cost": cost}


static func y_x(key: String) -> Vector2i:
	return Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))


## [flags, cost] of a kind of cell by `layouts.json`.
static func _kind(lib: Dictionary, c: String) -> Array:
	var d: Dictionary = lib["cells"].get(c, {})
	var bits := 0
	if bool(d.get("solid", false)):
		bits |= SOLID
	if bool(d.get("opaque", false)):
		bits |= OPAQUE
	match str(d.get("name", "")):
		"block":
			bits |= LOW
		"pit":
			bits = (bits | PIT) & ~SOLID
		"water":
			bits |= WET
		"door":
			bits |= DOOR
	if c == LayoutGen.BLANK:
		bits |= SOLID | OPAQUE
	return [bits, int(d.get("cost", 1))]


static func flags_at(g: Dictionary, at: Vector2i) -> int:
	if at.x < 0 or at.y < 0 or at.x >= int(g["w"]) or at.y >= int(g["h"]):
		return SOLID | OPAQUE
	return (g["flags"] as PackedByteArray)[at.y * int(g["w"]) + at.x]


static func walkable(g: Dictionary, at: Vector2i) -> bool:
	return flags_at(g, at) & (SOLID | PIT) == 0


static func door_state(s: GameSession, at: Vector2i) -> Dictionary:
	return (s.combat.get("doors", {}) as Dictionary).get(tag(at), {})


## A door nobody opened is shut. A beast does not work a latch.
static func shut(s: GameSession, g: Dictionary, at: Vector2i) -> bool:
	if flags_at(g, at) & DOOR == 0:
		return false
	var d := door_state(s, at)
	return not bool(d.get("open", false)) and not bool(d.get("gone", false))


static func fast(s: GameSession, g: Dictionary, at: Vector2i) -> bool:  # barred or locked: no way through until broken
	var d := door_state(s, at)
	return shut(s, g, at) and (bool(d.get("barred", false)) or bool(d.get("locked", false)))


## Everyone in the fight who stands: {square: side}; with `data` — but those who share a square (`shares`).
static func bodies(s: GameSession, except: String = "", data: Dictionary = {}) -> Dictionary:
	var out := {}
	for id: String in s.combat.get("fighters", []):
		var f: Dictionary = s.beings.get(id, {}).get("fight", {})
		if id == except or f.is_empty() or str(f.get("status", "active")) != "active" or not data.is_empty() and shares(s, data, f):
			continue
		for at: Vector2i in body(f):
			out[at] = str(f.get("side"))
	for c: Dictionary in s.combat.get("crowd", []):  # those who watch a bout (v0.8.4.5)
		out[Vector2i(int(c["x"]), int(c["y"]))] = "crowd"
	return out


## It shares a square (v0.8.4.27.1, the 5e swarm): a status with `share` — its square holds no one for another, and none for it.
static func shares(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return ConditionRules.does(Sheet.holder(s, f), data, "share")


## The bodies that stop `f`'s walk and where it may end: none for one that shares a square, else all but those that share.
static func in_way(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	return {} if shares(s, data, f) else bodies(s, str(f.get("id", "")), data)


static func side_of(side: String) -> String:
	return "friend" if side in ["player", "ally"] else "foe"


# --- lines -----------------------------------------------------------------------------------------------------


## Bresenham: free of what stops the eye, the ends do not count.
static func _ray(g: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var d := (b - a).abs()
	var step := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x - d.y
	var at := a
	while at != b:
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			at.x += step.x
		if e2 < d.x:
			err += d.x
			at.y += step.y
		if at != b and flags_at(g, at) & OPAQUE != 0:
			return false
	return true


static func clear(g: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return _ray(g, a, b) or _ray(g, b, a)


## The bodies' squares nearest to each other: from them the line and the cover are read.
static func _facing(a: Dictionary, b: Dictionary) -> Array[Vector2i]:
	var best: Array[Vector2i] = [cell(a), cell(b)]
	var length := 1 << 30
	for x: Vector2i in body(a):
		for y: Vector2i in body(b):
			var d := WalkRules.distance(x, y)
			if d < length:
				length = d
				best = [x, y]
	return best


static func sees(s: GameSession, data: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var ends := _facing(a, b)
	return clear(grid(s, data), ends[0], ends[1]) and veiled(s, data, a, b).is_empty()


## What `f` senses without its eyes, in squares: "blindsight", "truesight", "devils_sight" (v0.8.4.1).
static func senses(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var out := {}
	if CharacterRules.has_feature(Sheet.holder(s, f), "eldritch_invocation_devils_sight"):
		out["devils_sight"] = int(SightRules.cfg(data)["devils_sight"])
	if str(f.get("id")) == "p":
		return out
	var m := Sheet.template(data, f)
	for sense: String in ["blindsight", "truesight"]:
		if int(m.get(sense, 0)) > 0:
			out[sense] = squares_of(data, int(m[sense]))
	if MonsterRules.has_trait(data, f, "devils_sight"):
		out["devils_sight"] = int(SightRules.cfg(data)["devils_sight"])
	return out


static func blind(s: GameSession, f: Dictionary) -> bool:
	return ConditionRules.has(s.character, "blinded") if str(f.get("id")) == "p" else CombatRules._has(f, "blinded")


## `a` senses through this zone from `far` squares: Devil's Sight and truesight through Darkness, blindsight through any (`rules.sight.pierce`).
static func pierces(s: GameSession, data: Dictionary, a: Dictionary, z: Dictionary, far: int) -> bool:
	var sense := senses(s, data, a)
	return (SightRules.cfg(data)["pierce"].get(str(z.get("veil", "fog")), []) as Array).any(func(k: Variant) -> bool: return int(sense.get(str(k), -1)) >= far)


## Why `a` does not see `b` whatever the walls: blind, or a veil on the line, from inside it too. "" — sees.
static func veiled(s: GameSession, data: Dictionary, a: Dictionary, b: Dictionary) -> String:
	var far := dist(a, b)
	if ConditionRules.does(Sheet.holder(s, a), data, "averts") and ItemRules.born(data, Sheet.holder(s, b), "gaze"):
		return "отводит взгляд"  # a basilisk's gaze (v0.8.4.27.6): it does not see the one it looks away from
	if blind(s, a):
		if int(senses(s, data, a).get("blindsight", -1)) < far:
			return "ослеплён"
	for z: Dictionary in SpellEffects.zones(s):
		if not bool(z.get("obscure", false)) or pierces(s, data, a, z, far):
			continue
		var cells := zone_cells(s, data, z)
		var ends := _facing(a, b)
		if cells.has(ends[0]) or line_of(ends[0], ends[1]).any(func(c: Vector2i) -> bool: return cells.has(c)):
			return str(z["name"])
	return ""


## One the hero does not see but hears: unless it hides, its place is known (5e), a foe behind a wall is not.
static func heard(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	var ends := _facing(CombatRules.player(s), f)
	return not bool(f.get("hidden", false)) and not veiled(s, data, CombatRules.player(s), f).is_empty() and clear(grid(s, data), ends[0], ends[1])


## Reaches with a blade: beside it, not across a corner of two walls.
static func can_touch(s: GameSession, data: Dictionary, a: Dictionary, b: Dictionary, reach: int = 1) -> bool:
	if dist(a, b) > reach:
		return false
	var ends := _facing(a, b)
	var d := ends[1] - ends[0]
	if absi(d.x) == 1 and absi(d.y) == 1:
		var g := grid(s, data)
		return flags_at(g, ends[0] + Vector2i(d.x, 0)) & SOLID == 0 or flags_at(g, ends[0] + Vector2i(0, d.y)) & SOLID == 0
	return dist(a, b) <= 1 or clear(grid(s, data), ends[0], ends[1])


## The cover of `t` from `a` by 5e: four lines from the shooter to the corners of the target's square. All stopped — full,
## three — three quarters, one or two, or something low or someone in the way — half. The bonus to AC and Dexterity saves.
static func cover(s: GameSession, data: Dictionary, a: Dictionary, t: Dictionary) -> int:
	var ends := _facing(a, t)
	return cover_at(s, data, ends[0], ends[1], [str(a.get("id", "")), str(t.get("id", ""))])


static func cover_at(s: GameSession, data: Dictionary, from: Vector2i, to: Vector2i, skip: Array = []) -> int:
	if WalkRules.distance(from, to) <= 1:
		return 0
	var g := grid(s, data)
	var occupied := {}
	for id: String in s.combat.get("fighters", []):
		var f: Dictionary = s.beings.get(id, {}).get("fight", {})
		if not f.is_empty() and str(f.get("status", "active")) == "active" and not skip.has(id):
			for at: Vector2i in body(f):
				occupied[at] = true
	var mid := Vector2(from) + Vector2(0.5, 0.5)
	var hard := 0
	var soft := false
	for corner: Vector2 in CORNERS:
		var r := _trace(g, occupied, mid, Vector2(to) + corner, from, to)
		if r == 2:
			hard += 1
		elif r == 1:
			soft = true
	var c: Dictionary = cfg(data)["cover"]
	if hard >= 4:
		return FULL_COVER
	if hard == 3:
		return int(c["three_quarters"])
	return int(c["half"]) if hard > 0 or soft else 0


## 2 — the line is stopped, 1 — it passes something low or someone, 0 — free.
static func _trace(g: Dictionary, occupied: Dictionary, a: Vector2, b: Vector2, from: Vector2i, to: Vector2i) -> int:
	var length := a.distance_to(b)
	var n := int(ceil(length * 2.0))
	var was := NONE
	var out := 0
	for i: int in range(1, n):
		var at := Vector2i((a + (b - a) * (float(i) / n)).floor())
		if at == was or at == from or at == to:
			continue
		was = at
		var bits := flags_at(g, at)
		if bits & OPAQUE != 0:
			return 2
		if bits & LOW != 0 or occupied.has(at):
			out = 1
	return out


# --- walking ---------------------------------------------------------------------------------------------------


## The flags of a list of names: a row of `rules.combat.moves` says what it crosses by name.
static func mask(names: Array) -> int:
	var out := 0
	for n: String in names:
		out |= int(FLAG_NAMES[n])
	return out


static func _body_free(g: Dictionary, at: Vector2i, span: int, passes: int) -> bool:
	for c: Vector2i in body_at(at, span):
		var bits := flags_at(g, c)
		if bits & SOLID != 0 or (bits & PIT != 0 and passes & PIT == 0):
			return false
	return true


## The squares a fighter can walk to with `budget` squares: {square: [cost, from]}, its own square at cost 0. A friend is
## passed through, a foe is not unless `passable` (sizes apart, `opts.larger_by`); a square to stop on holds no one. A diagonal does not cut a corner. A wide body fits a
## passage one size narrower by squeezing (5e): each such square costs one more. `opts` is Move.opts: passes (flags it crosses),
## flat (every square costs one), on (flags whose squares cost one), only (flags it cannot leave), fear (a square not to come
## nearer to), latch (false — a beast at a shut door).
static func reach(s: GameSession, data: Dictionary, f: Dictionary, budget: int, opts: Dictionary = {}) -> Dictionary:
	var g := grid(s, data)
	var from := cell(f)
	var span := int(f.get("span", 1))
	var passes := int(opts.get("passes", 0))
	var flat := bool(opts.get("flat", false))
	var flat_on := int(opts.get("on", 0))
	var only := int(opts.get("only", 0))
	var mine := side_of(str(f.get("side", "enemy")))
	var occupied := in_way(s, data, f)
	var across := passable(s, data, f, int(opts.get("larger_by", 2)))
	var slow := slow_cells(s, data, f)
	var fear: Vector2i = opts.get("fear", NONE)
	var latch := bool(opts.get("latch", true))
	var cost: PackedByteArray = g["cost"]
	var w := int(g["w"])
	var out: Dictionary = {from: [0, from]}
	var buckets: Array = [[from]]
	var at_cost := 0
	while at_cost < buckets.size():
		var bucket: Array = buckets[at_cost]
		var i := 0
		while i < bucket.size():
			var at: Vector2i = bucket[i]
			i += 1
			if int(out[at][0]) != at_cost:
				continue
			for d: Vector2i in WalkRules.DIRS:
				var next := at + d
				var extra := 0
				if not _body_free(g, next, span, passes):
					if span < 2 or not _body_free(g, next, span - 1, passes):
						continue
					extra = 1
				var bits := flags_at(g, next)
				if only != 0 and bits & only == 0:
					continue
				if d.x != 0 and d.y != 0 and (flags_at(g, at + Vector2i(d.x, 0)) & SOLID != 0 or flags_at(g, at + Vector2i(0, d.y)) & SOLID != 0):
					continue
				if not latch and shut(s, g, next) or fast(s, g, next):
					continue
				var stop := false
				for c: Vector2i in body_at(next, span):
					if occupied.has(c):
						if side_of(str(occupied[c])) != mine and not across.has(c):
							stop = true
							break
				if stop:
					continue
				if fear.x >= 0 and WalkRules.distance(next, fear) < WalkRules.distance(at, fear):
					continue
				var step := extra + (1 if flat or bits & flat_on != 0 else int(cost[next.y * w + next.x]))
				if not flat and slow.has(next):
					step += 1
				var total := at_cost + step
				if total > budget or (out.has(next) and int(out[next][0]) <= total):
					continue
				out[next] = [total, at]
				while buckets.size() <= total:
					buckets.append([])
				(buckets[total] as Array).append(next)
		at_cost += 1
	return out


## The squares of foes `f` may walk through (5e): a body two sizes apart from its own (`rules.combat.grid.pass_foe.sizes`),
## or larger by `larger_by` (Halfling Nimbleness: one).
static func passable(s: GameSession, data: Dictionary, f: Dictionary, larger_by: int) -> Dictionary:
	var out := {}
	var order: Array = (cfg(data)["spans"] as Dictionary).keys()
	var apart := int(cfg(data).get("pass_foe", {}).get("sizes", 2))
	var mine := order.find(Sheet.size(s, data, f))
	for id: String in s.combat.get("fighters", []):
		var o: Dictionary = s.beings.get(id, {}).get("fight", {})
		if o.is_empty() or side_of(str(o.get("side"))) == side_of(str(f.get("side", "enemy"))):
			continue
		var d := order.find(Sheet.size(s, data, o)) - mine
		if absi(d) >= apart or d >= larger_by:
			for at: Vector2i in body(o):
				out[at] = true
	return out


## Where a walk may end: the squares of `reach` that nobody stands on (`in_way`: a swarm's square is free, a swarm stops anywhere).
static func stops(s: GameSession, data: Dictionary, f: Dictionary, routes: Dictionary) -> Array[Vector2i]:
	var occupied := in_way(s, data, f)
	var out: Array[Vector2i] = []
	var span := int(f.get("span", 1))
	for at: Vector2i in routes:
		var free := true
		for c: Vector2i in body_at(at, span):
			if occupied.has(c):
				free = false
				break
		if free:
			out.append(at)
	return out


## The steps to `to` in a `reach` result; `from` is not in it.
static func route(routes: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not routes.has(to):
		return out
	var at := to
	while int(routes[at][0]) > 0:
		out.push_front(at)
		at = routes[at][1]
	return out


## Walking distance to `to` from every square, walls and doors counted, others' bodies not: how far a square really is for
## one who wants to get there. Kept for the round: the foes of a turn ask for the same hero.
static func flow(s: GameSession, data: Dictionary, to: Vector2i, passes: int = 0) -> Dictionary:
	var key := "%d|%d|%s" % [s.get_instance_id(), int(s.combat.get("rev", 0)), str(s.combat.get("map", ""))]
	if key != _flow_key:
		_flow_key = key
		_flows = {}
	var ask := "%s|%d" % [tag(to), passes]
	if _flows.has(ask):
		return _flows[ask]
	var g := grid(s, data)
	var out: Dictionary = {to: 0}
	var queue: Array[Vector2i] = [to]
	var head := 0
	var most := int(data["rules"]["combat"]["ai"]["flow"])
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		var n := int(out[at]) + 1
		if n > most:
			break
		for d: Vector2i in WalkRules.DIRS:
			var next := at + d
			if out.has(next):
				continue
			var bits := flags_at(g, next)
			if bits & SOLID != 0 or (bits & PIT != 0 and passes & PIT == 0):
				continue
			out[next] = n
			queue.append(next)
	_flows[ask] = out
	return out


## The nearest free square to `at`, for a body of `span`.
static func free_near(s: GameSession, data: Dictionary, spot: Vector2i, span: int = 1, room: String = "") -> Vector2i:
	var g := grid(s, data)
	var occupied := bodies(s)
	var at := _open_near(g, spot)
	var seen := {at: true}
	var queue: Array[Vector2i] = [at]
	var head := 0
	var m: Dictionary = g["map"]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if _body_free(g, c, span, 0) and (room.is_empty() or WalkRules.room_of(m, c) in [room, ""]):
			var ok := true
			for b: Vector2i in body_at(c, span):
				if occupied.has(b):
					ok = false
			if ok:
				return c
		for d: Vector2i in WalkRules.DIRS:
			var next := c + d
			if not seen.has(next) and flags_at(g, next) & SOLID == 0 and next.x >= 0 and next.y >= 0 and next.x < int(g["w"]) and next.y < int(g["h"]):
				seen[next] = true
				queue.append(next)
	return at


## The nearest square on the map that is not solid: `spot` may be in a wall or off the map.
static func _open_near(g: Dictionary, spot: Vector2i) -> Vector2i:
	var at := spot.clamp(Vector2i.ZERO, Vector2i(int(g["w"]) - 1, int(g["h"]) - 1))
	var seen := {at: true}
	var queue: Array[Vector2i] = [at]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if flags_at(g, c) & SOLID == 0:
			return c
		for d: Vector2i in WalkRules.DIRS:
			var next := c + d
			if not seen.has(next) and next.x >= 0 and next.y >= 0 and next.x < int(g["w"]) and next.y < int(g["h"]):
				seen[next] = true
				queue.append(next)
	return at


## A free square `far` steps of walking from `at`, on the side of `d`: one who has no place on the map always has a way
## to the hero. A square of `room` first.
static func walked_off(s: GameSession, data: Dictionary, at: Vector2i, d: Vector2i, far: int, span: int, room: String = "") -> Vector2i:
	var g := grid(s, data)
	var m: Dictionary = g["map"]
	var ways := flow(s, data, at)
	var occupied := bodies(s)
	var aim := at + d * far
	var best := NONE
	var rank := 1 << 40
	for c: Vector2i in ways:
		if not _body_free(g, c, span, 0) or body_at(c, span).any(func(b: Vector2i) -> bool: return occupied.has(b)):
			continue
		var other := not room.is_empty() and not WalkRules.room_of(m, c) in [room, ""]
		var r := (1 << 30 if other else 0) + absi(int(ways[c]) - far) * 1024 + WalkRules.distance(c, aim)
		if r < rank:
			rank = r
			best = c
	return best if best != NONE else free_near(s, data, at, span, room)


## The ways out of the map from where the hero is.
static func exits(s: GameSession, data: Dictionary) -> Array:
	return (map(s, data).get("exits", []) as Array).filter(func(e: Dictionary) -> bool:
		return WayRules.open_exits(s, data["world"], str(e["room"])).has(str(e["to"])))


## The square a newcomer comes in by: the way into the place farthest from the hero on the named side.
static func way_in(s: GameSession, data: Dictionary, side: String) -> Vector2i:
	var m := map(s, data)
	var hero := cell(s.beings.get("p", {}).get("fight", {}))
	var best := NONE
	var score := -INF
	for e: Dictionary in m.get("exits", []):
		var at := Vector2i(int(e["ax"]), int(e["ay"]))
		var gain := float((at.x - hero.x) * (-1 if side == "left" else 1) * 2 + WalkRules.distance(at, hero))
		if gain > score:
			score = gain
			best = at
	if best.x >= 0:
		return best
	var g := grid(s, data)
	return free_near(s, data, Vector2i(clampi(hero.x + (-1 if side == "left" else 1) * int(cfg(data)["start"]["arrival"]), 0, int(g["w"]) - 1), hero.y))


# --- areas -----------------------------------------------------------------------------------------------------


## The squares a shape covers. `area` {type, size ft}; `from` — the caster's square, `aim` — the point of origin for what is
## cast at a range, the direction for what starts at the caster. A wall stops it, it does not turn corners. SRD shapes:
## a sphere of 20 ft — radius 4, a cone of 15 ft is as wide as it is far, a line of 100 × 5 ft, a cube of 15 ft — 3 × 3.
static func area(s: GameSession, data: Dictionary, shape: Dictionary, from: Vector2i, aim: Vector2i, from_self: bool) -> Array[Vector2i]:
	var g := grid(s, data)
	var type := str(shape.get("type", "sphere"))
	var n := maxi(1, squares_of(data, int(shape.get("size", shape.get("ft", 5)))))
	var out: Array[Vector2i] = []
	match type:
		"line":
			var dir := (Vector2(aim - from)).normalized() if aim != from else Vector2.RIGHT
			var was := from
			for i: int in range(1, n * 2 + 1):
				var at := Vector2i((Vector2(from) + Vector2(0.5, 0.5) + dir * (i * 0.5)).floor())
				if WalkRules.distance(at, from) > n:
					break
				if at == was:
					continue
				if flags_at(g, at) & SOLID != 0 and flags_at(g, at) & LOW == 0:
					break
				was = at
				out.append(at)
		"cone":
			var dir := (Vector2(aim - from)).normalized() if aim != from else Vector2.RIGHT
			for y: int in range(from.y - n, from.y + n + 1):
				for x: int in range(from.x - n, from.x + n + 1):
					var at := Vector2i(x, y)
					var d := Vector2(at - from)
					var along := d.dot(dir)
					if at == from or along <= 0.0 or along > n + 0.5 or absf(d.cross(dir)) > (along + 1.0) / 2.0:
						continue
					if _reached(g, from, at):
						out.append(at)
		"wall":  # across the line from the caster to the aim, on the aim
			var across := Vector2(aim - from).normalized().orthogonal() if aim != from else Vector2.UP
			for i: int in range(-n, n + 1):
				var at := Vector2i((Vector2(aim) + Vector2(0.5, 0.5) + across * (i * 0.5)).floor())
				if not out.has(at) and flags_at(g, at) & SOLID == 0:
					out.append(at)
		"cube":
			var corner := aim - Vector2i(n / 2, n / 2)
			if from_self:  # the cube's face touches the caster, on the side of the aim
				var dir := (aim - from).sign()
				if dir == Vector2i.ZERO:
					dir = Vector2i.RIGHT
				corner = from + dir * (n / 2 + 1) - Vector2i(n / 2, n / 2)
			for y: int in range(corner.y, corner.y + n):
				for x: int in range(corner.x, corner.x + n):
					var at := Vector2i(x, y)
					if _reached(g, from if from_self else aim, at):
						out.append(at)
		_:  # a sphere or a cylinder, on the square of the aim
			var center := from if from_self else aim
			var r := n + 0.5
			for y: int in range(center.y - n, center.y + n + 1):
				for x: int in range(center.x - n, center.x + n + 1):
					var at := Vector2i(x, y)
					if Vector2(at - center).length() <= r and _reached(g, center, at):
						out.append(at)
	return out


static func _reached(g: Dictionary, origin: Vector2i, at: Vector2i) -> bool:
	if flags_at(g, at) & SOLID != 0 and flags_at(g, at) & LOW == 0:
		return false
	return origin == at or clear(g, origin, at)


static func in_cells(f: Dictionary, cells: Array[Vector2i]) -> bool:
	for at: Vector2i in body(f):
		if cells.has(at):
			return true
	return false


# --- zones on squares ------------------------------------------------------------------------------------------


## The squares of a zone now. A zone that follows the hero is drawn around the hero; the rest are kept as "x,y".
static func zone_cells(s: GameSession, data: Dictionary, z: Dictionary) -> Array[Vector2i]:
	if bool(z.get("follow", false)):
		var p: Dictionary = s.beings.get(str(z.get("by", "p")), {}).get("fight", {})
		return area(s, data, z["shape"], cell(p), cell(p), true)
	var out: Array[Vector2i] = []
	for key: Variant in z.get("cells", []):
		out.append(y_x(str(key)))
	return out


static func pack_cells(cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for at: Vector2i in cells:
		out.append(tag(at))
	return out


## Squares that slow `f`: a zone that says so; the caster's friends pass where it spares them, a web walker its webs.
static func slow_cells(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var out := {}
	for z: Dictionary in s.combat.get("zones", []):
		if bool(z.get("slow", false)) and not (bool(z.get("spares_friends", false)) and side_of(str(f.get("side", "enemy"))) == "friend") \
				and not FightField.passes(s, data, f, z):
			for at: Vector2i in zone_cells(s, data, z):
				out[at] = true
	return out


## The squares of the line from `a` to `b`, without `a`.
static func line_of(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
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
		out.append(at)
	return out


## The line between two squares crosses one of `cells`.
static func crosses(a: Vector2i, b: Vector2i, cells: Array[Vector2i]) -> bool:
	var d := (b - a).abs()
	var step := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x - d.y
	var at := a
	while at != b:
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			at.x += step.x
		if e2 < d.x:
			err += d.x
			at.y += step.y
		if at != b and cells.has(at):
			return true
	return false
