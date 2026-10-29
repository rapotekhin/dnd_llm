extends GdUnitTestSuite
## Weather and seasons (v0.7.46): a location's weather by the pack's tables of terrain and season, rolled each day;
## fog and a downpour — disadvantage on ranged attacks and Perception, the watchers see less; a downpour soaks an open
## camp and floods the ford; snow and mud lengthen the way; a night in frost without a guard costs a CON save against
## exhaustion; the heat on the way; the catch by weather; the master's `weather` for hours.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = "brod-square", day: int = 2) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.settings["weather"] = true
	s.room_id = room
	s.minute = 12 * 60
	s.day = day
	s.rng.seed = 7
	WeatherRules.sync(s, data)
	return s


func _weather(s: GameSession, loc: String, k: String) -> void:
	WeatherRules._state(s)["by_loc"][loc] = k
	WeatherRules._flags(s, data)


func test_every_outdoor_location_rolls_by_its_terrain_and_season() -> void:
	var s := _session()
	var st := WeatherRules._state(s)
	assert_int(int(st["day"])).is_equal(2)
	for loc: String in ["brod", "pushcha", "outpost"]:
		var k := WeatherRules.at(s, data, loc)
		assert_bool(WeatherRules.table(s, data, loc).has(k)).override_failure_message("%s: %s" % [loc, k]).is_true()
		assert_bool(s.flags.has("weather_%s_%s" % [k, loc])).is_true()
	assert_str(WeatherRules.at(s, data, "mine")).is_empty()  # under the earth there is no sky
	# summer in the start month: no snow or frost in the grassland
	assert_bool(WeatherRules.table(s, data, "brod").has("snow")).is_false()
	var again := _session()
	assert_str(WeatherRules.at(again, data, "pushcha")).is_equal(WeatherRules.at(s, data, "pushcha"))  # seeded by the day


func test_a_new_day_rolls_again_and_the_old_flags_go() -> void:
	var s := _session()
	_weather(s, "brod", "downpour")
	assert_bool(s.flags.has("weather_downpour_brod")).is_true()
	var seen := {}
	for i in 30:
		TimeRules.advance(s, data, 1440)
		seen[WeatherRules.at(s, data, "brod")] = true
		var mine := (s.flags as Array).filter(func(f: Variant) -> bool: return str(f).begins_with("weather_") and str(f).ends_with("_brod"))
		assert_int(mine.size()).is_equal(1)
	assert_int(seen.size()).is_greater(1)


func test_under_a_roof_the_weather_does_not_touch_the_hero() -> void:
	var s := _session("brod-tavern-hall")
	_weather(s, "brod", "fog")
	assert_str(WeatherRules.here(s, data)).is_empty()
	assert_str(WeatherRules.obscure_why(s, data)).is_empty()
	assert_str(WeatherRules.text(s, data)).contains("под крышей")
	s.room_id = "brod-square"
	assert_str(WeatherRules.obscure_why(s, data)).is_equal("туман")


func test_fog_gives_disadvantage_to_ranged_attacks_not_to_melee() -> void:
	var s := _session("pushcha-glade")
	_weather(s, "pushcha", "fog")
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк", "desc": "", "col": 4}], {})
	var wolf: Dictionary = CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_array(CombatRules.hero_attack_dis(s, data, wolf)).contains(["туман"])
	wolf["col"] = int(CombatRules.player(s)["col"])
	assert_array(CombatRules.hero_attack_dis(s, data, wolf)).not_contains(["туман"])
	_weather(s, "pushcha", "clear")
	wolf["col"] = 4
	assert_array(CombatRules.hero_attack_dis(s, data, wolf)).not_contains(["туман"])


func test_fog_and_downpour_blind_the_watchers_and_the_hero() -> void:
	var s := _session()
	_weather(s, "brod", "clear")
	var base := TimeRules.passive_penalty(s, data)
	var unseen := WeatherRules.unseen(s, data)
	_weather(s, "brod", "downpour")
	assert_int(TimeRules.passive_penalty(s, data)).is_equal(base + 5)
	assert_int(WeatherRules.unseen(s, data)).is_equal(unseen + 5)


func test_a_night_in_frost_without_a_fire_costs_a_save_against_exhaustion() -> void:
	var s := _session("pushcha-glade")
	var c := s.character
	c["inventory"].erase("tinderbox")
	c["inventory"].erase("blanket")
	c["inventory"]["rations"] = 2
	c["saves"]["con"] = -40  # only a natural 20 saves
	_weather(s, "pushcha", "frost")
	var lines := ExplorationRules.long_rest(s, data, ExplorationRules.camp_default(c, data))
	var text := "\n".join(lines)
	assert_str(text).contains("без защиты")
	assert_int(ConditionRules.exhaustion(c)).override_failure_message(text).is_equal(1)


func test_a_fire_warm_clothes_or_a_roof_guard_against_frost() -> void:
	var s := _session("pushcha-glade")
	var c := s.character
	c["inventory"].erase("blanket")
	c["inventory"]["rations"] = 4
	c["inventory"]["tinderbox"] = 1
	c["saves"]["con"] = -40
	_weather(s, "pushcha", "frost")
	var text := "\n".join(ExplorationRules.long_rest(s, data, ExplorationRules.camp_default(c, data)))
	assert_str(text).contains("костёр")
	assert_int(ConditionRules.exhaustion(c)).is_equal(0)
	c["inventory"].erase("tinderbox")
	c["inventory"]["winter_clothes"] = 1
	assert_str(WeatherRules.guard(s, data, "cold", WeatherRules.camp_fire(s, data))).is_equal("Тёплая одежда")


