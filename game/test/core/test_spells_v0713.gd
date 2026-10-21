extends GdUnitTestSuite
## «Правила 5e: заклинания», пачка 1 (roadmap v0.7.13): every spell the engine resolves is checked against the 5e SRD —
## dice and their growth by slot and by the caster's level, range, save and half damage, the attack, the area; and the
## riders: Guiding Bolt's advantage, Vicious Mockery's disadvantage, Ray of Frost's slow, Chill Touch, Shocking Grasp,
## Acid Arrow's burn and half on a miss, Acid Splash's second target, Lightning Bolt's line; healing out of a fight.

var data: Dictionary

## 5e SRD: id → [circle, range ft, damage or healing at the base, at a higher slot / level, save ability ("" — attack),
## half on a save].
const TABLE := {
	"acid_arrow": [2, 90, "4d4", {"3": "5d4"}, "", false],
	"acid_splash": [0, 60, "1d6", {"5": "2d6", "11": "3d6"}, "dex", false],
	"burning_hands": [1, 0, "3d6", {"2": "4d6", "3": "5d6"}, "dex", true],
	"chill_touch": [0, 120, "1d8", {"5": "2d8"}, "", false],
	"cure_wounds": [1, 5, "1d8+MOD", {"2": "2d8+MOD"}, "", false],
	"eldritch_blast": [0, 120, "1d10", {"5": "1d10"}, "", false],
	"fire_bolt": [0, 120, "1d10", {"5": "2d10", "11": "3d10"}, "", false],
	"fireball": [3, 150, "8d6", {"4": "9d6"}, "dex", true],
	"guiding_bolt": [1, 120, "4d6", {"2": "5d6"}, "", false],
	"healing_word": [1, 60, "1d4+MOD", {"2": "2d4+MOD"}, "", false],
	"inflict_wounds": [1, 5, "3d10", {"2": "4d10"}, "", false],
	"lightning_bolt": [3, 0, "8d6", {"4": "9d6"}, "dex", true],
	"magic_missile": [1, 120, "1d4+1", {"2": "1d4+1"}, "", false],
	"mass_healing_word": [3, 60, "1d4+MOD", {"4": "2d4+MOD"}, "", false],
	"poison_spray": [0, 10, "1d12", {"5": "2d12"}, "con", false],
	"prayer_of_healing": [2, 30, "2d8+MOD", {"3": "3d8+MOD"}, "", false],
	"produce_flame": [0, 30, "1d8", {"5": "2d8"}, "", false],
	"ray_of_frost": [0, 60, "1d8", {"5": "2d8"}, "", false],
	"sacred_flame": [0, 60, "1d8", {"5": "2d8"}, "dex", false],
	"scorching_ray": [2, 120, "2d6", {}, "", false],
	"shatter": [2, 60, "3d8", {"3": "4d8"}, "con", true],
	"shocking_grasp": [0, 5, "1d8", {"5": "2d8"}, "", false],
	"thunderwave": [1, 0, "2d8", {"2": "3d8"}, "con", true],
	"vicious_mockery": [0, 60, "1d4", {"5": "2d4"}, "wis", false],
}


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


## The spell given to the hero, its slots full, any class.
func _learn(s: GameSession, spell_id: String) -> void:
	var c := s.character
	var sp: Dictionary = c["spells"]
	var always: Array = sp.get("always", [])
	always.append(spell_id)
	sp["always"] = always
	c["slots_max"] = [4, 3, 3, 0, 0]
	c["slots_used"] = [0, 0, 0, 0, 0]


# --- the table ----------------------------------------------------------------------------------------


