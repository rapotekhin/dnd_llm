extends GdUnitTestSuite
## One base of acts (v0.8.4.7, ADR-0016): every file of core/acts/ works for the hero, a foe and an ally; a turn's points are on
## every fighter; a new row of `rules.combat.moves` is a new way for everybody; one walk with one attack of opportunity.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	(data["rules"]["combat"]["moves"] as Dictionary).erase("glide")
	(data["monsters"] as Dictionary).erase("glider")
	GameState.session = null


func _fight(foes: Array = [{"monster": "wolf", "col": 0}, {"monster": "goblin", "col": 2}], allies: Array = [{"monster": "wolf"}]) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	TestUtils.fight(s, data, foes, {"allies": allies})
	return s


## The turn of `f` from its start.
func _turn(s: GameSession, f: Dictionary) -> void:
	var order: Array = s.combat["order"]
	s.combat["turn"] = order.find(str(f["id"]))
	CombatRules._begin_turn(s, data, [] as Array[String])


func _each(s: GameSession) -> Array[Dictionary]:
	return [CombatRules.player(s), CombatRules.fighter(s, TestUtils.foe(s, 1)), CombatRules.fighter(s, CombatRules.allies(s)[0])]


func test_the_folder_is_read_by_itself() -> void:
	var ids := Acts.all().map(func(a: Act) -> String: return a.id)
	for id: String in ["walk", "dash", "dodge", "disengage", "stand", "hide"]:
		assert_bool(ids.has(id)).override_failure_message(id).is_true()
	assert_bool(ids.has("act")).is_false()
	assert_str(Acts.one("dash").title()).is_not_equal("dash")


func test_every_act_is_there_for_every_fighter_at_its_turn() -> void:
	for act: Act in [Acts.one("walk"), Acts.one("dash"), Acts.one("dodge"), Acts.one("disengage"), Acts.one("stand"), Acts.one("hide")]:
		var s := _fight([{"monster": "wolf", "col": 2}, {"monster": "goblin", "col": 3}])
		for f: Dictionary in _each(s):
			_turn(s, f)
			for g: Dictionary in _each(s):
				FightGrid.put(g, FightGrid.free_near(s, data, FightGrid.cell(g)))
			ConditionRules.add_effect(Sheet.holder(s, f), {"condition": "prone", "ends": {}, "source": {"kind": "test"}})
			if act.id != "stand":
				ConditionRules.remove(Sheet.holder(s, f), "prone")
			var to := FightGrid.aim_id(FightGrid.cell(f) + Vector2i(0, 2)) if act.aim() == "square" else ""
			assert_str(act.can(s, data, f, to)).override_failure_message("%s by %s" % [act.id, f["id"]]).is_empty()
			act.go(s, data, f, to)


func test_a_turn_gives_points_to_anybody() -> void:
	var s := _fight()
	for f: Dictionary in _each(s):
		_turn(s, f)
		var e: Dictionary = f["points"]
		assert_int(int(e["action"])).is_equal(1)
		assert_int(int(e["bonus"])).is_equal(1)
		assert_int(int(e["move"])).is_equal(FightGrid.steps_of(data, Sheet.speed(s, data, f)))
	assert_str(str(CombatRules.economy(s))).is_equal(str(CombatRules.player(s)["points"]))


func test_a_foes_own_turn_only() -> void:
	var s := _fight()
	var wolf := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, CombatRules.player(s))
	assert_str(Acts.one("dodge").can(s, data, wolf)).is_equal("COMBAT_NOT_YOUR_TURN")
	_turn(s, wolf)
	assert_str(Acts.one("dodge").can(s, data, wolf)).is_empty()
	Acts.one("dodge").go(s, data, wolf)
	assert_bool(bool(wolf["dodging"])).is_true()
	assert_str(Acts.one("dodge").can(s, data, wolf)).is_equal("COMBAT_NO_ACTION")


