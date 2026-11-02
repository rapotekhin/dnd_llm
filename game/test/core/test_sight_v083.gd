extends GdUnitTestSuite
## v0.8.3: what is seen on a map and who sees the hero. A line of sight over opaque squares, light and darkvision by the
## SRD, the fog that remembers; foes on the map before a fight, a meeting by who sees whom, cones and rounds of a sneaking
## walk; witnesses who really see; traps and caches on squares.

const TRAIL := "pushcha-trail"

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	s.minute = 720
	s.character["inventory"] = {}
	s.character["traits"] = []
	CharacterRules.refresh(s.character, data, s.items)
	return s


func _map(s: GameSession) -> Dictionary:
	return WalkRules.view(s, data)


func _plain() -> Dictionary:  # a wall across the middle, a door in it
	return {"id": "t", "w": 7, "h": 5, "rows": ["       ", " ..#.. ", " ..+.. ", " ..#.. ", "       "] as Array[String]}


func _enc(id: String = "t_wolves", monster: String = "wolf") -> Dictionary:
	return {"id": id, "enemies": [{"monster": monster, "count": 2, "name": "Зверь"}]}


## The hero in the room with foes, out of their sight for now.
func _met(s: GameSession, enc: Dictionary = _enc()) -> Array[Dictionary]:
	EncounterRules.heads(s, data, s.room_id, enc)
	s.lurking[s.room_id] = {"encounter": str(enc["id"]), "from": "", "seen": false}
	var room: Dictionary = data["world"]["rooms"][s.room_id]
	room["encounter"] = enc
	return MapSpots.foes(s, data, _map(s))


func _at(t: Dictionary) -> Vector2i:
	return Vector2i(int(t["x"]), int(t["y"]))


## A free square where `test` holds for the first foe.
func _square(s: GameSession, foe: Dictionary, test: Callable) -> Vector2i:
	var map := _map(s)
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var cell := Vector2i(x, y)
			if WalkRules.room_of(map, cell) == s.room_id and WalkRules.passable(map, data["layouts"], cell) and test.call(map, _at(foe), cell):
				return cell
	return Vector2i(-1, -1)


func _stand(s: GameSession, cell: Vector2i) -> void:
	WalkRules.stand(s, _map(s), s.room_id, cell)


func _in_cone(s: GameSession, id: String, want: bool) -> Callable:
	return func(map: Dictionary, at: Vector2i, cell: Vector2i) -> bool:
		var d := WalkRules.distance(at, cell)
		return d >= 2 and d <= 6 and SightRules.line(map, data["layouts"], at, cell) and WatchRules.in_cone(s, data, map, id, at, cell) == want


# --- the line and the view ------------------------------------------------------------------------------------


func test_a_wall_and_a_door_close_the_view() -> void:
	var lib: Dictionary = data["layouts"]
	var map := _plain()
	assert_bool(SightRules.line(map, lib, Vector2i(1, 2), Vector2i(2, 1))).is_true()
	assert_bool(SightRules.line(map, lib, Vector2i(1, 2), Vector2i(5, 2))).is_false()
	var seen := SightRules.view(map, lib, Vector2i(1, 2), 10)
	assert_bool(seen.has(Vector2i(3, 2))).is_true()  # the door itself
	assert_bool(seen.has(Vector2i(4, 2))).is_false()


func test_from_a_door_both_rooms_are_seen() -> void:
	var seen := SightRules.view(_plain(), data["layouts"], Vector2i(3, 2), 10)
	assert_bool(seen.has(Vector2i(1, 2))).is_true()
	assert_bool(seen.has(Vector2i(5, 2))).is_true()


func test_the_view_ends_at_its_reach() -> void:
	var map := {"id": "t", "w": 20, "h": 1, "rows": [".".repeat(20)] as Array[String]}
	var seen := SightRules.view(map, data["layouts"], Vector2i(0, 0), 8)
	assert_bool(seen.has(Vector2i(8, 0))).is_true()
	assert_bool(seen.has(Vector2i(9, 0))).is_false()


# --- light ----------------------------------------------------------------------------------------------------


