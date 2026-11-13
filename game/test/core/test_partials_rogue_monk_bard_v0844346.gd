extends GdUnitTestSuite
## v0.8.4.43.46: the partial abilities of a fight done whole by 5e (abilities_reviewed.json). Deflect Missiles catches a missile
## its damage cut to 0 and throws it back for 1 ki (the passive «Метнуть пойманный снаряд»), the Gloves only catch; Cutting
## Words cut an attack roll, the damage of a hit that cannot be turned and a check of a contest, of anybody who hears and may
## be charmed; Fast Hands makes Use an Object and a lock picked with thieves' tools a bonus action; a rogue's Expertise may
## double thieves' tools.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data)
	s.character["hp"] = int(s.character["max_hp"])
	s.settings["reactions"] = "always"
	return s


func _fight(s: GameSession, monster: String, col: int = 1) -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "col": col}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func _action(monster: String, name_en: String) -> Dictionary:
	for a: Dictionary in data["monsters"][monster]["actions"]:
		if str(a["name_en"]) == name_en:
			return a
	return {}


## The hit of a shot of `f` at `t` as the attack's own road leaves it: the arrow spent, the damage `dmg` to cut.
func _shot(s: GameSession, f: Dictionary, monster: String, action: String, dmg: int) -> Dictionary:
	var b := Attack.of_action(data, f, _action(monster, action))
	if bool(Attack.throwable(b)):
		b["thrown"] = true
		Gear.throw_out(s, data, f, b, FightGrid.cell(CombatRules.player(s)))
	else:
		Gear.spend_ammo(s, data, f, str(b.get("ammo", "")))
	return {"foe": str(f["id"]), "blow": b, "dmg": dmg, "hit": true, "total": 30, "ac": 10, "nat20": false}


# --- Deflect Missiles -----------------------------------------------------------------------------------------


func test_deflect_missiles_catches_an_arrow_and_throws_it_back_for_one_ki() -> void:
	var s := _hero("monk_taras", 3)
	assert_bool(FeatureRules.has(s.character, "deflect_missiles")).is_true()
	assert_bool(ToggleRules.on(s, data, Sheet.HERO, "deflect_throw")).is_true()  # on by default, a passive of the hotbar
	var gob := _fight(s, "goblin")
	var arrows := Thing.count(s.character, "arrows")
	var ki := Stock.left(s.character, data, "ki")
	var ctx := _shot(s, gob, "goblin", "Shortbow", 1)
	assert_int(int(gob["ammo_spent"]["arrows"])).is_equal(1)
	var lines: Array[String] = []
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), gob, "deflect_missiles", ctx, lines)
	assert_int(int(ctx["dmg"])).is_equal(0)
	assert_str(" · ".join(lines)).contains("ловит на лету")
	assert_str(" · ".join(lines)).contains("мечет")
	assert_int(Stock.left(s.character, data, "ki")).is_equal(ki - 1)
	assert_int(int(gob["ammo_spent"]["arrows"])).is_equal(0)  # not the goblin's to gather after the fight
	assert_int(Thing.count(s.character, "arrows")).is_equal(arrows)  # caught, then thrown
	var at := FightGrid.cell(gob)
	var down: Array = (s.combat.get("dropped", []) as Array).filter(func(d: Dictionary) -> bool: return str(d["item"]) == "arrows")
	assert_int(down.size()).is_equal(1)
	assert_str(str(down[0]["by"])).is_equal(CombatRules.PLAYER)
	assert_bool(Vector2i(int(down[0]["x"]), int(down[0]["y"])) == at).is_true()


func test_with_the_passive_off_the_missile_stays_in_the_hand() -> void:
	var s := _hero("monk_taras", 3)
	assert_str(ToggleRules.put(s, data, Sheet.HERO, "deflect_throw", false)).is_empty()
	var gob := _fight(s, "goblin")
	var arrows := Thing.count(s.character, "arrows")
	var ki := Stock.left(s.character, data, "ki")
	var lines: Array[String] = []
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), gob, "deflect_missiles", _shot(s, gob, "goblin", "Shortbow", 1), lines)
	assert_int(Thing.count(s.character, "arrows")).is_equal(arrows + 1)
	assert_int(Stock.left(s.character, data, "ki")).is_equal(ki)
	assert_str(" · ".join(lines)).not_contains("мечет")


