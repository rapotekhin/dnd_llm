extends GdUnitTestSuite
## Needs (v0.7.23): food and water empty over the game clock, stages hamper saves, an empty need past its grace
## gives exhaustion (the scale itself takes a day to empty); eating, drinking, the waterskin, the long rest's meal, the paid meal, the setting.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.character["inventory"].erase("rations")
	s.character["inventory"].erase("bread")
	s.character["inventory"].erase("goodberry")
	NeedRules.state(s, data)
	return s


func test_food_and_water_empty_over_the_clock() -> void:
	var s := _session()
	assert_float(NeedRules.value(s, data, "food")).is_equal(100.0)
	s.minute += 12 * 60
	s.rested_at = TimeRules.abs_minute(s)
	assert_float(NeedRules.value(s, data, "food")).is_equal_approx(50.0, 0.5)
	assert_float(NeedRules.value(s, data, "water")).is_equal_approx(50.0, 0.5)
	assert_bool(NeedRules.stage(s, data, "food").is_empty()).is_true()
	s.minute += 60
	assert_str(str(NeedRules.stage(s, data, "food")["chip"])).is_equal("Голоден")


func test_a_low_stage_hampers_constitution_saves() -> void:
	var s := _session()
	NeedRules.set_value(s, data, "food", 10.0)
	NeedRules.tick(s, data)
	assert_str(str(s.character["need_mods"].get("con", ""))).is_equal("disadvantage")
	NeedRules.set_value(s, data, "food", 90.0)
	assert_bool((s.character["need_mods"] as Dictionary).has("con")).is_false()


func test_thirst_gives_exhaustion_after_a_day_at_zero() -> void:
	var s := _session()
	var before := int(s.character.get("exhaustion", 0))
	NeedRules.set_value(s, data, "water", 0.0)
	assert_array(NeedRules.tick(s, data)).is_empty()  # a day without water already passed while it emptied
	s.day += 1
	NeedRules.tick(s, data)
	assert_int(int(s.character.get("exhaustion", 0))).is_equal(before + 1)
	NeedRules.tick(s, data)  # the same day is not counted twice
	assert_int(int(s.character.get("exhaustion", 0))).is_equal(before + 1)


func test_hunger_bears_three_days_plus_constitution() -> void:
	var s := _session()
	var g := NeedRules.grace(s.character, data, "food")
	assert_int(g).is_equal(maxi(1, 3 + CharacterRules.mod(CharacterRules.ability(s.character, "con"))))
	var before := int(s.character.get("exhaustion", 0))
	NeedRules.set_value(s, data, "food", 0.0)
	s.day += g - 1
	NeedRules.set_value(s, data, "water", 100.0)  # only hunger here
	NeedRules.tick(s, data)
	assert_int(int(s.character.get("exhaustion", 0))).is_equal(before)
	s.day += 1
	NeedRules.set_value(s, data, "water", 100.0)
	NeedRules.tick(s, data)
	assert_int(int(s.character.get("exhaustion", 0))).is_equal(before + 1)


func test_eating_takes_the_cheapest_food_first() -> void:
	var s := _session()
	assert_str(NeedRules.can_eat(s, data)).is_equal("NEED_NO_FOOD")
	s.character["inventory"]["rations"] = 1
	s.character["inventory"]["bread"] = 1
	assert_str(NeedRules.can_eat(s, data)).is_equal("NEED_NOT_HUNGRY")
	NeedRules.set_value(s, data, "food", 40.0)
	NeedRules.eat(s, data)
	assert_int(int(s.character["inventory"].get("bread", 0))).is_equal(0)
	assert_int(int(s.character["inventory"].get("rations", 0))).is_equal(1)
	assert_float(NeedRules.value(s, data, "food")).is_equal_approx(90.0, 0.5)


func test_drinking_from_the_skin_and_filling_it_at_a_source() -> void:
	var s := _session()
	s.character["inventory"]["waterskin"] = 1
	s.character["vessels"] = {}
	NeedRules.set_value(s, data, "water", 20.0)
	s.room_id = "brod-gate"
	assert_bool(NeedRules.water_here(s, data)).is_false()
	assert_str(NeedRules.can_drink(s, data)).is_equal("NEED_NO_WATER")
	assert_str(NeedRules.can_fill(s, data)).is_equal("NEED_NO_SOURCE")
	s.room_id = "brod-square"
	assert_bool(NeedRules.water_here(s, data)).is_true()
	NeedRules.fill(s, data)
	assert_float(NeedRules.drinks(s, data)).is_equal(NeedRules.capacity(s.character, data))
	s.room_id = "brod-gate"
	NeedRules.drink(s, data)
	assert_float(NeedRules.value(s, data, "water")).is_greater_equal(75.0)
	assert_float(NeedRules.drinks(s, data)).is_less(NeedRules.capacity(s.character, data))


func test_a_bed_feeds_and_a_camp_eats_its_supplies() -> void:
	var s := _session()
	NeedRules.set_value(s, data, "food", 10.0)
	NeedRules.set_value(s, data, "water", 10.0)
	NeedRules.rest_meal(s, data, 0, true)
	assert_float(NeedRules.value(s, data, "food")).is_equal(100.0)
	assert_float(NeedRules.value(s, data, "water")).is_equal(100.0)
	NeedRules.set_value(s, data, "food", 10.0)
	NeedRules.set_value(s, data, "water", 10.0)
	s.room_id = "brod-gate"
	s.character["vessels"] = {}
	NeedRules.rest_meal(s, data, 1, false)
	assert_float(NeedRules.value(s, data, "food")).is_equal_approx(60.0, 0.5)
	assert_float(NeedRules.value(s, data, "water")).is_equal_approx(10.0, 0.5)  # no source, no skin


func test_the_inn_sells_a_meal() -> void:
	var s := _session()
	NeedRules.set_value(s, data, "food", 30.0)
	NeedRules.meal(s, data)
	assert_float(NeedRules.value(s, data, "food")).is_equal(100.0)
	assert_str(str(data["rules"]["item_rules"]["services"]["meal"]["op"])).is_equal("meal")


func test_off_the_needs_show_nothing_and_hamper_nothing() -> void:
	var s := _session()
	NeedRules.set_value(s, data, "food", 5.0)
	NeedRules.tick(s, data)
	assert_array(NeedRules.shown(s, data)).is_not_empty()
	s.settings["needs"] = false
	assert_array(NeedRules.tick(s, data)).is_empty()
	assert_array(NeedRules.shown(s, data)).is_empty()
	assert_bool((s.character["need_mods"] as Dictionary).is_empty()).is_true()


func test_the_needs_survive_a_save() -> void:
	var s := _session()
	NeedRules.set_value(s, data, "food", 42.5)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_str(JSON.stringify(back.character["needs"])).is_equal(JSON.stringify(s.character["needs"]))
