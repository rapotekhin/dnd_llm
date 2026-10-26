extends GdUnitTestSuite
## Own trade (v0.7.29): a stall rented at the town hall, the hero's shift sells by the price, the charter and its tax,
## the guard's fine without it, a staffed shop selling by days into its till, a tavern sells only food, the merchant's
## reputation, wholesale at a supplier, the master's supplier.

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


func _stall(s: GameSession) -> String:
	ShopRules.rent(s, data, "npc_clerk", 7)
	s.room_id = "brod-square"
	return ShopRules.STALL + "brod-square"


func test_a_stall_is_rented_at_the_town_hall() -> void:
	var s := _hero()
	assert_str(ShopRules.rent_why(s, data, "npc_clerk", 7)).is_empty()
	assert_str(ShopRules.rent_why(s, data, "npc_clerk", 3)).is_equal("SHOP_NO_SERVICE")
	var vid := _stall(s)
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 140)
	assert_str(ShopRules.here(s, data)).is_equal(vid)
	assert_bool(ShopRules.stall_open(s, vid)).is_true()
	assert_str(ShopRules.shift_why(s, data, vid)).is_equal("SHOP_EMPTY")


func test_the_buyers_follow_the_price() -> void:
	assert_float(ShopRules.buy_chance(data, 1.0)).is_equal_approx(0.6, 0.001)
	assert_float(ShopRules.buy_chance(data, 0.9)).is_equal_approx(0.7, 0.001)
	assert_float(ShopRules.buy_chance(data, 3.0)).is_equal_approx(0.02, 0.001)


func test_a_shift_at_the_stall_sells_cheap_goods() -> void:
	var s := _hero()
	var vid := _stall(s)
	s.character["inventory"]["silver_ring"] = 10
	ShopRules.put(s, data, vid, "silver_ring", 10)
	for i in 5:
		ShopRules.price_step(s, data, vid, "silver_ring", -1)
	assert_int(ShopRules.price(s, data, vid, "silver_ring")).is_equal(1250)
	assert_str(ShopRules.price_step_why(s, data, vid, "silver_ring", -1)).is_equal("SHOP_PRICE_LIMIT")
	var gold := int(s.character["gold_cp"])
	ShopRules.shift(s, data, vid, ShopRules.shift_hours(data) * 60)
	assert_int(int(s.character["gold_cp"])).is_greater(gold)
	assert_int(int(ShopRules.venue(s.character, vid)["stock"].get("silver_ring", 0))).is_less(10)
	assert_str(ShopRules.shift_why(s, data, vid)).is_equal("SHOP_DONE_TODAY")


func test_the_charter_taxes_and_opens_wholesale() -> void:
	var s := _hero()
	assert_str(ShopRules.charter_why(s, data, "npc_clerk")).is_empty()
	ShopRules.charter(s, data, "npc_clerk")
	assert_bool(ShopRules.has_charter(s, "brod")).is_true()
	assert_str(ShopRules.charter_why(s, data, "npc_clerk")).is_equal("SHOP_HAS_CHARTER_ERR")
	assert_bool(s.character["inventory"].has("gen_charter_brod")).is_true()
	assert_array(ShopRules._after_tax(s, data, "brod", 1000)).is_equal([950, 50])
	s.room_id = "brod-square"
	assert_bool(ShopRules.goods(s, data, "npc_merchant").has("torch")).is_true()
	assert_str(ShopRules.wholesale_why(s, data, "npc_merchant", "rope")).is_empty()
	var price := ShopRules.wholesale_price(s, data, "npc_merchant", "rope")
	assert_int(price).is_equal(ceili(ShopRules.value(s, data, "rope") * 0.6))
	var had := int(s.character["inventory"].get("rope", 0))
	ShopRules.wholesale(s, data, "npc_merchant", "rope")
	assert_int(int(s.character["inventory"]["rope"])).is_equal(had + 5)


func test_wholesale_needs_the_charter() -> void:
	var s := _hero("brod-square")
	assert_str(ShopRules.wholesale_why(s, data, "npc_merchant", "rope")).is_equal("SHOP_NEED_CHARTER")


