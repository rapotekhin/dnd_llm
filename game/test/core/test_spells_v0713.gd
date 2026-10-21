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


# --- batch 2 (v0.7.13.1): dice of the buffs, concentration ------------------------------------------------


func test_bless_adds_a_d4_to_attacks_and_saves() -> void:
	var s := _hero("cleric_branko")
	_learn(s, "bless")
	var c := s.character
	SpellRules.cast(c, data, "bless", 1, s, true)
	assert_str(str(c["concentration"])).is_equal("bless")
	var r := HeroDefense.save(s, data, "dex", 30)
	assert_str(str(r["text"])).contains("Благословение")
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	var lines: Array[String] = []
	CombatRules._attack(s, data, "x", "удар", 3, false, false, f, "1d4", 0, "bludgeoning", lines)
	assert_str(lines[0]).contains("Благословение")


func test_guidance_is_one_roll() -> void:
	var s := _hero("cleric_branko")
	_learn(s, "guidance")
	SpellRules.cast(s.character, data, "guidance", 0, s, true)
	var first := SpellEffects.hero_die(s, data, "check")
	assert_int(int(first["bonus"])).is_between(1, 4)
	assert_int(int(SpellEffects.hero_die(s, data, "check")["bonus"])).is_equal(0)
	assert_str(str(s.character["concentration"])).is_empty()


func test_bane_takes_a_d4_from_foes() -> void:
	var s := _hero("cleric_branko")
	_learn(s, "bane")
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 2}])
	s.character["spell_dc"] = 30  # they fail
	var lines := CombatRules.player_cast(s, data, "bane", 1, str(foes[0]["id"]))
	assert_bool(foes.all(func(f: Dictionary) -> bool: return f.has("minus_die"))).override_failure_message(" · ".join(lines)).is_true()
	var out := ConditionRules.end_concentration(s, data, "проверка")
	assert_bool(foes.any(func(f: Dictionary) -> bool: return f.has("minus_die"))).is_false()
	assert_int(out.size()).is_greater(1)


func test_heroism_keeps_fear_away_and_gives_temp_hp() -> void:
	var s := _hero("paladin_gordey")
	_learn(s, "heroism")
	SpellRules.cast(s.character, data, "heroism", 1, s, true)
	assert_int(int(s.character["temp_hp"])).is_greater(0)
	assert_str(HeroDefense.immune(s.character, data, "frightened", "fear")).is_equal("Героизм")


func test_true_strike_gives_advantage_once() -> void:
	var s := _hero("wizard_yalika")
	_learn(s, "true_strike")
	SpellRules.cast(s.character, data, "true_strike", 0, s, true)
	assert_bool(SpellEffects.has_next_attack_adv(s.character)).is_true()
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	var lines: Array[String] = []
	CombatRules._attack(s, data, "x", "удар", 3, false, false, f, "1d4", 0, "bludgeoning", lines)
	assert_str(lines[0]).contains("(с преимуществом)")
	assert_bool(SpellEffects.has_next_attack_adv(s.character)).is_false()


func test_a_second_concentration_spell_is_asked_about() -> void:
	var s := _hero("cleric_branko")
	_learn(s, "bless")
	_learn(s, "bane")
	SpellRules.cast(s.character, data, "bless", 1, s, true)
	assert_str(str(s.character["concentration"])).is_equal("bless")
	assert_bool(bool(data["spells"]["bane"]["concentration"])).is_true()
	assert_array(ConditionRules.shown(s, data).filter(func(e: Dictionary) -> bool: return str(e["text"]).contains("+к4"))).is_not_empty()


# --- batch 3 (v0.7.13.2): defenses ----------------------------------------------------------------------


func _cast_self(s: GameSession, id: String, slot: int = 0) -> Array[String]:
	_learn(s, id)
	var lv := int(data["spells"][id]["level"])
	return SpellRules.cast(s.character, data, id, maxi(lv, slot), s, true)


