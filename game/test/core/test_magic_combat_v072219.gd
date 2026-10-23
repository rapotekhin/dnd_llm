extends GdUnitTestSuite
## Magic and combat by 5e (roadmap v0.7.22.19, the author's fixes check #1, #9, #13, #14, #19, #31): what a higher slot
## gives, the Shield hint against the same roll and AC as the hit, a thrown dagger thrown once, a caster that heals its
## side and does not repeat Command, a threat without a common tongue, one cantrip not taken twice.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String = "fighter_aira", room: String = "pushcha-hollow") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_a_higher_slot_shows_what_it_gives() -> void:
	assert_str(SpellRules.at_slot(data, "cure_wounds", 2)).contains("лечение 2к8 + мод.")
	assert_str(SpellRules.at_slot(data, "burning_hands", 3)).contains("урон 5к6")
	assert_str(SpellRules.at_slot(data, "burning_hands", 1)).is_empty()  # its own circle: nothing grows
	assert_str(SpellRules.at_slot(data, "magic_missile", 3)).contains("снарядов 5")
	assert_str(SpellRules.at_slot(data, "fire_bolt", 0)).is_empty()
	assert_str(SpellRules.describe(data, "burning_hands", 2)).contains("усилено: урон 4к6")
	assert_str(DetailsPanel.spell_text(data, "magic_missile", 2)).contains("Ячейкой 2 круга")


func test_the_shield_hint_uses_the_hits_own_roll() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	if not SpellRules.ready(c).has("shield"):
		(c["spells"]["prepared"] as Array).append("shield")
		(c["spells"]["known"] as Array).append("shield")
	var label := func(ctx: Dictionary) -> String:
		for r: Dictionary in SpellEffects.hit_reactions(s, data, ctx):
			if str(r["id"]) == "spell_shield":
				return str(r["label"])
		return ""
	assert_str(label.call({"total": 14, "ac": 12, "nat20": true})).contains("всё равно попадёт")  # a natural 20 hits through Shield
	assert_str(label.call({"total": 14, "ac": 12, "nat20": false})).contains("мимо")
	assert_str(label.call({"total": 18, "ac": 12, "nat20": false})).contains("всё равно попадёт")


func test_a_thrown_dagger_is_thrown_once() -> void:
	var s := _hero()
	CombatRules.start(s, data, [{"monster": "cult_fanatic", "name": "Жрец Пепла", "col": 2}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	f["col"] = int(CombatRules.player(s)["col"]) + 2
	s.character["hp"] = 999
	s.character["max_hp"] = 999
	var dagger := MonsterRules.pick(s, data, f, "ranged")
	assert_str(str(dagger.get("name_en", ""))).is_equal("Dagger")
	var lines: Array[String] = []
	CombatRules._enemy_attack_full(s, data, f, dagger, lines)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("Кинжал")).size()).is_equal(1)  # one throw, not Multiattack
	assert_array(f.get("thrown", [])).contains(["Dagger"])
	assert_dict(MonsterRules.pick(s, data, f, "ranged")).is_empty()  # the dagger is gone: it closes in


func test_a_caster_heals_its_side_and_varies() -> void:
	var s := _hero()
	CombatRules.start(s, data, [{"monster": "acolyte", "name": "Служка", "col": 3}, {"monster": "goblin", "name": "Гоблин", "col": 3}], {})
	var ids := CombatRules.enemies(s)
	var priest := CombatRules.fighter(s, ids[0])
	var gob := CombatRules.fighter(s, ids[1])
	gob["col"] = int(priest["col"])
	gob["hp"] = 1
	var lines: Array[String] = []
	assert_bool(MonsterRules.cast_turn(s, data, priest, lines)).is_true()
	assert_int(int(gob["hp"])).is_greater(1)
	assert_str(" ".join(lines)).contains("на Гоблин")

	var t := _hero()
	CombatRules.start(t, data, [{"monster": "cult_fanatic", "name": "Жрец Пепла", "col": 0}], {})
	var fan := CombatRules.fighter(t, CombatRules.enemies(t)[0])
	fan["col"] = int(CombatRules.player(t)["col"])
	fan["last_spell"] = "command"
	var more: Array[String] = []
	MonsterRules.cast_turn(t, data, fan, more)
	assert_str(str(fan.get("last_spell", ""))).is_not_equal("command")


func test_a_threat_needs_no_common_tongue() -> void:
	var s := _hero()
	var gnolls := [{"monster": "gnoll", "name": "Гнолл", "count": 2}]
	if LanguageRules.foe_understands(s.character, data, gnolls[0]):
		return  # this hero happens to speak Gnoll
	assert_str(EncounterRules.talkable(s, data, gnolls)).is_equal("COMBAT_NO_LANGUAGE")
	assert_str(EncounterRules.talkable(s, data, gnolls, "intimidation")).is_empty()
	assert_str(EncounterRules.talkable(s, data, [{"monster": "wolf", "count": 2}], "intimidation")).is_equal("COMBAT_NO_PARLEY")
	var r := EncounterRules.roll(s, data, "intimidation", 12, EncounterRules.mute(s, data, gnolls))
	assert_str(str(r["line"])).contains("помеха")


func test_one_cantrip_is_not_taken_twice() -> void:
	var ch := {}
	for p: Dictionary in data["presets"]:
		if p["id"] == "wizard_yalika":
			ch = (p["choices"] as Dictionary).duplicate(true) if p.has("choices") else {}
	if ch.is_empty() or int(CharacterBuilder.spell_choices(ch, data)["race_cantrips"]) == 0:
		ch = CharacterBuilder.random_choices(data, RandomNumberGenerator.new())
		ch["race"] = "elf"
		ch["subrace"] = "high_elf"
		ch["class"] = "wizard"
	var sp := CharacterBuilder.spell_choices(ch, data)
	assert_int(int(sp["race_cantrips"])).is_equal(1)
	ch["cantrips"] = (sp["cantrip_list"] as Array).slice(0, int(sp["cantrips"]))
	ch["spells"] = (sp["spell_list"] as Array).slice(0, int(sp["spells"]))
	ch["race_cantrips"] = [ch["cantrips"][0]]
	assert_array(CharacterBuilder.errors(ch, data, CharacterBuilder.STEP_SPELLS)).contains(["CC_ERR_SPELLS"])
	ch["race_cantrips"] = [(sp["race_list"] as Array).filter(func(x: Variant) -> bool: return not (ch["cantrips"] as Array).has(x))[0]]
	assert_array(CharacterBuilder.errors(ch, data, CharacterBuilder.STEP_SPELLS)).is_empty()
	for i in 20:  # a random high-elf wizard never doubles one
		var rch := CharacterBuilder.random_choices(data, RandomNumberGenerator.new())
		if int(CharacterBuilder.spell_choices(rch, data)["race_cantrips"]) > 0:
			assert_bool((rch["race_cantrips"] as Array).any(func(x: Variant) -> bool: return (rch["cantrips"] as Array).has(x))).is_false()