func test_a_dodging_foe_is_harder_to_hit() -> void:
	var s := _fight()
	var wolf := CombatRules.fighter(s, TestUtils.foe(s, 1))
	wolf["dodging"] = true
	_turn(s, CombatRules.player(s))
	assert_array(CombatRules.attack_preview(s, data, str(wolf["id"]), false)["dis"]).is_not_empty()


func test_a_goblin_slips_off_and_hides_by_its_bonus_action() -> void:
	var s := _fight([{"monster": "goblin", "col": 0}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, g)
	assert_str(Acts.one("disengage").cost(s, data, g, {})).is_equal("bonus")
	assert_str(Acts.one("hide").cost(s, data, g, {})).is_equal("bonus")
	assert_str(Acts.one("hide").can(s, data, g)).is_equal("COMBAT_HIDE_SEEN")  # the hero is beside it
	assert_float(Acts.one("disengage").worth(s, data, g)).is_greater(0.0)
	var lines: Array[String] = []
	FightAI.first(s, data, g, lines)
	assert_bool(bool(g["disengaged"])).override_failure_message(str(lines)).is_true()
	assert_int(int(g["points"]["bonus"])).is_equal(0)
	assert_str(Acts.one("hide").can(s, data, g)).is_equal("COMBAT_HIDE_SEEN")


func test_an_orc_runs_up_by_its_bonus_action() -> void:
	var s := _fight([{"monster": "orc", "col": 4}], [])
	var o := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, o)
	var n := int(o["points"]["move"])
	var lines: Array[String] = []
	FightAI.first(s, data, o, lines)
	assert_int(int(o["points"]["move"])).is_equal(n * 2)
	assert_int(int(o["points"]["bonus"])).is_equal(0)
	assert_int(int(o["points"]["action"])).is_equal(1)


func test_one_who_cannot_reach_dashes_with_its_action() -> void:
	var s := _fight([{"monster": "wolf", "col": 5}], [])
	var w := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, w)
	var d0 := FightGrid.dist(w, CombatRules.player(s))
	var n := int(w["points"]["move"])
	var lines: Array[String] = []
	FightAI.act(s, data, w, lines)
	assert_int(int(w["points"]["action"])).is_equal(0)
	assert_int(d0 - FightGrid.dist(w, CombatRules.player(s))).is_greater(n)


func test_one_walk_and_one_blow_in_the_back_for_everybody() -> void:
	var s := _fight([{"monster": "wolf", "col": 0}], [{"monster": "wolf", "col": 0}])
	var foe := CombatRules.fighter(s, TestUtils.foe(s, 1))
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	FightGrid.put(ally, FightGrid.cell(foe) + Vector2i(1, 0))
	_turn(s, ally)
	var far := FightGrid.cell(ally) + Vector2i(4, 0)
	assert_str(Acts.one("walk").can(s, data, ally, FightGrid.aim_id(far))).is_empty()
	var lines := Acts.one("walk").go(s, data, ally, FightGrid.aim_id(far))
	assert_str(" ".join(lines)).contains("вдогонку")
	assert_bool(bool(foe["reacted"])).is_true()
	assert_int(int(ally["points"]["walked"])).is_greater(0)


func test_disengage_guards_a_foe_too() -> void:
	var s := _fight([{"monster": "wolf", "col": 0}], [])
	var w := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, w)
	Acts.one("disengage").go(s, data, w)
	var away := FightGrid.cell(w) + (FightGrid.cell(w) - FightGrid.cell(CombatRules.player(s))) * 3
	var lines := Acts.one("walk").go(s, data, w, FightGrid.aim_id(away))
	assert_str(" ".join(lines)).not_contains("вдогонку")
	assert_bool(bool(CombatRules.player(s).get("reacted", false))).is_false()


func test_the_hero_stands_as_a_foe_does() -> void:
	var s := _fight()
	for f: Dictionary in _each(s):
		_turn(s, f)
		ConditionRules.add_effect(Sheet.holder(s, f), {"condition": "prone", "ends": {}, "source": {"kind": "test"}})
		var n := int(f["points"]["move"])
		assert_str(Move.why(s, data, f)).is_equal("COMBAT_PRONE")
		assert_bool(Move.routes(s, data, f).is_empty()).is_true()
		Acts.one("stand").go(s, data, f)
		assert_bool(ConditionRules.has(Sheet.holder(s, f), "prone")).is_false()
		assert_int(int(f["points"]["move"])).is_equal(n - n / 2)