func test_mage_armor_shield_of_faith_and_barkskin() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	var dex := CharacterRules.mod(CharacterRules.ability(c, "dex"))
	_cast_self(s, "mage_armor")
	assert_int(int(c["ac"])).is_equal(13 + dex)
	_cast_self(s, "shield_of_faith")
	assert_int(int(c["ac"])).is_equal(15 + dex)
	var druid := _hero("druid_olha")
	_cast_self(druid, "barkskin")
	assert_int(int(druid.character["ac"])).is_greater_equal(16)
	ConditionRules.end_concentration(druid, data, "проверка")
	assert_int(int(druid.character["ac"])).is_less(16)


func test_false_life_and_aid() -> void:
	var s := _hero("cleric_branko", 3)
	var c := s.character
	_cast_self(s, "false_life")
	assert_int(int(c["temp_hp"])).is_between(5, 8)
	var max_hp := int(c["max_hp"])
	_cast_self(s, "aid", 3)
	assert_int(int(c["max_hp"])).is_equal(max_hp + 10)


func test_blur_and_protection_from_evil_hamper_attackers() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "skeleton", "col": 0}])[0]
	_cast_self(s, "blur")
	assert_array(SpellEffects.attack_dis(s, data, f)).contains(["Размытость"])
	var c2 := _hero("cleric_branko")
	var f2 := _fight(c2, [{"monster": "skeleton", "col": 0}])[0]
	_cast_self(c2, "protection_from_evil_and_good")
	assert_int(SpellEffects.attack_dis(c2, data, f2).size()).is_equal(1)


func test_mirror_image_takes_hits() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	_cast_self(s, "mirror_image")
	var stopped := 0
	for i in 20:
		if not str(SpellEffects.against_attack(s, data, f, 30, true)["stop"]).is_empty():
			stopped += 1
	assert_int(stopped).is_greater(0)
	assert_bool(SpellEffects.hero_effects(s.character, "images").all(func(e: Dictionary) -> bool: return int(e["images"]) < 3)).is_true()


func test_sanctuary_holds_and_breaks() -> void:
	var s := _hero("cleric_branko")
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	_cast_self(s, "sanctuary")
	s.character["spell_dc"] = 40
	assert_str(SpellEffects.sanctuary_holds(s, data, f)).contains("Святилище")
	s.combat["economy"]["action"] = 1
	CombatRules.player_attack(s, data, str(f["id"]))
	assert_array(SpellEffects.hero_effects(s.character, "sanctuary")).is_empty()


func test_protection_from_energy_picks_the_foes_type() -> void:
	var s := _hero("wizard_yalika", 5)
	_fight(s, [{"monster": "fire_beetle" if data["monsters"].has("fire_beetle") else "goblin", "col": 2}])
	_cast_self(s, "protection_from_energy")
	assert_int(HeroDefense.resistances(s, data).size()).is_greater(0)
	var p := _hero("cleric_branko", 3)
	ConditionRules.add_effect(p.character, {"condition": "poisoned", "ends": {}, "source": {"kind": "master", "name": "яд"}})
	_cast_self(p, "protection_from_poison")
	assert_bool(ConditionRules.has(p.character, "poisoned")).is_false()
	assert_bool(HeroDefense.resistances(p, data).has("poison")).is_true()


func test_beacon_of_hope_maximizes_healing() -> void:
	var s := _hero("cleric_branko", 5)
	_cast_self(s, "beacon_of_hope")
	s.character["hp"] = 1
	_learn(s, "cure_wounds")
	SpellRules.cast(s.character, data, "cure_wounds", 1, s, true)
	var mod := CharacterRules.mod(CharacterRules.ability(s.character, "wis"))
	assert_int(int(s.character["hp"])).is_equal(mini(int(s.character["max_hp"]), 1 + 8 + mod + 3))  # + Disciple of Life 2 + 1
	assert_str(SpellEffects.save_adv(s.character, "wis")).is_not_empty()


# --- batch 4 (v0.7.13.3): movement and form ---------------------------------------------------------------


