extends GdUnitTestSuite
## v0.8.4.44.8, what the tutorial played end to end found: a potion at hand is drunk by a double click in the pack, as the
## screen «Рана» teaches (the belt's cell and the pack's grid share one «Использовать», ItemActs.use_row).


func test_a_potion_at_hand_is_drunk_from_the_pack() -> void:
	var data := TestUtils.data()
	var s := ChecklistProbe.session(data)
	Gear.give(s, data, Being.HERO, "healing_potion", 2)
	assert_bool(ItemRules.on_belt(s.character, data, s.items, "healing_potion")).is_true()
	var main := ItemActs.main(ItemActs.of(s, data, Being.HERO, "healing_potion"))
	assert_str(str(main.get("act", ""))).is_equal("use")
	assert_str(str(main["why"])).is_empty()


func test_a_thing_off_the_belt_is_put_on_it_first() -> void:
	var data := TestUtils.data()
	var s := ChecklistProbe.session(data)
	Gear.give(s, data, Being.HERO, "healing_potion", 1)
	s.character["belt"] = ["", "", "", "", ""]
	var acts: Array = ItemActs.of(s, data, Being.HERO, "healing_potion").map(func(r: Dictionary) -> String: return str(r["act"]))
	assert_array(acts).contains(["belt"])
	assert_array(acts).not_contains(["use"])
