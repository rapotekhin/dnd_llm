extends GdUnitTestSuite
## The roll's breakdown (v0.7.39.5, the author: «весь функционал игры, только в чате»): the sheet's numbers are the
## sums of their labelled parts for every ready-made hero and a hero with items and spells; every roll of the rules
## notes its parts with no unlabeled remainder; the chat line takes the notes; the card shows the parts.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _rich() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	var c := s.character
	for id: String in ["cloak_of_protection", "stone_of_good_luck", "thieves_tools", "herbalism_kit"]:
		c["inventory"][id] = 1
	c["attuned"] = ["cloak_of_protection", "stone_of_good_luck"]
	c["equipped"][CharacterRules.wear_slot(ItemRules.def_of(data["items"], {}, "cloak_of_protection"), data)] = "cloak_of_protection"
	c["expertise"] = ["athletics"]
	c["features"].append("jack_of_all_trades")
	c["tools"] = ["thieves_tools", "herbalism_kit"]
	ConditionRules.effects(c).append({"uid": 99, "skill_bonus": {"stealth": 10}, "source": {"name": "Бесследное передвижение"}})
	CharacterRules.refresh(c, data, s.items)
	return s


func _labels(parts: Array) -> Array:
	return parts.map(func(p: Dictionary) -> String: return str(p["label"]))


func test_the_sheet_is_the_sum_of_its_parts() -> void:
	var heroes: Array[Dictionary] = [_rich().character]
	for p: Dictionary in data["presets"]:
		heroes.append(CharacterBuilder.build_preset(p, data))
	for c: Dictionary in heroes:
		for id: String in data["rules"]["skills"]:
			assert_int(RollParts.sum(RollParts.sheet(c, data, "skill", id))).override_failure_message("%s %s" % [c["name"], id]).is_equal(int(c["skills"][id]))
		for ab: String in CharacterRules.ABILITIES:
			assert_int(RollParts.sum(RollParts.sheet(c, data, "save", ab))).override_failure_message("%s save %s" % [c["name"], ab]).is_equal(int(c["saves"][ab]))


func test_the_parts_name_their_sources() -> void:
	var s := _rich()
	var c := s.character
	assert_array(_labels(RollParts.sheet(c, data, "skill", "athletics", s.items))).contains(["компетентность (двойное владение)", "Камень удачи"])
	assert_array(_labels(RollParts.sheet(c, data, "skill", "stealth", s.items))).contains(["Бесследное передвижение"])
	assert_array(_labels(RollParts.sheet(c, data, "skill", "arcana", s.items))).contains(["мастер на все руки (½ владения)"])
	assert_array(_labels(RollParts.sheet(c, data, "save", "con", s.items))).contains(["Плащ защиты", "Камень удачи"])
	assert_int(int(c["saves"]["con"])).is_equal(CharacterRules.save_bonus(c, data, "con") + 2)  # the stone and the cloak (DMG)


func test_every_rule_roll_is_labelled_and_reaches_the_chat_line() -> void:
	var s := _rich()
	s.settings["difficulty"] = "easy"
	var before := RollParts.unlabeled
	EncounterRules.roll(s, data, "persuasion", 12)
	HeroDefense.save(s, data, "con", 12)
	CombatRules.stealth_roll(s, data)
	BondRules.confess(s, data, "npc_innkeeper")
	SiteRules.ask(s, data, "npc_innkeeper")
	s.room_id = "brod-forest-edge" if WorldView.new(data["world"]).room("brod-forest-edge").size() > 0 else s.room_id
	CraftRules.gather(s, data, "herbs")
	JobRules.state(s.character)["serve_tables"] = {"rank": 0, "good": 0, "shifts": 0}
	JobRules.shift(s, data, "serve_tables", JobRules.hours(s, data, "serve_tables") * 60)
	assert_int(s.roll_notes.size()).is_equal(7)
	assert_int(RollParts.unlabeled).is_equal(before)
	for r: Dictionary in s.roll_notes:
		assert_int(int(r["total"])).is_equal(int(r["nat"]) + RollParts.sum(r["parts"]))
		assert_array(_labels(r["parts"])).not_contains([RollParts.OTHER])
	assert_array(_labels(s.roll_notes[0]["parts"])).contains(["сложность «%s»" % DifficultyRules.cfg(data)["levels"][DifficultyRules.level(s, data)]["name"]])
	assert_str(str(s.roll_notes[5]["what"])).is_equal("Собрать травы")  # skilled with the kit too: advantage, not a bonus (XGtE)
	assert_int(s.roll_notes[5]["rolls"].size()).is_equal(2)
	var e := GameSession.effect_entry(["x"])
	e["rolls"] = s.roll_notes.duplicate()
	assert_str(RollParts.entry_text(e)).contains("Камень удачи").contains("против Сл 12")


func test_a_fight_keeps_its_rolls_to_its_log() -> void:
	var s := _rich()
	s.combat = {"active": true}
	if CombatRules.active(s):
		HeroDefense.save(s, data, "dex", 10)
		assert_bool(s.roll_notes.is_empty()).is_true()


func test_a_remainder_is_named_and_counted() -> void:
	var before := RollParts.unlabeled
	var parts: Array[Dictionary] = [RollParts.part("Сила", 3)]
	var fit := RollParts.fit(parts, 5)
	assert_array(_labels(fit)).contains([RollParts.OTHER])
	assert_int(RollParts.unlabeled).is_equal(before + 1)
	RollParts.unlabeled = before


func test_the_card_shows_the_breakdown() -> void:
	var e := {"rolls": [14, 7], "nat": 14, "total": 19, "dc": 15, "parts": [RollParts.part("Харизма", 3), RollParts.part("владение навыком", 2)]}
	var t := CheckCard.breakdown(e)
	assert_str(t).contains("к20 14 (14, 7)").contains("+3 Харизма").contains("+2 владение навыком").contains("= 19 против Сл 15")
	assert_str(CheckCard.breakdown({"nat": 3})).is_empty()
