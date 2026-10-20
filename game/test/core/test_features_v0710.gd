extends GdUnitTestSuite
## «Правила 5e: особенности классов и черты рас» (roadmap v0.7.10, «как в Baldur's Gate 3»): choices of creation and
## level-up, Extra Attack of every class, the monk's ki, Divine Smite and reactions as prompts, Channel Divinity, Wild
## Shape, Font of Magic and metamagic, Arcane Recovery, Song of Rest, Danger Sense, Reckless Attack, temporary HP,
## the dragonborn's breath, darkness of the pack's rooms.

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


func _fight(s: GameSession, monster: String, col: int = 0) -> Dictionary:
	CombatRules.start(s, data, [{"monster": monster, "col": col}], {})
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


# --- choices ---------------------------------------------------------------------------------------


func test_choices_the_srd_has_only_in_prose() -> void:
	var ranger := _hero("ranger_velena")
	assert_bool(CharacterRules.has_feature(ranger.character, "favored_enemy_undead")).is_true()
	assert_bool(CharacterRules.has_feature(ranger.character, "natural_explorer_forest")).is_true()
	var warlock := _hero("warlock_fiber", 2)
	var invocations := (warlock.character["features"] as Array).filter(func(f: Variant) -> bool: return str(f).begins_with("eldritch_invocation_"))
	assert_int(invocations.size()).is_equal(2)
	assert_int(_hero("warlock_fiber", 5).character["features"].filter(func(f: Variant) -> bool:
		return str(f).begins_with("eldritch_invocation_")).size()).is_equal(3)


func test_every_class_gets_extra_attack_at_level_5() -> void:
	for id: String in ["barbarian_urga", "paladin_gordey", "ranger_velena", "monk_taras", "fighter_aira"]:
		assert_int(CharacterRules.extra_attacks(_hero(id, 5).character, data)).is_equal(1)
	assert_int(CharacterRules.extra_attacks(_hero("wizard_yalika", 5).character, data)).is_equal(0)


# --- warriors --------------------------------------------------------------------------------------


func test_monk_martial_arts_and_ki() -> void:
	var s := _hero("monk_taras", 2)
	var c := s.character
	var bare := CombatRules.unarmed_profile(c, data)
	assert_str(str(bare["dice"])).is_equal("1d4")
	assert_int(int(bare["bonus"])).is_equal(maxi(FeatureRules.ab_mod(c, "str"), FeatureRules.ab_mod(c, "dex")))
	var f := _fight(s, "ogre")
	assert_str(FeatureRules.can_act(s, data, "flurry", str(f["id"]))).is_equal("COMBAT_ATTACK_FIRST")
	CombatRules.player_attack(s, data, str(f["id"]))
	var ki := FeatureUses.left(c, data, "ki")
	assert_str(FeatureRules.can_act(s, data, "flurry", str(f["id"]))).is_empty()
	var lines := FeatureRules.act(s, data, "flurry", str(f["id"]))
	assert_int(FeatureUses.left(c, data, "ki")).is_equal(ki - 1)
	assert_str(", ".join(lines)).contains("шквал")
	assert_str(FeatureRules.can_act(s, data, "patient_defense")).is_equal("COMBAT_NO_BONUS")


func test_reckless_attack_cuts_both_ways() -> void:
	var s := _hero("barbarian_urga", 2)
	var f := _fight(s, "ogre")
	FeatureRules.act(s, data, "reckless")
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"]["main_hand"]))
	assert_array(CombatRules._attack_mods(s, data, w, f)["adv"]).contains(["безрассудная атака"])
	CombatRules._begin_turn(s, data, [] as Array[String])  # the hero's next turn: it is over
	assert_bool(bool(s.combat.get("reckless", false))).is_false()


func test_rage_ends_without_a_blow_and_danger_sense_helps_dex_saves() -> void:
	var s := _hero("barbarian_urga", 2)
	_fight(s, "ogre", 3)
	s.combat["raging"] = true
	var lines: Array[String] = []
	FeatureRules.end_hero_turn(s, data, lines)
	assert_bool(bool(s.combat["raging"])).is_false()
	assert_array(HeroDefense.save_advantages(s.character, data, "dex", "")).is_not_empty()
	assert_array(HeroDefense.save_advantages(s.character, data, "str", "", true)).contains(["ярость"])


