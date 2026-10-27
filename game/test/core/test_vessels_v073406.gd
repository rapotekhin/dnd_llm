extends GdUnitTestSuite
## Vessels of water (v0.7.34.6, the author's review): each waterskin, flask or jug keeps its own pints, the water
## weighs, a drink takes from the least full; the master fills them by words where the scene has water.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.character["inventory"] = {"waterskin": 2, "flask_or_tankard": 1}
	s.character["vessels"] = {}
	NeedRules.state(s, data)
	fx = EffectEngine.new()


func test_each_vessel_keeps_its_water_and_the_water_weighs() -> void:
	var dry := CharacterRules.carried_weight(s.character, data, s.items)
	s.room_id = "brod-square"
	NeedRules.fill(s, data)
	assert_str(VesselRules.summary(s.character, data, "waterskin")).is_equal("вода 4/4, вода 4/4")
	assert_str(VesselRules.summary(s.character, data, "flask_or_tankard")).is_equal("вода 1/1")
	assert_float(CharacterRules.carried_weight(s.character, data, s.items) - dry).is_equal_approx(9.0, 0.01)
	NeedRules.set_value(s, data, "water", 50.0)
	s.room_id = "brod-gate"
	NeedRules.drink(s, data)  # 25 points → a pint of 25: the flask first, then a skin
	assert_str(VesselRules.summary(s.character, data, "flask_or_tankard")).is_equal("пусто")
	assert_float(NeedRules.value(s, data, "water")).is_greater_equal(75.0)
	assert_float(VesselRules.pints(s.character, data)).is_equal_approx(8.0, 0.01)


func test_an_old_pool_of_drinks_pours_into_the_waterskins() -> void:
	s.character.erase("vessels")
	s.character["inventory"] = {"waterskin": 2}
	s.character["needs"]["skin"] = 3  # 3 drinks × 2 pints
	assert_str(VesselRules.summary(s.character, data, "waterskin")).is_equal("вода 4/4, вода 2/4")
	assert_bool(s.character["needs"].has("skin")).is_false()


func test_the_master_fills_by_words_only_where_there_is_water() -> void:
	s.room_id = "brod-gate"
	var dry := fx.validate(s, data, "t-1", {"kind": "fill"})
	assert_str(str(dry.get("reason", ""))).contains("нет воды")
	s.room_id = "brod-square"
	var r := fx.validate(s, data, "t-2", {"kind": "fill", "item_id": "flask_or_tankard"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-2", [r["effect_id"]])
	assert_str(VesselRules.summary(s.character, data, "flask_or_tankard")).is_equal("вода 1/1")
	assert_str(VesselRules.summary(s.character, data, "waterskin")).is_equal("пусто, пусто")
	var none := fx.validate(s, data, "t-3", {"kind": "fill", "item_id": "bucket"})
	assert_str(str(none.get("reason", ""))).contains("нет такой ёмкости")


func test_a_furnished_source_is_water_for_the_vessels() -> void:
	s.room_id = "brod-tavern-hall"
	assert_bool(NeedRules.water_here(s, data)).is_false()
	var r := fx.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Кадка", "description": "Стоячая вода с ряской", "source": "foul_water"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_bool(NeedRules.water_here(s, data)).is_true()
	assert_bool(NeedRules.foul_here(s, data)).is_true()
	assert_str(str(PropRules.snapshot(s, data, s.room_id)[0].get("source", ""))).is_equal("foul_water")
