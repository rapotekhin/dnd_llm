class_name WatchRules
extends RefCounted
## Who sees whom on the map (v0.8.3; anybody of either since v0.8.4.12, ADR-0016). One who does not hide is seen by anyone
## with a line of sight in range; one who sneaks, hides or is invisible only in a watcher's cone, and then Stealth decides. A watcher looks towards the middle of the map,
## off by the seed, and turns with the rounds of a sneaking walk, so a save holds nothing but the round. The numbers are
## `rules.sight`.

const FACES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]


## It goes unseen but in a cone: the hero sneaking, anybody hidden or invisible (v0.8.4.12).
static func sneaky(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> bool:
	if Sheet.is_hero(who):
		return s.sneaking or ConditionRules.invisible(s.character, data)
	var h := Sheet.holder(s, who)
	return bool(h.get("hidden", false)) or ConditionRules.invisible(h, data)


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


## The squares `watcher` takes in of `doer` (v0.8.4.12: anybody of either). `wide` — the whole room in the light: a deed in
## the open is seen from further than a stranger is noticed. A doer that carries a light in the dark shows from afar; else
## the watcher's own darkvision or light; a blinded one only hears beside it.
static func range_of(s: GameSession, data: Dictionary, watcher: Dictionary, wide: bool = false, doer: Dictionary = Sheet.HERO) -> int:
	var c := SightRules.cfg(data)
	if ConditionRules.has(Sheet.holder(s, watcher), "blinded"):
		return int(c["blind"])
	var near := int(c["obscured"]) if WeatherRules.passive(s, data) > 0 else int(c["day"]) if wide else int(c["watch"])
	if not TimeRules.unlit(s, data) or SightRules.lit(s, data, doer):
		return near
	return SightRules.reach(s, data, watcher)


## This one on the square `at` sees `cell`, where `doer` stands.
static func sees(s: GameSession, data: Dictionary, map: Dictionary, id: String, at: Vector2i, cell: Vector2i, reach: int, doer: Dictionary = Sheet.HERO) -> bool:
	if WalkRules.distance(at, cell) > reach:
		return false
	if sneaky(s, data, doer) and not in_cone(s, data, map, id, at, cell):
		return false
	return SightRules.line(map, data["layouts"], at, cell)


## Those of `ids`, people of the room here, who see `doer` now: the hero, or anybody who stands on this map (v0.8.4.12).
## One who does not stand on the map here walks with the hero or is behind a door being forced: it counts; a doer off the
## map is seen by them all. v0.8.4.16, the one place for «nobody saw»: an invisible doer is made out only by `pierces`, a
## sneaking, hidden or invisible one in a watcher's cone still has its Stealth against the watcher's passive Perception
## (one roll for the deed). No caller decides it again.
static func eyes(s: GameSession, data: Dictionary, ids: Array, doer: String = Being.HERO) -> Array:
	if ids.is_empty():
		return []
	var map := WalkRules.view(s, data)
	var at := {}
	for t: Dictionary in MapSpots.of(s, data, map) + MapSpots.foes(s, data, map):
		if str(t["kind"]) in ["npc", "foe"]:
			at[str(t["id"])] = _cell(t)
	var cell: Vector2i = WalkRules.settle(s, data, map) if doer == Being.HERO else at.get(doer, Vector2i(-1, -1))
	var who := Sheet.who(s, data, doer)
	var roll := {}  # the doer's one Stealth roll for this deed, made when a watcher's cone takes it in
	return ids.filter(func(id: String) -> bool:
		if id == doer:
			return false
		var w := Sheet.who(s, data, id)
		if cell == Vector2i(-1, -1) or not at.has(id):
			return pierces(s, data, w, who, -1)
		if not sees(s, data, map, id, at[id], cell, range_of(s, data, w, true, who), who) or not pierces(s, data, w, who, WalkRules.distance(at[id], cell)):
			return false
		if not sneaky(s, data, who):
			return true
		if not roll.has("total"):
			roll.merge(CombatRules.stealth_roll(s, data, who))
		return int(roll["total"]) < Sheet.passive(s, data, w))


## `watcher` makes out `doer` for all its invisibility (v0.8.4.16): the doer is not invisible or is outlined, the watcher
## sees the invisible, or its truesight or blindsight reaches `far` squares (-1 — no square: only the first two).
static func pierces(s: GameSession, data: Dictionary, watcher: Dictionary, doer: Dictionary, far: int) -> bool:
	var it := Sheet.holder(s, doer)
	if not ConditionRules.invisible(it, data) or ConditionRules.has(it, "outlined"):
		return true
	if SpellEffects.has(Sheet.holder(s, watcher), "see_invisible"):
		return true
	if far < 0:
		return false
	var sense := FightGrid.senses(s, data, watcher)
	return int(sense.get("truesight", -1)) >= far or int(sense.get("blindsight", -1)) >= far


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
		var far := range_of(s, data, Sheet.who(s, data, id) if str(t["kind"]) == "npc" else t["record"])
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
