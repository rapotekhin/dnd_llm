extends GdUnitTestSuite
## v0.8.4.1: sight in a fight: Fog Cloud and Darkness, blindness, the dark and light, an area at one the hero does not see.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


## A fight on an open field, the hero's turn with its action. The foes in the order given.
func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	TestUtils.fight(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	CombatRules.economy(s)["action"] = 1
	CombatRules.economy(s)["bonus"] = 1
	return out


## The foes by their monsters: the fight has them in the order of initiative.
func _ordered(foes: Array[Dictionary], monsters: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: String in monsters:
		out.append(foes.filter(func(f: Dictionary) -> bool: return str(f["monster"]) == m and not out.has(f))[0])
	return out


func _bow(s: GameSession) -> void:
	var c := s.character
	c["inventory"]["longbow"] = 1
	c["inventory"]["arrows"] = 20
	c["equipped"]["main_hand"] = "longbow"
	c["equipped"]["off_hand"] = ""
	c["equipped"]["shield"] = ""
	c["stowed"] = {}


## A zone of the spell on the square `at`, as the cast lays it.
func _zone(s: GameSession, id: String, at: Vector2i) -> Dictionary:
	var sus := SpellEffects.sustained(data, id)
	var z := {"spell": id, "name": str(data["spells"][id]["name"]), "shape": data["spells"][id]["area"], "follow": false, "on": [],
		"obscure": bool(sus["obscure"]), "veil": str(sus["veil"])}
	SpellEffects._lay(s, data, z, at)
	s.combat["zones"] = [z]
	return z


func _learn(s: GameSession, id: String) -> void:
	var sp: Dictionary = s.character["spells"]
	var always: Array = sp.get("always", [])
	always.append(id)
	sp["always"] = always
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	Stock.fill_slots(s.character)


func _says(list: Variant, word: String) -> bool:
	return (list as Array).any(func(x: Variant) -> bool: return str(x).to_lower().contains(word.to_lower()))


func _dis(s: GameSession, f: Dictionary) -> Array:
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"].get("main_hand", "")))
	return Attack.mods(s, data, CombatRules.player(s), f, Attack.of_weapon(w))["dis"]


# --- Fog Cloud and Darkness -----------------------------------------------------------------------------------------


func _adv(s: GameSession, f: Dictionary) -> Array:
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"].get("main_hand", "")))
	return Attack.mods(s, data, CombatRules.player(s), f, Attack.of_weapon(w))["adv"]


func test_a_shot_through_a_veil_is_rolled_as_plain() -> void:  # neither side sees: disadvantage and advantage cancel out
	for spell: String in ["fog_cloud", "darkness"]:
		var s := _hero("fighter_aira")
		_bow(s)
		var f := _fight(s, [{"monster": "goblin", "col": 3}])[0]
		assert_array(_dis(s, f)).is_empty()
		var z := _zone(s, spell, FightGrid.cell(CombatRules.player(s)) + Vector2i(9, 0))  # between them, neither inside
		assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
		assert_bool(_says(_dis(s, f), str(z["name"]))).is_true()
		assert_bool(_says(_adv(s, f), "не видно")).is_true()


func test_a_shot_out_of_a_veil_and_into_it_goes_too() -> void:
	for spell: String in ["fog_cloud", "darkness"]:
		var s := _hero("fighter_aira")
		_bow(s)
		var f := _fight(s, [{"monster": "goblin", "col": 3}])[0]
		_zone(s, spell, FightGrid.cell(CombatRules.player(s)))
		assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
		_zone(s, spell, FightGrid.cell(f))
		assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()


func test_a_seeing_shooter_at_one_it_cannot_be_seen_by_has_advantage_only() -> void:
	var s := _hero("fighter_aira")
	_bow(s)
	(s.character["features"] as Array).append("eldritch_invocation_devils_sight")
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_zone(s, "darkness", FightGrid.cell(f))
	assert_array(_dis(s, f)).is_empty()
	assert_bool(_says(_adv(s, f), "не видно")).is_true()


func test_a_blind_foe_in_the_open_is_shot_with_the_condition_only() -> void:
	var s := _hero("fighter_aira")
	_bow(s)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	(f["conditions"] as Array).append("blinded")
	assert_array(_dis(s, f)).is_empty()
	assert_bool(_adv(s, f).size() >= 1).is_true()
	assert_bool(_says(_adv(s, f), "не видно")).is_false()  # the condition gives it, not twice


func test_a_bolt_goes_by_guess_a_spell_of_sight_does_not() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_learn(s, "magic_missile")
	_learn(s, "sacred_flame")
	_learn(s, "hold_person")
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "magic_missile", "slot": 1})).is_empty()
	_zone(s, "fog_cloud", FightGrid.cell(f))
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "fire_bolt", "slot": 0})).is_empty()  # the spell's text does not ask to see
	for id: Array in [["magic_missile", 1], ["sacred_flame", 0], ["hold_person", 2]]:
		assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": str(id[0]), "slot": int(id[1])})).is_equal("COMBAT_NO_LINE")