func test_a_foe_gets_up_at_the_start_of_its_turn_for_half_its_walk() -> void:
	var s := _fight([{"monster": "wolf", "col": 0}], [])
	var w := CombatRules.fighter(s, TestUtils.foe(s, 1))
	_turn(s, w)
	CombatRules._hold(w, "prone")
	var n := int(w["points"]["move"])
	var lines: Array[String] = []
	FightAI.first(s, data, w, lines)
	assert_bool(CombatRules._has(w, "prone")).is_false()
	assert_int(int(w["points"]["move"])).is_equal(n - n / 2)


func test_a_new_row_of_the_moves_is_a_way_for_everybody() -> void:
	data["rules"]["combat"]["moves"]["glide"] = {"speed": "glide", "status": "glide_speed", "word": "планирование", "passes": ["pit"], "flat": true}
	var glider: Dictionary = (data["monsters"]["wolf"] as Dictionary).duplicate(true)
	glider["speed"] = 0
	glider["glide"] = 90
	data["monsters"]["glider"] = glider
	assert_int(Move.feet_of(data, glider)).is_equal(90)
	assert_str(Move.text(data, glider)).is_equal("0 фт, планирование 90 фт")
	var s := _fight([{"monster": "glider", "col": 3}], [{"monster": "wolf"}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	assert_int(Sheet.speed(s, data, g)).is_equal(90)
	assert_bool(int(Move.opts(s, data, g)["passes"]) & FightGrid.PIT != 0).is_true()
	assert_bool(int(Move.opts(s, data, ally)["passes"]) & FightGrid.PIT != 0).is_false()
	for f: Dictionary in [CombatRules.player(s), ally]:  # a status gives it to anybody
		Sheet.holder(s, f).get_or_add("effects", []).append({"id": 90, "glide_speed": 50, "source": {"kind": "spell", "id": "test", "name": "x"}, "ends": {}})
		assert_bool(Move.speeds(s, data, f).has("glide")).override_failure_message(str(f["id"])).is_true()
		assert_bool(int(Move.opts(s, data, f)["passes"]) & FightGrid.PIT != 0).is_true()


func test_swimming_goes_only_on_water_for_one_with_no_land_speed() -> void:
	data["monsters"]["reef_shark"] = TestUtils.uncut("monsters", "reef_shark")  # out of the game (v0.8.4.28.4); its road stays
	var fish: Dictionary = data["monsters"]["reef_shark"]
	assert_int(int(fish["speed"])).is_equal(0)
	assert_int(Move.feet_of(data, fish)).is_equal(int(fish["swim"]))
	assert_str(Move.text(data, fish)).contains("плавание")


func test_the_srd_gives_climb_and_burrow() -> void:
	assert_int(int(data["monsters"]["giant_spider"]["climb"])).is_equal(30)
	assert_str(Move.text(data, data["monsters"]["giant_spider"])).contains("лазание")
	assert_int(int(data["monsters"]["giant_badger"]["burrow"])).is_equal(10)
	assert_str(Move.text(data, data["monsters"]["giant_badger"])).contains("копание")


func test_fly_on_an_ally_lifts_it_as_it_does_the_hero() -> void:
	var s := _fight()
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	assert_bool(Move.air(s, data, ally)).is_false()
	SpellEffects.on_friend(s, data, "fly", 3, ally, [] as Array[String])
	assert_bool(Move.air(s, data, ally)).is_true()
	assert_int(Sheet.speed(s, data, ally)).is_equal(60)
	assert_bool(CombatRules.airborne(s, data, ally)).is_true()
	assert_bool(int(Move.opts(s, data, ally)["passes"]) & FightGrid.PIT != 0).is_true()
