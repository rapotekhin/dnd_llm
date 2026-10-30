extends GdUnitTestSuite
## A meeting is not a fight from the doorway, and a lost fight to thinking foes is a captivity (roadmap v0.7.22.12).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset := "rogue_damir") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


func _wolves() -> Dictionary:
	return {"id": "test_wolves", "enemies": [{"monster": "wolf", "count": 2, "name": "Волк"}]}


func _bandits() -> Dictionary:
	return {"id": "test_bandits", "enemies": [{"monster": "bandit", "count": 2, "name": "Разбойник"}]}


func test_not_sneaking_they_see_the_hero() -> void:
	var s := _hero()
	s.sneaking = false
	var m := EncounterRules.meet(s, data, "r1", "r0", _wolves())
	assert_bool(bool(m["lurk"])).is_false()
	assert_int(int(m["stealth"])).is_equal(-1)


func test_sneaking_unseen_no_fight() -> void:
	var s := _hero()
	s.sneaking = true
	s.character["skills"]["stealth"] = 40  # nobody notices this one
	var m := EncounterRules.meet(s, data, "r1", "r0", _wolves())
	assert_bool(bool(m["lurk"])).is_true()
	assert_dict(EncounterRules.lurking(s, "r1")).is_not_empty()
	s.character["skills"]["stealth"] = -40
	s.lurking.clear()
	assert_bool(bool(EncounterRules.meet(s, data, "r1", "r0", _wolves())["lurk"])).is_false()


func test_slipping_past_unseen_passes_the_encounter_back_the_way_in_does_not() -> void:
	var s := _hero()
	s.sneaking = true
	s.character["skills"]["stealth"] = 40
	EncounterRules.meet(s, data, "r1", "r0", _wolves())
	assert_str(EncounterRules.slip_past(s, "r1", "r0")).is_empty()  # turned back — not past them
	assert_bool(QuestRules.met(s, {"encounter": "test_wolves"})).is_false()
	assert_str(EncounterRules.slip_past(s, "r1", "r2")).contains("незамеченными")
	assert_bool(QuestRules.met(s, {"encounter": "test_wolves", "defeat": true})).is_false()  # the step asks them beaten
	assert_bool(QuestRules.met(s, {"all": [{"encounter": "test_wolves"}]})).is_true()
	assert_bool(s.encounters_done.has("test_wolves")).is_false()  # the wolves are still there, not beaten
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_bool(back.encounters_passed.has("test_wolves")).is_true()
	assert_str(EncounterRules.slip_past(s, "r5", "r2")).is_empty()  # no foes lurk there


func test_an_ambush_strikes_anyway() -> void:
	var s := _hero()
	s.sneaking = true
	s.character["skills"]["stealth"] = 40
	var enc := _wolves()
	enc["ambush"] = true
	assert_bool(bool(EncounterRules.meet(s, data, "r1", "r0", enc)["lurk"])).is_false()


func test_wolves_cannot_be_talked_to_bandits_can() -> void:
	var s := _hero()
	assert_str(EncounterRules.talkable(s, data, _wolves()["enemies"])).is_equal("COMBAT_NO_PARLEY")
	assert_str(EncounterRules.talkable(s, data, _bandits()["enemies"])).is_empty()


func test_a_parley_before_the_fight() -> void:
	var s := _hero()
	s.room_id = "r1"
	s.lurking["r1"] = {"encounter": "test_bandits", "from": "r0"}
	s.character["skills"]["persuasion"] = 40
	var r := EncounterRules.parley(s, data, "r1", _bandits(), "persuasion")
	assert_bool(bool(r["fight"])).is_false()
	assert_bool(s.encounters_done.has("test_bandits")).is_true()
	assert_int(CreatureRules.here(s, "r1").size()).is_equal(2)  # a truce — they stay
	s.lurking["r1"] = {"encounter": "test_bandits2", "from": "r0"}
	s.character["skills"]["persuasion"] = -40
	var enc := _bandits()
	enc["id"] = "test_bandits2"
	assert_bool(bool(EncounterRules.parley(s, data, "r1", enc, "persuasion")["fight"])).is_true()
	assert_dict(EncounterRules.lurking(s, "r1")).is_empty()


func test_captivity_and_escape() -> void:
	var s := _hero()
	s.room_id = "r1"
	EncounterRules.capture(s, [{"monster": "bandit", "name": "Разбойник", "count": 1}], "test_bandits", "r0")
	assert_bool(EncounterRules.captive(s)).is_true()
	assert_str(str(EffectEngine.new().validate(s, data, "t-1", {"kind": "move", "room_id": "brod-square"}).get("reason", ""))).contains("плену")
	s.character["skills"]["athletics"] = -40
	var minute := TimeRules.abs_minute(s)
	EncounterRules.escape(s, data, "escape_athletics")
	assert_bool(EncounterRules.captive(s)).is_true()
	assert_int(TimeRules.abs_minute(s)).is_greater(minute)  # a failure costs time
	s.character["skills"]["athletics"] = 40
	var lines := EncounterRules.escape(s, data, "escape_athletics")
	assert_bool(EncounterRules.captive(s)).is_false()
	assert_dict(EncounterRules.lurking(s, "r1")).is_not_empty()  # free and unseen — the captors lurk
	assert_bool(s.sneaking).is_true()
	assert_str(" · ".join(lines)).contains("Путы сброшены")
	var back := GameSession.from_dict(s.to_dict(5))
	assert_dict(back.lurking).is_not_empty()