func test_a_thrown_javelin_is_caught_off_the_field() -> void:
	var s := _hero("monk_taras", 3)
	ToggleRules.put(s, data, Sheet.HERO, "deflect_throw", false)
	var orc := _fight(s, "orc")
	var ctx := _shot(s, orc, "orc", "Javelin", 1)
	assert_int((s.combat.get("dropped", []) as Array).size()).is_equal(1)  # it flew onto the hero's square
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), orc, "deflect_missiles", ctx, [] as Array[String])
	assert_array(s.combat.get("dropped", [])).is_empty()
	assert_int(Thing.count(s.character, "javelin")).is_greater_equal(1)


func test_no_catch_with_both_hands_full_or_damage_left() -> void:
	var s := _hero("monk_taras", 3)
	var gob := _fight(s, "goblin")
	var arrows := Thing.count(s.character, "arrows")
	var ctx := _shot(s, gob, "goblin", "Shortbow", 99)
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), gob, "deflect_missiles", ctx, [] as Array[String])
	assert_int(int(ctx["dmg"])).is_greater(0)
	assert_int(Thing.count(s.character, "arrows")).is_equal(arrows)
	ItemRules.add(s.character, "greataxe", 1)
	(s.character["equipped"] as Dictionary)["main_hand"] = "greataxe"
	(s.character["equipped"] as Dictionary)["off_hand"] = ""
	assert_bool(CharacterRules.free_hand(s.character, data, s.items)).is_false()
	gob["reacted"] = false
	CombatRules.player(s)["reacted"] = false
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), gob, "deflect_missiles", _shot(s, gob, "goblin", "Shortbow", 1), [] as Array[String])
	assert_int(Thing.count(s.character, "arrows")).is_equal(arrows)


func test_a_monk_of_the_foes_catches_the_hero_s_arrow_by_the_same_road() -> void:
	var s := _hero("ranger_velena", 3)
	TestUtils.fight(s, data, [{"monster": "bandit", "col": 3, "class": "monk", "level": 3}], {})
	var monk := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_bool(FeatureRules.has(Sheet.holder(s, monk), "deflect_missiles")).is_true()
	(monk["equipped"] as Dictionary)["main_hand"] = ""  # a hand free
	var b := Attack.of_weapon(CombatRules.hand_profile(s, data, ""))
	b["ammo"] = "arrows"
	var ctx := {"foe": CombatRules.PLAYER, "blow": b, "dmg": 1, "hit": true, "total": 30, "ac": 10, "nat20": false}
	var lines: Array[String] = []
	assert_bool(Acts.react(s, data, monk, "hurt", ctx, lines)).is_true()
	assert_int(int(ctx["dmg"])).is_equal(0)
	assert_str(" · ".join(lines)).contains("ловит на лету")


func test_a_foe_left_without_its_blade_shoots_or_strikes_with_its_fists() -> void:  # it froze in its turn (live playtest)
	var s := _hero("monk_taras", 3)
	var gob := _fight(s, "goblin", 3)
	var id := str(gob["id"])
	Gear.take(s, data, id, "scimitar")
	Gear.follow(s, data, gob)
	var plan := FightAI.plan(s, data, gob)
	assert_str(str(plan["option"].get("how", {}).get("action", ""))).is_equal("Shortbow")
	Gear.take(s, data, id, "shortbow")
	Gear.follow(s, data, gob)
	TestUtils.beside(s, gob)
	s.combat["turn"] = (s.combat["order"] as Array).find(id)  # the goblin's turn
	CombatRules._begin_turn(s, data, [] as Array[String])
	plan = FightAI.plan(s, data, gob)
	assert_str(str(plan["option"].get("how", {}).get("action", ""))).is_equal("Unarmed Strike")
	assert_str(Acts.one("attack").can(s, data, gob, CombatRules.PLAYER, plan["option"]["how"])).is_empty()
	var lines: Array[String] = []
	FightAI.turn(s, data, gob, lines)
	assert_str(" · ".join(lines)).contains("Безоружный удар")


