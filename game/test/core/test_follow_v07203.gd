extends GdUnitTestSuite
## NPCs who go with the hero (roadmap v0.7.20.3): talked into it, an NPC follows the hero from room to room; told to
## stay, it stays where it was left; sent home, it is back in its own room. Bug: the master narrated «Бруно идёт с
## тобой», the hero went on, and the next room was empty.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.room_id = "brod-square"
	fx = EffectEngine.new()


func _do(e: Dictionary, turn := "t-1") -> Dictionary:
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_a_won_over_npc_goes_with_the_hero() -> void:
	var r := _do({"kind": "npc_follow", "npc_id": "npc_merchant"})
	assert_str(str(r["reason"])).contains("проверка")  # neither a friend nor won over
	fx.note_check("t-2", "medium", true, "npc_merchant")
	r = _do({"kind": "npc_follow", "npc_id": "npc_merchant"}, "t-2")
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	s.room_id = "brod-gate"
	assert_array(s.npcs_here(data["world"], "brod-gate")).contains(["npc_merchant"])
	assert_array(s.npcs_here(data["world"], "brod-square")).not_contains(["npc_merchant"])
	var snap := TurnSnapshot.build(s, data, 2000)
	var him: Array = snap["scene"]["npcs"].filter(func(n: Dictionary) -> bool: return n["npc_id"] == "npc_merchant")
	assert_bool(bool(him[0]["follows"])).is_true()


func test_a_follower_stays_where_left_or_goes_home() -> void:
	s.attitudes["npc_merchant"] = 2  # a friend comes by asking
	assert_bool(bool(_do({"kind": "npc_follow", "npc_id": "npc_merchant"})["accepted"])).is_true()
	s.room_id = "brod-gate"
	assert_bool(bool(_do({"kind": "npc_follow", "npc_id": "npc_merchant", "follow": false}, "t-2")["accepted"])).is_true()
	s.room_id = "brod-tavern-hall"
	assert_array(s.npcs_here(data["world"], "brod-gate")).contains(["npc_merchant"])
	assert_array(s.npcs_here(data["world"], "brod-tavern-hall")).not_contains(["npc_merchant"])
	s.room_id = "brod-gate"
	assert_bool(bool(_do({"kind": "npc_follow", "npc_id": "npc_merchant", "follow": false, "home": true}, "t-3")["accepted"])).is_true()
	assert_array(s.npcs_here(data["world"], "brod-square")).contains(["npc_merchant"])
	assert_bool(s.npc_at.is_empty() and s.followers.is_empty()).is_true()


func test_followers_survive_a_save() -> void:
	s.attitudes["npc_merchant"] = 3
	_do({"kind": "npc_follow", "npc_id": "npc_merchant"})
	var back := GameSession.from_dict(s.to_dict(5))
	assert_array(back.followers).contains_exactly(["npc_merchant"])
	back.room_id = "brod-smithy"
	assert_array(back.npcs_here(data["world"], "brod-smithy")).contains(["npc_merchant"])