func test_how_far_the_hero_sees() -> void:
	var c := SightRules.cfg(data)
	var s := _session("mine-gallery")
	assert_int(SightRules.reach(s, data)).is_equal(int(c["blind"]))
	s.character["inventory"] = {"torch": 1}
	assert_int(SightRules.reach(s, data)).is_equal(8)
	assert_bool(SightRules.lit(s, data)).is_true()
	s.character["traits"] = ["darkvision"]
	assert_int(SightRules.reach(s, data)).is_equal(12)
	assert_bool(SightRules.lit(s, data)).is_false()
	s.room_id = "brod-square"
	assert_int(SightRules.reach(s, data)).is_equal(int(c["day"]))


func test_a_light_shows_the_hero_in_the_dark() -> void:
	var s := _session("mine-gallery")
	assert_int(WatchRules.range_of(s, data, {"monster": "commoner"})).is_equal(int(SightRules.cfg(data)["blind"]))
	assert_int(WatchRules.range_of(s, data, {"monster": "goblin"})).is_equal(12)  # its 60 ft of darkvision
	s.character["inventory"] = {"torch": 1}
	assert_int(WatchRules.range_of(s, data, {"monster": "commoner"})).is_equal(int(SightRules.cfg(data)["watch"]))


# --- the hero's view ---------------------------------------------------------------------------------------------


func test_a_tree_closes_a_watchers_view_not_the_heros() -> void:
	var map := {"id": "t", "w": 7, "h": 1, "rows": ["...T..."] as Array[String]}
	var lib: Dictionary = data["layouts"]
	assert_bool(SightRules.view(map, lib, Vector2i(0, 0), 10).has(Vector2i(6, 0))).is_false()
	assert_bool(SightRules.view(map, lib, Vector2i(0, 0), 10, true).has(Vector2i(6, 0))).is_true()


func test_the_hero_looks_all_round_up_to_the_walls() -> void:
	var s := _session()
	var map := _plain()
	var seen := SightRules.look(s, data, map, Vector2i(1, 2))
	assert_bool(seen.has(Vector2i(2, 1)) and seen.has(Vector2i(2, 3))).is_true()
	assert_bool(seen.has(Vector2i(5, 2))).is_false()  # a wall still closes it
	assert_bool(s.layouts.has("seen")).is_false()  # the map is open: nothing to keep


# --- foes on the map ------------------------------------------------------------------------------------------


func test_foes_stand_away_from_the_ways_in_and_stay() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	assert_int(foes.size()).is_equal(2)
	var map := _map(s)
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == TRAIL:
			assert_bool(WalkRules.distance(_at(foes[0]), Vector2i(int(e["ax"]), int(e["ay"]))) >= int(SightRules.cfg(data)["lair"])).is_true()
	assert_array(MapSpots.foes(s, data, map).map(_at)).is_equal(foes.map(_at))
	assert_array(MapSpots.of(s, data, map).map(func(t: Dictionary) -> String: return str(t["kind"]))).not_contains(["foe"])


func test_a_hero_who_does_not_hide_is_noticed_in_range() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	_stand(s, _square(s, foes[0], func(map: Dictionary, at: Vector2i, cell: Vector2i) -> bool:
		return WalkRules.distance(at, cell) == 3 and SightRules.line(map, data["layouts"], at, cell)))
	var w := EncounterRules.watch(s, data, _map(s))
	assert_bool(bool(w["fight"])).is_true()
	assert_dict(w["source"]).is_empty()


func test_far_off_nobody_notices_but_the_hero_sees_them() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	var watch := int(SightRules.cfg(data)["watch"])
	_stand(s, _square(s, foes[0], func(map: Dictionary, at: Vector2i, cell: Vector2i) -> bool:
		return WalkRules.distance(at, cell) in [watch + 2, watch + 3] and SightRules.view(map, data["layouts"], cell, 30).has(at)))
	var w := EncounterRules.watch(s, data, _map(s))
	assert_bool(bool(w["fight"])).is_false()
	assert_bool(w.has("new_sight")).is_true()
	assert_bool(EncounterRules.sighted(s, TRAIL)).is_true()
	assert_bool(EncounterRules.watch(s, data, _map(s)).has("new_sight")).is_false()


