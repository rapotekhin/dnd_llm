extends GdUnitTestSuite
## Whose a zone of the field is (v0.8.4.43.52): a zone with no author was read as the hero's, so a spider's lair web held
## the hero «by the hero» and the end of the hero's own Web took the spider's webs and let go whom they held. Now the lair
## web is the spider's, a zone of nobody is nobody's, and what a foe throws — a flask, caltrops, a net — is the thrower's.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


## The spider's lair web laid on the hero's square, sure to hold.
func _lair_on_hero(s: GameSession, spider: Dictionary) -> Dictionary:
	var webs := SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == "web")
	assert_int(webs.size()).is_equal(1)
	var z: Dictionary = webs[0]
	z["cells"] = FightGrid.pack_cells([FightGrid.cell(CombatRules.player(s))] as Array[Vector2i])
	z["dc"] = 40
	return z


func test_the_lair_web_is_the_spiders_and_holds_by_it() -> void:
	var s := ChecklistProbe.session(data)
	var spider := ChecklistProbe.fight(s, data, "giant_spider", true)
	var z := _lair_on_hero(s, spider)
	assert_str(str(z.get("by", ""))).is_equal(str(spider["id"]))
	var lines := SpellEffects.zone_tick(s, data, CombatRules.player(s), "start")
	assert_bool(ConditionRules.has(s.character, "restrained")).override_failure_message(" · ".join(lines)).is_true()
	var held: Dictionary = ConditionRules.effects_of(s.character, "restrained")[0]
	assert_str(str(held["by"])).is_equal(str(spider["id"]))
	assert_str(ConditionRules.caused_by(s.character, "restrained")).is_not_equal(CombatRules.PLAYER)


func test_the_heros_own_web_ending_leaves_the_lair_and_its_hold() -> void:
	var s := ChecklistProbe.session(data)
	var spider := ChecklistProbe.fight(s, data, "giant_spider", true)
	var z := _lair_on_hero(s, spider)
	SpellEffects.zone_tick(s, data, CombatRules.player(s), "start")
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	SpellEffects.end_zones(s, "web")  # the hero's concentration on its Web is over: only the hero's web goes
	assert_bool(SpellEffects.zones(s).has(z)).is_true()
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	SpellEffects.end_zones(s, "web", str(spider["id"]))  # the spider's web gone: what it held is let go
	assert_bool(ConditionRules.has(s.character, "restrained")).is_false()


func test_a_zone_of_nobody_holds_by_nobody() -> void:
	var s := ChecklistProbe.session(data)
	ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	var row := (FightField.cfg(data)["strewn"]["web"] as Dictionary).merged({"side": "enemy", "dc": 40})
	SpellEffects.add_zone(s, FightField.zone_of("web", row, FightGrid.pack_cells([FightGrid.cell(CombatRules.player(s))] as Array[Vector2i])))
	SpellEffects.zone_tick(s, data, CombatRules.player(s), "start")
	assert_str(str(ConditionRules.effects_of(s.character, "restrained")[0]["by"])).is_empty()
	SpellEffects.end_zones(s, "web")
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()


func test_what_a_goblin_throws_is_the_goblins() -> void:
	var s := ChecklistProbe.session(data)
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(1, 1)
	ItemRules.add(Sheet.holder(s, g), "caltrops")
	CombatRules.throw_item(s, data, g, "caltrops", FightGrid.aim_id(at))
	var strewn: Dictionary = SpellEffects.zones(s)[-1]
	assert_str(str(strewn["spell"])).is_equal("caltrops")
	assert_str(str(strewn["by"])).is_equal(str(g["id"]))
	assert_bool(SpellEffects._by_hero(strewn)).is_false()
	var tries := 0
	while not ConditionRules.has(s.character, "restrained") and tries < 30:  # a net must hit first
		tries += 1
		ItemRules.add(Sheet.holder(s, g), "net")
		CombatRules.throw_item(s, data, g, "net", CombatRules.PLAYER)
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	assert_str(str(ConditionRules.effects_of(s.character, "restrained")[0]["by"])).is_equal(str(g["id"]))