func test_a_flask_is_thrown_into_a_veil() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	s.character["inventory"]["oil_flask"] = 1
	_zone(s, "fog_cloud", FightGrid.cell(f))
	FightGrid.put(CombatRules.player(s), FightGrid.cell(f) + Vector2i(-2, 0))
	assert_str(Acts.one("throw").can(s, data, CombatRules.player(s), str(f["id"]), {"item": "oil_flask"})).is_empty()


func test_a_blade_inside_a_veil_is_rolled_as_plain() -> void:  # both blind: the rule's cancelling, the blow is no worse
	for spell: String in ["fog_cloud", "darkness"]:
		var s := _hero("fighter_aira")
		var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
		var z := _zone(s, spell, FightGrid.cell(f))
		assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
		assert_bool(_says(_dis(s, f), str(z["name"]))).is_true()
		assert_bool(_says(_adv(s, f), "не видно")).is_true()
		var eyes := CombatRules.sight_mods(s, data, f, CombatRules.player(s))  # the foe the same
		assert_str(str(eyes["dis"])).is_not_empty()
		assert_str(str(eyes["adv"])).is_not_empty()


func test_a_foe_under_a_veil_is_heard_unless_it_hides() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	assert_bool(FightGrid.heard(s, data, f)).is_false()  # seen
	_zone(s, "fog_cloud", FightGrid.cell(f))
	assert_bool(FightGrid.heard(s, data, f)).is_true()
	f["hidden"] = true
	assert_bool(FightGrid.heard(s, data, f)).is_false()


func test_fog_cloud_grows_with_the_slot() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_learn(s, "fog_cloud")
	Acts.one("cast").go(s, data, CombatRules.player(s), FightGrid.aim_id(FightGrid.cell(f)), {"spell": "fog_cloud", "slot": 2})
	assert_int(int(SpellEffects.zones(s)[0]["shape"]["size"])).is_equal(40)


func test_the_sizes_are_those_of_the_spells() -> void:
	assert_int(int(data["spells"]["fog_cloud"]["area"]["size"])).is_equal(20)
	assert_int(int(data["spells"]["darkness"]["area"]["size"])).is_equal(15)


func test_darkness_puts_out_a_light_of_a_low_circle() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	var c := s.character
	ConditionRules.add_effect(c, {"condition": "", "source": {"kind": "spell", "id": "light", "name": "Свет"}, "ends": {}})
	ConditionRules.add_effect(c, {"condition": "", "source": {"kind": "spell", "id": "daylight", "name": "Дневной свет"}, "ends": {}})
	_learn(s, "darkness")
	assert_int(ConditionRules.effects(c).filter(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) in ["light", "daylight"]).size()).is_equal(2)
	var lines := Acts.one("cast").go(s, data, CombatRules.player(s), FightGrid.aim_id(FightGrid.cell(f)), {"spell": "darkness", "slot": 2})
	assert_str(" ".join(lines)).contains("Свет гаснет")
	var left: Array = ConditionRules.effects(c).map(func(e: Dictionary) -> String: return str(e.get("source", {}).get("id", "")))
	assert_bool(left.has("light")).is_false()
	assert_bool(left.has("daylight")).is_true()  # the third circle stands


func test_a_foe_in_the_open_is_seen_when_no_veil_is_near() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	_zone(s, "darkness", FightGrid.cell(CombatRules.player(s)) + Vector2i(30, 0))
	assert_bool(FightGrid.sees(s, data, CombatRules.player(s), f)).is_true()
	assert_array(_dis(s, f)).is_empty()


func test_a_stinking_cloud_is_a_veil_too() -> void:
	var s := _hero("fighter_aira")
	_bow(s)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	var z := _zone(s, "stinking_cloud", FightGrid.cell(f))
	assert_bool(_says(_dis(s, f), str(z["name"]))).is_true()


