extends GdUnitTestSuite
## TradeRules and their GameState wiring (roadmap v0.5.3): merchant purses and stock, prices by attitude and
## haggling, the deal transaction, restock on a new day, haggle checks, trade mode guards, B13, B16, B33.

const SMITH := "npc_smith"
const INNKEEPER := TestUtils.INNKEEPER

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	# These tests check the deal, the attitude and the haggle on a neutral market: demand off (it has its own tests,
	# test_demand_v07171.gd).
	var d: Dictionary = data["rules"]["trade"]["demand"]
	d["wanted"] = 1.0
	d["other"] = 1.0
	d["min_ratio"] = 0.0
	d["max_ratio"] = 1.0
	for id: String in data["world"]["npcs"]:
		(data["world"]["npcs"][id] as Dictionary).erase("shuns")
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)
	s.character["gold_cp"] = 10000
	s.mode = GameSession.MODE_TRADE
	s.npc_id = INNKEEPER


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""


func _win(total: int, dc: int) -> Dictionary:
	return {"check_id": "c-1", "rolls": [10], "bonus": total - 10, "total": total, "dc": dc, "success": total >= dc, "nat": 10, "blocked": false}


func test_a_merchant_starts_from_the_pack() -> void:
	var m := TradeRules.merchant(s, data, INNKEEPER)
	assert_int(m["purse_cp"]).is_equal(3000)
	assert_int(m["stock"]["ale"]).is_equal(40)
	var list_npc := {"stock": ["ale", "bread"]}
	assert_dict(TradeRules.pack_stock(list_npc, data["rules"])).is_equal({"ale": 5, "bread": 5})


func test_prices_follow_the_value_attitude_and_half_for_selling() -> void:
	assert_int(TradeRules.buy_price(s, data, SMITH, "longsword")).is_equal(1500)
	assert_int(TradeRules.sell_price(s, data, SMITH, "longsword")).is_equal(750)  # B13: sold for half
	s.attitudes[SMITH] = -2
	assert_int(TradeRules.buy_price(s, data, SMITH, "longsword")).is_equal(1875)
	assert_int(TradeRules.sell_price(s, data, SMITH, "longsword")).is_equal(600)
	s.attitudes[SMITH] = 2
	assert_int(TradeRules.buy_price(s, data, SMITH, "longsword")).is_equal(1350)
	assert_int(TradeRules.buy_price(s, data, INNKEEPER, "candle")).is_equal(1)  # never free
	assert_int(TradeRules.sell_price(s, data, INNKEEPER, "candle")).is_equal(0)


func test_a_deal_moves_coins_items_and_stock_both_ways() -> void:
	s.character["inventory"]["dagger"] = 1
	var cart := {"buy": {"ale": 2}, "sell": {"dagger": 1}}
	var q := TradeRules.quote(s, data, INNKEEPER, cart)
	assert_str(q["error"]).is_empty()
	assert_int(q["buy_cp"]).is_equal(8)
	assert_int(q["sell_cp"]).is_equal(100)
	var lines := TradeRules.execute(s, data, INNKEEPER, cart)
	assert_int(s.character["gold_cp"]).is_equal(10000 - 8 + 100)
	assert_int(s.character["inventory"]["ale"]).is_equal(2)
	assert_bool(s.character["inventory"].has("dagger")).is_false()
	var m := TradeRules.merchant(s, data, INNKEEPER)
	assert_int(m["stock"]["ale"]).is_equal(38)
	assert_int(m["stock"]["dagger"]).is_equal(1)  # resold later
	assert_int(m["purse_cp"]).is_equal(3000 + 8 - 100)
	assert_str(" ".join(lines)).contains("Куплено").contains("Продано").contains("Итого: +9 см 2 мм")
	assert_str(TradeRules.deal_note(lines, int(q["net_cp"]))).ends_with("итог: торговец доплачивает игроку 9 см 2 мм")