func test_improved_critical_of_the_champion() -> void:
	var s := _hero("fighter_aira", 3)
	s.character["subclass"] = "champion"
	(s.character["features"] as Array).append("improved_critical")
	assert_int(FeatureRules.crit_min(s.character)).is_equal(19)


# --- prompts and reactions -------------------------------------------------------------------------


func test_divine_smite_asks_and_spends_the_slot() -> void:
	var s := _hero("paladin_gordey", 2)
	s.settings["reactions"] = "ask"
	var f := _fight(s, "ogre")
	var lines: Array[String] = []
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"]["main_hand"]))
	FeatureRules.after_hit(s, data, w, f, false, {}, lines)
	var p: Dictionary = s.combat["prompt"]
	assert_str(str(p["kind"])).is_equal("smite")
	assert_str(str(p["options"][0]["id"])).is_equal("smite_1")
	var hp := int(f["hp"])
	FeatureRules.answer_prompt(s, data, "smite_1")
	assert_int(int(f["hp"])).is_less(hp)
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(int(s.character["slots_max"][0]) - 1)
	assert_bool(s.combat.has("prompt")).is_false()


func test_a_reaction_stops_the_foes_turn_until_answered() -> void:
	var s := _hero("rogue_damir", 5)
	s.settings["reactions"] = "ask"
	var f := _fight(s, "ogre")
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	s.character["ac"] = 1  # it hits
	var lines: Array[String] = []
	for i in 10:  # a natural 1 misses even AC 1
		CombatRules._enemy_attack(s, data, f, _action("ogre", "Greatclub"), lines)
		if s.combat.has("pending"):
			break
	assert_bool(s.combat.has("pending")).override_failure_message(", ".join(lines)).is_true()
	assert_str(str(s.combat["pending"]["options"][0]["id"])).is_equal("uncanny_dodge")
	var hp := int(s.character["hp"])
	var dmg := int(s.combat["pending"]["dmg"])
	CombatRules.answer_reaction(s, data, "uncanny_dodge")
	assert_int(int(s.character["hp"])).is_equal(maxi(0, hp - dmg / 2))
	assert_bool(s.combat.has("pending")).is_false()


func test_cutting_words_can_turn_a_hit_into_a_miss() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	var f := _fight(s, "goblin")
	var ctx := {"hit": true, "dmg": 5, "total": int(s.character["ac"]), "ac": int(s.character["ac"]), "nat20": false}
	FeatureRules.apply_reaction(s, data, f, "cutting_words", ctx, [] as Array[String])
	assert_bool(bool(ctx["hit"])).is_false()


# --- clerics, paladins, druids ---------------------------------------------------------------------


func test_turn_undead_and_preserve_life() -> void:
	var s := _hero("cleric_branko", 2)
	var f := _fight(s, "zombie", 1)
	f["max_hp"] = 99
	var lines := FeatureRules.act(s, data, "turn_undead")
	assert_str(", ".join(lines)).contains("Зомби")
	s.character["hp"] = 1
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.character["resources_used"] = {}
	FeatureRules.act(s, data, "preserve_life")
	assert_int(int(s.character["hp"])).is_equal(mini(1 + 10, int(s.character["max_hp"]) / 2))


func test_wild_shape_takes_the_beasts_body_and_gives_it_back() -> void:
	var s := _hero("druid_olha", 2)
	_fight(s, "goblin", 2)
	var beasts := FeatureRules.beasts(s.character, data)
	assert_array(beasts).is_not_empty()
	assert_bool(beasts.all(func(m: String) -> bool: return float(data["monsters"][m]["cr"]) <= 0.25 and int(data["monsters"][m].get("fly", 0)) == 0)).is_true()
	FeatureRules.act(s, data, "wild_shape")
	FeatureRules.answer_prompt(s, data, beasts[0])
	var m: Dictionary = data["monsters"][beasts[0]]
	assert_int(int(s.character["ac"])).is_equal(int(m["ac"]))
	var hp := int(s.character["hp"])
	var lines: Array[String] = []
	CombatRules._hurt_player(s, data, int(m["hp"]) + 3, false, lines)
	assert_bool(s.character.has("wild_shape")).is_false()
	assert_int(int(s.character["hp"])).is_equal(hp - 3)


