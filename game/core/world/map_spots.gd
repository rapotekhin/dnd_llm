class_name MapSpots
extends RefCounted
## Who and what stands where on the map of the room (v0.8.2). A person stands by its role at a mark of the room, else on a
## square of its own for this part of the day; a thing lies where the master said («у очага») or on a square of its own.
## Nothing here is kept except a move by the master's words: the rest follows from the seed, so a save holds no squares
## of people. People do not block the way. The master never sees squares: `words` and `near_word` speak for them.
## v0.8.3: foes before a fight stand away from the ways in (`foes`), a trap and a cache lie on a square (`secret_cell`).
## v0.8.4.43.23: a thing with a body (rules.things.bodies) takes the squares of its `size`, turned as the seed says, and a
## station of a mark stands as its thing (`rules.map.station_bodies`); `walls` — what the squares of things bar, for the
## walk, the eye and the fight.
## v0.8.4.43.26: the spots of a chunk (marks `spot:<group>`, `layouts.json` → `spots`) get the room's own things by the
## seed — a share of them filled with a body of the group, each with its companions (`near`); a mark of a station stands
## as its thing on every square of it; the spots left free are the master's, its furniture with a body stands there.

const SPOT := "spot:"  ## a mark of a chunk where a thing of a group may stand (v0.8.4.43.26)
const PATH := 1  ## a square of a thing bars the way
const SIGHT := 2  ## and the eye


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["map"]