func test_a_deal_needs_both_purses_and_the_goods() -> void:
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"buy": {}, "sell": {}})["error"]).is_equal("TRADE_ERR_EMPTY")
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"buy": {"ale": 41}})["error"]).is_equal("TRADE_ERR_NO_STOCK")
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"sell": {"healing_potion": 1}})["error"]).is_equal("TRADE_ERR_NO_ITEM")
	s.character["gold_cp"] = 5
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"buy": {"ale": 2}})["error"]).is_equal("TRADE_ERR_NO_MONEY")
	s.character["inventory"]["chain_shirt"] = 3  # 25 зм each, the innkeeper has 30 зм
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"sell": {"chain_shirt": 3}})["error"]).is_equal("TRADE_ERR_MERCHANT_NO_MONEY")
	s.character["inventory"]["candle"] = 3
	assert_str(TradeRules.quote(s, data, INNKEEPER, {"sell": {"candle": 1}})["error"]).is_equal("TRADE_ERR_WORTHLESS")


func test_b16_worn_things_are_not_for_sale() -> void:
	var c := s.character
	var sword := str(c["equipped"]["main_hand"])
	assert_str(sword).is_not_empty()
	assert_int(TradeRules.sellable(s, sword)).is_equal(int(c["inventory"][sword]) - 1)
	var info := TradeRules.info(s, data, INNKEEPER)
	assert_bool(info["buys"].any(func(l: Dictionary) -> bool: return l["item_id"] == sword)).is_equal(int(c["inventory"][sword]) > 1)


func test_a_new_day_restocks_and_keeps_what_was_sold() -> void:
	s.character["inventory"]["dagger"] = 1
	TradeRules.execute(s, data, INNKEEPER, {"buy": {"ale": 10}, "sell": {"dagger": 1}})
	s.day += 1
	var m := TradeRules.merchant(s, data, INNKEEPER)
	assert_int(m["stock"]["ale"]).is_equal(40)
	assert_int(m["stock"]["dagger"]).is_equal(1)
	assert_int(m["purse_cp"]).is_equal(3000)  # the purse came back to the pack's after paying for the dagger


func test_haggling_by_margin_for_this_visit() -> void:
	assert_int(TradeRules.haggle_dc(s, data, INNKEEPER)).is_equal(13)
	s.attitudes[INNKEEPER] = -1
	assert_int(TradeRules.haggle_dc(s, data, INNKEEPER)).is_equal(15)
	assert_int(TradeRules.apply_haggle(s, data, INNKEEPER, _win(21, 15))).is_equal(15)
	assert_str(TradeRules.can_haggle(s, data, INNKEEPER)).is_equal("TRADE_HAGGLE_DONE")
	s.attitudes[INNKEEPER] = 0
	assert_int(TradeRules.buy_price(s, data, SMITH, "longsword")).is_equal(1500)  # another merchant
	assert_int(TradeRules.buy_price(s, data, INNKEEPER, "rations")).is_equal(43)  # 50 × 0.85, up
	assert_int(TradeRules.sell_price(s, data, INNKEEPER, "longsword")).is_equal(862)  # 750 × 1.15, down
	TradeRules.end_visit(s, INNKEEPER)
	assert_int(TradeRules.buy_price(s, data, INNKEEPER, "rations")).is_equal(50)
	assert_str(TradeRules.can_haggle(s, data, INNKEEPER)).is_empty()


func test_a_failed_haggle_locks_until_the_next_day() -> void:
	assert_int(TradeRules.apply_haggle(s, data, INNKEEPER, _win(9, 13))).is_equal(0)
	assert_str(TradeRules.can_haggle(s, data, INNKEEPER)).is_equal("TRADE_HAGGLE_LOCKED")
	TradeRules.end_visit(s, INNKEEPER)
	assert_str(TradeRules.can_haggle(s, data, INNKEEPER)).is_equal("TRADE_HAGGLE_LOCKED")
	s.day += 1
	assert_str(TradeRules.can_haggle(s, data, INNKEEPER)).is_empty()