func test_haste_gives_an_action_and_then_lethargy() -> void:
	var s := _hero("wizard_yalika", 5)
	var c := s.character
	var ac := int(c["ac"])
	var speed := int(c["speed"])
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	_cast_self(s, "haste")
	assert_int(int(c["ac"])).is_equal(ac + 2)
	assert_int(int(c["speed"])).is_equal(speed * 2)
	var lines: Array[String] = []
	CombatRules._begin_turn(s, data, lines)
	var e := CombatRules.economy(s)
	assert_int(int(e["haste"])).is_equal(1)
	e["action"] = 0
	assert_str(CombatRules.can_attack(s, data, str(f["id"]))).is_empty()
	CombatRules.player_attack(s, data, str(f["id"]))
	assert_int(int(e["haste"])).is_equal(0)
	ConditionRules.end_concentration(s, data, "проверка")
	CombatRules._begin_turn(s, data, lines)
	assert_int(int(CombatRules.economy(s)["action"])).is_equal(0)
	assert_int(int(CombatRules.economy(s)["move"])).is_equal(0)


func test_fly_keeps_melee_foes_off() -> void:
	var s := _hero("wizard_yalika", 5)
	var foes := _fight(s, [{"monster": "wolf", "col": 0}, {"monster": "goblin", "col": 1}])
	_cast_self(s, "fly")
	var lines: Array[String] = []
	var hp := int(s.character["hp"])
	CombatRules._enemy_turn(s, data, foes[0], lines)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("не достаёт летящего"))).override_failure_message(" · ".join(lines)).is_true()
	assert_int(int(s.character["hp"])).is_equal(hp)
	var shots: Array[String] = []
	CombatRules._enemy_turn(s, data, foes[1], shots)
	assert_bool(shots.any(func(l: String) -> bool: return l.contains("лук") or l.contains("Лук"))).override_failure_message(" · ".join(shots)).is_true()


func test_blink_hides_the_hero_between_turns() -> void:
	var s := _hero("wizard_yalika", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	_cast_self(s, "blink")
	CombatRules.player(s)["blinked"] = true
	var lines: Array[String] = []
	var hp := int(s.character["hp"])
	CombatRules._enemy_turn(s, data, f, lines)
	assert_int(int(s.character["hp"])).is_equal(hp)
	CombatRules._begin_turn(s, data, lines)
	assert_bool(bool(CombatRules.player(s)["blinked"])).is_false()


func test_misty_step_moves_away_without_leaving_an_effect() -> void:
	var s := _hero("wizard_yalika", 3)
	_learn(s, "misty_step")
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	var lines := CombatRules.player_cast(s, data, "misty_step", 2, "")
	assert_int(int(CombatRules.player(s)["col"])).is_not_equal(int(f["col"]))
	assert_array(SpellEffects.hero_effects(s.character, "teleport")).is_empty()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("туманом"))).is_true()


func test_longstrider_darkvision_pass_without_trace() -> void:
	var s := _hero("druid_olha", 3)
	var c := s.character
	var speed := int(c["speed"])
	var stealth := int(c["skills"]["stealth"])
	_cast_self(s, "longstrider")
	assert_int(int(c["speed"])).is_equal(speed + 10)
	_cast_self(s, "pass_without_trace")
	assert_int(int(c["skills"]["stealth"])).is_equal(stealth + 10)
	var w := _hero("wizard_yalika", 3)
	_cast_self(w, "darkvision")
	assert_bool(SpellEffects.has(w.character, "darkvision")).is_true()


func test_see_invisibility_removes_the_disadvantage() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	CombatRules._add_condition(f, "invisible", {"rounds": 10})
	assert_array(CombatRules.hero_attack_dis(s, data, f)).contains(["цель невидима"])
	_cast_self(s, "see_invisibility")
	assert_array(CombatRules.hero_attack_dis(s, data, f)).not_contains(["цель невидима"])


# --- batch 5 (v0.7.13.4): spells on the weapon -------------------------------------------------------------


func test_shillelagh_uses_wisdom_and_a_d8() -> void:
	var s := _hero("druid_olha")
	var c := s.character
	c["inventory"]["quarterstaff"] = 1
	c["equipped"]["main_hand"] = "quarterstaff"
	var before := CombatRules.weapon_profile(c, data, s.items, "quarterstaff")
	_cast_self(s, "shillelagh")
	var w := CombatRules.weapon_profile(c, data, s.items, "quarterstaff")
	assert_str(str(w["dice"])).is_equal("1d8")
	assert_bool(bool(w["magical"])).is_true()
	assert_int(int(w["to_hit"])).is_greater_equal(int(before["to_hit"]))