func test_the_cast_itself_lays_a_veil() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_learn(s, "fog_cloud")
	Acts.one("cast").go(s, data, CombatRules.player(s), FightGrid.aim_id(FightGrid.cell(f)), {"spell": "fog_cloud", "slot": 1})
	CombatRules.economy(s)["action"] = 1
	assert_str(str(FightGrid.veiled(s, data, CombatRules.player(s), f))).is_not_empty()
	assert_str(str(SpellEffects.zones(s)[0]["veil"])).is_equal("fog")


func test_devils_sight_sees_through_darkness_only() -> void:
	var s := _hero("fighter_aira")
	_bow(s)
	(s.character["features"] as Array).append("eldritch_invocation_devils_sight")
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_zone(s, "darkness", FightGrid.cell(f))
	assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
	assert_bool(_says(_dis(s, f), "тьма")).is_false()
	var w := CombatRules.weapon_profile(s.character, data, s.items, "longbow")
	assert_bool(_says(Attack.mods(s, data, CombatRules.player(s), f, Attack.of_weapon(w))["adv"], "не видно")).is_true()  # it sees, it is not seen
	var z := _zone(s, "fog_cloud", FightGrid.cell(f))
	assert_bool(_says(_dis(s, f), str(z["name"]))).is_true()


func test_darkvision_does_not_pierce_magical_darkness() -> void:
	var s := _hero("fighter_aira")
	_bow(s)
	(s.character["traits"] as Array).append("darkvision")
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	_zone(s, "darkness", FightGrid.cell(f))
	assert_int(SightRules.dark_sight(s, data)).is_greater(0)
	assert_str(FightGrid.veiled(s, data, CombatRules.player(s), f)).is_not_empty()


func test_senses_of_monsters_by_the_srd() -> void:
	var s := _hero("fighter_aira")
	var foes := _ordered(_fight(s, [{"monster": "bat", "col": 1}, {"monster": "imp", "col": 2}, {"monster": "goblin", "col": 2}]), ["bat", "imp", "goblin"])
	var hero := CombatRules.player(s)
	_zone(s, "darkness", FightGrid.cell(hero))
	assert_str(FightGrid.veiled(s, data, foes[0], hero)).is_empty()  # the bat's blindsight, 60 ft
	assert_str(FightGrid.veiled(s, data, foes[1], hero)).is_empty()  # the imp's Devil's Sight
	assert_str(FightGrid.veiled(s, data, foes[2], hero)).is_not_empty()
	_zone(s, "fog_cloud", FightGrid.cell(hero))
	assert_str(FightGrid.veiled(s, data, foes[0], hero)).is_empty()
	assert_str(FightGrid.veiled(s, data, foes[1], hero)).is_not_empty()  # Devil's Sight is no help in a fog
	assert_array(SightRules.cfg(data)["pierce"]["fog"]).is_equal(["blindsight"])  # nor truesight: only darkness and magic
	FightGrid.put(foes[0], FightGrid.cell(hero) + Vector2i(13, 0))
	assert_str(FightGrid.veiled(s, data, foes[0], hero)).is_not_empty()  # past 60 ft


func test_a_foe_shoots_through_a_veil_too() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "bandit", "col": 1}])[0]
	assert_str(str(FightAI.plan(s, data, f)["option"].get("kind", ""))).is_equal("ranged")
	_zone(s, "darkness", FightGrid.cell(CombatRules.player(s)))
	assert_str(str(FightAI.plan(s, data, f)["option"].get("kind", ""))).is_equal("ranged")


func test_no_blow_of_opportunity_from_inside_a_veil() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	assert_bool(CombatRules.can_react(s, data, f, CombatRules.player(s))).is_true()
	_zone(s, "fog_cloud", FightGrid.cell(f))
	assert_bool(CombatRules.can_react(s, data, f, CombatRules.player(s))).is_false()


func test_the_map_hides_what_is_under_a_veil() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 3}])[0]
	var hero := FightGrid.cell(CombatRules.player(s))
	var map := FightGrid.map(s, data)
	assert_bool(SightRules.look(s, data, map, hero).has(FightGrid.cell(f))).is_true()
	_zone(s, "darkness", hero + Vector2i(9, 0))  # across the way
	var seen := SightRules.look(s, data, map, hero)
	assert_bool(seen.has(FightGrid.cell(f))).is_false()
	assert_bool(seen.has(hero + Vector2i(9, 0))).is_false()
	assert_bool(seen.has(hero + Vector2i(-9, 0))).is_true()
	_zone(s, "darkness", hero)  # from inside: the next square only
	seen = SightRules.look(s, data, map, hero)
	assert_bool(seen.has(hero + Vector2i(1, 0))).is_true()
	assert_bool(seen.has(hero + Vector2i(2, 0))).is_false()
	assert_bool(seen.has(hero + Vector2i(-9, 0))).is_false()
	(s.character["features"] as Array).append("eldritch_invocation_devils_sight")
	assert_bool(SightRules.look(s, data, map, hero).has(hero + Vector2i(2, 0))).is_true()


