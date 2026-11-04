extends GdUnitTestSuite
## Coated and puddles (roadmap v0.8.4.28.2): one status `coated` with its liquid on any holder — a foe, the hero, a thing —
## gives what the liquid's `coat` says (oil: fire +5, alchemist's fire: burns until put out, water: puts the fire out); a
## flask is thrown by its liquid; a liquid poured on a square is a zone of the ground (oil to slip on and burn, water that
## puts the fire out).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hit(s: GameSession, item: String, t: Dictionary) -> Array[String]:
	var hero := CombatRules.player(s)
	s.character["inventory"][item] = 9
	ItemRules.belt_put(s.character, data, s.items, item)
	t["ac"] = 1
	var lines: Array[String] = []
	for i in 9:
		ChecklistProbe.turn(s, data, hero)
		lines.append_array(Acts.one("throw").go(s, data, hero, str(t["id"]), {"item": item}))
		if not LiquidRules.coat_on(s, t).is_empty():
			break
	return lines


func test_oil_on_a_foe_makes_the_next_fire_burn_more() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["hp"] = 100
	var lines := _hit(s, "oil_flask", goblin)
	assert_str(str(LiquidRules.coat_on(s, goblin).get("liquid", ""))).override_failure_message(" · ".join(lines)).is_equal("oil")
	assert_int(int(goblin["hp"])).is_equal(100)  # oil does no harm by itself
	lines.clear()
	Harm.typed(s, data, goblin, 1, "fire", lines, "огонь", false)
	assert_int(int(goblin["hp"])).override_failure_message(" · ".join(lines)).is_less_equal(100 - 6)
	assert_bool(LiquidRules.coat_on(s, goblin).is_empty()).is_true()


func test_alchemists_fire_burns_until_water_puts_it_out() -> void:
	var s := ChecklistProbe.session(data)
	var ogre := ChecklistProbe.fight(s, data, "ogre")
	_hit(s, "alchemists_fire_flask", ogre)
	assert_str(LiquidRules.burning(s, ogre)).is_equal("1d4")
	var hp := int(ogre["hp"])
	var lines: Array[String] = []
	CombatRules._fire(s, data, ogre, lines)
	assert_int(int(ogre["hp"])).is_less(hp)
	if LiquidRules.burning(s, ogre).is_empty():  # it beat the flames itself
		LiquidRules.coat(s, data, ogre, "alchemists_fire", "Алхимический огонь")
	lines.assign(LiquidRules.coat(s, data, ogre, LiquidRules.WATER, "вода"))
	assert_str(LiquidRules.burning(s, ogre)).is_empty()
	assert_bool(LiquidRules.douses(s, ogre)).is_true()


func test_spilt_oil_trips_and_burns_away() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	var lines: Array[String] = []
	FightField.splash(s, data, at, {"liquid": "oil"}, "Масло", lines)
	assert_array(TestUtils.zones_on_cell(s, at)).contains(["Масло"])
	for z: Dictionary in SpellEffects.zones(s):
		z["dc"] = 99
	FightGrid.put(goblin, at)
	goblin["zoned"] = []
	SpellEffects.zone_tick(s, data, goblin, "enter")
	assert_bool(CombatRules._has(goblin, "prone")).is_true()
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).is_true()
	assert_bool(SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "puddle:oil")).is_false()


func test_water_on_a_square_puts_the_fire_out_and_does_not_catch() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(2, 0)
	var lines: Array[String] = []
	FightField.splash(s, data, at, {"liquid": "alchemists_fire"}, "Огонь", lines)
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).is_true()
	FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(FightField.douses_at(s, data, at)).is_true()
	FightField.splash(s, data, at, {"liquid": "alchemists_fire"}, "Огонь", lines)
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).is_false()
	LiquidRules.coat(s, data, goblin, "alchemists_fire", "Огонь")
	FightGrid.put(goblin, at)
	FightField.stepped(s, data, goblin, lines)
	assert_str(LiquidRules.burning(s, goblin)).is_empty()


func test_a_thing_wet_or_oiled_by_the_master_is_the_same_coat() -> void:
	var s := ChecklistProbe.session(data)
	var iron := {}
	assert_bool(ThingRules.burns(s, data, iron, {"made_of": "iron"})).is_false()
	LiquidRules.coat(s, data, iron, "oil", "масло")
	assert_bool(ThingRules.burns(s, data, iron, {"made_of": "iron"})).is_true()
	var wood := {}
	ThingRules.douse(s, data, wood)
	assert_str(ThingRules.ignite(s, data, wood, {"made_of": "wood"}, "факел")).is_equal("мокрое не горит")


func test_a_flask_is_thrown_by_its_liquid() -> void:
	var fx := ItemRules.consumable(data, "holy_water")
	assert_str(str(fx["throw"]["liquid"])).is_equal("holy_water")
	assert_array(fx["throw"]["types"]).contains(["undead"])
	assert_bool(ItemRules.spills(ItemRules.consumable(data, "oil_flask")["throw"])).is_true()
	assert_bool(ItemRules.spills(ItemRules.consumable(data, "acid_vial")["throw"])).is_false()
	assert_bool(data["rules"]["consumables"].has("oil_flask")).is_false()