func test_magic_weapon_and_divine_favor() -> void:
	var s := _hero("paladin_gordey", 5)
	var c := s.character
	var main := str(c["equipped"]["main_hand"])
	var before := CombatRules.weapon_profile(c, data, s.items, main)
	_cast_self(s, "magic_weapon")
	assert_int(int(CombatRules.weapon_profile(c, data, s.items, main)["to_hit"])).is_equal(int(before["to_hit"]) + 1)
	ConditionRules.end_concentration(s, data, "проверка")
	_cast_self(s, "divine_favor")
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	var extras := SpellEffects.hit_extras(c, f, "slashing")
	assert_str(str(extras[0]["type"])).is_equal("radiant")


func test_branding_smite_once_and_hunters_mark_on_the_target() -> void:
	var s := _hero("paladin_gordey", 5)
	var c := s.character
	var f := _fight(s, [{"monster": "ogre", "col": 0}, {"monster": "goblin", "col": 0}])
	_cast_self(s, "branding_smite")
	assert_int(SpellEffects.hit_extras(c, f[0], "slashing").size()).is_equal(1)
	assert_int(SpellEffects.hit_extras(c, f[0], "slashing").size()).is_equal(0)
	ConditionRules.end_concentration(s, data, "проверка")
	var r := _hero("ranger_velena", 2)
	var g := _fight(r, [{"monster": "ogre", "col": 1}, {"monster": "goblin", "col": 1}])
	_learn(r, "hunters_mark")
	CombatRules.player_cast(r, data, "hunters_mark", 1, str(g[0]["id"]))
	assert_int(SpellEffects.hit_extras(r.character, g[0], "piercing").size()).is_equal(1)
	assert_int(SpellEffects.hit_extras(r.character, g[1], "piercing").size()).is_equal(0)
	g[0]["status"] = "dead"
	assert_bool(SpellEffects.mark_free(r)).is_true()
	r.combat["economy"]["bonus"] = 1
	FeatureRules.act(r, data, "move_mark", str(g[1]["id"]))
	assert_int(SpellEffects.hit_extras(r.character, g[1], "piercing").size()).is_equal(1)


func test_flame_blade_attacks_with_the_spell() -> void:
	var s := _hero("druid_olha", 3)
	_cast_self(s, "flame_blade")
	var b := SpellEffects.blade_profile(s.character)
	assert_str(str(b["dice"])).is_equal("3d6")
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	assert_bool(FeatureRules.actions(s, data).any(func(a: Dictionary) -> bool: return str(a["id"]) == "flame_blade")).is_true()
	var hp := int(f["hp"])
	f["ac"] = 1
	for i in 4:
		s.combat["economy"]["action"] = 1
		FeatureRules.act(s, data, "flame_blade", str(f["id"]))
		if int(f["hp"]) < hp:
			break
	assert_int(int(f["hp"])).is_less(hp)


# --- batch 6 (v0.7.13.5): sustained damage ----------------------------------------------------------------


func _cast_at(s: GameSession, id: String, slot: int, target: String) -> Array[String]:
	_learn(s, id)
	s.combat["economy"]["action"] = 1
	s.combat["economy"]["bonus"] = 1
	return CombatRules.player_cast(s, data, id, slot, target)


func test_spiritual_weapon_strikes_now_and_each_turn() -> void:
	var s := _hero("cleric_branko", 3)
	var f := _fight(s, [{"monster": "ogre", "col": 1}])[0]
	f["ac"] = 1
	var lines := _cast_at(s, "spiritual_weapon", 2, str(f["id"]))
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("Духовное оружие") and l.contains("КД"))).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(FeatureRules.actions(s, data).any(func(a: Dictionary) -> bool: return str(a["id"]) == "spell_spiritual_weapon")).is_true()
	s.combat["economy"]["bonus"] = 1
	assert_str(FeatureRules.can_act(s, data, "spell_spiritual_weapon", str(f["id"]))).is_empty()
	var again := FeatureRules.act(s, data, "spell_spiritual_weapon", str(f["id"]))
	assert_int(int(s.combat["economy"]["bonus"])).is_equal(0)
	assert_bool(again.any(func(l: String) -> bool: return l.contains("КД"))).is_true()