func test_only_persuasion_or_deception_at_the_merchant_in_trade_is_haggling() -> void:
	assert_bool(TradeRules.is_haggle(s, data, {"skill": "persuasion", "target_id": INNKEEPER})).is_true()
	assert_bool(TradeRules.is_haggle(s, data, {"skill": "deception", "target_id": INNKEEPER})).is_true()
	assert_bool(TradeRules.is_haggle(s, data, {"skill": "intimidation", "target_id": INNKEEPER})).is_false()
	assert_bool(TradeRules.is_haggle(s, data, {"skill": "persuasion", "target_id": TestUtils.SERVING})).is_false()
	s.mode = GameSession.MODE_SOCIAL
	assert_bool(TradeRules.is_haggle(s, data, {"skill": "persuasion", "target_id": INNKEEPER})).is_false()


func test_the_engine_check_of_a_haggle_uses_the_attitude_dc_and_repeats_without_a_roll() -> void:
	GameState.start(s)
	GameState.busy_turn = "t-9"
	var params := {"turn_id": "t-9", "skill": "persuasion", "dc_tier": "very_easy", "target_id": INNKEEPER}
	var first := GameState.handle_engine_check(params)
	assert_int(first["dc"]).is_equal(13)
	assert_str(first["note"]).contains("Торг")
	var again := GameState.handle_engine_check(params)
	assert_bool(again["blocked"]).is_true()
	assert_int(again["total"]).is_equal(int(first["total"]))


func test_coin_and_item_effects_are_refused_in_trade_mode() -> void:
	var fx := EffectEngine.new()
	for e: Dictionary in [{"kind": "coins", "delta_cp": -4}, {"kind": "give_item", "item_id": "ale"}, {"kind": "take_item", "item_id": "rations"}]:
		assert_bool(fx.validate(s, data, "t-1", e)["accepted"]).override_failure_message(str(e)).is_false()
	s.mode = GameSession.MODE_SOCIAL
	assert_bool(fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": -4})["accepted"]).is_true()


func test_the_snapshot_carries_the_trade_only_in_trade_mode() -> void:
	var snap := TurnSnapshot.build(s, data, 4000)
	assert_int(snap["trade"]["purse_cp"]).is_equal(3000)
	assert_bool(snap["trade"]["stock"].any(func(l: Dictionary) -> bool: return l["item_id"] == "ale" and l["price_cp"] == 4)).is_true()
	s.mode = GameSession.MODE_SOCIAL
	assert_bool(TurnSnapshot.build(s, data, 4000).has("trade")).is_false()


func test_b33_switching_talk_and_trade_with_the_same_partner_asks_no_new_turn() -> void:
	s.mode = GameSession.MODE_SOCIAL
	GameState.start(s)
	assert_bool(GameState.set_trade(true)).is_true()
	assert_str(s.mode).is_equal(GameSession.MODE_TRADE)
	assert_bool(GameState.set_trade(false)).is_true()
	assert_str(GameState._apply_result(s, "t-1", {"narration": "x", "next_mode": {"mode": "trade", "npc_id": INNKEEPER}}, "action")).is_empty()
	assert_str(s.mode).is_equal(GameSession.MODE_TRADE)
	GameState._apply_result(s, "t-2", {"narration": "x", "next_mode": {"mode": "social", "npc_id": INNKEEPER}}, "action")
	assert_str(s.mode).is_equal(GameSession.MODE_TRADE)  # only the player closes the deal panel
	s.npc_id = TestUtils.SERVING
	s.mode = GameSession.MODE_SOCIAL
	assert_bool(GameState.set_trade(true)).is_false()  # not a trader


func test_merchants_survive_a_save() -> void:
	s.character["inventory"]["dagger"] = 1
	TradeRules.execute(s, data, INNKEEPER, {"buy": {"ale": 1}, "sell": {"dagger": 1}})
	TradeRules.apply_haggle(s, data, INNKEEPER, _win(9, 13))
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_dict(back.merchants).is_equal(s.merchants)
	assert_int(back.merchants[INNKEEPER]["stock"]["ale"]).is_equal(39)
