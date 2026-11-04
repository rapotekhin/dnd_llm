extends GdUnitTestSuite
## «Налить» as a craft (roadmap v0.8.4.28.3): a liquid that `needs` a tool is poured only by one proficient with it and
## carrying it; a vessel takes only its `only` (a lamp only oil, never water at a source); a lamp lights the way only with
## oil in it and burns a pint in six hours in the dark; a vial of poison coats a blade by its liquid and leaves the vial.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.character["inventory"] = {}
	s.character["tools"] = []
	LiquidRules.drain(s.character)


func _of(id: String) -> Dictionary:
	return LiquidRules.first(s.character, data, id)


func test_acid_is_poured_only_with_alchemists_supplies() -> void:
	s.character["inventory"] = {"acid_vial": 1, "vial": 1}
	assert_str(LiquidRules.pour_why(s.character, data, _of("acid_vial"), _of("vial"))).is_equal("LIQUID_NEEDS")
	s.character["tools"] = ["alchemists_supplies"]
	assert_str(LiquidRules.pour_why(s.character, data, _of("acid_vial"), _of("vial"))).is_equal("LIQUID_NEEDS_KIT")
	s.character["inventory"]["alchemists_supplies"] = 1
	assert_str(LiquidRules.pour_why(s.character, data, _of("acid_vial"), _of("vial"))).is_empty()
	LiquidRules.pour_out(s.character, data, _of("acid_vial"))  # anybody may pour it out
	assert_int(int(s.character["inventory"]["vial"])).is_equal(2)


func test_a_lamp_takes_only_oil_and_no_water_at_a_well() -> void:
	s.character["inventory"] = {"lamp": 1, "waterskin": 1, "oil_flask": 1}
	Thing.nth(s.character, "waterskin", 0).merge({"liquid": "water", "pints": 4.0})
	assert_str(LiquidRules.pour_why(s.character, data, _of("waterskin"), _of("lamp"))).is_equal("LIQUID_NOT_FOR")
	assert_array(LiquidRules.to_fill(s.character, data, false).map(func(v: Dictionary) -> String: return v["id"])).not_contains(["lamp"])
	LiquidRules.pour(s.character, data, _of("oil_flask"), _of("lamp"))
	assert_str(LiquidRules.summary(s.character, data, "lamp")).is_equal("масло 1/1")
	assert_int(int(s.character["inventory"]["empty_flask"])).is_equal(1)


func test_a_lamp_lights_only_with_oil_and_burns_it_in_the_dark() -> void:
	s.room_id = "mine-gallery"
	s.character["inventory"] = {"lamp": 1}
	ItemRules.belt_put(s.character, data, s.items, "lamp")
	assert_bool(TimeRules.unlit(s, data)).is_true()
	assert_int(SightRules.light(s, data)).is_equal(0)
	Thing.nth(s.character, "lamp", 0).merge({"liquid": "oil", "pints": 1.0})
	assert_int(SightRules.light(s, data)).is_equal(int(SightRules.cfg(data)["lights"]["lamp"]))
	LiquidRules.burn(s, data)  # the clock of the lamps starts
	TimeRules.advance(s, data, 180)
	assert_str(LiquidRules.summary(s.character, data, "lamp")).is_equal("масло 0.5/1")
	var lines := TimeRules.advance(s, data, 200)
	assert_str(LiquidRules.summary(s.character, data, "lamp")).is_equal("пусто")
	assert_str(" · ".join(lines)).contains("выгорело")
	assert_int(SightRules.light(s, data)).is_equal(0)


func test_a_new_guard_s_lantern_is_full() -> void:
	var c := {"inventory": {"lantern": 1}}
	assert_bool(LiquidRules.fuelled(c, data, "lantern")).is_true()


func test_a_vial_of_poison_coats_the_blade_and_leaves_the_vial() -> void:
	s.character["inventory"] = {"poison_basic_vial": 1}
	var fx := ItemRules.consumable(data, "poison_basic_vial")
	assert_str(str(fx["coat"]["type"])).is_equal("poison")
	ItemRules.use(s.character, data, s.items, "poison_basic_vial", s.rng, s)
	assert_bool(s.character["inventory"].has("poison_basic_vial")).is_false()
	assert_str(LiquidRules.summary(s.character, data, "vial")).is_equal("пусто")
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return e.has("coat"))).is_true()


func _furnish(fx: EffectEngine, props: Array) -> void:
	var r := fx.validate(s, data, "t-f", {"kind": "furnish", "props": props})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-f", [r["effect_id"]])


func test_the_master_draws_wine_from_a_barrel_not_from_someone_s() -> void:
	var fx := EffectEngine.new()
	s.room_id = "brod-tavern-hall"
	s.character["inventory"] = {"bottle_glass": 2, "waterskin": 1}
	_furnish(fx, [{"name": "Бочка вина", "description": "Початая бочка", "source": "wine"}])
	assert_bool(NeedRules.water_here(s, data)).is_false()  # wine is no water
	var r := fx.validate(s, data, "t-1", {"kind": "fill", "liquid": "wine", "item_id": "bottle_glass"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_int(int(s.character["inventory"].get("bottle_wine", 0))).is_equal(2)  # a bottle full of wine is the bottle of wine
	PropRules.room_props(s, s.room_id)[0]["owner"] = "npc_innkeeper"
	var mine := fx.validate(s, data, "t-2", {"kind": "fill", "liquid": "wine"})
	assert_str(str(mine.get("reason", ""))).contains("чьё-то")
	var none := fx.validate(s, data, "t-3", {"kind": "fill", "liquid": "oil"})
	assert_str(str(none.get("reason", ""))).contains("неоткуда")


func test_the_master_pours_out_and_splashes_a_table_with_oil() -> void:
	var fx := EffectEngine.new()
	s.room_id = "brod-tavern-hall"
	s.character["inventory"] = {"oil_flask": 1, "bottle_wine": 1}
	_furnish(fx, [{"name": "Стол", "description": "Дубовый стол", "body": "table"}])
	var table: String = str(PropRules.snapshot(s, data, s.room_id).filter(func(p: Dictionary) -> bool: return p["name"] == "Стол")[0]["prop_id"])
	var r := fx.validate(s, data, "t-1", {"kind": "fill", "action": "splash", "item_id": "oil_flask", "prop_id": table})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_int(LiquidRules.fire_plus(s, PropRules.find(s, s.room_id, table))).is_equal(5)
	assert_int(int(s.character["inventory"]["empty_flask"])).is_equal(1)
	var out := fx.validate(s, data, "t-2", {"kind": "fill", "action": "pour_out", "item_id": "bottle_wine"})
	fx.apply(s, "t-2", [out["effect_id"]])
	assert_str(LiquidRules.summary(s.character, data, "bottle_glass")).is_equal("пусто")
	var dry := fx.validate(s, data, "t-3", {"kind": "fill", "action": "splash", "item_id": "bottle_glass"})
	assert_str(str(dry.get("reason", ""))).contains("пуст")
