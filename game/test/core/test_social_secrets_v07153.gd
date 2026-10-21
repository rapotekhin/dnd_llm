extends GdUnitTestSuite
## «Социальный режим 2.0» (roadmap v0.7.15.3): an NPC secret is knowledge behind a price — a won social check with
## the total it needs or the attitude it needs; told, it reveals a room secret or sets a flag and stays in the NPC's
## memory. A hostile NPC will not talk; a close friend offers help.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_a_won_check_pays_for_the_secret() -> void:
	var s := _hero("brod-tavern-kitchen")
	assert_array(SocialRules.reveal_by_check(s, data, "npc_cook", "persuasion", 11)).is_empty()  # dc 12
	assert_array(SocialRules.reveal_by_check(s, data, "npc_cook", "deception", 20)).is_empty()  # not a skill of it
	var told := SocialRules.reveal_by_check(s, data, "npc_cook", "intimidation", 12)
	assert_str(" ".join(told)).contains("лаз контрабандистов")
	assert_array(s.revealed.get("brod-tavern-cellar", [])).contains(["tunnel"])
	assert_str(" ".join(s.memory_of("npc_cook"))).contains("рассказал герою тайну")
	assert_array(SocialRules.reveal_by_check(s, data, "npc_cook", "persuasion", 20)).is_empty()  # once


func test_goodwill_tells_it_by_an_effect_and_opens_the_way() -> void:
	var s := _hero("brod-herbalist")
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "reveal_secret", "npc_id": "npc_herbalist", "secret_id": "hollow"})
	assert_str(str(r["reason"])).contains("не доверяет")
	s.attitudes["npc_herbalist"] = 2
	r = fx.validate(s, data, "t-2", {"kind": "reveal_secret", "npc_id": "npc_herbalist", "secret_id": "hollow"})
	assert_str(str(r["summary"])).contains("мёртвым дубом")
	fx.apply(s, "t-2", [r["effect_id"]])
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-hollow")).contains(["pushcha-burrow"])
	assert_str(str(fx.validate(s, data, "t-3", {"kind": "reveal_secret", "npc_id": "npc_herbalist", "secret_id": "nope"})["reason"])).contains("нет тайны")


func test_the_master_sees_only_hints_of_untold_secrets() -> void:
	var s := _hero("brod-tavern-kitchen")
	var cook: Dictionary = (TurnSnapshot.build(s, data, 2000)["scene"]["npcs"] as Array)[0]
	assert_str(str(cook["secrets"])).contains("[cellar]").contains("нервничает").not_contains("контрабандистов")
	SocialRules.reveal_by_check(s, data, "npc_cook", "persuasion", 15)
	cook = (TurnSnapshot.build(s, data, 2000)["scene"]["npcs"] as Array)[0]
	assert_array(cook["secrets"]).is_empty()


func test_attitude_thresholds() -> void:
	var s := _hero("brod-tavern-kitchen")
	s.attitudes["npc_cook"] = -3
	assert_bool(SocialRules.refuses(s, data, "npc_cook")).is_true()
	s.attitudes["npc_cook"] = 3
	assert_bool(SocialRules.refuses(s, data, "npc_cook")).is_false()
	var cook: Dictionary = (TurnSnapshot.build(s, data, 2000)["scene"]["npcs"] as Array)[0]
	assert_bool(bool(cook["eager"])).is_true()


func test_old_saves_know_no_secrets() -> void:
	var v25 := {"save_version": 25, "session": {}}
	SaveFormat._v25_to_v26(v25, {})
	assert_array(v25["session"]["secrets_told"]).is_empty()
	var s := _hero("brod-tavern-kitchen")
	SocialRules.reveal_by_check(s, data, "npc_cook", "persuasion", 15)
	assert_bool(SocialRules.told(GameSession.from_dict(s.to_dict(10)), "npc_cook", "cellar")).is_true()
