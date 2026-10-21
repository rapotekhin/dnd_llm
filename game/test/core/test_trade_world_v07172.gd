extends GdUnitTestSuite
## «Торговля 2.0» (roadmap v0.7.17.2): a haggle is won for one deal, and every next one with the trader that day is
## harder; the world's flags change a trader's prices and goods (`trade_variants`, with a piece of news for the
## master); the goods of a killed trader pass to its heir when the heir trades.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)
	s.character["gold_cp"] = 100000
	s.room_id = "brod-square"


func _win(total: int, dc: int) -> Dictionary:
	return {"check_id": "c-1", "rolls": [10], "bonus": total - 10, "total": total, "dc": dc, "success": total >= dc, "nat": 10, "blocked": false}


func test_a_haggle_is_for_one_deal_and_the_next_is_harder() -> void:
	var dc := TradeRules.haggle_dc(s, data, "npc_merchant")
	assert_int(TradeRules.apply_haggle(s, data, "npc_merchant", _win(dc + 6, dc))).is_greater(0)
	assert_str(TradeRules.can_haggle(s, data, "npc_merchant")).is_equal("TRADE_HAGGLE_DONE")
	TradeRules.execute(s, data, "npc_merchant", {"buy": {"rope": 1}})
	assert_int(int(TradeRules.merchant(s, data, "npc_merchant")["haggle_pct"])).is_equal(0)
	assert_str(TradeRules.can_haggle(s, data, "npc_merchant")).is_empty()
	assert_int(TradeRules.haggle_dc(s, data, "npc_merchant")).is_equal(dc + 2)
	s.day += 1
	assert_int(TradeRules.haggle_dc(s, data, "npc_merchant")).is_equal(dc)


func test_the_menhirs_fate_moves_prices_and_goods() -> void:
	var before := TradeRules.buy_price(s, data, "npc_merchant", "rope")
	s.flags.append("menhir_power")
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", "rope")).is_greater(before)
	assert_str(" ".join(TradeRules.info(s, data, "npc_merchant")["news"])).contains("поднял цены")
	s.day += 1
	assert_int(int(TradeRules.merchant(s, data, "npc_smith")["stock"]["spear"])).is_equal(8)
	var t := TestUtils.new_session()
	t.flags.append("menhir_restored")
	assert_int(int(TradeRules.merchant(t, data, "npc_merchant")["stock"]["torch"])).is_equal(20)
	assert_int(TradeRules.buy_price(t, data, "npc_merchant", "rope")).is_less(before + 1)


func test_a_killed_traders_goods_go_to_its_heir() -> void:
	var d := data.duplicate(true)
	d["world"]["npcs"]["npc_herbalist"]["heir"] = "npc_merchant"
	TradeRules.merchant(s, d, "npc_merchant")
	var lines := CrimeRules.on_death(s, d, "npc_herbalist", false, "brod-herbalist")
	assert_str(" ".join(lines)).contains("переходит к Ферн")
	assert_int(int(TradeRules.merchant(s, d, "npc_merchant")["stock"].get("healing_potion", 0))).is_greater(0)
