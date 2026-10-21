extends GdUnitTestSuite
## «Торговля 2.0» (roadmap v0.7.17.1): demand — a trader buys its own kind of goods dearer, other goods cheaper and
## some not at all; the same thing sold again and again fills the market, which forgets it by the days; the sell price
## stays within ¼…¾ of the value.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)
	s.character["gold_cp"] = 10000
	s.room_id = "brod-smithy"


func test_the_smith_wants_weapons_and_shuns_potions() -> void:
	assert_str(TradeRules.demand(s, data, "npc_smith", "longsword")).is_equal("wants")
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_equal(975)  # 1500 × ½ × 1.3
	assert_str(TradeRules.demand(s, data, "npc_smith", "rope")).is_equal("other")
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "rope")).is_equal(35)  # 100 × ½ × 0.7
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "healing_potion")).is_equal(0)  # will not buy
	assert_int(TradeRules.sell_price(s, data, "npc_herbalist", "healing_potion")).is_equal(3250)


func test_the_price_stays_within_a_quarter_and_three_quarters() -> void:
	s.attitudes["npc_smith"] = 3
	ReputationRules.add(s, data, "brod", 40, "герой")
	TradeRules.merchant(s, data, "npc_smith")["haggle_pct"] = 20
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_equal(1125)  # ¾ of 1500
	s.reputation.clear()  # a stranger again
	ReputationRules.refresh(s, data)
	s.attitudes["npc_merchant"] = -3
	assert_int(TradeRules.sell_price(s, data, "npc_merchant", "longsword")).is_equal(375)  # ¼ of 1500


func test_five_same_swords_fill_the_market_and_it_forgets() -> void:
	s.character["inventory"]["longsword"] = 6
	var one := TradeRules.sell_price(s, data, "npc_smith", "longsword")
	var five := TradeRules.sell_total(s, data, "npc_smith", "longsword", 5)
	assert_int(five).is_less(one * 5)
	TradeRules.execute(s, data, "npc_smith", {"sell": {"longsword": 5}})
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_equal(487)  # 975 × the floor ½
	s.day += 3
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_less(975)
	s.day += 5
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_equal(975)


func test_a_trader_without_wants_buys_its_own_kind() -> void:
	var d := data.duplicate(true)
	(d["world"]["npcs"]["npc_smith"] as Dictionary).erase("wants")
	assert_array(TradeRules.wants(d, "npc_smith")).contains(["weapon"])
	assert_str(TradeRules.info(s, data, "npc_smith")["wants"]).is_equal("оружие, доспехи")
