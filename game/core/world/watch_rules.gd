class_name WatchRules
extends RefCounted
## Who sees the hero on the map (v0.8.3). A hero who does not hide is seen by anyone with a line of sight in range; one who
## sneaks or is invisible only in a watcher's cone, and then Stealth decides. A watcher looks towards the middle of the map,
## off by the seed, and turns with the rounds of a sneaking walk, so a save holds nothing but the round. The numbers are
## `rules.sight`.

const FACES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]


static func sneaky(s: GameSession, data: Dictionary) -> bool:
	return s.sneaking or ConditionRules.invisible(s.character, data)


static func _cell(t: Dictionary) -> Vector2i:
	return Vector2i(int(t["x"]), int(t["y"]))


## Where a watcher on `at` looks now: an index of FACES. Towards the middle of the map, so nobody stares at the edge.
static func face(s: GameSession, data: Dictionary, map: Dictionary, id: String, at: Vector2i) -> int:
	var h := absi(("%d|%s" % [s.game_seed, id]).hash())
	var turns: Array = SightRules.cfg(data)["turns"]
	var spread := int(SightRules.cfg(data)["face_spread"])
	var middle := Vector2(int(map["w"]), int(map["h"])) / 2.0 - Vector2(at)
	var base := roundi(middle.angle() / (TAU / FACES.size())) + h % (spread * 2 + 1) - spread
	return posmod(base + int(turns[(h >> 8) % turns.size()]) * int(s.layouts.get("round", 0)), FACES.size())


## In the watcher's cone. Beside it nobody slips: the watcher hears that close.
static func in_cone(s: GameSession, data: Dictionary, map: Dictionary, id: String, at: Vector2i, cell: Vector2i) -> bool:
	if WalkRules.distance(at, cell) <= 1:
		return true
	var half := deg_to_rad(float(SightRules.cfg(data)["cone"]) / 2.0)
	return absf(Vector2(FACES[face(s, data, map, id, at)]).angle_to(Vector2(cell - at))) <= half


## The squares a watcher takes in. `sees_dark` — its darkvision in squares. `wide` — the whole room in the light: a deed in
## the open is seen from further than a stranger is noticed.
static func range_of(s: GameSession, data: Dictionary, sees_dark: int, wide: bool = false) -> int:
	var c := SightRules.cfg(data)
	var near := int(c["obscured"]) if WeatherRules.passive(s, data) > 0 else int(c["day"]) if wide else int(c["watch"])
	if not TimeRules.unlit(s, data) or SightRules.lit(s, data):
		return near
	return maxi(sees_dark, int(c["blind"]))


## Darkvision of a person or a foe in squares.
static func dark_of(data: Dictionary, f: Dictionary) -> int:
	return int(Sheet.template(data, f).get("darkvision", 0)) / 5


static func _npc_dark(data: Dictionary, id: String) -> int:
	var world := WorldView.new(data["world"])
	return dark_of(data, {"monster": str(world.npc(id).get("monster", CombatRules.cfg(data)["default_npc_monster"]))})


## This one on the square `at` sees `cell`.
static func sees(s: GameSession, data: Dictionary, map: Dictionary, id: String, at: Vector2i, cell: Vector2i, reach: int) -> bool:
	if WalkRules.distance(at, cell) > reach:
		return false
	if sneaky(s, data) and not in_cone(s, data, map, id, at, cell):
		return false
	return SightRules.line(map, data["layouts"], at, cell)


## Those of `ids`, people of the room here, who see the hero now. One who does not stand on the map here walks with the
## hero or is behind a door being forced: it counts.
static func eyes(s: GameSession, data: Dictionary, ids: Array) -> Array:
	if ids.is_empty():
		return []
	var map := WalkRules.view(s, data)
	var hero := WalkRules.settle(s, data, map)
	var at := {}
	for t: Dictionary in MapSpots.of(s, data, map):
		if str(t["kind"]) == "npc":
			at[str(t["id"])] = _cell(t)
	return ids.filter(func(id: String) -> bool:
		return not at.has(id) or sees(s, data, map, id, at[id], hero, range_of(s, data, _npc_dark(data, id), true)))


## A person of the room here sees the hero.
static func sees_hero(s: GameSession, data: Dictionary, id: String) -> bool:
	return s.npcs_here(data["world"], s.room_id).has(id) and not eyes(s, data, [id]).is_empty()


## The squares under watch of those the hero sees: the cones the player walks around.
static func cones(s: GameSession, data: Dictionary, map: Dictionary, seen: Dictionary) -> Dictionary:
	var out := {}
	if not sneaky(s, data):
		return out
	for t: Dictionary in MapSpots.of(s, data, map) + MapSpots.foes(s, data, map):
		if not str(t["kind"]) in ["npc", "foe"] or not seen.has(_cell(t)):
			continue
		var id := str(t["id"])
		var at := _cell(t)
		var far := range_of(s, data, _npc_dark(data, id) if str(t["kind"]) == "npc" else dark_of(data, t["record"]))
		for cell: Vector2i in SightRules.view(map, data["layouts"], at, far):
			if in_cone(s, data, map, id, at, cell):
				out[cell] = true
	return out


## A walk by rounds: the hero sneaks and sees foes who do not know of it.
static func by_rounds(s: GameSession, data: Dictionary, map: Dictionary, seen: Dictionary) -> bool:
	if not s.sneaking:
		return false
	return MapSpots.foes(s, data, map).any(func(t: Dictionary) -> bool: return seen.has(_cell(t)))


## Squares of one round of a sneaking walk.
static func round_steps(s: GameSession) -> int:
	return maxi(1, int(s.character.get("speed", 30)) / 5)


## The round is over: those who watch turn.
static func next_round(s: GameSession) -> void:
	s.layouts["round"] = int(s.layouts.get("round", 0)) + 1