# --- blindness ------------------------------------------------------------------------------------------------------


func test_a_blind_shot_goes_with_disadvantage() -> void:
	var s := _hero("wizard_yalika", 3)
	_bow(s)
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
	assert_bool(_says(_dis(s, f), "ослеплены")).is_true()
	assert_array(_adv(s, f)).is_empty()  # the foe sees the hero
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "fire_bolt", "slot": 0})).is_empty()
	_learn(s, "magic_missile")
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "magic_missile", "slot": 1})).is_equal("COMBAT_NO_LINE")


func test_the_text_of_blindness_is_that_of_the_rules() -> void:
	assert_str(str(data["rules"]["conditions"]["blinded"])).not_contains("стрелять")


func test_a_blind_hero_strikes_beside_it_with_disadvantage_and_is_struck_with_advantage() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	assert_str(Acts.one("attack").can(s, data, CombatRules.player(s), str(f["id"]))).is_empty()
	assert_bool(_says(_dis(s, f), "ослеплены")).is_true()
	assert_array(ConditionRules.attack(data, f, s.character, true)["adv"]).is_not_empty()


func test_blindness_closes_the_view_and_the_perception() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	var hero := FightGrid.cell(CombatRules.player(s))
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	assert_int(SightRules.reach(s, data)).is_equal(int(SightRules.cfg(data)["blind"]))
	var seen := SightRules.look(s, data, FightGrid.map(s, data), hero)
	assert_bool(seen.has(FightGrid.cell(f))).is_false()
	assert_bool(seen.has(hero + Vector2i(2, 0))).is_false()
	assert_array(ConditionRules.check_mods(s.character, data, {"skill": "perception"})["auto_fail"]).contains(["blinded"])


func test_a_touch_goes_blind_too() -> void:
	var s := _hero("cleric_branko", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	_learn(s, "inflict_wounds")
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "inflict_wounds", "slot": 1})).is_empty()


func test_a_blind_foe_shoots_but_does_not_catch_the_hero() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "bandit", "col": 1}])[0]
	(f["conditions"] as Array).append("blinded")
	assert_str(FightGrid.veiled(s, data, f, CombatRules.player(s))).is_not_empty()
	assert_str(str(FightAI.plan(s, data, f)["option"].get("kind", ""))).is_equal("ranged")
	assert_bool(CombatRules.can_react(s, data, f, CombatRules.player(s))).is_false()


func test_blindsight_works_in_spite_of_blindness() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "bat", "col": 1}])[0]
	(f["conditions"] as Array).append("blinded")
	assert_str(FightGrid.veiled(s, data, f, CombatRules.player(s))).is_empty()


# --- the dark and light ---------------------------------------------------------------------------------------------


func _dark(preset: String = "rogue_damir") -> GameSession:
	var s := _hero(preset)
	s.room_id = "mine-gallery"
	for id: String in (s.character["inventory"] as Dictionary).keys():
		if (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("light_source"):
			s.character["inventory"].erase(id)
	(s.character["traits"] as Array).erase("darkvision")
	return s


func test_how_far_the_hero_sees_by_its_light() -> void:
	var s := _dark()
	var cfg: Dictionary = SightRules.cfg(data)
	assert_bool(TimeRules.unlit(s, data)).is_true()
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["blind"]))
	s.character["inventory"]["torch"] = 1
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["lights"]["torch"]))
	LiquidRules.drain(s.character)
	s.character["inventory"]["lantern"] = 1
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["lights"]["torch"]))  # no oil in it (v0.8.4.28.3)
	Thing.nth(s.character, "lantern", 0).merge({"liquid": "oil", "pints": 1.0})
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["lights"]["lantern"]))
	s.character["inventory"].erase("torch")
	s.character["inventory"].erase("lantern")
	(s.character["traits"] as Array).append("darkvision")
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["darkvision"]))
	(s.character["features"] as Array).append("eldritch_invocation_devils_sight")
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["devils_sight"]))
	s.room_id = "brod-gate"
	assert_int(SightRules.reach(s, data)).is_equal(int(cfg["day"]))


