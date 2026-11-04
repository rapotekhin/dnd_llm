extends GdUnitTestSuite
## Liquids (roadmap v0.8.4.28): one row per liquid; a vessel holds one liquid on its copy, a ready thing is a vessel with
## its liquid — poured out or drunk it leaves the vessel, a vessel filled to the brim is the thing again; ale and wine
## make one drunk past 2 + CON; anybody drinks alike.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.character["inventory"] = {}
	LiquidRules.drain(s.character)
	NeedRules.state(s, data)


func _of(id: String) -> Dictionary:
	return LiquidRules.first(s.character, data, id)


func test_a_ready_thing_poured_out_leaves_its_vessel() -> void:
	s.character["inventory"] = {"oil_flask": 2}
	assert_str(str(_of("oil_flask")["liquid"])).is_equal("oil")
	assert_str(LiquidRules.drink_why(data, _of("oil_flask"))).is_equal("LIQUID_NOT_DRINK")
	LiquidRules.pour_out(s.character, data, _of("oil_flask"))
	assert_int(int(s.character["inventory"]["oil_flask"])).is_equal(1)
	assert_int(int(s.character["inventory"]["empty_flask"])).is_equal(1)
	assert_str(LiquidRules.summary(s.character, data, "empty_flask")).is_equal("пусто")


func test_a_flask_filled_to_the_brim_is_the_ready_thing() -> void:
	s.character["inventory"] = {"jug_or_pitcher": 1, "empty_flask": 2}
	var st := Thing.nth(s.character, "jug_or_pitcher", 0)
	st["liquid"] = "oil"
	st["pints"] = 3.0
	for i in 2:
		var jug := _of("jug_or_pitcher")
		var flask: Dictionary = LiquidRules.pour_targets(s.character, data, jug).filter(func(v: Dictionary) -> bool: return v["id"] == "empty_flask")[0]
		LiquidRules.pour(s.character, data, jug, flask)
	assert_int(int(s.character["inventory"].get("oil_flask", 0))).is_equal(2)
	assert_bool(s.character["inventory"].has("empty_flask")).is_false()
	assert_str(LiquidRules.summary(s.character, data, "jug_or_pitcher")).is_equal("масло 1/8")


func test_one_vessel_holds_one_liquid() -> void:
	s.character["inventory"] = {"waterskin": 1, "goat_milk": 1, "ale": 1}
	LiquidRules.pour_out(s.character, data, _of("goat_milk"))  # the jug is left
	Thing.nth(s.character, "waterskin", 0).merge({"liquid": "water", "pints": 4.0})
	var jug := _of("jug_or_pitcher")
	var milk := Thing.nth(s.character, "jug_or_pitcher", jug["i"])
	milk.merge({"liquid": "milk", "pints": 2.0})
	assert_str(LiquidRules.pour_why(_of("waterskin"), _of("jug_or_pitcher"))).is_equal("LIQUID_OTHER")
	assert_str(LiquidRules.pour_why(_of("waterskin"), _of("ale"))).is_equal("LIQUID_FULL")
	assert_str(LiquidRules.pour_why(_of("waterskin"), _of("waterskin"))).is_equal("LIQUID_SAME")


func test_a_bottle_drunk_from_keeps_the_rest() -> void:
	s.character["inventory"] = {"bottle_wine": 1}
	LiquidRules.drink(s, data, Sheet.HERO, _of("bottle_wine"))
	assert_bool(s.character["inventory"].has("bottle_wine")).is_false()
	assert_str(LiquidRules.summary(s.character, data, "bottle_glass")).is_equal("вино 0.5/1.5")


func test_ale_makes_one_drunk_past_its_constitution_and_it_sobers() -> void:
	s.character["abilities"]["con"] = 10
	s.character["inventory"] = {"ale": 3}
	NeedRules.set_value(s, data, "water", 40.0)
	for i in 2:
		LiquidRules.drink(s, data, Sheet.HERO, _of("ale"))
	assert_float(NeedRules.value(s, data, "water")).is_greater(40.0)
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_false()
	var lines := LiquidRules.drink(s, data, Sheet.HERO, _of("ale"))
	assert_bool(ConditionRules.has(s.character, "poisoned")).override_failure_message(" · ".join(lines)).is_true()
	assert_int(int(s.character["inventory"]["cup_clay"])).is_equal(3)
	TimeRules.advance(s, data, 61)
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_false()


func test_thirst_drinks_water_not_ale() -> void:
	s.character["inventory"] = {"ale": 2}
	s.room_id = "brod-gate"
	NeedRules.set_value(s, data, "water", 30.0)
	assert_str(NeedRules.can_drink(s, data)).is_equal("NEED_NO_WATER")


func test_a_guard_drinks_on_the_same_road() -> void:
	var gs := ChecklistProbe.session(data)
	var guard := ChecklistProbe.fight(gs, data, "guard")
	guard["inventory"] = {"ale": 4}
	for i in 4:
		LiquidRules.drink(gs, data, guard, LiquidRules.first(guard, data, "ale"))
	assert_bool(ConditionRules.has(guard, "poisoned")).is_true()
	assert_int(int(guard["inventory"]["cup_clay"])).is_equal(4)