func test_a_downpour_puts_out_the_fire_and_soaks_an_open_camp() -> void:
	var s := _session("pushcha-glade")
	var c := s.character
	c["inventory"].erase("tent_two_person")
	c["inventory"]["rations"] = 4
	c["inventory"]["tinderbox"] = 1
	c["saves"]["con"] = -40
	c["hp"] = 1
	_weather(s, "pushcha", "downpour")
	assert_bool(WeatherRules.camp_fire(s, data)).is_false()
	var text := "\n".join(ExplorationRules.long_rest(s, data, ExplorationRules.camp_default(c, data)))
	assert_str(text).contains("промок")
	assert_int(int(c["hp"])).is_less_equal(int(c["max_hp"]) / 2)
	# a tent keeps it dry
	c["inventory"]["tent_two_person"] = 1
	_weather(s, "pushcha", "downpour")
	text = "\n".join(ExplorationRules.long_rest(s, data, ExplorationRules.camp_default(c, data)))
	assert_str(text).contains("в палатке сухо")
	assert_int(int(c["hp"])).is_equal(int(c["max_hp"]))


func test_a_downpour_floods_the_ford_to_the_glade() -> void:
	var s := _session("pushcha-trail")
	_weather(s, "pushcha", "clear")
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-trail")).contains(["pushcha-glade"])
	_weather(s, "pushcha", "downpour")
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-trail")).not_contains(["pushcha-glade"])
	assert_array(SceneRules.room(s, data["world"], "pushcha-trail")["hooks"]).contains(["ручей у брода вздулся от ливня и ревёт — к поляне не перейти"])
	_weather(s, "pushcha", "rain")
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-trail")).contains(["pushcha-glade"])


func test_snow_and_mud_lengthen_the_way_between_locations() -> void:
	var s := _session("brod-gate")
	_weather(s, "brod", "clear")
	_weather(s, "pushcha", "clear")
	var m0 := s.minute
	TimeRules.on_move(s, data, "brod-gate", "pushcha-edge")
	var plain := s.minute - m0
	_weather(s, "pushcha", "snow")
	m0 = s.minute
	var lines := TimeRules.on_move(s, data, "pushcha-edge", "brod-gate")
	assert_int(s.minute - m0).is_equal(plain * 2)
	assert_str("\n".join(lines)).contains("снег")
	assert_float(WeatherRules.travel_mult(s, data, "brod-square", "brod-gate")).is_equal(1.0)  # brod is clear


func test_heat_on_the_way_once_a_day_and_water_guards() -> void:
	var s := _session("pushcha-edge")
	var c := s.character
	c["saves"]["con"] = -40
	_weather(s, "pushcha", "heat")
	c["inventory"].erase("waterskin")
	var first := WeatherRules.on_way(s, data)
	assert_bool(first.is_empty()).is_false()
	assert_array(WeatherRules.on_way(s, data)).is_empty()  # once a day


func test_the_catch_follows_the_weather() -> void:
	var s := _session("brod-river-yard")
	_weather(s, "brod", "rain")
	assert_int(WeatherRules.wilds_pct(s, data, "fish")).is_equal(150)
	_weather(s, "brod", "downpour")
	assert_int(WeatherRules.wilds_pct(s, data, "fish")).is_equal(50)
	s.room_id = "pushcha-glade"
	_weather(s, "pushcha", "snow")
	assert_int(WeatherRules.wilds_pct(s, data, "game")).is_equal(150)


func test_the_masters_weather_holds_for_its_hours() -> void:
	var s := _session("pushcha-glade")
	_weather(s, "pushcha", "downpour")
	assert_str(str(WeatherRules.plan(s, data, {"weather": "storm", "hours": 2, "cause": "обряд друида у менгира"}).get("reason", ""))).contains("weather")
	assert_str(str(WeatherRules.plan(s, data, {"weather": "clear", "hours": 2, "cause": "так"}).get("reason", ""))).contains("cause")
	assert_str(str(WeatherRules.plan(s, data, {"weather": "clear", "hours": 99, "cause": "обряд друида у менгира"}).get("reason", ""))).contains("hours")
	s.room_id = "mine-gallery"
	assert_str(str(WeatherRules.plan(s, data, {"weather": "clear", "hours": 2, "cause": "обряд друида у менгира"}).get("reason", ""))).contains("неба")
	s.room_id = "pushcha-glade"
	var p := WeatherRules.plan(s, data, {"weather": "clear", "hours": 3, "cause": "обряд друида у менгира"})
	var lines := WeatherRules.apply(s, data, p["plan"])
	assert_str(lines[0]).contains("ясно")
	assert_str(WeatherRules.at(s, data, "pushcha")).is_equal("clear")
	assert_bool(s.flags.has("weather_clear_pushcha")).is_true()
	assert_bool(s.flags.has("weather_downpour_pushcha")).is_false()
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-trail")).contains(["pushcha-glade"])
	TimeRules.advance(s, data, 4 * 60)
	assert_bool(WeatherRules._state(s)["magic"].has("pushcha")).is_false()


func test_the_master_sees_the_weather_in_the_snapshot() -> void:
	var s := _session("brod-square")
	_weather(s, "brod", "fog")
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["scene"]["weather"])).contains("туман")
