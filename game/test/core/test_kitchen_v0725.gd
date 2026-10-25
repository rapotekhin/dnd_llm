extends GdUnitTestSuite
## The kitchen (v0.7.25): simple dishes anyone cooks at a fire, the complex ones with cook's utensils; a dish feeds
## better than a ration and gives water, temporary HP or a boon; fresh food spoils by the clock; meat from beasts,
## mushrooms and berries from the Pushcha.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _cook(proficient: bool = false) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = true
	var c := s.character
	c["tools"] = ["cooks_utensils"] if proficient else []
	c["inventory"].erase("cooks_utensils")
	if proficient:
		c["inventory"]["cooks_utensils"] = 1
	s.room_id = "pushcha-trail"
	s.minute = 12 * 60
	return s


func test_simple_dishes_for_anyone_the_rest_with_the_utensils() -> void:
	var s := _cook()
	var known := CraftRules.known(s, data)
	assert_array(known).contains(["roast_meat", "stew"])
	assert_array(known).not_contains(["hunters_stew", "mushroom_soup", "jerky"])
	assert_array(CraftRules.known(_cook(true), data)).contains(["hunters_stew", "mushroom_soup", "jerky"])


func test_a_fire_in_the_wild_or_a_hearth_not_the_square() -> void:
	var s := _cook()
	s.character["inventory"]["raw_meat"] = 1
	assert_str(CraftRules.why_not(s, data, "roast_meat")).is_empty()
	s.room_id = "brod-square"
	assert_str(CraftRules.why_not(s, data, "roast_meat")).is_equal("CRAFT_NO_STATION")
	s.room_id = "brod-tavern-kitchen"
	assert_str(CraftRules.why_not(s, data, "roast_meat")).is_empty()


func test_a_roast_in_half_an_hour_without_the_tool() -> void:
	var s := _cook()
	s.character["inventory"]["raw_meat"] = 1
	CraftRules.start(s, data, "roast_meat")
	assert_int(int(CraftRules.project(s.character)["total"])).is_equal(30)
	assert_int(CraftRules.shift_minutes(s, data, 1)).is_equal(30)
	CraftRules.worked(s, data, 30)
	assert_int(int(s.character["inventory"].get("roast_meat", 0))).is_between(1, 2)  # a good roast — more
	assert_bool(s.character["inventory"].has("raw_meat")).is_false()


func test_the_proficiency_adds_only_when_proficient() -> void:
	var plain := CraftRules.bonus(_cook(), data, "cooks_utensils")
	assert_int(CraftRules.bonus(_cook(true), data, "cooks_utensils")).is_equal(plain + CharacterRules.prof_bonus(_cook().character, data))


func test_a_hunters_stew_feeds_waters_and_steels() -> void:
	var s := _cook()
	NeedRules.set_value(s, data, "food", 10.0)
	NeedRules.set_value(s, data, "water", 10.0)
	s.character["temp_hp"] = 0
	s.character["inventory"]["hunters_stew"] = 1
	assert_str(ItemRules.can_use(s.character, data, s.items, "hunters_stew")).is_empty()
	var lines := ItemRules.use(s.character, data, s.items, "hunters_stew", s.rng, s)
	assert_int(roundi(NeedRules.value(s, data, "food"))).is_equal(100)
	assert_int(roundi(NeedRules.value(s, data, "water"))).is_equal(30)
	assert_int(int(s.character["temp_hp"])).is_equal(5)
	assert_str(" ".join(lines)).contains("временные хиты: 5")


func test_a_mushroom_soup_helps_against_poison() -> void:
	var s := _cook()
	s.character["inventory"]["mushroom_soup"] = 1
	ItemRules.use(s.character, data, s.items, "mushroom_soup", s.rng, s)
	var boon := ConditionRules.effects(s.character).filter(func(e: Dictionary) -> bool: return str(e.get("adv_tag", "")) == "poison")
	assert_array(boon).has_size(1)


func test_eating_takes_what_spoils_first() -> void:
	var s := _cook()
	NeedRules.set_value(s, data, "food", 40.0)
	s.character["inventory"]["rations"] = 2
	s.character["inventory"]["stew"] = 1
	var lines := NeedRules.eat(s, data)
	assert_bool(s.character["inventory"].has("stew")).is_false()
	assert_int(int(s.character["inventory"]["rations"])).is_equal(2)
	assert_str(lines[0]).contains("Похлёбка")


func test_fresh_food_spoils_oldest_first() -> void:
	var s := _cook()
	var inv: Dictionary = s.character["inventory"]
	inv["raw_meat"] = 2
	FoodRules.tick(s, data)
	TimeRules.advance(s, data, 1440)
	inv["raw_meat"] = 3
	FoodRules.tick(s, data)
	assert_int(FoodRules.days_left(s, data, "raw_meat")).is_equal(1)
	var lines := TimeRules.advance(s, data, 1440)
	assert_str(" ".join(lines)).contains("Испортилось: Сырое мясо ×2")
	assert_int(int(inv["raw_meat"])).is_equal(1)
	assert_int(int(inv["spoiled_food"])).is_equal(2)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_int(FoodRules.days_left(back, data, "raw_meat")).is_equal(1)


func test_nothing_spoils_with_the_needs_off() -> void:
	var s := _cook()
	s.settings["needs"] = false
	s.character["inventory"]["raw_meat"] = 1
	TimeRules.advance(s, data, 5 * 1440)
	assert_int(int(s.character["inventory"].get("raw_meat", 0))).is_equal(1)


func test_spoiled_food_risks_a_disease() -> void:
	var s := _cook()
	s.character["inventory"]["spoiled_food"] = 1
	var lines := ItemRules.use(s.character, data, s.items, "spoiled_food", s.rng, s)
	assert_str(" ".join(lines)).contains("Дурная еда")


func test_a_dead_wolf_leaves_meat_and_the_pushcha_gives_mushrooms_or_berries() -> void:
	assert_int(CraftRules.meat(data, data["monsters"]["wolf"])).is_equal(2)
	assert_int(CraftRules.meat(data, data["monsters"]["goblin"])).is_equal(0)
	var s := _cook()
	s.room_id = "pushcha-glade"
	assert_array(CraftRules.gather_here(s, data)).contains(["forage"])
	s.character["skills"]["survival"] = 30
	CraftRules.gather(s, data, "forage")
	var inv: Dictionary = s.character["inventory"]
	assert_int(int(inv.get("mushrooms", 0)) + int(inv.get("berries", 0))).is_between(1, 3)


func test_the_master_makes_a_dish_at_the_fire() -> void:
	var s := _cook(true)
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "recipe", "tool": "cooks_utensils", "station": "fire", "hours": 1, "dc_tier": "easy",
		"materials": [{"item_id": "raw_meat", "qty": 1}, {"item_id": "berries", "qty": 1}], "output": {"name": "Мясо в ягодном соусе",
		"item_type": "consumable", "rarity": "common", "value_cp": 30, "description": "Жареное мясо с кислым ягодным соусом."}})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()


func test_a_dish_is_not_taken_apart() -> void:
	var s := _cook()
	s.character["inventory"]["roast_meat"] = 1
	s.character["inventory"]["rations"] = 1
	assert_array(CraftRules.salvageable(s, data)).not_contains(["roast_meat", "rations"])
