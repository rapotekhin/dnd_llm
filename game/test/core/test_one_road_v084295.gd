extends GdUnitTestSuite
## One road, review 2, groups G, K, O (v0.8.4.29.5): where a person is (Where with a festival's guests, the people of a location,
## Life.beside, a place's own staff, the room of an encounter), time (TimeRules.in_hours, today / count, periods), a person of
## standing in one list, rarity by Scale, one line of a check.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_one_window_of_hours() -> void:
	var s := TestUtils.new_session()
	s.minute = 22 * 60
	assert_bool(TimeRules.in_hours(s, 20, 7)).is_true()
	assert_bool(TimeRules.in_hours(s, 8, 20)).is_false()
	assert_bool(TimeRules.in_hours(s, 9, 9)).is_true()  # all day, a door and a schedule alike
	s.minute = 3 * 60
	assert_bool(TimeRules.in_hours(s, 20, 7)).is_true()


func test_one_catch_up_of_periods() -> void:
	var rec := {"fee_day": 1}
	assert_int(TimeRules.periods(rec, "fee_day", 16, 7)).is_equal(2)
	assert_int(int(rec["fee_day"])).is_equal(15)
	assert_int(TimeRules.periods(rec, "fee_day", 16, 7)).is_equal(0)
	assert_int(TimeRules.days_since(0, 3 * 1440 + 5)).is_equal(3)


func test_a_haggle_counts_by_the_days_record() -> void:
	var s := TestUtils.new_session()
	var m := {}
	assert_int(TimeRules.today(s, m, "haggles")).is_equal(0)
	TimeRules.count(s, m, "haggles")
	TimeRules.count(s, m, "haggles")
	assert_int(TimeRules.today(s, m, "haggles")).is_equal(2)
	s.day += 1
	assert_int(TimeRules.today(s, m, "haggles")).is_equal(0)


func test_a_festivals_guest_is_where_the_room_says() -> void:
	var s := TestUtils.new_session()
	var world: Dictionary = data["world"]
	for fid: String in CalendarRules.all(s, world):
		var g: Dictionary = CalendarRules.all(s, world)[fid].get("guests", {})
		if g.is_empty():
			continue
		var npc := str(g.keys()[0])
		var room := str(g[npc])
		var tries := 0
		while not CalendarRules.active(s, world).has(fid) and tries < 400:
			s.day += 1
			tries += 1
		if not CalendarRules.active(s, world).has(fid):
			return
		assert_str(CalendarRules.guest_room(s, world, npc)).is_equal(room)
		assert_str(Where.npc_room(s, data, npc)).is_equal(room)
		var home := ReputationRules.home_room(data, npc)
		if not home.is_empty() and home != room:
			assert_bool(SceneRules.npcs(s, world, home).has(npc)).is_false()  # not in two rooms at once
		return


func test_the_people_of_a_location_are_the_living() -> void:
	var s := TestUtils.new_session()
	var loc := ReputationRules.home_of(data, "npc_innkeeper")
	var people := Where.people_of(s, data, loc)
	assert_array(people).contains(["npc_innkeeper"])
	Being.of(s, "npc_innkeeper")["dead"] = true
	assert_array(Where.people_of(s, data, loc)).not_contains(["npc_innkeeper"])


func test_beside_the_one_who_acts() -> void:
	var s := TestUtils.new_session()
	var here := s.npcs_here(data["world"], s.room_id)
	if here.is_empty():
		return
	assert_bool(Life.beside(s, data, Being.HERO, here[0])).is_true()
	assert_bool(Life.beside(s, data, Being.HERO, "nobody_at_all")).is_false()


func test_a_person_of_standing_in_one_list() -> void:
	var s := TestUtils.new_session()
	for o: Dictionary in data["world"].get("offices", {}).values():
		var chief := str(o.get("chief", ""))
		if not chief.is_empty():
			assert_bool(LetterRules.notable(s, data, chief, false)).is_true()  # a headman robbed weighs on the wergild too
			return


func test_rarity_by_the_scale() -> void:
	var items: Dictionary = data["items"]
	assert_str(ItemRules.rarity_for_points(items, 0)).is_equal("common")
	var steps: Array = items["rarity_by_points"]
	var last: Array = steps[-1]
	assert_str(ItemRules.rarity_for_points(items, int(last[0]) + 100)).is_equal(str(last[1]))
	assert_int(ItemRules.rarity_level(items, str(last[1]))).is_greater_equal(1)
	assert_dict(Scale.up_to([{"points": 2, "n": "a"}, {"points": 5, "n": "b"}], 3)).is_equal({"points": 5, "n": "b"})
	assert_dict(Scale.up_to([{"points": 2}], 3)).is_empty()


func test_one_line_of_a_check() -> void:
	var r := {"nat": 12, "total": 15, "dc": 13}
	assert_str(Activity.line("Приручение", "Уход за животными", r, "успех", " (угощение: мясо)")).is_equal(
		"Приручение: Уход за животными 12 + 3 = 15 против Сл 13 (угощение: мясо) — успех")
