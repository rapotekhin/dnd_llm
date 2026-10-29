extends GdUnitTestSuite
## The calendar and festivals (v0.7.44): the game's day as a date of the pack's calendar; a festival's flags on for its
## days and off after; the fair's guest trader and its prices; the harvest's cheap food and its quest; the master's
## own festival on the calendar within rules.calendar.make; the date and the festivals in the snapshot.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(day: int, room: String = "brod-square") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 10 * 60
	s.day = day
	CalendarRules.sync(s, data["world"])
	return s


func test_the_game_day_is_a_date_of_the_marks_calendar() -> void:
	var w: Dictionary = data["world"]
	assert_str(CalendarRules.text(w, 1)).is_equal("3 Жатвеня, день Пряжи")
	assert_str(CalendarRules.text(w, 12)).is_equal("14 Жатвеня, день Торга")
	assert_str(CalendarRules.text(w, 13)).is_equal("1 Листопада, день Кузни")
	assert_str(CalendarRules.season_text(w, 13)).contains("осень")
	var year := CalendarRules.year_days(w)
	assert_int(int(CalendarRules.date(w, 1 + year)["year"])).is_equal(int(CalendarRules.date(w, 1)["year"]) + 1)


func test_the_fair_sets_its_flags_for_its_days_and_takes_them_off() -> void:
	var s := _session(5)
	assert_bool(s.flags.has("fair")).is_false()
	assert_array(SceneRules.npcs(s, data["world"], "brod-square")).not_contains(["npc_pedlar"])
	s.day = 6
	var lines := CalendarRules.sync(s, data["world"])
	assert_str(" ".join(lines)).contains("Бродская ярмарка")
	assert_bool(s.flags.has("fair")).is_true()
	assert_array(SceneRules.npcs(s, data["world"], "brod-square")).contains(["npc_pedlar"])
	assert_str(str(SceneRules.room(s, data["world"], "brod-square")["description"])).contains("Ярмарка")
	s.day = 8
	CalendarRules.sync(s, data["world"])
	assert_bool(s.flags.has("fair")).is_true()
	s.day = 9
	lines = CalendarRules.sync(s, data["world"])
	assert_str(" ".join(lines)).contains("кончился")
	assert_bool(s.flags.has("fair")).is_false()
	assert_array(SceneRules.npcs(s, data["world"], "brod-square")).not_contains(["npc_pedlar"])


func test_a_flag_of_the_world_is_not_taken_off_by_the_calendar() -> void:
	var s := _session(5)
	s.flags.append("fair")  # set by something else before the fair
	s.day = 6
	CalendarRules.sync(s, data["world"])
	s.day = 9
	CalendarRules.sync(s, data["world"])
	assert_bool(s.flags.has("fair")).is_true()


func test_the_fair_buys_dearer_and_sells_cheaper() -> void:
	var s := _session(5)
	var sell_before := TradeRules.sell_price(s, data, "npc_merchant", "longsword")
	var buy_before := TradeRules.buy_price(s, data, "npc_merchant", "lantern")
	s.day = 6
	CalendarRules.sync(s, data["world"])
	assert_int(TradeRules.sell_price(s, data, "npc_merchant", "longsword")).is_greater(sell_before)
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", "lantern")).is_less(buy_before)


func test_the_harvest_makes_food_cheap_and_opens_its_quest() -> void:
	var s := _session(9, "brod-tavern-hall")
	var bread_before := TradeRules.buy_price(s, data, "npc_innkeeper", "roast_meat")
	assert_array(QuestRules.offers_here(s, data["world"])).not_contains(["harvest_table"])
	s.day = 10
	CalendarRules.sync(s, data["world"])
	assert_bool(s.flags.has("harvest_feast")).is_true()
	assert_int(TradeRules.buy_price(s, data, "npc_innkeeper", "roast_meat")).is_less(bread_before)
	assert_float(CalendarRules.price_pct(s, data, "longsword", "buy")).is_equal(1.0)  # only food
	assert_array(QuestRules.offers_here(s, data["world"])).contains(["harvest_table"])


func test_the_panel_and_the_master_see_the_nearest_festivals() -> void:
	var s := _session(2)
	var near := CalendarRules.upcoming(s, data, data["world"])
	assert_bool(near.is_empty()).is_false()
	assert_str(str(near[0]["name"])).is_equal("Торговый день")
	assert_int(int(near[0]["in"])).is_equal(3)
	assert_str(str(near[1]["name"])).is_equal("Бродская ярмарка")
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["scene"]["time_of_day"])).contains("Жатвеня")
	assert_str(" ".join(snap["scene"]["calendar"])).contains("Дожинки")


func test_the_master_puts_a_feast_of_its_own_on_the_calendar() -> void:
	var s := _session(2)
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t1", {"kind": "festival", "name": "Свадьба кузнеца", "cause": "Дрогин женится на дочери мельника",
		"starts_in": 2, "days": 1, "buy_pct": 80, "tags": ["food"]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t1", [r["effect_id"]])
	assert_str(" ".join(CalendarRules.snapshot(s, data, data["world"]))).contains("Свадьба кузнеца")
	assert_bool(bool(fx.validate(s, data, "t2", {"kind": "festival", "name": "Ещё пир", "cause": "староста хочет праздника", "starts_in": 1})["accepted"])).is_false()
	assert_bool(bool(fx.validate(s, data, "t3", {"kind": "festival", "name": "Долгий пир", "cause": "вернулся караван с юга", "days": 9})["accepted"])).is_false()
	s.day = 4
	CalendarRules.sync(s, data["world"])
	assert_array(CalendarRules.active(s, data["world"])).contains(["made_1"])
	assert_float(CalendarRules.price_pct(s, data, "roast_meat", "buy")).is_equal_approx(0.8, 0.001)
	s.day = 5
	CalendarRules.sync(s, data["world"])
	assert_array(CalendarRules.active(s, data["world"])).not_contains(["made_1"])