func test_moonbeam_burns_who_starts_in_it_and_moves() -> void:
	var s := _hero("druid_olha", 3)
	var foes := _fight(s, [{"monster": "ogre", "col": 2}, {"monster": "goblin", "col": 3}])
	_cast_at(s, "moonbeam", 2, str(foes[0]["id"]))
	assert_array(SpellEffects.zone_names(s, 2)).contains(["Лунный луч"])
	var hp := int(foes[0]["hp"])
	var lines := SpellEffects.zone_tick(s, data, foes[0], "start")
	assert_int(int(foes[0]["hp"])).override_failure_message(" · ".join(lines)).is_less_equal(hp)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("спасбросок Тел"))).is_true()
	s.combat["economy"]["action"] = 1
	FeatureRules.act(s, data, "spell_moonbeam", str(foes[1]["id"]))
	assert_array(SpellEffects.zone_names(s, 3)).contains(["Лунный луч"])
	ConditionRules.end_concentration(s, data, "проверка")
	assert_array(SpellEffects.zones(s)).is_empty()


func test_spirit_guardians_follow_and_slow() -> void:
	var s := _hero("cleric_branko", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	_cast_at(s, "spirit_guardians", 3, "")
	assert_array(SpellEffects.zone_names(s, 0)).contains(["Духовные стражи"])
	assert_bool(SpellEffects.slowed(s, f)).is_true()
	CombatRules.player(s)["col"] = 1
	assert_array(SpellEffects.zone_names(s, 1)).contains(["Духовные стражи"])
	assert_bool(SpellEffects.slowed(s, f)).is_false()


func test_spike_growth_hurts_who_walks_in() -> void:
	var s := _hero("druid_olha", 3)
	var f := _fight(s, [{"monster": "ogre", "col": 2}])[0]
	_cast_at(s, "spike_growth", 2, str(f["id"]))
	f["col"] = 1
	var zone: Dictionary = SpellEffects.zones(s)[0]
	zone["col"] = 1
	var hp := int(f["hp"])
	var lines := SpellEffects.zone_tick(s, data, f, "enter")
	assert_int(int(f["hp"])).override_failure_message(" · ".join(lines)).is_less(hp)
	assert_int(SpellEffects.zone_tick(s, data, f, "enter").size()).is_equal(0)  # once a turn


func test_call_lightning_heat_metal_vampiric_touch() -> void:
	var s := _hero("druid_olha", 5)
	var f := _fight(s, [{"monster": "knight" if data["monsters"].has("knight") else "ogre", "col": 1}])[0]
	var lines := _cast_at(s, "call_lightning", 3, str(f["id"]))
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("Призыв молнии:"))).override_failure_message(" · ".join(lines)).is_true()
	ConditionRules.end_concentration(s, data, "проверка")
	var hm := _cast_at(s, "heat_metal", 2, str(f["id"]))
	assert_bool(hm.any(func(l: String) -> bool: return l.contains("(огонь)"))).override_failure_message(" · ".join(hm)).is_true()
	assert_bool(SpellEffects.actions(s, data).any(func(a: Dictionary) -> bool: return not bool(a["target"]))).is_true()
	ConditionRules.end_concentration(s, data, "проверка")
	var w := _hero("wizard_yalika", 5)
	var g := _fight(w, [{"monster": "ogre", "col": 0}])[0]
	g["ac"] = 1
	w.character["hp"] = 1
	var vt: Array[String] = []
	for i in 4:
		vt = _cast_at(w, "vampiric_touch", 3, "")
		if vt.any(func(l: String) -> bool: return l.contains("+") and l.contains("HP")):
			break
		ConditionRules.end_concentration(w, data, "ещё раз")
	assert_int(int(w.character["hp"])).override_failure_message(" · ".join(vt)).is_greater(1)


# --- batch 7 (v0.7.13.6): zones and control ---------------------------------------------------------------


func test_grease_lays_them_down() -> void:
	var s := _hero("wizard_yalika", 3)
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}])
	s.character["spell_dc"] = 40
	var lines := _cast_at(s, "grease", 1, str(foes[0]["id"]))
	assert_bool(foes.all(func(f: Dictionary) -> bool: return CombatRules._has(f, "prone"))).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(SpellEffects.slowed(s, foes[0])).is_true()


