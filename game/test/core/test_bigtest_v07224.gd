extends GdUnitTestSuite
## The big test, batch 3b (roadmap v0.7.22.4): Command speaks a word of 5e, a caster does not repeat a spell the
## hero shook off and shows its slots; the warlock's invocations give spells at will; darts and rays fly one by one,
## each at a target of its own (as in BG3).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
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


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func test_command_speaks_a_word() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "cult_fanatic", "col": 0}])[0]
	var spec: Dictionary = CombatRules.cfg(data)["condition_spells"]["command"]
	var words := {}
	for i in 30:
		words[str(MonsterRules._command_word(s, spec)["word"])] = true
	assert_bool(words.has("Пади!") and words.has("Брось!")).is_true()
	ConditionRules.add(s.character, "prone")
	for i in 30:
		assert_str(str(MonsterRules._command_word(s, spec)["word"])).is_not_equal("Пади!")  # already down
	ConditionRules.remove(s.character, "prone")
	s.character["equipped"]["main_hand"] = ""
	for i in 30:
		assert_str(str(MonsterRules._command_word(s, spec)["word"])).is_not_equal("Брось!")  # nothing in hand
	var lines: Array[String] = []
	s.character["abilities"]["wis"] = 1
	s.settings["difficulty"] = "hard"
	for i in 10:
		lines.clear()
		ConditionRules.remove(s.character, "incapacitated")
		ConditionRules.remove(s.character, "prone")
		MonsterRules._cast_condition_on_hero(s, data, f, "command", 1, spec, 30, lines)
		if ConditionRules.has(s.character, "incapacitated"):
			break
	assert_str(" · ".join(lines)).contains("«Приказ» — «")
	assert_bool(ConditionRules.has(s.character, "incapacitated")).is_true()


func test_a_dropped_weapon_is_picked_up_next_turn() -> void:
	var s := _hero("fighter_aira")
	_fight(s, [{"monster": "cult_fanatic", "col": 0}])
	var c := s.character
	var held := str(c["equipped"]["main_hand"])
	c["equipped"]["main_hand"] = ""
	c["dropped"] = held
	var lines: Array[String] = []
	CombatRules._begin_turn(s, data, lines)
	assert_str(str(c["equipped"]["main_hand"])).is_equal(held)
	assert_str(" · ".join(lines)).contains("поднимает")


func test_the_foe_card_shows_its_slots() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, [{"monster": "cult_fanatic", "col": 0}])[0]
	s.known_monsters.append("cult_fanatic")
	f["slots"] = {"1": 1, "2": 3}
	assert_str(CombatRules.monster_card(s, data, f)).contains("Ячейки: 1 круг 1/4")


func test_misty_visions_gives_silent_image_at_will() -> void:
	var s := _hero("warlock_fiber", 2)
	var c := s.character
	(c["features"] as Array).append("eldritch_invocation_misty_visions")
	CharacterRules.refresh(c, data, s.items)
	assert_bool(SpellRules.is_free(c, "silent_image")).is_true()
	assert_bool(SpellRules.ready(c).has("silent_image")).is_true()
	c["slots_used"] = (c["slots_max"] as Array).duplicate()  # no slots at all
	var chk := SpellRules.check(c, data, "silent_image", 0)
	assert_int(int(chk.get("slot", -1))).override_failure_message(str(chk)).is_equal(0)
	SpellRules.cast(c, data, "silent_image", 0, s)
	assert_array(c["slots_used"]).is_equal(c["slots_max"])
	(c["features"] as Array).erase("eldritch_invocation_misty_visions")
	CharacterRules.refresh(c, data, s.items)
	assert_bool(SpellRules.is_free(c, "silent_image")).is_false()


func test_agonizing_blast_adds_charisma() -> void:
	var s := _hero("warlock_fiber", 2)
	var c := s.character
	(c["features"] as Array).append("eldritch_invocation_agonizing_blast")
	c["abilities"]["cha"] = 18
	var f := _fight(s, [{"monster": "ogre", "col": 1}])[0]
	f["ac"] = 0
	var low := 99
	for i in 20:
		f["hp"] = 999
		var lines: Array[String] = []
		CombatRules._bolt(s, data, "eldritch_blast", 0, f, "1d10", lines)
		var at := lines[0].find("попадание, ")
		if at >= 0:
			low = mini(low, int(lines[0].substr(at + 11).get_slice(" ", 0)))
	assert_int(low).is_greater_equal(5)  # 1d10 + CHA 4: never below 5


func test_darts_fly_one_by_one() -> void:
	var s := _hero("wizard_yalika", 1)
	var c := s.character
	if not SpellRules.ready(c).has("magic_missile"):
		(c["spells"]["prepared"] as Array).append("magic_missile")
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}])
	var a := str(foes[0]["id"])
	var b := str(foes[1]["id"])
	var lines := CombatRules.player_cast(s, data, "magic_missile", 1, a)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("Волшебная стрела:")).size()).is_equal(1)
	assert_int(int(CombatRules.volley(s)["left"])).is_equal(2)
	assert_str(CombatRules.can_volley(s, data, b)).is_empty()
	CombatRules.volley_shot(s, data, b)
	assert_int(int(CombatRules.volley(s)["left"])).is_equal(1)
	var rest := CombatRules.end_player_turn(s, data)  # the last dart flies at the last target
	assert_str(" · ".join(rest)).contains("Волшебная стрела")
	assert_bool(CombatRules.volley(s).is_empty()).is_true()