func test_unseen_at_first_there_is_nothing_to_act_on() -> void:
	var s := _session(TRAIL)
	_met(s)
	assert_bool(EncounterRules.sighted(s, TRAIL)).is_false()
	assert_array(EncounterRules.snapshot(s, data, TRAIL)).is_empty()


func test_foes_in_the_dark_have_the_drop_on_a_hero_who_sees_nothing() -> void:
	var s := _session("mine-deep")
	var foes := _met(s, _enc("t_dark", "goblin"))
	_stand(s, _square(s, foes[0], func(map: Dictionary, at: Vector2i, cell: Vector2i) -> bool:
		return WalkRules.distance(at, cell) == 4 and SightRules.line(map, data["layouts"], at, cell)))
	var w := EncounterRules.watch(s, data, _map(s))
	assert_bool(bool(w["fight"])).is_true()
	assert_bool(bool(w["source"]["ambush"])).is_true()


# --- sneaking -------------------------------------------------------------------------------------------------


func test_behind_a_watcher_the_hero_is_not_seen() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	var id := str(foes[0]["id"])
	var behind := _square(s, foes[0], _in_cone(s, id, false))
	assert_bool(WatchRules.sees(s, data, _map(s), id, _at(foes[0]), behind, 12)).is_true()
	s.sneaking = true
	assert_bool(WatchRules.sees(s, data, _map(s), id, _at(foes[0]), behind, 12)).is_false()


func test_one_stealth_roll_for_the_room() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	s.sneaking = true
	s.character["skills"]["stealth"] = 40
	_stand(s, _square(s, foes[0], _in_cone(s, str(foes[0]["id"]), true)))
	assert_bool(bool(EncounterRules.watch(s, data, _map(s))["fight"])).is_false()
	var rolled := int(EncounterRules.lurking(s, TRAIL)["stealth"])
	s.character["skills"]["stealth"] = -40
	assert_bool(bool(EncounterRules.watch(s, data, _map(s))["fight"])).is_false()
	assert_int(int(EncounterRules.lurking(s, TRAIL)["stealth"])).is_equal(rolled)


func test_a_failed_roll_in_a_cone_is_a_fight_with_that_roll() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	s.sneaking = true
	s.character["skills"]["stealth"] = -40
	_stand(s, _square(s, foes[0], _in_cone(s, str(foes[0]["id"]), true)))
	var w := EncounterRules.watch(s, data, _map(s))
	assert_bool(bool(w["fight"])).is_true()
	assert_bool(bool(w["source"]["sneak"])).is_true()
	assert_bool(int(w["source"]["stealth_total"]) < 0).is_true()


func test_watchers_turn_with_the_rounds() -> void:
	var s := _session(TRAIL)
	var turned := false
	for i: int in 20:
		var id := "foe%d" % i
		var was := WatchRules.face(s, data, _map(s), id, Vector2i(3, 3))
		s.layouts["round"] = 1
		turned = turned or WatchRules.face(s, data, _map(s), id, Vector2i(3, 3)) != was
		s.layouts["round"] = 0
	assert_bool(turned).is_true()


func test_a_watcher_at_the_edge_looks_inward() -> void:
	var s := _session(TRAIL)
	var map := {"w": 20, "h": 20}
	for i: int in 20:  # by the left edge: east, a step off at most
		assert_bool(WatchRules.face(s, data, map, "foe%d" % i, Vector2i(0, 10)) in [7, 0, 1]).is_true()
		assert_bool(WatchRules.face(s, data, map, "foe%d" % i, Vector2i(19, 10)) in [3, 4, 5]).is_true()


func test_cones_show_only_while_hiding_and_a_walk_goes_by_rounds() -> void:
	var s := _session(TRAIL)
	var foes := _met(s)
	var map := _map(s)
	var seen := {_at(foes[0]): true}
	assert_dict(WatchRules.cones(s, data, map, seen)).is_empty()
	assert_bool(WatchRules.by_rounds(s, data, map, seen)).is_false()
	s.sneaking = true
	assert_dict(WatchRules.cones(s, data, map, seen)).is_not_empty()
	assert_bool(WatchRules.by_rounds(s, data, map, seen)).is_true()
	assert_bool(WatchRules.by_rounds(s, data, map, {})).is_false()
	assert_int(WatchRules.round_steps(s)).is_equal(int(s.character["speed"]) / 5)