func test_fog_and_darkness_blind_the_column() -> void:
	var s := _hero("wizard_yalika", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 1}])[0]
	_cast_at(s, "fog_cloud", 1, str(f["id"]))
	var w := CombatRules.weapon_profile(s.character, data, s.items, "")
	assert_bool((CombatRules._attack_mods(s, data, w, f)["dis"] as Array).any(func(x: String) -> bool: return x.contains("туман"))).is_true()
	CombatRules.player(s)["col"] = 1  # both inside: they cancel
	assert_bool((CombatRules._attack_mods(s, data, w, f)["dis"] as Array).any(func(x: String) -> bool: return x.contains("туман"))).is_false()


func test_silence_stops_spells_inside() -> void:
	var s := _hero("cleric_branko", 3)
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	_cast_at(s, "silence", 2, str(f["id"]))
	_learn(s, "guiding_bolt")
	s.combat["economy"]["action"] = 1
	assert_str(CombatRules.can_cast(s, data, "guiding_bolt", 1, str(f["id"]))).is_equal("COMBAT_SILENCED")
	assert_bool(SpellEffects.silenced(s, int(f["col"]))).is_true()


func test_stinking_cloud_takes_the_turn() -> void:
	var s := _hero("wizard_yalika", 5)
	var f := _fight(s, [{"monster": "ogre", "col": 0}])[0]
	s.character["spell_dc"] = 40
	_cast_at(s, "stinking_cloud", 3, str(f["id"]))
	var hp := int(s.character["hp"])
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, f, lines)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("пропускает ход"))).override_failure_message(" · ".join(lines)).is_true()
	assert_int(int(s.character["hp"])).is_equal(hp)


func test_wind_wall_stops_arrows_and_gust_pushes() -> void:
	var s := _hero("druid_olha", 5)
	var foes := _fight(s, [{"monster": "goblin", "col": 3}])
	var wall := _cast_at(s, "wind_wall", 3, str(foes[0]["id"]))
	(SpellEffects.zones(s)[0] as Dictionary)["col"] = 1
	assert_str(SpellEffects.wall_between(s, 3, 0)).is_not_empty()
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, foes[0], lines)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("Стена ветра"))).override_failure_message(" · ".join(lines) + " | " + " · ".join(wall)).is_true()
	var g := _hero("wizard_yalika", 3)
	var gf := _fight(g, [{"monster": "goblin", "col": 1}])[0]
	g.character["spell_dc"] = 40
	_cast_at(g, "gust_of_wind", 2, str(gf["id"]))
	assert_int(int(gf["col"])).is_equal(2)


func test_faerie_fire_slow_ray_and_curse() -> void:
	var s := _hero("bard_yas", 3)
	var foes := _fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}])
	s.character["spell_dc"] = 40
	_cast_at(s, "faerie_fire", 1, str(foes[0]["id"]))
	assert_bool(foes.all(func(f: Dictionary) -> bool: return f.has("outlined"))).is_true()
	var w := CombatRules.weapon_profile(s.character, data, s.items, "")
	assert_array(CombatRules._attack_mods(s, data, w, foes[0])["adv"]).contains(["Огонь фей"])
	ConditionRules.end_concentration(s, data, "проверка")
	assert_bool(foes.any(func(f: Dictionary) -> bool: return f.has("outlined"))).is_false()
	var z := _hero("wizard_yalika", 5)
	var o := _fight(z, [{"monster": "ogre", "col": 1}])[0]
	z.character["spell_dc"] = 40
	var ac := int(o["ac"])
	_cast_at(z, "slow", 3, str(o["id"]))
	assert_int(int(o["ac"])).is_equal(ac - 2)
	ConditionRules.end_concentration(z, data, "проверка")
	assert_int(int(o["ac"])).is_equal(ac)
	_cast_at(z, "bestow_curse", 3, str(o["id"]))
	assert_bool(o.has("cursed_dis")).is_true()


func test_hypnotic_pattern_is_a_condition_spell() -> void:
	var cs: Dictionary = data["rules"]["combat"]["condition_spells"]
	assert_array(cs["hypnotic_pattern"]["conditions"]).contains(["charmed", "incapacitated"])
	assert_bool(bool(cs["hypnotic_pattern"]["ends_on_damage"])).is_true()
