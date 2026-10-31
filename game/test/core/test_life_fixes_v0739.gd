extends GdUnitTestSuite
## The author's acceptance of «Своя жизнь», broken mechanics (v0.7.39): no work, cooking, shifts or study bound, a
## captive or held; a course of what the hero knows is learned already; the hero's shop shift grows «Торговля» by its
## revenue; the tax debt paid by the button and by the master's words; a sick NPC gets well; the rest's meal is the
## breakfast.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-townhall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


func test_bound_captive_or_held_hero_does_not_work() -> void:
	var s := _hero()
	assert_str(EncounterRules.unfree_why(s)).is_empty()
	s.character["conditions"] = ["restrained"]
	assert_str(EncounterRules.unfree_why(s)).is_equal("UNFREE_RESTRAINED")
	assert_str(CraftRules.can_work(s, data)).is_equal("UNFREE_RESTRAINED")
	assert_str(JobRules.shift_why(s, data, "any")).is_equal("UNFREE_RESTRAINED")
	assert_str(StudyRules.lesson_why(s, data, "letters")).is_equal("UNFREE_RESTRAINED")
	s.character["conditions"] = []
	s.captive = {"room": s.room_id, "foes": []}
	assert_str(CraftRules.why_not(s, data, "shield")).is_equal("UNFREE_CAPTIVE")  # unbound, yet a captive
	s.captive = {}
	s.arrest = s.room_id
	assert_str(StudyRules.enroll_why(s, data, "letters")).is_equal("UNFREE_HELD")


func test_a_course_of_what_the_hero_knows_is_learned_already() -> void:
	var s := _hero()
	assert_bool(StudyRules.known_already(s, data, "herbalism")).is_false()
	s.character["tools"] = ["herbalism_kit"]
	assert_bool(StudyRules.known_already(s, data, "herbalism")).is_true()
	assert_str(StudyRules.enroll_why(s, data, "herbalism")).is_equal("STUDY_KNOWN")
	s.character["tools"] = ["carpenters_tools"]  # a recipe without `learn` is known by the tool's proficiency
	var co := {"name": "Щиты", "teaches": {"kind": "recipe", "id": "shield"}, "lessons": 4}
	data["world"]["courses"]["shields_test"] = co
	assert_bool(StudyRules.known_already(s, data, "shields_test")).is_true()
	data["world"]["courses"].erase("shields_test")


func test_own_shop_shift_grows_trade_by_revenue() -> void:
	var s := _hero()
	PropertyRules.rent(s, data, "npc_clerk", "stall", 7)
	var vid := PropertyRules.rented(s, data, "stall", "brod")
	s.room_id = ShopRules.room_of(s, data, vid)
	s.character["inventory"]["silver_ring"] = 10
	ShopRules.put(s, data, vid, "silver_ring", 10)
	for i in 5:
		ShopRules.price_step(s, data, vid, "silver_ring", -1)
	var lines := ShopRules.shift(s, data, vid, ShopRules.shift_hours(data) * 60)
	assert_str("\n".join(lines)).contains("Торговля: +")
	assert_int(int(DevelopmentRules.state(s.character, "trade")["xp"])).is_between(1, 25)


func test_the_tax_debt_is_paid_at_the_clerk() -> void:
	var s := _hero()
	PropertyRules.buy(s, data, "river_house")
	assert_str(PropertyRules.pay_tax_why(s, data, "river_house")).is_equal("PROPERTY_NO_DEBT")
	Ledger.owe(s, "tax:river_house", "tax", 500, "")
	assert_str(PropertyRules.pay_tax_why(s, data, "river_house")).is_empty()
	var gold := int(s.character["gold_cp"])
	PropertyRules.pay_tax(s, data, "river_house")
	assert_int(Ledger.owed(s, "tax:river_house")).is_equal(0)
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 500)
	Ledger.owe(s, "tax:river_house", "tax", 500, "")
	s.room_id = "brod-square"  # neither the place nor the clerk
	assert_str(PropertyRules.pay_tax_why(s, data, "river_house")).is_equal("PROPERTY_TAX_WHERE")


func test_the_master_takes_the_tax_by_words() -> void:
	var s := _hero()
	PropertyRules.buy(s, data, "river_house")
	Ledger.owe(s, "tax:river_house", "tax", 500, "")
	var engine := EffectEngine.new()
	var over := engine.validate(s, data, "t-1", {"kind": "coins", "delta_cp": -900, "reason": "налог", "settles": "tax"})
	assert_bool(bool(over["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "coins", "delta_cp": -300, "reason": "налог", "settles": "tax"})
	assert_bool(bool(r["accepted"])).is_true()
	var gold := int(s.character["gold_cp"])
	var lines := engine.apply(s, "t-1", [r["effect_id"]])
	assert_int(Ledger.owed(s, "tax:river_house")).is_equal(200)
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 300)
	assert_str("\n".join(lines)).contains("долг ещё")


func test_a_sick_npc_gets_well() -> void:
	var s := _hero()
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_equal("cackle_fever")
	DiseaseRules.tick(s, data)
	var until := int(s.npc_sick["npc_sick_pilgrim"]["until"])
	assert_int(until).is_greater(s.clock)
	s.clock = until
	DiseaseRules.tick(s, data)
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_empty()
	var back := GameSession.from_dict(s.to_dict(10))  # kept in the save
	assert_str(DiseaseRules.npc_disease(back, data, "npc_sick_pilgrim")).is_empty()


func test_magic_cures_a_sick_npc() -> void:
	var s := _hero()
	var lines := DiseaseRules.cure_npc(s, data, "npc_sick_pilgrim", "magic")
	assert_str("\n".join(lines)).contains("исцелён")
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_empty()


func test_the_rest_meal_is_the_breakfast() -> void:
	var s := _hero("brod-tavern-hall")
	s.settings["needs"] = true
	var began := TimeRules.abs_minute(s)
	NeedRules.set_value(s, data, "food", 100.0)
	NeedRules.set_value(s, data, "water", 100.0)
	TimeRules.advance(s, data, 8 * 60)
	assert_float(NeedRules.value(s, data, "food")).is_less(100.0)
	NeedRules.woke(s, data, began)
	assert_float(NeedRules.value(s, data, "food")).is_equal(100.0)
	assert_float(NeedRules.value(s, data, "water")).is_equal(100.0)