# --- an ambush ------------------------------------------------------------------------------------------------


func test_an_ambush_hides_by_a_roll_and_strikes_close() -> void:
	var s := _session(TRAIL)
	var enc := _enc("t_ambush")
	enc["ambush"] = true
	s.character["passive_perception"] = -50
	EncounterRules.meet(s, data, TRAIL, "pushcha-edge", enc)
	var lk := EncounterRules.lurking(s, TRAIL)
	assert_int((lk["hidden"] as Array).size()).is_equal(2)
	(data["world"]["rooms"][TRAIL] as Dictionary)["encounter"] = enc
	var foes := MapSpots.foes(s, data, _map(s))
	_stand(s, _square(s, foes[0], func(map: Dictionary, at: Vector2i, cell: Vector2i) -> bool:
		return WalkRules.distance(at, cell) == 2 and SightRules.line(map, data["layouts"], at, cell)))
	var w := EncounterRules.watch(s, data, _map(s))
	assert_bool(bool(w["fight"])).is_true()
	assert_bool(bool(w["source"]["hidden"])).is_true()


func test_an_ambush_seen_through_has_no_surprise() -> void:
	var s := _session(TRAIL)
	var enc := _enc("t_ambush2")
	enc["ambush"] = true
	s.character["passive_perception"] = 99
	EncounterRules.meet(s, data, TRAIL, "pushcha-edge", enc)
	assert_array(EncounterRules.lurking(s, TRAIL)["hidden"]).is_empty()


# --- witnesses ------------------------------------------------------------------------------------------------


func test_a_witness_needs_a_line_of_sight() -> void:
	var s := _session("brod-square")
	var map := _map(s)
	var people := MapSpots.of(s, data, map).filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "npc")
	assert_bool(people.is_empty()).is_false()
	var who: Dictionary = people[0]
	var blocked := _square(s, who, func(m: Dictionary, at: Vector2i, cell: Vector2i) -> bool: return not SightRules.line(m, data["layouts"], at, cell))
	var open := _square(s, who, func(m: Dictionary, at: Vector2i, cell: Vector2i) -> bool: return WalkRules.distance(at, cell) in [2, 3] and SightRules.line(m, data["layouts"], at, cell))
	assert_bool(open.x >= 0).is_true()
	_stand(s, open)
	assert_bool(WatchRules.sees_hero(s, data, str(who["id"]))).is_true()
	if blocked.x >= 0:
		_stand(s, blocked)
		assert_bool(WatchRules.sees_hero(s, data, str(who["id"]))).is_false()


func test_while_sneaking_a_back_turned_sees_nothing() -> void:
	var s := _session("brod-square")
	var people := MapSpots.of(s, data, _map(s)).filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "npc")
	var who: Dictionary = people[0]
	s.sneaking = true
	_stand(s, _square(s, who, _in_cone(s, str(who["id"]), false)))
	assert_bool(WatchRules.sees_hero(s, data, str(who["id"]))).is_false()


func test_in_the_dark_a_deed_is_seen_only_up_close() -> void:
	var s := _session(TRAIL)
	assert_int(WatchRules.range_of(s, data, {"monster": "commoner"}, true)).is_equal(int(SightRules.cfg(data)["day"]))
	s.minute = 60
	assert_int(WatchRules.range_of(s, data, {"monster": "commoner"}, true)).is_equal(int(SightRules.cfg(data)["blind"]))


func test_one_absent_from_the_map_still_counts() -> void:
	var s := _session()
	assert_array(WatchRules.eyes(s, data, ["npc_walks_with_the_hero"])).contains_exactly(["npc_walks_with_the_hero"])
	assert_array(WatchRules.eyes(s, data, [])).is_empty()


# --- traps and caches on squares ------------------------------------------------------------------------------


func _yard(s: GameSession, passive: int) -> Dictionary:
	s.character["passive_perception"] = passive
	for sec: Dictionary in ExplorationRules.secrets(data["world"], s.room_id):
		if sec.get("trap") is Dictionary:
			return sec
	return {}