# --- Cutting Words --------------------------------------------------------------------------------------------


func test_cutting_words_cut_the_damage_of_a_hit_that_cannot_be_turned() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	var gob := _fight(s, "goblin")
	var ctx := {"hit": true, "dmg": 20, "total": 40, "ac": 12, "nat20": false}
	FeatureRules.apply_reaction(s, data, CombatRules.player(s), gob, "cutting_words", ctx, [] as Array[String])
	assert_bool(bool(ctx["hit"])).is_true()
	assert_int(int(ctx["dmg"])).is_less(20)
	CombatRules.player(s)["reacted"] = false
	var rx := FeatureRules.reactions(s, data, CombatRules.player(s), gob, {}, false, 20, {"total": 40, "ac": 12, "nat20": false})
	assert_str(str(rx.filter(func(r: Dictionary) -> bool: return str(r["id"]) == "cutting_words")[0]["label"])).contains("к урону")


func test_cutting_words_turn_a_foe_s_check_of_a_contest() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	var gob := _fight(s, "goblin")
	var left := Stock.left(s.character, data, "bardic_inspiration")
	var ctx := {"total": 11, "ac": 10, "nat20": false, "hit": true, "what": "проверка"}
	var lines: Array[String] = []
	assert_bool(FeatureRules.cutting_words(s, data, gob, ctx, "roll", lines)).is_true()
	assert_int(int(ctx["total"])).is_less(11)
	assert_int(Stock.left(s.character, data, "bardic_inspiration")).is_equal(left - 1)
	assert_str(lines[0]).contains("проверка")
	assert_bool(bool(CombatRules.player(s).get("reacted", false))).is_true()


func test_cutting_words_spare_a_roll_they_cannot_turn_and_who_cannot_hear() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	var gob := _fight(s, "goblin")
	assert_bool(FeatureRules.cutting_words(s, data, gob, {"total": 40, "ac": 10, "nat20": false, "hit": true}, "roll", [] as Array[String])).is_false()
	ConditionRules.add_effect(gob, {"condition": "deafened", "source": {"kind": "engine", "name": ""}})
	assert_bool(FeatureRules.cutting_words(s, data, gob, {"total": 11, "ac": 10, "nat20": false, "hit": true}, "roll", [] as Array[String])).is_false()
	var s2 := _hero("bard_yas", 3)
	(s2.character["features"] as Array).append("cutting_words")
	var ghoul := _fight(s2, "ghoul")  # immune to charm (5e: not for one that cannot be charmed)
	assert_bool(FeatureRules.hears_words(s2, data, ghoul)).is_false()
	assert_bool(FeatureRules.cutting_words(s2, data, ghoul, {"total": 11, "ac": 10, "nat20": false, "hit": true}, "roll", [] as Array[String])).is_false()


func test_a_contest_carries_the_words_of_a_bard() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	var gob := _fight(s, "goblin")
	FightGrid.put(gob, FightGrid.cell(CombatRules.player(s)) + Vector2i(1, 0))
	var spoke := false
	for i: int in 40:  # the goblin grapples the bard until a roll the bard's die could turn comes up
		CombatRules.player(s)["reacted"] = false
		Stock.give(s.character, "bardic_inspiration", 5)
		var lines: Array[String] = []
		CombatRules.contest(s, data, gob, "athletics", CombatRules.player(s), ["athletics", "acrobatics"], lines)
		if not lines.is_empty():
			spoke = true
			assert_str(lines[0]).contains("Язвительные слова")
			break
	assert_bool(spoke).is_true()


# --- Fast Hands, Expertise ------------------------------------------------------------------------------------


func test_fast_hands_make_use_an_object_a_bonus_action() -> void:
	var thief := _hero("rogue_damir", 3)
	assert_bool(FeatureRules.has(thief.character, "fast_hands")).is_true()
	_fight(thief, "goblin", 3)
	assert_str(Acts.one("use_item").cost(thief, data, CombatRules.player(thief), {"item": "torch"})).is_equal("bonus")
	var rogue := _hero("rogue_damir", 2)
	_fight(rogue, "goblin", 3)
	assert_str(Acts.one("use_item").cost(rogue, data, CombatRules.player(rogue), {"item": "torch"})).is_equal("action")


