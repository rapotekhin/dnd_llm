extends GdUnitTestSuite
## Combat traits on the engine's roads (roadmap v0.8.4.27.5): advantage on saves by a trait is one road for a race and a
## monster — an `adv_tag` row of `rules.feature_wear` (Magic Resistance, Gnome Cunning on INT / WIS / CHA, Two-Headed);
## Steadfast keeps fear away while it sees an ally near; Grappler strikes the one it holds with advantage; Rampage and a
## pounce are one bonus bite; Divine Eminence is a feature action paid with any slot of a template caster, whose slots are
## the hero's road of slots now; Damage Transfer puts half the hurt on the one it holds.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _trait(monster: String, id: String) -> String:
	for t: Dictionary in data["monsters"][monster]["traits"]:
		if str(t["id"]) == id:
			return str(t["name"])
	return id


## A fight of `foes` [{monster, x, y}] with `allies` of the hero; the hero at (40, 30). The foes, in order.
func _fight(s: GameSession, foes: Array, allies: Array = []) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {"field": {"w": 80, "h": 60}, "allies": allies})
	var p := CombatRules.player(s)
	FightGrid.put(p, Vector2i(40, 30))
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	for i in out.size():
		FightGrid.put(out[i], Vector2i(int(foes[i]["x"]), int(foes[i]["y"])))
	return out


func test_two_heads_watch_and_resist() -> void:
	var s := ChecklistProbe.session(data)
	var dog := ChecklistProbe.fight(s, data, "death_dog")
	var name := _trait("death_dog", "two_headed")
	assert_array(Roll.check(s, data, dog, {"skill": "perception", "quiet": true})["adv"]).contains([name])
	assert_array(Sheet.save(s, data, dog, "wis", 15, HeroDefense.cond_tags(data, ["charmed"]))["adv"]).contains([name])
	assert_array(Sheet.save(s, data, dog, "con", 15, HeroDefense.cond_tags(data, ["stunned"]))["adv"]).contains([name])
	assert_array(Sheet.save(s, data, dog, "dex", 15, "magic")["adv"]).not_contains([name])


func test_trait_saves_are_rows_for_anybody() -> void:
	var gnome := {"monster": "deep_gnome_svirfneblin"}
	assert_array(HeroDefense.save_advantages(gnome, data, "int", "magic")).contains([_trait("deep_gnome_svirfneblin", "gnome_cunning")])
	assert_array(HeroDefense.save_advantages(gnome, data, "dex", "magic")).is_empty()
	assert_array(HeroDefense.save_advantages({"monster": "bearded_devil"}, data, "dex", "magic,fear")).contains([_trait("bearded_devil", "magic_resistance")])
	assert_bool(data["rules"]["hero_effects"].has("trait_saves")).is_false()


func test_steadfast_while_an_ally_is_seen_near() -> void:
	var s := ChecklistProbe.session(data)
	var two := _fight(s, [{"monster": "bearded_devil", "x": 46, "y": 30}, {"monster": "goblin", "x": 47, "y": 30}])
	var devil := two[0]
	assert_str(HeroDefense.immune(s, data, devil, "frightened", "fear")).is_equal(_trait("bearded_devil", "steadfast"))
	var fear := {"condition": "frightened", "ends": {}, "source": {"kind": "engine", "name": "страх"}}
	ConditionRules.impose(s, data, fear, devil)
	assert_bool(ConditionRules.has(devil, "frightened")).is_false()
	assert_str(CombatRules._resists(s, data, devil, {"conditions": ["frightened"]}, ["frightened"], "fear,magic")).is_equal(_trait("bearded_devil", "steadfast"))
	FightGrid.put(two[1], Vector2i(75, 55))
	assert_str(HeroDefense.immune(s, data, devil, "frightened", "fear")).is_empty()
	ConditionRules.impose(s, data, fear, devil)
	assert_bool(ConditionRules.has(devil, "frightened")).is_true()
	assert_str(HeroDefense.immune(ChecklistProbe.session(data), data, {"monster": "bearded_devil"}, "frightened", "fear")).is_empty()


func test_a_grappler_strikes_the_held_with_advantage() -> void:
	data["monsters"]["mimic"] = TestUtils.uncut("monsters", "mimic")  # out of the game (v0.8.4.28.4); its trait's road stays
	var s := ChecklistProbe.session(data)
	var mimic := _fight(s, [{"monster": "mimic", "x": 41, "y": 30}])[0]
	var p := CombatRules.player(s)
	var blow := Attack.of_action(data, mimic, Sheet.template(data, mimic)["actions"][0])
	var name := _trait("mimic", "grappler").to_lower()
	assert_array(Attack.mods(s, data, mimic, p, blow)["adv"]).not_contains([name])
	CombatRules._hold(s.character, "grappled", str(mimic["id"]))
	assert_bool(CombatRules.held_by(s, mimic, p)).is_true()
	assert_array(Attack.mods(s, data, mimic, p, blow)["adv"]).contains([name])