func test_a_trap_lies_before_the_way_it_guards() -> void:
	var s := _session("mine-gallery")
	var sec := _yard(s, 30)
	var map := _map(s)
	var at := MapSpots.secret_cell(s, data, map, s.room_id, sec)
	assert_bool(at.x >= 0).is_true()
	assert_vector(MapSpots.secret_cell(s, data, map, s.room_id, sec)).is_equal(at)
	assert_str(WalkRules.room_of(map, at)).is_equal(s.room_id)


func test_a_trap_is_not_noticed_at_the_door_but_on_the_way() -> void:
	var s := _session("mine-gallery")
	var sec := _yard(s, 30)
	assert_array(ExplorationRules.enter_room(s, data["world"], s.room_id, 0)).is_empty()
	assert_bool(ExplorationRules.is_found(s, s.room_id, sec)).is_false()
	var map := _map(s)
	var at := MapSpots.secret_cell(s, data, map, s.room_id, sec)
	var near := at
	for cell: Vector2i in WalkRules.around(map, data["layouts"], at, 8):
		if SightRules.line(map, data["layouts"], cell, at):
			near = cell
			break
	var far := Vector2i(-1, -1)
	for cell: Vector2i in WalkRules.around(map, data["layouts"], at, 200):
		if WalkRules.distance(cell, at) > int(SightRules.cfg(data)["notice"]):
			far = cell
	assert_array(ExplorationRules.notice(s, data, map, far)).is_empty()
	assert_str(str(ExplorationRules.notice(s, data, map, near))).contains("Замечено")
	assert_array(MapSpots.traps(s, data, map).map(func(t: Dictionary) -> String: return str(t["kind"]))).contains(["trap"])


func test_a_trap_springs_underfoot_only_unknown() -> void:
	var s := _session("mine-gallery")
	var sec := _yard(s, 1)
	var map := _map(s)
	var at := MapSpots.secret_cell(s, data, map, s.room_id, sec)
	assert_str(str(ExplorationRules.trap_at(s, data, map, at).get("id", ""))).is_equal(str(sec["id"]))
	assert_dict(ExplorationRules.trap_at(s, data, map, at + Vector2i(1, 1))).is_empty()
	s.character["passive_perception"] = 30
	ExplorationRules.notice(s, data, map, at)
	assert_dict(ExplorationRules.trap_at(s, data, map, at)).is_empty()


func test_the_last_look_finds_a_trap_on_a_move_that_was_no_walk() -> void:
	var s := _session("mine-gallery")
	var sec := _yard(s, 1)
	assert_str(ExplorationRules.approach(s, data, s.room_id, sec)).is_empty()
	s.character["passive_perception"] = 30
	assert_str(ExplorationRules.approach(s, data, s.room_id, sec)).is_equal(str(sec["text"]))


func test_a_cache_is_taken_on_the_way_past_it() -> void:
	var s := _session("mine-flooded")
	s.character["passive_perception"] = 30
	var sec: Dictionary = ExplorationRules.secrets(data["world"], s.room_id).filter(func(x: Dictionary) -> bool: return x.has("loot"))[0]
	assert_array(ExplorationRules.enter_room(s, data["world"], s.room_id, 0).filter(func(t: String) -> bool: return t == str(sec["text"]))).is_empty()
	var map := _map(s)
	var at := MapSpots.secret_cell(s, data, map, s.room_id, sec)
	var lines := ExplorationRules.notice(s, data, map, at)
	assert_str(str(lines)).contains("Тайник")
	assert_array(ExplorationRules.notice(s, data, map, at)).is_empty()


# --- people behind a door -------------------------------------------------------------------------------------


func test_people_of_another_room_of_the_map_stand_there_too() -> void:
	var s := _session("brod-tavern-kitchen")
	s.visited.append("brod-tavern-hall")
	var map := _map(s)
	for t: Dictionary in MapSpots.others(s, data, map):
		assert_str(str(t["ref"])).starts_with("far:")
		assert_str(WalkRules.room_of(map, _at(t))).is_not_equal(s.room_id)