func test_every_engine_spell_matches_the_srd() -> void:
	var engine: Array = data["rules"]["combat"]["engine_spells"]
	for id: String in TABLE:
		assert_bool(engine.has(id)).override_failure_message("не в движке: " + id).is_true()
	for id: Variant in engine:
		assert_bool(TABLE.has(str(id))).override_failure_message("нет в таблице проверки: %s" % id).is_true()
	for id: String in TABLE:
		var row: Array = TABLE[id]
		var sp: Dictionary = data["spells"][id]
		assert_int(int(sp["level"])).override_failure_message(id).is_equal(int(row[0]))
		assert_int(int(sp.get("range_ft", 0))).override_failure_message(id + " range").is_equal(int(row[1]))
		var base_key := str(maxi(1, int(row[0])))
		var heal := sp.has("heal_at_slot")
		if heal:
			assert_str(str(sp["heal_at_slot"][str(int(row[0]))])).override_failure_message(id).is_equal(str(row[2]))
			for k: String in row[3]:
				assert_str(str(sp["heal_at_slot"][k])).override_failure_message(id + " " + k).is_equal(str(row[3][k]))
			continue
		var lv0 := int(row[0]) == 0
		assert_str(CombatRules._spell_dice(sp, 0 if lv0 else int(row[0]), 1)).override_failure_message(id).is_equal(str(row[2]))
		for k: String in row[3]:
			var at := CombatRules._spell_dice(sp, 0, int(k)) if lv0 else CombatRules._spell_dice(sp, int(k), 1)
			assert_str(at).override_failure_message("%s at %s" % [id, k]).is_equal(str(row[3][k]))
		if str(row[4]).is_empty():
			assert_bool(sp.has("attack") or id == "magic_missile").override_failure_message(id + " attack").is_true()
		else:
			assert_str(str(sp["save"]["ability"])).override_failure_message(id + " save").is_equal(str(row[4]))
			assert_bool(str(sp["save"]["success"]) == "half").override_failure_message(id + " half").is_equal(bool(row[5]))
		assert_str(base_key).is_not_empty()


func test_multi_beams_and_darts() -> void:
	var multi: Dictionary = data["rules"]["combat"]["multi"]
	assert_int(int(multi["magic_missile"]["base"])).is_equal(3)
	assert_int(int(multi["scorching_ray"]["base"])).is_equal(3)
	assert_int(int(multi["eldritch_blast"]["by_level"]["5"])).is_equal(2)
	assert_int(int(multi["eldritch_blast"]["by_level"]["11"])).is_equal(3)


func test_condition_spells_match_the_srd() -> void:
	var cs: Dictionary = data["rules"]["combat"]["condition_spells"]
	var want := {"sleep": ["unconscious", "5d8"], "color_spray": ["blinded", "6d10"], "hold_person": ["paralyzed", ""],
		"command": ["incapacitated", ""], "charm_person": ["charmed", ""], "blindness_deafness": ["blinded", ""],
		"hideous_laughter": ["prone", ""], "entangle": ["restrained", ""], "fear": ["frightened", ""], "web": ["restrained", ""]}
	for id: String in want:
		assert_bool((cs[id]["conditions"] as Array).has(want[id][0])).override_failure_message(id).is_true()
		if not str(want[id][1]).is_empty():
			assert_str(str(cs[id]["pool"])).is_equal(str(want[id][1]))
	assert_bool(bool(cs["hold_person"]["repeat_save"])).is_true()
	assert_array(cs["hold_person"]["types"]).contains(["humanoid"])
	assert_int(int(cs["hideous_laughter"]["min_int"])).is_equal(5)


# --- in a fight -------------------------------------------------------------------------------------------


func test_fire_bolt_grows_with_the_caster() -> void:
	var sp: Dictionary = data["spells"]["fire_bolt"]
	assert_str(CombatRules._spell_dice(sp, 0, 4)).is_equal("1d10")
	assert_str(CombatRules._spell_dice(sp, 0, 5)).is_equal("2d10")


func test_guiding_bolt_gives_advantage_to_the_next_attack() -> void:
	var s := _hero("cleric_branko")
	_learn(s, "guiding_bolt")
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	f["ac"] = 1
	f["hp"] = 500
	f["max_hp"] = 500
	for i in 5:
		s.combat["economy"]["action"] = 1
		CombatRules.player_cast(s, data, "guiding_bolt", 1, str(f["id"]))
		if f.has("guided"):
			break
	assert_bool(f.has("guided")).is_true()
	var w := CombatRules.weapon_profile(s.character, data, s.items, "")
	assert_array(CombatRules._attack_mods(s, data, w, f)["adv"]).contains(["Направляющий снаряд"])
	var lines: Array[String] = []
	CombatRules._attack(s, data, "x", "y", 5, true, false, f, "1d4", 0, "bludgeoning", lines)
	assert_bool(f.has("guided")).is_false()


