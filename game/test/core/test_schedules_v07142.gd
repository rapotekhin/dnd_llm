extends GdUnitTestSuite
## «Последствия и время» (roadmap v0.7.14.2): NPCs keep hours — the pack's `schedule` moves them by the clock: the
## trader goes home at night, the captain drinks in the tavern in the evening; whoever is away is named for the
## master, a conversation ends when its partner's hour comes.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _at(room: String, hour: int) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.minute = hour * 60
	return s


func test_the_trader_goes_home_at_night() -> void:
	var s := _at("brod-square", 12)
	assert_array(s.npcs_here(data["world"], s.room_id)).contains(["npc_merchant"])
	s.minute = 23 * 60
	assert_array(s.npcs_here(data["world"], s.room_id)).not_contains(["npc_merchant"])
	s.minute = 3 * 60  # past midnight — still away
	assert_array(s.npcs_here(data["world"], s.room_id)).not_contains(["npc_merchant"])
	assert_str(" ".join(SceneRules.absent(s, data["world"], s.room_id))).contains("Ферн Кривой — ушёл домой, вернётся к 7:00")


func test_the_captain_drinks_in_the_tavern_in_the_evening() -> void:
	var s := _at("brod-tavern-hall", 20)
	assert_array(s.npcs_here(data["world"], "brod-tavern-hall")).contains(["npc_captain", "npc_smith"])
	assert_array(s.npcs_here(data["world"], "brod-gate")).not_contains(["npc_captain"])
	s.minute = 22 * 60
	assert_array(s.npcs_here(data["world"], "brod-gate")).contains(["npc_captain"])


func test_the_master_hears_who_is_away() -> void:
	var s := _at("brod-herbalist", 22)
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_array(snap["scene"]["npcs"]).is_empty()
	assert_bool((snap["scene"]["hooks"] as Array).any(func(h: Variant) -> bool: return str(h).contains("Ведана — ушла домой"))).is_true()


func test_a_bad_schedule_is_refused() -> void:
	var w: Dictionary = data["world"].duplicate(true)
	w["npcs"]["npc_merchant"]["schedule"] = [{"from": 25, "to": 7, "room": "nowhere"}]
	assert_bool(WorldPack._validate_world(w, data).any(func(e: String) -> bool: return e.contains("schedule"))).is_true()
