extends GdUnitTestSuite
## The visit to a trader told once (v0.8.4.43.12, the author: «запустить мастера один раз, когда торговля завершится… Как в
## бою»): the engine makes each deal and haggle at once, they wait on the trader's record, the master tells them when the
## trade window closes. And how a drop in the trade window moves a thing (TradePanel._drop, BG3's barter).

const INNKEEPER := TestUtils.INNKEEPER

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)
	s.character["gold_cp"] = 10000
	s.mode = GameSession.MODE_TRADE
	s.npc_id = INNKEEPER


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""


func test_the_visit_is_told_once_with_its_total() -> void:
	TradeRules.merchant(s, data, INNKEEPER)
	TradeRules.keep(s, INNKEEPER, "Куплено: Кружка эля — 4 мм; итог: игрок платит торговцу 4 мм", 4, true)
	TradeRules.keep(s, INNKEEPER, "Торг: Торг удался")
	TradeRules.keep(s, INNKEEPER, "Продано: Кинжал — 1 зм; итог: торговец доплачивает игроку 1 зм", -100, true)
	var note := TradeRules.told(s, INNKEEPER)
	var lines := note.split("\n")
	assert_int(lines.size()).is_equal(4)
	assert_str(lines[1]).is_equal("Торг: Торг удался")
	assert_str(lines[3]).is_equal("Всего за торговлю: торговец доплачивает игроку " + Money.format(96))
	assert_str(TradeRules.told(s, INNKEEPER)).is_empty()  # told once


func test_one_deal_has_no_total_and_nothing_done_tells_nothing() -> void:
	TradeRules.merchant(s, data, INNKEEPER)
	assert_str(TradeRules.told(s, INNKEEPER)).is_empty()
	TradeRules.keep(s, INNKEEPER, "Куплено: Свеча — 1 мм; итог: игрок платит торговцу 1 мм", 1, true)
	assert_str(TradeRules.told(s, INNKEEPER)).is_equal("Куплено: Свеча — 1 мм; итог: игрок платит торговцу 1 мм")
	assert_str(TradeRules.farewell("Бруно", "")).is_empty()
	assert_str(TradeRules.farewell("Бруно", "x")).contains("торговец — Бруно")


func test_a_visit_broken_off_is_not_told_and_survives_a_save() -> void:
	TradeRules.merchant(s, data, INNKEEPER)
	TradeRules.keep(s, INNKEEPER, "Торг: Торг не удался")
	TradeRules.keep(s, INNKEEPER, "Куплено: Свеча — 1 мм; итог: игрок платит торговцу 1 мм", 1, true)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_dict(back.merchants).is_equal(s.merchants)
	TradeRules.end_visit(s, INNKEEPER)  # a fight broke the talk off
	assert_str(TradeRules.told(s, INNKEEPER)).is_empty()


func test_a_deal_and_a_haggle_of_the_window_ask_no_turn_of_the_master() -> void:
	GameState.start(s)
	var chat := s.chat.size()
	var q := GameState.deal({"buy": {"ale": 2}, "sell": {}})
	assert_str(str(q["error"])).is_empty()
	assert_bool(GameState.is_busy()).is_false()
	assert_int(int(s.character["inventory"].get("ale", 0))).is_equal(2)
	assert_int(s.chat.size()).is_equal(chat + 1)  # the deal's lines in the chat, no master's words
	assert_str(GameState.haggle()).is_empty()
	assert_bool(GameState.is_busy()).is_false()
	var v: Dictionary = s.merchants[INNKEEPER]["visit"]
	assert_int((v["lines"] as Array).size()).is_equal(2)
	assert_str(str(v["lines"][0])).contains("Кружка эля ×2").contains("итог: игрок платит торговцу")
	assert_str(str(v["lines"][1])).starts_with("Торг: ")


func test_without_the_master_the_visit_waits_for_the_next_close() -> void:
	GameState.start(s)
	GameState.deal({"buy": {"ale": 1}, "sell": {}})
	assert_bool(GameState.set_trade(false)).is_true()  # no backend in the tests: nothing sent, nothing lost
	assert_str(s.mode).is_equal(GameSession.MODE_SOCIAL)
	assert_str(GameState._last_kind).is_not_equal("deal")
	assert_str(TradeRules.told(s, INNKEEPER)).contains("Кружка эля")


func test_a_drop_moves_into_the_deal_out_of_it_or_across() -> void:
	var stock := {"kind": "trade", "side": "buy", "deal": false}
	var buy := {"kind": "trade", "side": "buy", "deal": true}
	var sell := {"kind": "trade", "side": "sell", "deal": true}
	var mine := {"kind": "trade", "side": "sell", "deal": false}
	assert_int(TradePanel._drop(buy, stock)).is_equal(1)  # the trader's goods onto its column of the deal
	assert_int(TradePanel._drop(sell, mine)).is_equal(1)
	assert_int(TradePanel._drop(stock, buy)).is_equal(-1)  # back out of the deal
	assert_int(TradePanel._drop(mine, sell)).is_equal(-1)
	assert_int(TradePanel._drop(mine, stock)).is_equal(1)  # across onto the other side, as BG3's Trade
	assert_int(TradePanel._drop(stock, mine)).is_equal(1)
	assert_int(TradePanel._drop(sell, stock)).is_equal(0)  # the trader's goods never into the hero's column
	assert_int(TradePanel._drop(buy, mine)).is_equal(0)
	assert_int(TradePanel._drop(mine, buy)).is_equal(0)
	assert_int(TradePanel._drop(buy, {"kind": "hero"})).is_equal(0)