func test_vicious_mockery_hampers_the_next_attack() -> void:
	var s := _hero("bard_yas")
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	var lines: Array[String] = []
	CombatRules._spell_rider(s, data, "vicious_mockery", 0, f, true, lines)
	assert_bool(bool(f.get("mocked", false))).is_true()
	f["col"] = 0
	var turn: Array[String] = []
	CombatRules._enemy_turn(s, data, f, turn)
	assert_bool(f.has("mocked")).is_false()
	assert_bool(turn.any(func(l: String) -> bool: return l.contains("(с помехой)"))).override_failure_message(" · ".join(turn)).is_true()


func test_ray_of_frost_slows_until_the_hero_turn() -> void:
	var s := _hero("wizard_yalika")
	var f := _fight(s, [{"monster": "goblin", "col": 2}])[0]
	var lines: Array[String] = []
	CombatRules._spell_rider(s, data, "ray_of_frost", 0, f, true, lines)
	assert_int(int(f["slowed"])).is_equal(10)
	CombatRules._begin_turn(s, data, lines)
	assert_bool(f.has("slowed")).is_false()


func test_shocking_grasp_against_metal_and_no_reaction() -> void:
	var s := _hero("wizard_yalika")
	var f := _fight(s, [{"monster": "knight", "col": 0}])[0]
	assert_bool(CombatRules._metal_armor(data, f)).is_true()
	var lines: Array[String] = []
	CombatRules._spell_rider(s, data, "shocking_grasp", 0, f, true, lines)
	assert_bool(bool(f["reacted"])).is_true()


func test_acid_arrow_burns_later_and_splashes_on_a_miss() -> void:
	var s := _hero("wizard_yalika")
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	var lines: Array[String] = []
	CombatRules._spell_rider(s, data, "acid_arrow", 2, f, true, lines)
	assert_str(str(f["acid"])).is_equal("2d4")
	var hp := int(f["hp"])
	CombatRules._end_actor(s, data, f, lines)
	assert_int(int(f["hp"])).is_less(hp)
	hp = int(f["hp"])
	CombatRules._spell_rider(s, data, "acid_arrow", 2, f, false, lines)
	assert_int(int(f["hp"])).is_less_equal(hp)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("брызги"))).is_true()


func test_lightning_bolt_is_a_line() -> void:
	var s := _hero("wizard_yalika")
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 3}, {"monster": "goblin", "col": -1}])
	var near: Dictionary = foes.filter(func(f: Dictionary) -> bool: return int(f["col"]) == 1)[0]
	var hit := CombatRules.area_targets(s, data, data["spells"]["lightning_bolt"], near)
	assert_int(hit.size()).is_equal(2)  # 1 and 3 (90 ft) on the line; the one behind is not
	assert_bool(hit.all(func(f: Dictionary) -> bool: return int(f["col"]) > 0)).is_true()


func test_acid_splash_takes_a_second_neighbour() -> void:
	var s := _hero("wizard_yalika")
	_learn(s, "acid_splash")
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}])
	var lines := CombatRules.player_cast(s, data, "acid_splash", 0, str(foes[0]["id"]))
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("спасбросок")).size()).override_failure_message(" · ".join(lines)).is_equal(2)


func test_prayer_of_healing_is_not_for_a_fight() -> void:
	var s := _hero("cleric_branko", 3)
	_learn(s, "prayer_of_healing")
	_fight(s, [{"monster": "goblin", "col": 2}])
	assert_str(CombatRules.can_cast(s, data, "prayer_of_healing", 2, "")).is_equal("COMBAT_SPELL_TOO_LONG")


func test_charm_person_save_has_advantage_in_a_fight() -> void:
	var s := _hero("bard_yas")
	var f := _fight(s, [{"monster": "bandit", "col": 1}])[0]
	assert_bool(MonsterRules.save_advantage(data, f, "wis", ["magic", "charm", "fighting"])).is_true()


# --- out of a fight ---------------------------------------------------------------------------------------


func test_cure_wounds_heals_the_hero_out_of_a_fight() -> void:
	var s := _hero("cleric_branko")
	var c := s.character
	c["hp"] = 1
	var chk := SpellRules.check(c, data, "cure_wounds", 0)
	var lines := SpellRules.cast(c, data, chk["spell_id"], int(chk["slot"]), s, true)
	assert_int(int(c["hp"])).override_failure_message(" · ".join(lines)).is_greater(1)
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("+"))).is_true()
