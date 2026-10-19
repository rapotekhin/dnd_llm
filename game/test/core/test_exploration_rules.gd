extends GdUnitTestSuite
## ExplorationRules and their GameState wiring: check locks, hidden things (passive and active), long rest.

var data: Dictionary
var world: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	world = data["world"]
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)


func _fail_result() -> Dictionary:
	return {"check_id": "c-1", "rolls": [3], "bonus": 1, "total": 4, "dc": 15, "success": false, "nat": 3, "blocked": false}


func test_a_failed_check_is_locked_by_skill_and_target() -> void:
	var params := {"skill": "persuasion", "dc_tier": "medium", "target_id": TestUtils.INNKEEPER}
	assert_dict(ExplorationRules.locked(s, params, s.room_id)).is_empty()
	ExplorationRules.lock(s, params, s.room_id, _fail_result())
	assert_dict(ExplorationRules.locked(s, params, s.room_id)).is_not_empty()
	var other_target := params.duplicate()
	other_target["target_id"] = TestUtils.SERVING
	assert_dict(ExplorationRules.locked(s, other_target, s.room_id)).is_empty()
	var other_skill := params.duplicate()
	other_skill["skill"] = "intimidation"
	assert_dict(ExplorationRules.locked(s, other_skill, s.room_id)).is_empty()


func test_a_new_advantage_reopens_the_check_once() -> void:
	var params := {"skill": "perception", "dc_tier": "medium"}
	ExplorationRules.lock(s, params, s.room_id, _fail_result())
	var with_lamp := params.duplicate()
	with_lamp["advantage_reason"] = "фонарь"
	assert_dict(ExplorationRules.locked(s, with_lamp, s.room_id)).is_empty()
	ExplorationRules.lock(s, with_lamp, s.room_id, _fail_result())
	assert_dict(ExplorationRules.locked(s, with_lamp, s.room_id)).is_not_empty()  # the lamp is used up


func test_successes_and_saves_are_not_locked() -> void:
	var win := _fail_result()
	win["success"] = true
	ExplorationRules.lock(s, {"skill": "stealth", "dc_tier": "easy"}, s.room_id, win)
	ExplorationRules.lock(s, {"save": "dex", "dc_tier": "easy"}, s.room_id, _fail_result())
	assert_dict(s.locks).is_empty()


func test_passive_perception_notices_on_entering() -> void:
	# Айра: passive Perception 13. The cellar: tracks DC 12 (perception), tunnel DC 15 (investigation).
	var noticed := ExplorationRules.enter_room(s, world, "brod-tavern-cellar")
	assert_array(noticed).has_size(1)
	assert_str(noticed[0]).contains("следы")
	assert_array(s.visited).contains(["brod-tavern-cellar"])
	assert_array(ExplorationRules.enter_room(s, world, "brod-tavern-cellar")).is_empty()  # once


func test_investigation_finds_what_perception_would_notice() -> void:
	ExplorationRules.enter_room(s, world, "brod-tavern-kitchen")  # the new bolt: DC 13, perception; passive 13 notices it
	s.revealed.clear()
	assert_array(ExplorationRules.active_reveal(s, world, "investigation", 13)).has_size(1)


func test_active_search_finds_only_its_skill_and_dc() -> void:
	ExplorationRules.enter_room(s, world, "brod-tavern-cellar")
	assert_array(ExplorationRules.active_reveal(s, world, "perception", 20)).is_empty()  # the tunnel needs Investigation
	assert_array(ExplorationRules.active_reveal(s, world, "investigation", 14)).is_empty()
	var found := ExplorationRules.active_reveal(s, world, "investigation", 15)
	assert_str(found[0]).contains("лаз")
	assert_array(ExplorationRules.found_texts(s, world, "brod-tavern-cellar")).has_size(2)
	var snap := TurnSnapshot.build(s, data, 4000)
	assert_array(snap["scene"]["found"]).has_size(2)


func test_long_rest_only_in_safe_rooms_and_for_the_price() -> void:
	assert_str(ExplorationRules.can_rest(s, world)).is_equal("REST_NOT_SAFE")
	ExplorationRules.enter_room(s, world, "brod-tavern-upstairs")
	assert_str(ExplorationRules.can_rest(s, world)).is_empty()
	s.character["gold_cp"] = 10
	assert_str(ExplorationRules.can_rest(s, world)).is_equal("REST_NO_MONEY")
	ExplorationRules.enter_room(s, world, "brod-temple")
	assert_str(ExplorationRules.can_rest(s, world)).is_empty()  # the temple is free
	s.mode = GameSession.MODE_SOCIAL
	assert_str(ExplorationRules.can_rest(s, world)).is_equal("REST_IN_CONVERSATION")


func test_long_rest_restores_and_clears_locks() -> void:
	ExplorationRules.enter_room(s, world, "brod-tavern-upstairs")
	s.character["hp"] = 3
	s.character["slots_used"] = [1, 0, 0, 0, 0]
	ExplorationRules.lock(s, {"skill": "perception", "dc_tier": "hard"}, s.room_id, _fail_result())
	var gold := int(s.character["gold_cp"])
	var lines := ExplorationRules.long_rest(s, data)
	assert_int(s.character["hp"]).is_equal(int(s.character["max_hp"]))
	assert_array(s.character["slots_used"]).is_equal([0, 0, 0, 0, 0])
	assert_dict(s.locks).is_empty()
	assert_int(s.character["gold_cp"]).is_equal(gold - 50)
	assert_int(s.day).is_equal(2)
	assert_str(" ".join(lines)).contains("5 см")


func test_every_room_of_the_start_pack_has_a_secret() -> void:
	for room_id: String in world["rooms"]:
		assert_array(ExplorationRules.secrets(world, room_id)).override_failure_message(room_id).is_not_empty()


func test_locks_and_secrets_survive_a_save() -> void:
	ExplorationRules.enter_room(s, world, "brod-tavern-cellar")
	ExplorationRules.lock(s, {"skill": "perception", "dc_tier": "hard"}, s.room_id, _fail_result())
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_dict(back.locks).is_equal(s.locks)
	assert_dict(back.revealed).is_equal(s.revealed)
	assert_array(back.visited).is_equal(s.visited)
	assert_int(int(back.locks.values()[0]["result"]["total"])).is_equal(4)