func test_the_guard_fines_trade_without_the_charter() -> void:
	var s := _hero()
	var was := float(data["rules"]["shop"]["charter"]["fine_chance"])
	data["rules"]["shop"]["charter"]["fine_chance"] = 1.0
	var lines := ShopRules._fine(s, data, "brod")
	data["rules"]["shop"]["charter"]["fine_chance"] = was
	assert_str(" ".join(lines)).contains("без грамоты")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 200)


func test_a_staffed_shop_sells_by_days_into_its_till() -> void:
	var s := _hero()
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(s.character)["river_house"]["kind"] = "shop"
	s.room_id = PropertyRules.main_room(s, data, "river_house")
	var vid := ShopRules.here(s, data)
	assert_str(vid).is_equal("river_house")
	PropertyRules.hire_worker(s, data, "river_house")
	s.character["inventory"]["silver_ring"] = 20
	ShopRules.put(s, data, vid, "silver_ring", 20)
	assert_int(PropertyRules.income_day(s, data, "river_house")).is_equal(0)
	assert_str(PropertyRules.shift_why(s, data, "river_house")).is_equal("PROPERTY_SHOP_SHIFT")
	TimeRules.advance(s, data, 3 * 1440)
	var v := ShopRules.venue(s.character, vid)
	assert_int(int(v["cash"])).is_greater(0)
	assert_int(int(v["stock"].get("silver_ring", 0))).is_less(20)
	var gold := int(s.character["gold_cp"])
	ShopRules.collect(s, data, vid)
	assert_int(int(s.character["gold_cp"])).is_greater(gold)


func test_a_tavern_sells_only_food_and_drink() -> void:
	var s := _hero()
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(s.character)["river_house"]["kind"] = "tavern"
	s.room_id = PropertyRules.main_room(s, data, "river_house")
	s.character["inventory"]["bread"] = 3
	s.character["inventory"]["silver_ring"] = 1
	assert_str(ShopRules.put_why(s, data, "river_house", "silver_ring")).is_equal("SHOP_TAVERN_FOOD")
	assert_str(ShopRules.put_why(s, data, "river_house", "bread")).is_empty()


func test_dear_sales_spoil_the_merchants_name() -> void:
	var s := _hero()
	var vid := _stall(s)
	s.character["inventory"]["silver_ring"] = 40
	ShopRules.put(s, data, vid, "silver_ring", 40)
	ShopRules.venue(s.character, vid)["prices"]["silver_ring"] = 150
	ShopRules.sell_round(s, data, vid, 200)
	assert_float(ShopRules.rep(s, "brod")).is_less(0.0)
	var s2 := _hero()
	var vid2 := _stall(s2)
	s2.character["inventory"]["silver_ring"] = 40
	ShopRules.put(s2, data, vid2, "silver_ring", 40)
	ShopRules.venue(s2.character, vid2)["prices"]["silver_ring"] = 90
	ShopRules.sell_round(s2, data, vid2, 40)
	assert_float(ShopRules.rep(s2, "brod")).is_greater(0.0)


func test_the_master_makes_a_supplier() -> void:
	var s := _hero("brod-smithy")
	var engine := EffectEngine.new()
	var bad := engine.validate(s, data, "t-1", {"kind": "supplier", "npc_id": "npc_smith", "pct": 50})
	assert_bool(bool(bad["accepted"])).is_false()  # the smith is already a supplier in the pack
	s.room_id = "brod-herbalist"
	var cheap := engine.validate(s, data, "t-1", {"kind": "supplier", "npc_id": "npc_herbalist", "pct": 10})
	assert_bool(bool(cheap["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "supplier", "npc_id": "npc_herbalist", "pct": 70})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	assert_bool(ShopRules.is_supplier(s, data, "npc_herbalist")).is_true()
	assert_str(str(TurnSnapshot.build(s, data, 1000)["character"]["shop"])).contains("оптом продаёт Ведана (70% цены")
