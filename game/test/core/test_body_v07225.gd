extends GdUnitTestSuite
## Age, build and height (the author's request, v0.7.22.5): words the engine picks from its lists, their own for men
## and women; the same for the same person; what the pack or the master set stays; the master and the sheet see them.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_the_same_person_keeps_the_same_body() -> void:
	var a := BodyRules.make(data, "male", {}, "hero:Торин", true)
	assert_dict(a).is_equal(BodyRules.make(data, "male", {}, "hero:Торин", true))
	for k: String in BodyRules.KEYS:
		assert_str(str(a[k])).is_not_empty()


func test_lists_by_gender_and_grown_up_heroes() -> void:
	for i in 60:
		var f := BodyRules.make(data, "female", {}, "f%d" % i, true)
		assert_bool(["wiry", "stocky"].has(str(f["build"]))).is_false()  # no female word
		assert_bool(["child", "teen", "elderly", "old"].has(str(f["age"]))).is_false()  # a hero: grown-up, not old
		var m := BodyRules.make(data, "male", {}, "m%d" % i)
		assert_bool(["slender", "curvy"].has(str(m["build"]))).is_false()
		assert_bool(["child", "teen"].has(str(m["age"]))).is_false()  # only when set
	assert_str(BodyRules.text(data, {"age": "young", "build": "thin", "height": "tall"}, "female")).is_equal("молодая, худая, высокая")
	assert_str(BodyRules.text(data, {"age": "old", "build": "heavy", "height": "short"}, "male")).is_equal("старик, грузный, невысокий")


func test_a_set_body_stays() -> void:
	var b := BodyRules.npc(data, "npc_x", {"gender": "male", "age": "child"})
	assert_str(str(b["age"])).is_equal("child")
	assert_str(str(BodyRules.check(data, {"build": "huge"}).get("reason", ""))).contains("build")
	assert_dict(BodyRules.check(data, {"age": "teen", "height": "short"})).is_equal({"age": "teen", "height": "short"})


func test_the_hero_and_the_npcs_have_a_body_for_the_master() -> void:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	assert_str(str(s.character["body"]["build"])).is_not_empty()
	s.room_id = "brod-tavern-hall"
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"]["body"])).is_not_empty()
	assert_bool((snap["scene"]["npcs"] as Array).all(func(n: Dictionary) -> bool: return str(n["body"]).count(",") == 2)).is_true()


func test_an_old_save_gets_a_body() -> void:
	var s := TestUtils.new_session()
	s.character["body"] = {}
	CharacterRules.refresh(s.character, data, s.items)
	assert_bool((s.character["body"] as Dictionary).has("height")).is_true()
	var back := GameSession.from_dict(s.to_dict(5))
	assert_dict(back.character["body"]).is_equal(s.character["body"])
