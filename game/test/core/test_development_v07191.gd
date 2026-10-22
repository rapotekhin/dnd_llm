extends GdUnitTestSuite
## «Мирное развитие» (roadmap v0.7.19.1): the 5e levelling carried over to peaceful deeds — a direction with its own
## experience, levels 0–5 and a skill picked from a list on every level; «Торговля» earns from deals and haggles and its
## skills work only in trade.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data, s.items)
	s.character["gold_cp"] = 100000
	s.room_id = "brod-smithy"


func _win(total: int, dc: int) -> Dictionary:
	return {"check_id": "c-1", "rolls": [10], "bonus": total - 10, "total": total, "dc": dc, "success": total >= dc, "nat": 10, "blocked": false}


func test_levels_by_experience_and_a_skill_each() -> void:
	var c := s.character
	assert_int(DevelopmentRules.level(c, data, "trade")).is_equal(0)
	DevelopmentRules.add_xp(c, data, "trade", 60)
	assert_int(DevelopmentRules.level(c, data, "trade")).is_equal(1)
	assert_int(DevelopmentRules.next_xp(c, data, "trade")).is_equal(150)
	assert_array(DevelopmentRules.choices(c, data, "trade")).contains_exactly_in_any_order(["appraiser", "regular"])
	assert_str(DevelopmentRules.pick(c, data, "trade", "silver_tongue")).is_equal("DEV_CANNOT_PICK")  # level 2
	assert_str(DevelopmentRules.pick(c, data, "trade", "appraiser")).is_empty()
	assert_int(DevelopmentRules.picks_left(c, data, "trade")).is_equal(0)
	var lines := DevelopmentRules.add_xp(c, data, "trade", 2000)
	assert_str(" ".join(lines)).contains("уровень 5")
	assert_array(DevelopmentRules.choices(c, data, "trade")).not_contains(["merchant_name"])  # needs «regular» first
	DevelopmentRules.pick(c, data, "trade", "regular")
	assert_array(DevelopmentRules.choices(c, data, "trade")).contains(["merchant_name"])


func test_trade_skills_work_in_trade() -> void:
	var c := s.character
	var sell := TradeRules.sell_price(s, data, "npc_smith", "longsword")
	var buy := TradeRules.buy_price(s, data, "npc_smith", "longsword")
	DevelopmentRules.add_xp(c, data, "trade", 2000)
	for sk: String in ["appraiser", "regular"]:
		DevelopmentRules.pick(c, data, "trade", sk)
	assert_int(TradeRules.sell_price(s, data, "npc_smith", "longsword")).is_greater(sell)
	assert_int(TradeRules.buy_price(s, data, "npc_smith", "longsword")).is_less(buy)
	var dc := TradeRules.haggle_dc(s, data, "npc_smith")
	TradeRules.apply_haggle(s, data, "npc_smith", _win(dc, dc))
	assert_int(TradeRules.haggle_dc(s, data, "npc_smith")).is_equal(dc + 2)
	DevelopmentRules.pick(c, data, "trade", "stubborn")
	assert_int(TradeRules.haggle_dc(s, data, "npc_smith")).is_equal(dc)  # «Упорство»


func test_deals_and_haggles_teach_trade() -> void:
	var c := s.character
	TradeRules.execute(s, data, "npc_smith", {"buy": {"longsword": 1}})  # 15 gp
	assert_int(DevelopmentRules.xp(c, "trade")).is_equal(15)
	var dc := TradeRules.haggle_dc(s, data, "npc_smith")
	TradeRules.apply_haggle(s, data, "npc_smith", _win(dc + 1, dc))
	assert_int(DevelopmentRules.xp(c, "trade")).is_equal(25)
	assert_int(int(c["xp"])).is_equal(0)  # never into the class


func test_the_second_chance_and_the_snapshot_and_a_save() -> void:
	var c := s.character
	DevelopmentRules.add_xp(c, data, "trade", 700)
	for sk: String in ["appraiser", "silver_tongue", "stubborn", "second_chance"]:
		DevelopmentRules.pick(c, data, "trade", sk)
	TradeRules.apply_haggle(s, data, "npc_smith", _win(1, 20))
	assert_str(TradeRules.can_haggle(s, data, "npc_smith")).is_empty()  # once a day the failure does not lock
	TradeRules.apply_haggle(s, data, "npc_smith", _win(1, 20))
	assert_str(TradeRules.can_haggle(s, data, "npc_smith")).is_equal("TRADE_HAGGLE_LOCKED")
	assert_str(" ".join(TurnSnapshot.character_sheet(s, data)["development"])).contains("Торговля 4").contains("Второй заход")
	var back := GameSession.from_dict(s.to_dict(5))
	assert_array(DevelopmentRules.skills(back.character, "trade")).has_size(4)
