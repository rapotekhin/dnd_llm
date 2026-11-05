extends GdUnitTestSuite
## One road, review 2, group M (v0.8.4.29.6): a creature's acts by `can` alone, a scroll's numbers for the cast and its window,
## the scope of a thing's cast taken back, one attitude word.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession, state: String) -> Dictionary:
	return CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": state, "bound": false, "led": false, "since": 0, "hp": 7, "max_hp": 7})


func _whats(s: GameSession, c: Dictionary) -> Array:
	return CreatureRules.acts(s, data, c).map(func(a: Array) -> String: return str(a[0]))


func test_the_panel_offers_only_what_can_allows() -> void:
	var s := TestUtils.new_session()
	for state: String in ["surrendered", "truce", "unconscious", PetRules.WILD, CreatureRules.DEAD]:
		var c := _goblin(s, state)
		for a: Array in CreatureRules.acts(s, data, c):
			assert_str(CreatureRules.can(s, str(c["id"]), str(a[0]), data)).is_empty()
		for what: String in ["talk", "tame", "bind", "free", "attack", "finish", "search", "hide"]:
			if not _whats(s, c).has(what):
				assert_str(CreatureRules.can(s, str(c["id"]), what, data)).is_not_empty()


func test_a_wild_beast_is_neither_bound_nor_talked_to_nor_freed() -> void:
	var s := TestUtils.new_session()
	var c := _goblin(s, PetRules.WILD)
	var id := str(c["id"])
	assert_str(CreatureRules.can(s, id, "bind", data)).is_not_empty()
	assert_str(CreatureRules.can(s, id, "talk", data)).is_equal("CREATURE_CANNOT_TALK")
	assert_str(CreatureRules.can(s, id, "free", data)).is_equal("CREATURE_CANNOT_FREE")


func test_one_knocked_out_does_not_talk() -> void:
	var s := TestUtils.new_session()
	var c := _goblin(s, "unconscious")
	assert_bool(_whats(s, c).has("talk")).is_false()
	assert_str(CreatureRules.can(s, str(c["id"]), "talk", data)).is_equal("CREATURE_CANNOT_TALK")


func test_a_scroll_casts_and_shows_by_one_set_of_numbers() -> void:
	var item := ""
	for id: String in data["items"]["catalog"]:
		var fx: Dictionary = ItemRules.consumable(data, id, {})
		if not str(fx.get("spell", "")).is_empty() and not fx.has("dc"):
			item = id
			break
	assert_str(item).is_not_empty()
	var c := TestUtils.character()
	c["spell_ability"] = "wis"
	var by := ItemRules.spell_numbers(c, data, {}, item)
	var nums := ItemRules.scroll_numbers(data, int(by["level"]))
	assert_int(int(by["dc"])).is_equal(int(nums[0]))
	assert_int(int(by["attack"])).is_equal(int(nums[1]))
	assert_str(str(by["ability"])).is_equal("wis")
	c.erase("spell_ability")
	assert_str(str(ItemRules.spell_numbers(c, data, {}, item)["ability"])).is_equal("int")


func test_a_things_cast_scope_is_taken_back() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 1}])
	var me := CombatRules.player(s)
	var seen: Dictionary = ActionRules.as_by(s, data, me, "fire_bolt", {"dc": 17, "attack": 9, "ability": "int", "level": 3},
		func() -> Dictionary: return (s.combat["by"] as Dictionary).duplicate())
	assert_int(int(seen["dc"])).is_equal(17)
	assert_bool(s.combat.has("by")).is_false()
	s.combat["by"] = {"dc": 11}
	ActionRules.as_by(s, data, me, "fire_bolt", {"dc": 17, "attack": 9, "ability": "int"}, func() -> int: return 0)
	assert_int(int(s.combat["by"]["dc"])).is_equal(11)


func test_one_attitude_word_within_the_range() -> void:
	var r := GameSession.attitude_bounds(data)
	assert_str(GameSession.attitude_word(data, r.y + 5)).is_equal(GameSession.attitude_word(data, r.y))
	assert_str(GameSession.attitude_word(data, r.x - 5)).is_equal(GameSession.attitude_word(data, r.x))
	assert_str(GameSession.attitude_word(data, 0)).is_equal(TranslationServer.translate("ATTITUDE_0"))