# --- casters --------------------------------------------------------------------------------------


func test_font_of_magic_and_quickened_spell() -> void:
	var s := _hero("sorcerer_zlata", 3)
	var c := s.character
	c["slots_used"] = [1, 0, 0, 0, 0]
	var opts := FeatureRules.font_options(c, data).map(func(o: Dictionary) -> String: return o["id"])
	assert_array(opts).contains(["slot_1"])
	FeatureRules.font_convert(s, data, "slot_1")
	assert_int(int(c["slots_used"][0])).is_equal(0)
	(c["features"] as Array).append("metamagic_quickened_spell")
	c["resources_used"] = {}  # the points spent on the slot come back for the test
	var f := _fight(s, "goblin", 1)
	s.combat["metamagic"] = "quickened_spell"
	CombatRules.economy(s)["action"] = 0
	assert_str(CombatRules.can_cast(s, data, "fire_bolt", 0, str(f["id"]))).is_empty()  # a bonus action now


func test_arcane_recovery_brings_slots_back() -> void:
	var s := _hero("wizard_yalika", 3)
	var c := s.character
	c["slots_used"] = [2, 1, 0, 0, 0]
	FeatureUses.use(c, data, "arcane_recovery", 1, s.rng)
	assert_array(c["slots_used"]).is_equal([2, 0, 0, 0, 0])  # level 3: circles worth 2 back, the highest first (one 2nd)


func test_inspiration_is_added_to_a_failed_save() -> void:
	var s := _hero("bard_yas")
	FeatureUses.use(s.character, data, "bardic_inspiration", 1, s.rng)
	assert_int(FeatureRules.inspiration_die(s.character)).is_equal(6)
	s.character["saves"]["wis"] = -30
	HeroDefense.save(s, data, "wis", 40)
	assert_int(FeatureRules.inspiration_die(s.character)).is_equal(0)  # spent on the failure


func test_song_of_rest() -> void:
	var s := _hero("bard_yas", 2)
	s.character["hp"] = 1
	var lines := ExplorationRules.short_rest(s, data, 1, s.rng)
	assert_str(", ".join(lines)).contains("Песнь отдыха")


func test_dark_ones_blessing_and_temporary_hp() -> void:
	var s := _hero("warlock_fiber")
	var f := _fight(s, "goblin")
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, f, 999, lines)
	assert_int(int(s.character.get("temp_hp", 0))).is_greater(0)
	var thp := int(s.character["temp_hp"])
	var hp := int(s.character["hp"])
	CombatRules._hurt_player(s, data, thp + 1, false, lines)
	assert_int(int(s.character["hp"])).is_equal(hp - 1)


# --- races ----------------------------------------------------------------------------------------


func test_breath_weapon_once_a_rest() -> void:
	var s := _hero("paladin_gordey")
	var f := _fight(s, "ogre")
	assert_str(FeatureRules.can_act(s, data, "breath", str(f["id"]))).is_empty()
	var hp := int(f["hp"])
	FeatureRules.act(s, data, "breath", str(f["id"]))
	assert_int(int(f["hp"])).is_less_equal(hp)
	CombatRules._begin_turn(s, data, [] as Array[String])
	assert_str(FeatureRules.can_act(s, data, "breath", str(f["id"]))).is_equal("COMBAT_NO_CHARGE")
	s.combat = {}
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_bool(bool(s.character["breath_used"])).is_false()


func test_dark_rooms_of_the_pack() -> void:
	var human := _hero("fighter_aira")
	human.room_id = "mine-gallery"
	human.character["inventory"].erase("torch")
	human.character["inventory"].erase("lantern")
	assert_bool(TimeRules.dark(human, data)).is_true()
	human.character["inventory"]["torch"] = 1
	assert_bool(TimeRules.dark(human, data)).is_false()
	var dwarf := _hero("cleric_branko")
	dwarf.room_id = "mine-gallery"
	assert_bool(TimeRules.dark(dwarf, data)).is_false()