func test_rampage_walks_and_bites_after_a_kill() -> void:
	var s := ChecklistProbe.session(data)
	var gnoll := _fight(s, [{"monster": "gnoll", "x": 45, "y": 30}], [{"monster": "commoner", "x": 46, "y": 30}])[0]
	var p := CombatRules.player(s)
	FightGrid.put(p, Vector2i(42, 30))
	var victim := CombatRules.fighter(s, CombatRules.allies(s)[0])
	FightGrid.put(victim, Vector2i(46, 30))
	victim["hp"] = 1
	victim["ac"] = 1
	gnoll["hp"] = 999
	ChecklistProbe.turn(s, data, gnoll)
	var bite := Attack.of_action(data, gnoll, Attack.bite_of(data, gnoll))
	var lines: Array[String] = []
	for i in 30:
		if not Attack.up(s, victim):
			break
		Attack.swing(s, data, gnoll, victim, bite, lines)
	assert_bool(Attack.up(s, victim)).is_false()
	assert_str(" ".join(lines)).contains(_trait("gnoll", "rampage"))
	assert_bool(FightGrid.touching(gnoll, p)).override_failure_message(" · ".join(lines)).is_true()
	assert_int(int(CombatRules.points(s, data, gnoll)["bonus"])).is_equal(0)
	assert_int(int(CombatRules.points(s, data, gnoll)["move"])).is_equal(Move.steps(s, data, gnoll))  # its own walk is kept


func test_a_pounce_bite_pays_the_bonus_action() -> void:
	var s := ChecklistProbe.session(data)
	var tiger := _fight(s, [{"monster": "tiger", "x": 41, "y": 30}])[0]
	ChecklistProbe.turn(s, data, tiger)
	var lines: Array[String] = []
	assert_bool(Attack.follow_up(s, data, tiger, CombatRules.player(s), "%s кусает упавшего", lines)).is_true()
	assert_int(int(CombatRules.points(s, data, tiger)["bonus"])).is_equal(0)
	assert_bool(Attack.follow_up(s, data, tiger, CombatRules.player(s), "%s кусает упавшего", lines)).is_false()


func test_divine_eminence_pays_the_lowest_slot() -> void:
	var s := ChecklistProbe.session(data)
	var priest := _fight(s, [{"monster": "priest", "x": 41, "y": 30}])[0]
	ChecklistProbe.turn(s, data, priest)
	var full := int(data["monsters"]["priest"]["spellcasting"]["slots"]["1"])
	assert_int(SpellRules.slots_left(priest, 1)).is_equal(full)
	assert_bool(FeatureRules.actions(s, data, priest).any(func(a: Dictionary) -> bool: return str(a["id"]) == "divine_eminence")).is_true()
	assert_bool(Acts.one("feature").spare(s, data, priest, "first").any(func(o: Dictionary) -> bool: return str(o["how"].get("id", "")) == "divine_eminence")).is_true()
	FeatureRules.run(s, data, priest, "divine_eminence")
	assert_int(SpellRules.slots_left(priest, 1)).is_equal(full - 1)
	var extra := SpellEffects.hit_extras(priest, CombatRules.player(s), "bludgeoning")
	assert_bool(extra.any(func(x: Dictionary) -> bool: return str(x["dice"]) == "3d6" and str(x["type"]) == "radiant")).is_true()
	ConditionRules.turn_comes(priest, str(priest["id"]))
	assert_array(SpellEffects.hit_extras(priest, CombatRules.player(s), "bludgeoning")).is_empty()
	FightGrid.put(priest, Vector2i(60, 30))  # no foe beside: the AI keeps its slots
	assert_bool(Acts.one("feature").spare(s, data, priest, "first").is_empty()).is_true()


func test_a_template_caster_spends_and_rests_its_slots() -> void:
	var s := ChecklistProbe.session(data)
	var priest := _fight(s, [{"monster": "priest", "x": 46, "y": 30}])[0]
	var guiding: Dictionary = MonsterRules.castable(data, priest).filter(func(o: Dictionary) -> bool: return str(o["id"]) == "guiding_bolt")[0]
	MonsterRules.pay_spell(priest, "guiding_bolt", guiding)
	Knows.add(s, Knows.MONSTER, "priest")
	assert_int(Stock.spent(priest, "slot_%d" % int(guiding["slot"]))).is_equal(1)
	assert_str(CombatRules.monster_card(s, data, priest)).contains("1 круг %d/%d" % [SpellRules.slots_left(priest, 1), int(data["monsters"]["priest"]["spellcasting"]["slots"]["1"])])
	Stock.recharge_all(priest, data, "long")
	assert_int(Stock.spent(priest, "slot_1")).is_equal(0)


func test_damage_transfer_hurts_the_held() -> void:
	data["monsters"]["rug_of_smothering"] = TestUtils.uncut("monsters", "rug_of_smothering")  # out of the game (v0.8.4.28.4); its road stays
	var s := ChecklistProbe.session(data)
	var rug := _fight(s, [{"monster": "rug_of_smothering", "x": 41, "y": 30}])[0]
	rug["hp"] = 100
	rug["max_hp"] = 100
	s.character["hp"] = 30
	s.character["max_hp"] = 30
	CombatRules._hold(s.character, "grappled", str(rug["id"]))
	var lines: Array[String] = []
	Harm.take(s, data, rug, 11, lines, "slashing", false, true)
	assert_int(int(rug["hp"])).is_equal(95)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_equal(24)
	assert_str(" ".join(lines)).contains(_trait("rug_of_smothering", "damage_transfer"))
