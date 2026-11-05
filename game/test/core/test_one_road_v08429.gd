extends GdUnitTestSuite
## One road, review 2, group A·H·L (v0.8.4.29): a thing given away goes through ItemRules.remove and comes off its slot,
## every service refuses the wanted by one SocialRules.service_why, the place's tills pay first by one
## PropertyRules.pay_from_till, a shift of anything pays by JobRules.earned, «21 день».

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	return s


func test_a_thing_handed_over_comes_off_its_slot() -> void:
	var s := _hero("brod-square")
	s.character["inventory"]["dagger"] = 1
	s.character["equipped"]["main_hand"] = "dagger"
	var lines: Array[String] = []
	QuestRules._hand_over(s, data, "dagger", lines, "Отдано")
	assert_bool(s.character["inventory"].has("dagger")).is_false()
	assert_str(str(s.character["equipped"].get("main_hand", ""))).is_empty()


func test_a_thing_known_is_added_by_one_road() -> void:
	var s := _hero("brod-square")
	assert_str(ItemRules.add(s.character, "dagger", 2)).is_equal("dagger")
	ItemRules.add(s.character, "dagger")
	assert_int(int(s.character["inventory"]["dagger"])).is_equal(3)


func test_the_wanted_get_no_loan_and_no_supplier() -> void:
	var s := _hero("brod-exchange")
	s.character["gold_cp"] = 100000
	assert_str(BankRules.deposit_why(s, data, "npc_changer", "demand", 1000)).is_empty()
	s.wanted[ReputationRules.home_of(data, "npc_changer")] = TimeRules.abs_minute(s)
	assert_str(BankRules.deposit_why(s, data, "npc_changer", "demand", 1000)).is_equal("SHOP_CLOSED_WANTED")
	assert_str(SocialRules.service_why(s, data, "npc_changer")).is_equal("SHOP_CLOSED_WANTED")


func test_the_tills_pay_before_the_purse() -> void:
	var s := _hero("brod-square")
	s.character["gold_cp"] = 100
	PropertyRules.state(s.character)["p"] = {"cash": 50}
	ShopRules.venue(s.character, "p")["cash"] = 30
	assert_int(PropertyRules.pay_from_till(s, data, "p", 100, "test")).is_equal(0)
	assert_int(int(PropertyRules.state(s.character)["p"]["cash"])).is_equal(0)
	assert_int(ShopRules.till(s.character, "p")).is_equal(0)
	assert_int(Ledger.balance(s)).is_equal(80)
	PropertyRules.state(s.character)["p"]["cash"] = 10
	assert_int(PropertyRules.pay_from_till(s, data, "p", 200, "test", Being.HERO, true, true)).is_equal(200)  # whole: nothing taken
	assert_int(int(PropertyRules.state(s.character)["p"]["cash"])).is_equal(10)
	assert_int(PropertyRules.pay_from_till(s, data, "p", 50, "test", Being.HERO, false)).is_equal(40)  # no purse: the rest unpaid
	PropertyRules.to_till(s, data, "p", 7, "test")
	assert_int(int(PropertyRules.state(s.character)["p"]["cash"])).is_equal(7)
	PropertyRules.to_till(s, data, "", 5, "test")  # no place — the purse
	assert_int(Ledger.balance(s)).is_equal(85)


func test_a_shift_pays_by_one_rule() -> void:
	var s := _hero("brod-square")
	var e := JobRules.earned(s.character, data, 100, {"pay": 1.0, "tips": 0.25}, 2.0)
	assert_int(int(e["pay"])).is_equal(100)
	assert_int(int(e["tips"])).is_equal(50)
	var spec := ShopRules.shift_spec(s, data, "")
	assert_str(str(spec["skill"])).is_equal(str(ShopRules.cfg(data)["shift"]["skill"]))
	assert_bool(spec.has("ladder")).is_true()


func test_days_are_counted_in_russian() -> void:
	assert_str(CalendarRules.days_count(21)).is_equal("21 день")
	assert_str(CalendarRules.days_count(3)).is_equal("3 дня")
	assert_str(CalendarRules.days_count(12)).is_equal("12 дней")