func test_who_stands_in_the_dark() -> void:
	var s := _dark()
	assert_str(SightRules.in_dark(s, data)).is_equal("темнота")
	s.character["inventory"]["torch"] = 1
	assert_str(SightRules.in_dark(s, data)).is_empty()  # a torch shows the hero
	s.character["inventory"].erase("torch")
	(s.character["traits"] as Array).append("darkvision")
	assert_str(SightRules.in_dark(s, data)).is_equal("темнота")  # to see in the dark is not to be lit
	s.character["inventory"]["torch"] = 1
	assert_str(SightRules.in_dark(s, data)).is_equal("темнота")  # the torch stays in the pack, it needs none
	s.room_id = "brod-gate"
	assert_str(SightRules.in_dark(s, data)).is_empty()


func test_the_dark_gives_advantage_on_stealth() -> void:
	var s := _dark()
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).contains("темнота")
	s.character["inventory"]["torch"] = 1
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).not_contains("темнота")


func test_heavy_armour_cancels_the_dark_on_stealth() -> void:
	var s := _dark("fighter_aira")
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).is_empty()  # advantage and disadvantage: a plain roll


func test_a_veil_gives_no_advantage_on_stealth() -> void:  # it gives the place to Hide, no more
	var s := _hero("rogue_damir")
	_fight(s, [{"monster": "goblin", "col": 3}])
	var z := _zone(s, "fog_cloud", FightGrid.cell(CombatRules.player(s)))
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).not_contains(str(z["name"]))


func test_a_foes_shot_at_the_hero_in_the_dark() -> void:
	var s := _dark()
	var foes := _ordered(_fight(s, [{"monster": "bandit", "col": 3}, {"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 3}]), ["bandit", "goblin", "goblin"])
	var hero := CombatRules.player(s)
	assert_bool(CombatRules.shot_in_dark(s, data, foes[0], hero)).is_true()  # no darkvision
	var near := foes[1] if FightGrid.dist(foes[1], hero) < FightGrid.dist(foes[2], hero) else foes[2]
	var far := foes[2] if near == foes[1] else foes[1]
	assert_bool(CombatRules.shot_in_dark(s, data, near, hero)).is_false()  # 30 ft of its 60 ft
	assert_bool(CombatRules.shot_in_dark(s, data, far, hero)).is_true()  # past its darkvision
	s.character["inventory"]["torch"] = 1
	assert_bool(CombatRules.shot_in_dark(s, data, foes[0], hero)).is_false()  # a torch is a mark


func test_a_foes_shot_in_the_dark_is_rolled_with_disadvantage() -> void:
	var s := _dark()
	var f := _fight(s, [{"monster": "bandit", "col": 2}])[0]
	var lines: Array[String] = []
	var bow: Dictionary = MonsterRules.pick(s, data, f, CombatRules.player(s), "ranged")
	Attack.one(s, data, f, CombatRules.player(s), bow, lines)
	assert_str(" ".join(lines)).contains("с помехой")
	s.character["inventory"]["torch"] = 1
	lines.clear()
	Attack.one(s, data, f, CombatRules.player(s), bow, lines)
	assert_str(" ".join(lines)).not_contains("с помехой")


func test_the_heros_shot_past_its_light() -> void:
	var s := _dark()
	_bow(s)
	s.character["inventory"]["torch"] = 1
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 3}])
	foes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return FightGrid.dist(a, CombatRules.player(s)) < FightGrid.dist(b, CombatRules.player(s)))
	assert_bool(_says(_dis(s, foes[0]), "темнота")).is_false()  # in the torch's 8 squares
	assert_bool(_says(_dis(s, foes[1]), "темнота")).is_true()


func test_the_heros_shot_with_no_light_at_all() -> void:
	var s := _dark()
	_bow(s)
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	assert_bool(_says(_dis(s, f), "темнота")).is_true()


# --- an area at one the hero does not see ---------------------------------------------------------------------------


