extends GdUnitTestSuite
## Shop kinds (roadmap v0.7.22.26): a trader's goods are the engine's data by its trade, more come each day, and the
## master's own goods are only extras — a bad one is skipped, the trader is made anyway.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-square"
	fx = EffectEngine.new()


func _make(npc: Dictionary, turn := "t-1") -> Dictionary:
	fx.searched_npcs[turn] = true
	var r := fx.validate(s, data, turn, {"kind": "create_npc", "npc": npc})
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_a_made_trader_gets_the_goods_of_its_kind() -> void:
	var r := _make({"name": "Олеся Румяная", "role": "пекарша", "trader": true})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_str(str(r["summary"])).contains("еда и питьё")
	var id := str(s.generated["npcs"].keys()[0])
	assert_str(str(data["world"]["npcs"][id]["trade_kind"])).is_equal("food")
	var stock: Dictionary = TradeRules.merchant(s, data, id)["stock"]
	assert_int(int(stock.get("bread", 0))).is_greater(0)
	assert_array(TradeRules.wants(data, id)).contains(["consumable"])


func test_the_masters_bad_goods_are_skipped() -> void:
	var r := _make({"name": "Карп Жила", "role": "кузнец-подмастерье", "trade_kind": "smith", "trader": true,
		"stock": ["plate_armor", "no_such_thing", "whetstone"],
		"stock_new": [{"name": "Меч королей", "item_type": "weapon", "rarity": "legendary", "value_cp": 900000}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_str(str(r["summary"])).contains("не взят")
	var stock: Dictionary = TradeRules.merchant(s, data, str(s.generated["npcs"].keys()[0]))["stock"]
	assert_bool(stock.has("plate_armor")).is_false()
	assert_bool(stock.has("whetstone")).is_true()
	assert_bool(stock.has("dagger")).is_true()


func test_a_trader_needs_a_kind() -> void:
	assert_str(str(_make({"name": "Меняла Сорока", "role": "меняла", "trader": true})["reason"])).contains("smith")


func test_extras_come_each_day_by_the_seed() -> void:
	var pool: Array = data["rules"]["trade"]["kinds"]["smith"]["extras"]["pool"]
	s.day = 1
	var day1: Dictionary = (TradeRules.merchant(s, data, "npc_smith")["extras"] as Dictionary).duplicate()
	assert_int(day1.size()).is_equal(int(data["rules"]["trade"]["kinds"]["smith"]["extras"]["per_day"]))
	for id: String in day1:
		assert_array(pool).contains([id])
		assert_int(int(TradeRules.merchant(s, data, "npc_smith")["stock"][id])).is_greater_equal(int(day1[id]))
	var again := TestUtils.new_session()
	again.day = 1
	assert_dict(TradeRules.merchant(again, data, "npc_smith")["extras"]).is_equal(day1)
	var seen := {}
	for d in range(2, 8):
		s.day = d
		var today: Dictionary = TradeRules.merchant(s, data, "npc_smith")["extras"]
		var stock: Dictionary = TradeRules.merchant(s, data, "npc_smith")["stock"]
		for id: String in today:
			seen[id] = true
		for id: String in day1:  # yesterday's leftovers are gone unless picked again
			if not today.has(id) and not TradeRules.pack_stock(data["world"]["npcs"]["npc_smith"], data["rules"]).has(id):
				assert_int(int(stock.get(id, 0))).is_equal(0)
		day1 = today.duplicate()
	assert_int(seen.size()).is_greater(2)


func test_pack_traders_have_kinds_and_every_good_is_in_the_catalog() -> void:
	assert_str(TradeRules.kind_of(data["rules"], data["world"]["npcs"]["npc_innkeeper"])).is_equal("food")
	assert_str(TradeRules.kind_of(data["rules"], {"role": "старый травник"})).is_equal("herbalist")
	var kinds := TradeRules.kinds(data["rules"])
	for k: String in kinds:
		for id: String in (kinds[k]["stock"] as Dictionary).keys() + (kinds[k]["extras"]["pool"] as Array):
			assert_bool(data["items"]["catalog"].has(id)).override_failure_message("%s: %s" % [k, id]).is_true()