func test_fast_hands_pick_a_locked_door_of_a_fight_as_a_bonus_action() -> void:
	var s := _hero("rogue_damir", 3)
	s.room_id = "brod-tavern-hall"
	s.minute = 720
	CombatRules.start(s, data, [{"monster": "goblin", "beside": true}], {})
	while not CombatRules.is_player_turn(s) and str(s.combat.get("outcome", "")).is_empty():
		CombatRules.next_actor(s, data)
	var d: Dictionary = FightGrid.map(s, data)["doors"][0]
	var door := Vector2i(int(d["x"]), int(d["y"]))
	var g := FightGrid.grid(s, data)
	FightGrid.put(CombatRules.fighter(s, CombatRules.enemies(s)[0]), Vector2i(0, 0))
	for way: Vector2i in WalkRules.DIRS:
		if FightGrid.walkable(g, door + way) and FightGrid.flags_at(g, door + way) & FightGrid.DOOR == 0:
			FightGrid.put(CombatRules.player(s), door + way)
			break
	s.combat["doors"][FightGrid.tag(door)] = {"locked": true}
	FightGrid.changed(s)
	ItemRules.add(s.character, "thieves_tools", 1)
	var p := CombatRules.player(s)
	assert_array(FightField.acts(s, data, p)).contains(["door_pick", "door_force"])
	assert_str(Acts.one("field").cost(s, data, p, {"how": "door_pick"})).is_equal("bonus")
	assert_str(Acts.one("field").cost(s, data, p, {"how": "door_force"})).is_equal("action")
	var opened := false
	for i: int in 30:
		CombatRules.economy(s)["bonus"] = 1
		Acts.one("field").go(s, data, p, "", {"how": "door_pick"})
		if not FightGrid.fast(s, FightGrid.grid(s, data), door):
			opened = true
			break
	assert_bool(opened).is_true()
	var m := FightGrid.map(s, data)
	assert_bool(bool(s.ways.get(WayRules.key(str(m["ids"][int(d["a"])]), str(m["ids"][int(d["b"])])), {}).get("locked", false))).is_false()


func test_a_rogue_may_take_expertise_in_thieves_tools() -> void:
	var ch := CharacterBuilder.empty_choices()
	ch["race"] = "human"
	ch["class"] = "rogue"
	ch["background"] = data["backgrounds"].keys()[0]
	assert_array(CharacterBuilder.expertise_pool(ch, data)).contains(["thieves_tools"])
	var bard := CharacterBuilder.empty_choices()
	bard["race"] = "human"
	bard["class"] = "bard"
	assert_array(CharacterBuilder.expertise_pool(bard, data)).not_contains(["thieves_tools"])
	assert_str(CharacterRules.expertise_word(data, "thieves_tools")).is_equal(BackgroundRules.tool_name(data, "thieves_tools"))


func test_thieves_tools_of_expertise_double_the_proficiency_of_a_pick() -> void:
	var s := _hero("rogue_damir", 1)
	var c := s.character
	c["skill_profs"] = (c["skill_profs"] as Array).filter(func(x: Variant) -> bool: return str(x) != "sleight_of_hand")
	c["expertise"] = []
	var prof := CharacterRules.prof_bonus(c, data)
	assert_int(int(BackgroundRules.tool_check(c, data, "thieves_tools", "sleight_of_hand")["bonus"])).is_equal(prof)
	c["expertise"] = ["thieves_tools"]
	assert_int(int(BackgroundRules.tool_check(c, data, "thieves_tools", "sleight_of_hand")["bonus"])).is_equal(prof * 2)
	c["skill_profs"] = (c["skill_profs"] as Array) + ["sleight_of_hand"]
	var t := BackgroundRules.tool_check(c, data, "thieves_tools", "sleight_of_hand")
	assert_int(int(t["bonus"])).is_equal(prof)  # the skill's proficiency once, the tool's doubles it
	assert_str(str(t["advantage"])).is_not_empty()
