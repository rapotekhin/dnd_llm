extends GdUnitTestSuite
## «Последствия и время» (roadmap v0.7.14.1): the menhir's choice changes the Pushcha through the rooms' variants
## by the world's flags — the restored glade is a safe free rest, the taken power empties it and sets wolves on the
## trail; without a flag the pack room stays as it is.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _at(room: String, flag: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	if not flag.is_empty():
		s.flags.append(flag)
	return s


func test_without_a_flag_the_room_is_the_packs() -> void:
	var s := _at("pushcha-glade", "")
	assert_str(str(SceneRules.room(s, data["world"], s.room_id)["description"])).is_equal(str(data["world"]["rooms"]["pushcha-glade"]["description"]))
	assert_array(s.npcs_here(data["world"], s.room_id)).contains_exactly(["npc_hermit"])
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_equal("REST_NOT_SAFE")


func test_the_restored_menhir_lights_the_glade_and_gives_a_free_rest() -> void:
	var s := _at("pushcha-glade", "menhir_restored")
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["scene"]["room_description"])).contains("залитая светом")
	assert_array(s.npcs_here(data["world"], s.room_id)).contains_exactly(["npc_hermit"])
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_empty()
	assert_int(int(ExplorationRules.rest_place(data["world"], s.room_id, s, data)["cost_cp"])).is_equal(0)


func test_the_taken_power_empties_the_glade_and_sets_wolves_on_the_trail() -> void:
	var s := _at("pushcha-glade", "menhir_power")
	assert_array(s.npcs_here(data["world"], s.room_id)).is_empty()
	s.encounters_done.append("trail_wolves")
	var trail := SceneRules.room(s, data["world"], "pushcha-trail")
	assert_str(str(trail["encounter"]["id"])).is_equal("trail_wolves_dark")
	s.room_id = "pushcha-trail"
	assert_str(ExplorationRules.can_camp(s, data)).is_equal("REST_DANGER")
	assert_str(str(SceneRules.room(s, data["world"], "pushcha-edge")["description"])).contains("вой")


func test_a_bad_variant_is_refused_by_the_validator() -> void:
	var w: Dictionary = data["world"].duplicate(true)
	w["rooms"]["pushcha-glade"]["variants"] = [{"description": "без условия"}, {"if_flag": "x", "npcs": ["npc_nobody"]}]
	var errors := WorldPack._validate_world(w, data)
	assert_bool(errors.any(func(e: String) -> bool: return e.contains("вариант"))).is_true()
	assert_bool(errors.any(func(e: String) -> bool: return e.contains("npc_nobody"))).is_true()