## The tokens of the room now: {"ref", "kind", "id", "name", "mark", "portrait", "x", "y", "attitude"} — `portrait` the face
## of a person, a creature or a foe (PortraitRules, "" — the letter). Those who walk with the hero are not here: they stand
## by the hero.
static func of(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	return _of(s, data, map)["tokens"]


## The spots of the room no thing stands on (v0.8.4.43.26): [{"group", "at"}], for the master and its furniture.
static func free_spots(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	return _of(s, data, WalkRules.view(s, data))["free"]


## {"tokens": the tokens of `of`, "free": the spots left free}.
static func _of(s: GameSession, data: Dictionary, map: Dictionary) -> Dictionary:
	var lib: Dictionary = data["layouts"]
	var cells := _cells(map, lib, s.room_id)
	var out: Array[Dictionary] = []
	var free: Array[Dictionary] = []
	if cells.is_empty():
		return {"tokens": out, "free": free}
	var taken := {}
	for e: Dictionary in map["exits"]:
		taken[Vector2i(int(e["ax"]), int(e["ay"]))] = true
	var index := (map["ids"] as Array).find(s.room_id)
	var stations: Array = cfg(data)["stations"]
	var seen := {}
	var spots := _clear(map, lib, cells)  # nobody and nothing stands in a doorway: a click there opens the door (v0.8.4.42.1)
	var walls := {}  # the squares of things that bar the way (a fight makes them blocks, FightField)
	var ways := _ways_in(map, s.room_id)
	var bodies: Dictionary = cfg(data).get("station_bodies", {})
	var room_key := "%d|%s" % [s.game_seed, s.room_id]
	for m: Dictionary in map["marks"]:
		var mark := str(m["name"])
		var at := Vector2i(int(m["x"]), int(m["y"]))
		if int(m["room"]) != index or taken.has(at):
			continue
		var station := stations.has(mark) and not seen.has(mark)
		var body_id := str(bodies.get(mark, ""))
		if not station and body_id.is_empty():
			continue
		var t := _token("station:" + mark, "station", mark, _word(data, mark), at) if station \
			else _token("thing:%d,%d" % [at.x, at.y], "thing", "%d,%d" % [at.x, at.y], _body_name(data, body_id), at)
		if not station:
			t["still"] = true
		seen[mark] = true
		if not body_id.is_empty():  # the mark's square is its thing's: the rest of it where it fits round the mark, along it
			var want := {}
			for o: Dictionary in map["marks"]:
				if str(o["name"]) == mark and int(o["room"]) == index:
					want[Vector2i(int(o["x"]), int(o["y"]))] = true
			var around: Array[Vector2i] = spots.duplicate()
			if not around.has(at):
				around.append(at)
			_with_body(data, t, body_id, _lay(data, body_id, "%s|%s|%d,%d" % [room_key, mark, at.x, at.y], at, around, cells, ways, walls, taken, true, want), walls)
		for c: Vector2i in t.get("cells", [at]):
			taken[c] = true
		out.append(t)
		if not body_id.is_empty():
			_companions(data, t, room_key, spots, cells, ways, walls, taken, out)
	_furnished(data, map, index, room_key, spots, cells, ways, walls, taken, out)
	var keys := LayoutGen.ground_keys(lib, map)
	for sp: Dictionary in spot_marks(map, index):  # the room's own things on its spots, by the seed
		var at: Vector2i = sp["at"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|spot|%d,%d" % [room_key, at.x, at.y])
		var group: Dictionary = (lib.get("spots", {}).get("groups", {}) as Dictionary).get(str(sp["group"]), {})
		if taken.has(at) or rng.randf() >= float(group.get("fill", 0.5)):
			free.append(sp)
			continue
		var body_id := _pick(_weights(group.get("bodies", {}), keys), rng)
		var laid := _lay(data, body_id, "%s|%d,%d" % [room_key, at.x, at.y], at, spots, cells, ways, walls, taken, true) if not body_id.is_empty() else {"loose": true}
		if bool(laid.get("loose", false)):
			free.append(sp)
			continue
		var t := _token("thing:%d,%d" % [at.x, at.y], "thing", "%d,%d" % [at.x, at.y], _body_name(data, body_id), at)
		t["still"] = true
		t["spot"] = str(sp["group"])
		_with_body(data, t, body_id, laid, walls)
		for c: Vector2i in t["cells"]:
			taken[c] = true
		out.append(t)
		_companions(data, t, room_key, spots, cells, ways, walls, taken, out)
	var world := WorldView.new(data["world"])
	var followers := Being.followers(s)
	var part := TimeRules.part_name(s, data)
	for id: String in _sorted(s.npcs_here(data["world"], s.room_id)):
		if followers.has(id):
			continue
		var at := _npc_cell(s, data, map, s.room_id, spots, taken, id, part)
		taken[at] = true
		var n := world.npc(id)
		var t := _token("npc:" + id, "npc", id, str(n.get("name", id)), at)
		t["attitude"] = s.attitude(id)
		t["portrait"] = PortraitRules.of(s, data, {"npc_id": id})
		out.append(t)
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		var id := str(c["id"])
		if CreatureRules.with_hero(c):
			continue
		var fell := Vector2i(int(c.get("x", -1)), int(c.get("y", -1)))
		var at := _closest(spots, taken, fell) if cells.has(fell) else _seeded(spots, taken, "%d|%s" % [s.game_seed, id])
		taken[at] = true
		var tc := _token("cr:" + id, "body" if str(c["state"]) == CreatureRules.DEAD else "creature", id, str(c["name"]), at)
		if str(tc["kind"]) == "creature":
			tc["portrait"] = PortraitRules.of(s, data, c)
		out.append(tc)
	for b: Dictionary in CrimeRules.bodies_here(s, data):
		var id := str(b["npc_id"])
		var at := _seeded(spots, taken, "%d|%s" % [s.game_seed, id])
		taken[at] = true
		out.append(_token("body:" + id, "body", id, str(b["name"]), at))
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if not _shown(data, p):
			continue
		var at := _prop_cell(s, data, map, spots, taken, out, p)
		var t := _token("prop:" + str(p["id"]), "prop", str(p["id"]), str(p["name"]), at)
		var body_id := ThingRules.body_id(data, p)
		if not body_id.is_empty():
			var key := "%d|%s" % [s.game_seed, str(p["id"])]
			var laid := {}
			if not p.get("at") is Array and str(p.get("near", "")).is_empty():  # the master's furniture on a free spot of its group
				var sp := _free_spot_for(lib, keys, body_id, free, taken, key)
				if not sp.is_empty():
					laid = _lay(data, body_id, key, sp["at"], spots, cells, ways, walls, taken, true)
					if bool(laid.get("loose", false)):
						laid = {}
					else:
						free.erase(sp)
			if laid.is_empty():
				laid = _lay(data, body_id, key, at, spots, cells, ways, walls, taken, p.get("at") is Array)
			_with_body(data, t, body_id, laid, walls)
		for c: Vector2i in t.get("cells", [at]):
			taken[c] = true
		out.append(t)
	return {"tokens": out, "free": free}


## The things of the room's furnishings (marks `set:<body>` of LayoutGen.furnish_marks, v0.8.4.43.31): all the
## furnishings of its chunk mixed — each thing in an order of the seed stands if its squares are free floor and it cuts no
## way; one that meets a thing already standing is left out. A room gets the bed of one furnishing, the cabinet of another.
static func _furnished(data: Dictionary, map: Dictionary, index: int, room_key: String, spots: Array[Vector2i], cells: Array[Vector2i],
		ways: Array[Vector2i], walls: Dictionary, taken: Dictionary, out: Array[Dictionary]) -> void:
	var marks: Array[Dictionary] = []
	for m: Dictionary in map["marks"]:
		if int(m["room"]) == index and str(m["name"]).begins_with(LayoutGen.SET):
			marks.append(m)
	if marks.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_key + "|furnish")
	for i: int in range(marks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var was := marks[i]
		marks[i] = marks[j]
		marks[j] = was
	var floor := {}
	for c: Vector2i in spots:
		floor[c] = true
	var bodies: Dictionary = ThingRules.cfg(data)["bodies"]
	for m: Dictionary in marks:
		var body_id := str(m["name"]).substr(LayoutGen.SET.length())
		if not bodies.has(body_id):
			continue
		var laid := set_laid(data, m)
		var mine: Array[Vector2i] = laid["cells"]
		if not mine.all(func(c: Vector2i) -> bool: return floor.has(c) and not taken.has(c)):
			continue
		if (bodies[body_id].get("blocks", []) as Array).has("path") and not _joined_without(cells, ways, walls, mine):
			continue
		var at: Vector2i = laid["at"]
		var t := _token("thing:%d,%d" % [at.x, at.y], "thing", "%d,%d" % [at.x, at.y], _body_name(data, body_id), at)
		t["still"] = true
		t["set"] = int(m.get("set", 0))
		_with_body(data, t, body_id, laid, walls)
		for c: Vector2i in mine:
			taken[c] = true
		out.append(t)


## The squares of a thing of a furnishing on the map from its mark: {"at": top left, "turn", "cells"}.
static func set_laid(data: Dictionary, m: Dictionary) -> Dictionary:
	var body_id := str(m["name"]).substr(LayoutGen.SET.length())
	var size: Array = ThingRules.cfg(data)["bodies"].get(body_id, {}).get("size", [1, 1])
	var rot := int(m.get("rot", 0))
	var flip := bool(m.get("flip", false))
	var turn := int(m.get("turn", 0))
	var from := Vector2i(int(m["x"]), int(m["y"]))
	var mine: Array[Vector2i] = []
	var corner := Vector2i(1 << 30, 1 << 30)
	for o: Vector2i in footprint(size, Vector2i.ZERO, turn):
		var c := from + LayoutGen.turn_offset(o, rot, flip)
		mine.append(c)
		corner = Vector2i(mini(corner.x, c.x), mini(corner.y, c.y))
	return {"at": corner, "turn": LayoutGen.turn_of(turn, rot, flip), "cells": mine}


## The marks `spot:<group>` of a room of the map: [{"group", "at"}] in the map's order.
static func spot_marks(map: Dictionary, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in map["marks"]:
		var name := str(m["name"])
		if int(m["room"]) == index and name.begins_with(SPOT):
			out.append({"group": name.substr(SPOT.length()), "at": Vector2i(int(m["x"]), int(m["y"]))})
	return out


## A free spot whose group holds `body_id` for this place, the first by the seed of `key`; {} — none.
static func _free_spot_for(lib: Dictionary, keys: Array[String], body_id: String, free: Array[Dictionary], taken: Dictionary, key: String) -> Dictionary:
	var groups: Dictionary = lib.get("spots", {}).get("groups", {})
	var fits := free.filter(func(sp: Dictionary) -> bool:
		var weights: Variant = _weights(groups.get(str(sp["group"]), {}).get("bodies", {}), keys)
		return weights is Dictionary and (weights as Dictionary).has(body_id) and not taken.has(sp["at"]))
	if fits.is_empty():
		return {}
	return fits[absi(key.hash()) % fits.size()]


## A body by weights {id: weight}; "" — none.
static func _pick(weights: Variant, rng: RandomNumberGenerator) -> String:
	if not weights is Dictionary or (weights as Dictionary).is_empty():
		return ""
	var total := 0.0
	for id: String in weights:
		total += float(weights[id])
	var roll := rng.randf() * total
	for id: String in weights:
		roll -= float(weights[id])
		if roll < 0.0:
			return id
	return str((weights as Dictionary).keys().back())


## The things that stand by a thing (`layouts.json` → `spots.near`): each row by its chance, `count` times, on squares
## beside the thing's own; one laid the way the thing is with `same_turn` (benches along a table). Nothing fits — none.
static func _companions(data: Dictionary, t: Dictionary, room_key: String, spots: Array[Vector2i], cells: Array[Vector2i], ways: Array[Vector2i],
		walls: Dictionary, taken: Dictionary, out: Array[Dictionary]) -> void:
	var rows: Array = data["layouts"].get("spots", {}).get("near", {}).get(str(t.get("body", "")), [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|near|%s" % [room_key, str(t["ref"])])
	var n := 0
	for row: Dictionary in rows:
		for i: int in int(row.get("count", 1)):
			if rng.randf() >= float(row.get("chance", 1.0)):
				continue
			var body_id := str(row["body"])
			var key := "%s|%s|%d" % [room_key, str(t["ref"]), n]
			n += 1
			var laid := _lay(data, body_id, key, t["corner"], spots, cells, ways, walls, taken, false, {}, t["cells"], int(t["turn"]) if bool(row.get("same_turn", false)) else -1)
			if bool(laid.get("loose", false)):
				continue
			var at: Vector2i = laid["cells"][0]
			var c := _token("thing:%d,%d" % [at.x, at.y], "thing", "%d,%d" % [at.x, at.y], _body_name(data, body_id), at)
			c["still"] = true
			_with_body(data, c, body_id, laid, walls)
			for sq: Vector2i in c["cells"]:
				taken[sq] = true
			out.append(c)


static func _body_name(data: Dictionary, body_id: String) -> String:
	return str(ThingRules.cfg(data)["bodies"].get(body_id, {}).get("name", body_id)).capitalize()


## The room's things in words for the master (v0.8.4.43.26): what the engine stood there — «стол ×2, скамья ×3» — and the
## spots left free with the bodies each takes — «место для припасов ×2 (barrel, crate, chest)».
static func furniture_words(s: GameSession, data: Dictionary, room := "") -> Dictionary:
	var keep := s.room_id
	if not room.is_empty():
		s.room_id = room  # a read of another room (the second line's furnishing): put back below
	var map := WalkRules.view(s, data)
	var got := _of(s, data, map)
	s.room_id = keep
	var count := {}
	for t: Dictionary in got["tokens"]:
		if str(t["kind"]) in ["thing", "station"] and not str(t.get("body", "")).is_empty():
			var name := str(ThingRules.cfg(data)["bodies"].get(str(t["body"]), {}).get("name", t["body"]))
			count[name] = int(count.get(name, 0)) + 1
	var stood: Array[String] = []
	for name: String in count:
		stood.append(name if int(count[name]) == 1 else "%s ×%d" % [name, count[name]])
	var groups: Dictionary = data["layouts"].get("spots", {}).get("groups", {})
	var keys := LayoutGen.ground_keys(data["layouts"], map)
	var by_group := {}
	for sp: Dictionary in got["free"]:
		by_group[str(sp["group"])] = int(by_group.get(str(sp["group"]), 0)) + 1
	var free: Array[String] = []
	for g: String in by_group:
		var weights: Variant = _weights(groups.get(g, {}).get("bodies", {}), keys)
		var ids: Array = (weights as Dictionary).keys() if weights is Dictionary else []
		free.append("%s ×%d (body: %s)" % [str(groups.get(g, {}).get("name", g)), by_group[g], ", ".join(ids)])
	return {"stood": stood, "free": free}


## What the squares of the things among `tokens` bar: {square: PATH | SIGHT} (v0.8.4.43.23). The walk, the eye and a
## fight read it; a thing that bars nothing is not here.
static func walls(tokens: Array[Dictionary]) -> Dictionary:
	var out := {}
	for t: Dictionary in tokens:
		var bits := int(t.get("bars", 0))
		if bits == 0:
			continue
		for c: Vector2i in t.get("cells", []):
			out[c] = int(out.get(c, 0)) | bits
	return out


## The squares a thing of `size` [long, short] takes from `at`, its top left, turned by `turn` quarters: an odd turn lays
## it the other way.
static func footprint(size: Array, at: Vector2i, turn: int) -> Array[Vector2i]:
	var w := int(size[1]) if turn % 2 == 1 else int(size[0])
	var h := int(size[0]) if turn % 2 == 1 else int(size[1])
	var out: Array[Vector2i] = []
	for y: int in h:
		for x: int in w:
			out.append(at + Vector2i(x, y))
	return out


## A thing of a body laid near `at`: its squares all free among `spots` and not `taken`, turned as the seed of `key` says
## first; one that bars the way keeps every way of the room joined. `must` — one of its squares is `at` itself (a station
## of a mark, a thing put by hand). {"at": top left, "turn", "cells"}; nothing fits — one square at `at`.
## `want` — of the fits the one with most squares in it (a counter along its marks); `beside` — one of its squares next to
## one of these (a companion); `turn_first` — that turn tried first. Nothing fits — "loose".
static func _lay(data: Dictionary, body_id: String, key: String, at: Vector2i, spots: Array[Vector2i], cells: Array[Vector2i],
		ways: Array[Vector2i], walls: Dictionary, taken: Dictionary, must: bool, want: Dictionary = {}, beside: Array = [], turn_first: int = -1) -> Dictionary:
	var body: Dictionary = ThingRules.cfg(data)["bodies"].get(body_id, {})
	var size: Array = body.get("size", [1, 1])
	var bars := (body.get("blocks", []) as Array).has("path")
	var free := {}
	for c: Vector2i in spots:
		if not taken.has(c) or (must and c == at):
			free[c] = true
	var h := absi(key.hash())
	var turns: Array[int] = [h % 4, (h + 1) % 4, (h + 2) % 4, (h + 3) % 4]
	if turn_first >= 0:
		turns = [turn_first % 4, (turn_first + 2) % 4, (turn_first + 1) % 4, (turn_first + 3) % 4]
	var near := {}
	for c: Vector2i in beside:
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				near[c + Vector2i(dx, dy)] = true
	var best := {}
	var best_score := -1
	var starts: Array[Vector2i] = [at]
	if not must:
		starts = spots.filter(func(c: Vector2i) -> bool: return free.has(c))
		starts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := WalkRules.distance(a, at)
			var db := WalkRules.distance(b, at)
			return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for start: Vector2i in starts:
		for turn: int in turns:
			var w := int(size[1]) if turn % 2 == 1 else int(size[0])
			var hh := int(size[0]) if turn % 2 == 1 else int(size[1])
			for oy: int in hh:  # the start square is one of its squares: each of its squares there in turn
				for ox: int in w:
					var mine := footprint(size, start - Vector2i(ox, oy), turn)
					if not mine.all(func(c: Vector2i) -> bool: return free.has(c)):
						continue
					if not beside.is_empty() and not mine.any(func(c: Vector2i) -> bool: return near.has(c)):
						continue
					if bars and not _joined_without(cells, ways, walls, mine):
						continue
					var laid := {"at": start - Vector2i(ox, oy), "turn": turn, "cells": mine}
					if want.is_empty():
						return laid
					var score := mine.filter(func(c: Vector2i) -> bool: return want.has(c)).size()
					if score > best_score:
						best = laid
						best_score = score
		if not beside.is_empty() and WalkRules.distance(start, at) > 4:
			break
	if not best.is_empty():
		return best
	return {"at": at, "turn": turns[0], "cells": [at] as Array[Vector2i], "loose": true}


## A token takes its thing's body: its squares, its turn, what it bars; its own square is one of them. The squares that
## bar the way join `walls`.
static func _with_body(data: Dictionary, t: Dictionary, body_id: String, laid: Dictionary, walls: Dictionary) -> void:
	var body: Dictionary = ThingRules.cfg(data)["bodies"].get(body_id, {})
	var mine: Array[Vector2i] = laid["cells"]
	var blocks: Array = body.get("blocks", [])
	var bars := (PATH if blocks.has("path") and not bool(laid.get("loose", false)) else 0) | (SIGHT if blocks.has("sight") else 0)
	t["body"] = body_id
	t["turn"] = int(laid["turn"])
	t["cells"] = mine
	t["corner"] = laid["at"]
	t["bars"] = bars
	if not mine.has(Vector2i(int(t["x"]), int(t["y"]))):
		t["x"] = mine[0].x
		t["y"] = mine[0].y
	if bars & PATH:
		for c: Vector2i in mine:
			walls[c] = true


static func _token(ref: String, kind: String, id: String, name: String, at: Vector2i) -> Dictionary:
	return {"ref": ref, "kind": kind, "id": id, "name": name, "mark": name.left(1), "portrait": "", "x": at.x, "y": at.y, "attitude": 0}


## On the map is what can be taken or used and a thing with a body (v0.8.4.43.23: drawn from above, it takes its
## squares); the rest of the furniture and decor stays words.
static func _shown(data: Dictionary, p: Dictionary) -> bool:
	if p.has("wares") or bool(p.get("hidden", false)):
		return false
	return not str(p.get("item_id", "")).is_empty() or not str(p.get("container", "")).is_empty() or p.has("source") \
		or not str(p.get("text", "")).is_empty() or QuestGen.is_board(data, p) or not ThingRules.body_id(data, p).is_empty()


static func _npc_cell(s: GameSession, data: Dictionary, map: Dictionary, room: String, cells: Array[Vector2i], taken: Dictionary, id: String, part: String) -> Vector2i:
	var moved: Dictionary = (s.layouts.get("moved", {}) as Dictionary).get(id, {})
	if str(moved.get("room", "")) == room and str(moved.get("part", "")) == part:
		var at := LayoutGen.off_grid(map, Vector2i(int(moved["x"]), int(moved["y"])))
		return at if cells.has(at) else _closest(cells, taken, at)  # walked up to the hero in a doorway: the free square beside it
	if WorldView.new(data["world"]).is_trader(id):
		for wanted: String in cfg(data)["trader_marks"]:
			var at := _mark_cell(map, room, wanted)
			if at.x >= 0:
				return _closest(cells, taken, at)
	return _seeded(cells, taken, "%d|%s|%s" % [s.game_seed, id, part])


## People of the other rooms of this map the hero knows: seen through a door, walked up to on the map, spoken to there.
static func others(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world := WorldView.new(data["world"])
	var part := TimeRules.part_name(s, data)
	var followers := Being.followers(s)
	for room: String in map["ids"]:
		if room == s.room_id or not s.visited.has(room):
			continue
		var cells := _clear(map, data["layouts"], _cells(map, data["layouts"], room))
		var taken := {}
		for id: String in _sorted(s.npcs_here(data["world"], room)):
			if followers.has(id) or cells.is_empty():
				continue
			var at := _npc_cell(s, data, map, room, cells, taken, id, part)
			taken[at] = true
			var t := _token("far:" + id, "npc", id, str(world.npc_name(id)), at)
			t["attitude"] = s.attitude(id)
			out.append(t)
	return out


## Those who came to watch a bout: on the fight's record, gone with it (v0.8.4.5).
static func crowd(s: GameSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in s.combat.get("crowd", []):
		out.append(_token("crowd:" + str(c["id"]), "npc", str(c["id"]), str(c["name"]), Vector2i(int(c["x"]), int(c["y"]))))
	return out


## The square a fighter of a fight starts on: its person's, its creature's. (-1, -1) — no such. The heads of an
## encounter come to the fight with their squares of the map (`on_lair`).
static func of_fighter(s: GameSession, data: Dictionary, spec: Dictionary) -> Vector2i:
	var npc := str(spec.get("npc_id", ""))
	var creature := str(spec.get("creature_id", ""))
	if not npc.is_empty() or not creature.is_empty():
		var ref := "npc:" + npc if not npc.is_empty() else "cr:" + creature
		for t: Dictionary in of(s, data, FightGrid.map(s, data)):
			if str(t["ref"]) == ref:
				return Vector2i(int(t["x"]), int(t["y"]))
	return Vector2i(-1, -1)


## The foes of the room before a fight, each with its "record", on their squares by `on_lair`. `_map` is the hero's
## view: the squares come from the whole map.
static func foes(s: GameSession, data: Dictionary, _map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if EncounterRules.lurking(s, s.room_id).is_empty():
		return out
	var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
	var heads: Array = enc.get("enemies", [])
	var placed := on_lair(s, data, str(enc.get("id", "")), heads)
	for i: int in heads.size():
		var e: Dictionary = heads[i]
		var p: Dictionary = placed[i]
		if Being.dead(s, EncounterRules.foe_id(e)) or not p.has("x"):
			continue
		var t := _token("foe:" + EncounterRules.foe_id(e), "foe", EncounterRules.foe_id(e), str(e.get("name", e.get("monster", ""))), Vector2i(int(p["x"]), int(p["y"])))
		t["record"] = e
		var w := e.duplicate()
		w["id"] = EncounterRules.foe_id(e)
		t["portrait"] = PortraitRules.of(s, data, w)
		out.append(t)
	return out


## The heads of an encounter on the room's map, each a copy with its "x", "y": together by the lair, away from the ways
## in, kept by the seed. The whole map, not the hero's view of it: a way shut for now (a ford in a downpour) moves
## nobody. One road for the foes on the map and the fight's start (v0.8.4.24). A head with its own square keeps it.
static func on_lair(s: GameSession, data: Dictionary, key: String, heads: Array) -> Array:
	var map := LayoutRules.map_of(s, data, s.room_id)
	var cells := _clear(map, data["layouts"], _cells(map, data["layouts"], s.room_id))
	var lair := _lair(s, data, map, cells, key) if not cells.is_empty() else FightGrid.NONE
	var taken := {}
	var out: Array = []
	for e: Dictionary in heads:
		var spec := e.duplicate()
		if lair != FightGrid.NONE and not spec.has("x") and not Being.dead(s, EncounterRules.foe_id(e)):
			var at := _closest(cells, taken, lair)
			taken[at] = true
			spec["x"] = at.x
			spec["y"] = at.y
		out.append(spec)
	return out


static func _lair(s: GameSession, data: Dictionary, map: Dictionary, cells: Array[Vector2i], key: String) -> Vector2i:
	var ways := _ways_in(map, s.room_id)
	var far := int(SightRules.cfg(data)["lair"])
	var fit: Array[Vector2i] = cells.filter(func(cell: Vector2i) -> bool:
		return ways.all(func(way: Vector2i) -> bool: return WalkRules.distance(way, cell) >= far))
	return _seeded(fit if not fit.is_empty() else cells, {}, "%d|%s" % [s.game_seed, key])


static func _ways_in(map: Dictionary, room: String) -> Array[Vector2i]:
	var ways: Array[Vector2i] = []
	var index := (map["ids"] as Array).find(room)
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room:
			ways.append(Vector2i(int(e["ax"]), int(e["ay"])))
	for d: Dictionary in map["doors"]:
		if index in [int(d["a"]), int(d["b"])]:
			ways.append(Vector2i(int(d["x"]), int(d["y"])))
	return ways


## The square of a trap or a cache: a trap lies before the way it guards, a thing where the pack says (`near`, a mark) or
## where the seed puts it. (-1, -1) — the room has no free square.
static func secret_cell(s: GameSession, data: Dictionary, map: Dictionary, room: String, sec: Dictionary) -> Vector2i:
	var cells := _clear(map, data["layouts"], _cells(map, data["layouts"], room))
	if cells.is_empty():
		return Vector2i(-1, -1)
	var to := str((sec.get("trap", {}) as Dictionary).get("guards", ""))
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room and str(e["to"]) == to:
			return Vector2i(int(e["ax"]), int(e["ay"]))
	var ids: Array = map["ids"]
	for d: Dictionary in map["doors"]:
		if not to.is_empty() and ids[int(d["a"])] in [room, to] and ids[int(d["b"])] in [room, to]:
			return _closest(cells, {}, Vector2i(int(d["x"]), int(d["y"])))
	var near := _mark_cell(map, room, str(sec.get("near", "")))
	return near if cells.has(near) else _seeded(cells, {}, "%d|%s|%s" % [s.game_seed, room, str(sec["id"])])


## The traps the hero found, on their squares.
static func traps(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ft: Dictionary in ExplorationRules.found_traps(s, data["world"], s.room_id):
		var sec: Dictionary = ft["secret"]
		var at := secret_cell(s, data, map, s.room_id, sec)
		if at.x >= 0:
			out.append(_token("trap:" + str(sec["id"]), "trap", str(sec["id"]), str(sec["text"]), at))
	return out


static func _prop_cell(s: GameSession, data: Dictionary, map: Dictionary, cells: Array[Vector2i], taken: Dictionary, placed: Array[Dictionary], p: Dictionary) -> Vector2i:
	if p.get("at") is Array:  # put on its square by hand (v0.8.4.42), kept on the grid
		var own := LayoutGen.off_grid(map, Vector2i(int(p["at"][0]), int(p["at"][1])))
		if cells.has(own) and not taken.has(own):
			return own
	var near := str(p.get("near", ""))
	if not near.is_empty():
		var at := _mark_cell(map, s.room_id, near)
		for t: Dictionary in placed:
			if str(t["id"]) == near:
				at = Vector2i(int(t["x"]), int(t["y"]))
		if at.x >= 0:
			return _closest(cells, taken, at)
	return _seeded(cells, taken, "%d|%s" % [s.game_seed, str(p["id"])])


## The free squares of a room, in a fixed order.
static func _cells(map: Dictionary, lib: Dictionary, room: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var cell := Vector2i(x, y)
			if WalkRules.room_of(map, cell) == room and WalkRules.floor_at(map, lib, cell):
				out.append(cell)
	return out


## The squares of `cells` a thing may lie on (v0.8.4.24): no cell kept free by layouts.json (a door), no door between
## rooms, no way out nor the square before it. None left — `cells` as they are.
static func _clear(map: Dictionary, lib: Dictionary, cells: Array[Vector2i]) -> Array[Vector2i]:
	var ways := {}
	for e: Dictionary in map["exits"]:
		ways[Vector2i(int(e["x"]), int(e["y"]))] = true
		ways[Vector2i(int(e["ax"]), int(e["ay"]))] = true
	for d: Dictionary in map["doors"]:
		ways[Vector2i(int(d["x"]), int(d["y"]))] = true
	var rows: Array = map["rows"]
	var out: Array[Vector2i] = cells.filter(func(at: Vector2i) -> bool:
		return not ways.has(at) and not bool(lib["cells"].get(str(rows[at.y])[at.x], {}).get("keep_free", false)))
	return out if not out.is_empty() else cells


## A thing that bars the way never cuts one door or way out of the room from another (v0.8.4.30, the author's
## feedback: only the doorways and the squares before them were kept free). `at` if the ways stay joined, else the
## nearest free square that keeps them so; none — `at`.
static func _off_the_way(cells: Array[Vector2i], spots: Array[Vector2i], ways: Array[Vector2i], walls: Dictionary, taken: Dictionary, at: Vector2i) -> Vector2i:
	if ways.size() < 2 or _joined(cells, ways, walls, at) or not _joined(cells, ways, walls, Vector2i(-1, -1)):  # already cut: not by this thing
		return at
	var order := spots.filter(func(c: Vector2i) -> bool: return not taken.has(c) and c != at)
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return WalkRules.distance(a, at) < WalkRules.distance(b, at))
	for c: Vector2i in order:
		if _joined(cells, ways, walls, c):
			return c
	return at


## Every way of the room joined with the squares of `extra` barred too.
## v0.8.4.43.26: and no square of the room's floor shut off from the rest (a corner walled by a hearth, a table and its
## benches), unless it was shut off before.
static func _joined_without(cells: Array[Vector2i], ways: Array[Vector2i], walls: Dictionary, extra: Array[Vector2i]) -> bool:
	var more := walls.duplicate()
	for c: Vector2i in extra:
		more[c] = true
	return _whole(cells, ways, more) or not _whole(cells, ways, walls)


## The free squares of the room and its ways one region: each reached from any other over the free ones.
static func _whole(cells: Array[Vector2i], ways: Array[Vector2i], walls: Dictionary) -> bool:
	var open := {}
	for c: Vector2i in cells:
		if not walls.has(c):
			open[c] = true
	for c: Vector2i in ways:
		if not walls.has(c):
			open[c] = true
	if open.is_empty():
		return true
	var first: Vector2i = open.keys()[0]
	var seen := {first: true}
	var front: Array[Vector2i] = [first]
	while not front.is_empty():
		var c: Vector2i = front.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if open.has(n) and not seen.has(n):
				seen[n] = true
				front.append(n)
	return seen.size() == open.size()


## Every way of the room reached from the first over its free squares, with `walls` and `extra` barred.
static func _joined(cells: Array[Vector2i], ways: Array[Vector2i], walls: Dictionary, extra: Vector2i) -> bool:
	var open := {}
	for c: Vector2i in cells:
		open[c] = true
	for c: Vector2i in ways:
		open[c] = true
	for c: Variant in walls:
		open.erase(c)
	open.erase(extra)
	if not open.has(ways[0]):
		return false
	var seen := {ways[0]: true}
	var front: Array[Vector2i] = [ways[0]]
	while not front.is_empty():
		var c: Vector2i = front.pop_back()
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if open.has(n) and not seen.has(n):
					seen[n] = true
					front.append(n)
	return ways.all(func(w: Vector2i) -> bool: return seen.has(w))


static func _seeded(cells: Array[Vector2i], taken: Dictionary, key: String) -> Vector2i:
	var start := absi(key.hash()) % cells.size()
	for i: int in cells.size():
		var at := cells[(start + i) % cells.size()]
		if not taken.has(at):
			return at
	return cells[start]


static func _closest(cells: Array[Vector2i], taken: Dictionary, to: Vector2i) -> Vector2i:
	var best := cells[0]
	var length := 1 << 30
	for at: Vector2i in cells:
		var d := WalkRules.distance(at, to)
		if d < length and not taken.has(at):
			length = d
			best = at
	return best


static func _mark_cell(map: Dictionary, room: String, name: String) -> Vector2i:
	var index := (map["ids"] as Array).find(room)
	for m: Dictionary in map["marks"]:
		if str(m["name"]) == name and int(m["room"]) == index:
			return Vector2i(int(m["x"]), int(m["y"]))
	return Vector2i(-1, -1)


static func _sorted(ids: Array[String]) -> Array[String]:
	var out := ids.duplicate()
	out.sort()
	return out


static func _word(data: Dictionary, mark: String) -> String:
	return str(cfg(data)["mark_words"].get(mark, mark))


## The square of the one or the thing named by the master: "hero", a person, a thing, a mark of the room. (-1, -1) — none.
static func cell_of(s: GameSession, data: Dictionary, map: Dictionary, name: String) -> Vector2i:
	if name == "hero":
		return WalkRules.settle(s, data, map)
	for t: Dictionary in of(s, data, map):
		if str(t["id"]) == name:
			return Vector2i(int(t["x"]), int(t["y"]))
	if Being.follows(s, name):
		return WalkRules.settle(s, data, map)
	return _mark_cell(map, s.room_id, name)


## How far an act of `kind` reaches from the hero, in squares (`rules.map.reach`): a thing — farther by Mage Hand
## (v0.8.4.26.3); a person — never.
static func reach(s: GameSession, data: Dictionary, kind: String, ref: String = "") -> int:
	var r := int(cfg(data)["reach"][kind])
	if kind == "touch" and not ref.begins_with("npc:"):
		for e: Dictionary in SpellEffects.hero_effects(s.character, "hand_ft"):
			r = maxi(r, FightGrid.squares_of(data, int(e["hand_ft"])))
	return r


## Is `name` within `kind` of the hero, in a line of sight? One who has no square here stands in reach.
static func in_reach(s: GameSession, data: Dictionary, name: String, kind: String) -> bool:
	var map := LayoutRules.map_of(s, data, s.room_id)
	var at := cell_of(s, data, map, name)
	if at.x < 0:
		return true
	var hero := WalkRules.settle(s, data, map)
	return WalkRules.distance(hero, at) <= reach(s, data, kind, name) and SightRules.line(map, data["layouts"], hero, at)


## What the master may name as a place of the room: «очаг [hearth]»; of another room for a furnishing readied ahead.
static func words(s: GameSession, data: Dictionary, room := "") -> Array[String]:
	var here := s.room_id if room.is_empty() else room
	var map := LayoutRules.map_of(s, data, here)
	var index := (map["ids"] as Array).find(here)
	var out: Array[String] = []
	for m: Dictionary in map["marks"]:
		var mark := str(m["name"])
		var line := "%s [%s]" % [_word(data, mark), mark]
		if int(m["room"]) == index and mark != LayoutGen.ENTRY and not mark.begins_with(SPOT) and not mark.begins_with(LayoutGen.SET) and not out.has(line):
			out.append(line)
	return out


## How far from the hero, in words: {id: «рядом»}; the mark the hero stands by is under "hero" («стойка»).
static func near_words(s: GameSession, data: Dictionary) -> Dictionary:
	var map := WalkRules.view(s, data)
	var hero := WalkRules.settle(s, data, map)
	var out := {}
	for t: Dictionary in of(s, data, map):
		out[t["id"]] = str(Scale.step(cfg(data)["distance"], WalkRules.distance(hero, Vector2i(int(t["x"]), int(t["y"]))))["word"])
	var index := (map["ids"] as Array).find(s.room_id)
	var length := int(cfg(data)["by_mark"]) + 1
	for m: Dictionary in map["marks"]:
		var d := WalkRules.distance(hero, Vector2i(int(m["x"]), int(m["y"])))
		if int(m["room"]) == index and str(m["name"]) != LayoutGen.ENTRY and not str(m["name"]).begins_with(LayoutGen.SET) and d < length:
			length = d
			out["hero"] = _word(data, str(m["name"]))
	return out


## The master's `approach`: the hero or a person walks up to someone or something of the room. The engine finds the square.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var who := str(e.get("who", "hero"))
	var to := str(e.get("to", ""))
	var world := WorldView.new(data["world"])
	if who == to:
		return {"reason": "подойти к самому себе нельзя"}
	if who != "hero" and not s.npcs_here(data["world"], s.room_id).has(who):
		return {"reason": "%s нет в этой комнате: подходят те, кто здесь" % who}
	var map := WalkRules.view(s, data)
	var target := cell_of(s, data, map, to)
	if target.x < 0:
		return {"reason": "«%s» нет в этой комнате: подойти можно к человеку и вещи сцены или к месту из scene.spots" % to}
	var from := cell_of(s, data, map, who)
	var steps := WalkRules.near(map, data["layouts"], from, target, int(cfg(data)["reach"]["touch"]), s.room_id)
	var at := steps[-1] if not steps.is_empty() else from
	var name := "Герой" if who == "hero" else str(world.npc_name(who))
	var aim := "герою" if to == "hero" else str(world.npc(to).get("name", _name_of(s, data, map, to)))
	return {"plan": {"who": who, "x": at.x, "y": at.y}, "summary": "%s: к %s" % [name, aim]}


static func _name_of(s: GameSession, data: Dictionary, map: Dictionary, to: String) -> String:
	for t: Dictionary in of(s, data, map):
		if str(t["id"]) == to:
			return str(t["name"])
	return _word(data, to)


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var cell := Vector2i(int(p["x"]), int(p["y"]))
	if str(p["who"]) == "hero":
		WalkRules.stand(s, LayoutRules.map_of(s, data, s.room_id), s.room_id, cell)
		return []
	var moved: Dictionary = s.layouts.get_or_add("moved", {})
	var kept := LayoutGen.on_grid(LayoutRules.map_of(s, data, s.room_id), cell)
	moved[str(p["who"])] = {"room": s.room_id, "part": TimeRules.part_name(s, data), "x": kept.x, "y": kept.y}
	return []


## The weights of a spot group's bodies for this place: the first row of `row` by `keys` (LayoutGen.ground_keys); {} — none.
static func _weights(row: Variant, keys: Array[String]) -> Dictionary:
	if row is Dictionary:
		for k: String in keys:
			if (row as Dictionary).has(k) and row[k] is Dictionary:
				return row[k]
	return {}