## A wizard with Fireball in a fight on the place's map.
func _caster(room: String) -> GameSession:
	var s := _hero("wizard_yalika", 5)
	s.room_id = room
	CombatRules.start(s, data, [{"monster": "ogre", "beside": true}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	_learn(s, "fireball")
	CombatRules.economy(s)["action"] = 1
	return s


## Squares [hero, foe, aim]: a wall stops every line from the hero to the foe, the aim is in the open and the blast gets there.
func _round_the_corner(s: GameSession) -> Array:
	var g := FightGrid.grid(s, data)
	var m: Dictionary = g["map"]
	var sp: Dictionary = data["spells"]["fireball"]
	var open: Array[Vector2i] = []
	for y: int in int(g["h"]):
		for x: int in int(g["w"]):
			if FightGrid.walkable(g, Vector2i(x, y)):
				open.append(Vector2i(x, y))
	for aim: Vector2i in open:
		var cells := FightGrid.area(s, data, sp["area"], aim, aim, false)
		for foe: Vector2i in cells:
			if not FightGrid.walkable(g, foe):
				continue
			for hero: Vector2i in open:
				if WalkRules.distance(hero, aim) in range(2, 20) and hero != foe and not cells.has(hero) and FightGrid.clear(g, hero, aim) \
						and FightGrid.cover_at(s, data, hero, foe) >= FightGrid.FULL_COVER:
					return [hero, foe, aim]
	assert_str(str(m["id"])).is_equal("a map with a corner")
	return []


func test_an_area_reaches_a_foe_behind_a_wall() -> void:
	var s := _caster("brod-tavern-hall")
	var spots := _round_the_corner(s)
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(CombatRules.player(s), spots[0])
	FightGrid.put(f, spots[1])
	FightGrid.changed(s)
	var id := str(f["id"])
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), id, {"spell": "fireball", "slot": 3})).is_equal("COMBAT_NO_LINE")
	var aim := FightGrid.aim_id(spots[2])
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})).is_empty()
	assert_array(CombatRules.area_targets(s, data, data["spells"]["fireball"], CombatRules.aimed(s, aim)).map(func(t: Dictionary) -> String: return str(t["id"]))).contains([id])
	var hp := int(f["hp"])
	Acts.one("cast").go(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})
	assert_int(int(f["hp"])).is_less(hp)


func test_an_area_reaches_an_invisible_foe() -> void:
	var s := _hero("wizard_yalika", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	_learn(s, "fireball")
	CombatRules.economy(s)["action"] = 1
	(f["conditions"] as Array).append("invisible")
	var id := str(f["id"])
	var at := FightGrid.cell(f)
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), id, {"spell": "fire_bolt", "slot": 0})).is_empty()  # by guess, where it was seen
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), id, {"spell": "fireball", "slot": 3})).is_equal("COMBAT_NO_LINE")  # not at it by name
	var aim := FightGrid.aim_id(at)
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})).is_empty()
	var hp := int(f["hp"])
	Acts.one("cast").go(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})
	assert_int(int(f["hp"])).is_less(hp)


func test_see_invisibility_gives_the_foe_back_to_a_spell() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	(f["conditions"] as Array).append("invisible")
	(f["conditions"] as Array).append("outlined")  # Faerie Fire
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), str(f["id"]), {"spell": "fire_bolt", "slot": 0})).is_empty()


func test_an_area_reaches_a_foe_under_a_veil() -> void:
	var s := _hero("wizard_yalika", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	_learn(s, "fireball")
	CombatRules.economy(s)["action"] = 1
	_zone(s, "darkness", FightGrid.cell(f))
	var aim := FightGrid.aim_id(FightGrid.cell(f))
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})).is_empty()
	var hp := int(f["hp"])
	Acts.one("cast").go(s, data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})
	assert_int(int(f["hp"])).is_less(hp)


func test_a_blind_caster_can_lay_an_area_on_a_square() -> void:
	var s := _hero("wizard_yalika", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	_learn(s, "fireball")
	CombatRules.economy(s)["action"] = 1
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), FightGrid.aim_id(FightGrid.cell(f)), {"spell": "fireball", "slot": 3})).is_empty()


func test_an_area_still_stops_at_a_wall() -> void:
	var s := _caster("brod-tavern-hall")
	var g := FightGrid.grid(s, data)
	var hero := FightGrid.cell(CombatRules.player(s))
	for y: int in int(g["h"]):
		for x: int in int(g["w"]):
			var at := Vector2i(x, y)
			if WalkRules.distance(hero, at) < 20 and not FightGrid.clear(g, hero, at):
				assert_str(Acts.one("cast").can(s, data, CombatRules.player(s), FightGrid.aim_id(at), {"spell": "fireball", "slot": 3})).is_equal("COMBAT_NO_LINE")
				return
