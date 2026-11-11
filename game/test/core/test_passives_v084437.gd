extends GdUnitTestSuite
## v0.8.4.43.7: the passives as in BG3 (ToggleRules) — what a character keeps on or off, read on the one road of a blow
## for anybody — and the choice of each reaction kept on the character (FeatureRules.policy with an id), the hero's,
## a companion's or a foe's alike.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(cls: String, level: int, features: Array = []) -> GameSession:
	var s := ChecklistProbe.session(data)
	var c := s.character
	c["class"] = cls
	c["level"] = level
	(c["features"] as Array).append_array(features)
	CharacterRules.refresh(c, data, s.items)
	return s


static func _ids(rows: Array) -> Array:
	return rows.map(func(r: Dictionary) -> String: return str(r["id"]))


func test_anybody_may_spare_a_foe_and_a_barbarian_is_reckless() -> void:
	var s := _hero("fighter", 1)
	assert_array(_ids(ToggleRules.of(s, data, Sheet.HERO))).contains_exactly(["nonlethal"])
	var b := _hero("barbarian", 2, ["reckless_attack"])
	assert_array(_ids(ToggleRules.of(b, data, Sheet.HERO))).contains_exactly(["nonlethal", "reckless"])
	assert_str(ToggleRules.put(s, data, Sheet.HERO, "reckless", true)).is_equal("TOGGLE_NOT_YOURS")


func test_a_toggle_is_kept_on_the_character_for_life() -> void:
	var s := _hero("fighter", 1)
	assert_bool(ToggleRules.on(s, data, Sheet.HERO, "nonlethal")).is_false()
	assert_str(ToggleRules.put(s, data, Sheet.HERO, "nonlethal", true)).is_empty()
	assert_bool(bool(s.character["toggles"]["nonlethal"])).is_true()
	assert_bool(ToggleRules.on(s, data, Sheet.HERO, "nonlethal")).is_true()
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	var mate := Sheet.who(s, data, "npc_mercenary")
	assert_str(ToggleRules.put(s, data, mate, "nonlethal", true)).is_empty()
	assert_bool(bool(Being.view(s, "npc_mercenary")["toggles"]["nonlethal"])).is_true()  # its record, not a fighter
	assert_bool(ToggleRules.on(s, data, Sheet.who(s, data, "npc_mercenary"), "nonlethal")).is_true()


func test_reckless_goes_first_on_a_strength_blow_only() -> void:
	var s := _hero("barbarian", 2, ["reckless_attack"])
	ChecklistProbe.fight(s, data, "goblin", true)
	var f := CombatRules.player(s)
	ToggleRules.put(s, data, Sheet.HERO, "reckless", true)
	var lines: Array[String] = []
	var shot := ToggleRules.before_blow(s, data, f, {"melee": false, "str_based": false}, lines)
	assert_bool(bool(f.get("reckless", false))).is_false()  # a bow is never reckless
	assert_dict(shot.get("opts", {})).is_empty()
	ToggleRules.before_blow(s, data, f, {"melee": true, "str_based": true}, lines)
	assert_bool(bool(f.get("reckless", false))).is_true()
	assert_str(" ".join(lines)).contains("безрассудно")
	lines.clear()
	ToggleRules.before_blow(s, data, f, {"melee": true, "str_based": true}, lines)
	assert_array(lines).is_empty()  # once a turn: the feature's own rule


func test_a_monk_stuns_on_every_close_hit_while_the_toggle_is_on() -> void:
	var s := _hero("monk", 5, ["stunning_strike"])
	ChecklistProbe.fight(s, data, "goblin", true)
	var f := CombatRules.player(s)
	var lines: Array[String] = []
	assert_bool(bool(ToggleRules.before_blow(s, data, f, {"melee": true}, lines).get("opts", {}).get("stunning", false))).is_false()
	ToggleRules.put(s, data, Sheet.HERO, "stunning", true)
	assert_bool(bool(ToggleRules.before_blow(s, data, f, {"melee": true}, lines)["opts"]["stunning"])).is_true()


func test_not_to_kill_is_the_strikers_own_and_fixed_in_a_bout_to_surrender() -> void:
	var s := _hero("fighter", 1)
	ChecklistProbe.fight(s, data, "goblin", true)
	var f := CombatRules.player(s)
	var lines: Array[String] = []
	ToggleRules.put(s, data, Sheet.HERO, "nonlethal", true)
	assert_bool(bool(ToggleRules.before_blow(s, data, f, {"melee": true}, lines)["opts"]["spare"])).is_true()
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	s.combat["spare_blow"] = true
	s.combat["melee_strike"] = true
	Harm.take(s, data, foe, 999, lines, "", false, false)  # not the hero's blow: a companion's spares as well
	assert_str(str(foe["status"])).is_equal("unconscious")
	ToggleRules.put(s, data, Sheet.HERO, "nonlethal", false)
	s.combat["arena"] = {"rule": "yield"}
	assert_bool(ArenaRules.yield_bout(s)).is_true()
	assert_str(ToggleRules.why(s, data, Sheet.HERO, "nonlethal")).is_equal("COMBAT_NONLETHAL_ARENA")
	assert_bool(ToggleRules.on(s, data, Sheet.HERO, "nonlethal")).is_true()  # on and fixed while the bout goes


func test_each_reaction_has_its_own_choice_over_the_common_one() -> void:
	var s := _hero("fighter", 1)
	s.settings["reactions"] = "ask"
	assert_str(FeatureRules.policy(s, Sheet.HERO, "opportunity")).is_equal("ask")
	assert_str(FeatureRules.choose(s, Sheet.HERO, "opportunity", "never")).is_empty()
	assert_str(FeatureRules.policy(s, Sheet.HERO, "opportunity")).is_equal("never")
	assert_str(FeatureRules.policy(s, Sheet.HERO, "shield")).is_equal("ask")  # the others stay as the settings say
	assert_str(FeatureRules.policy(s, Sheet.HERO, "spell_shield")).is_equal(FeatureRules.policy(s, Sheet.HERO, "shield"))
	assert_str(str(s.character["reacts"]["opportunity"])).is_equal("never")


func test_a_reaction_set_to_never_does_not_fire() -> void:
	var s := _hero("fighter", 1)
	ChecklistProbe.fight(s, data, "goblin", true)
	var me := CombatRules.player(s)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	TestUtils.beside(s, foe)
	assert_bool(CombatRules.can_react(s, data, me, foe)).is_true()
	FeatureRules.choose(s, Sheet.HERO, "opportunity", "never")
	assert_bool(CombatRules.can_react(s, data, me, foe)).is_false()  # the goblin walks off unharmed


func test_a_foe_or_a_companion_is_never_asked_but_never_holds() -> void:
	var s := _hero("fighter", 1)
	ChecklistProbe.fight(s, data, "bandit_captain", true)
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var hit := {"foe": CombatRules.PLAYER, "total": int(f["ac"]), "melee": true}
	var lines: Array[String] = []
	assert_str(FeatureRules.choose_why(f, "ask")).is_equal("REACTIONS_BAD_CHOICE")
	assert_str(FeatureRules.policy(s, f, "parry")).is_equal("always")
	FeatureRules.choose(s, f, "parry", "never")
	assert_str(FeatureRules.policy(s, f, "parry")).is_equal("never")
	assert_bool(Acts.react(s, data, f, "hit", hit, lines)).is_false()
	FeatureRules.choose(s, f, "parry", "always")
	assert_bool(Acts.react(s, data, f, "hit", hit, lines)).is_true()


func test_the_book_lists_what_the_character_answers_with() -> void:
	var s := _hero("wizard", 3)
	var ids := _ids(FeatureRules.reaction_list(s, data, Sheet.HERO))
	assert_array(ids).contains(["opportunity"])
	var monk := _hero("monk", 4, ["deflect_missiles", "slow_fall"])
	assert_array(_ids(FeatureRules.reaction_list(monk, data, Sheet.HERO))).contains(["opportunity", "deflect_missiles", "slow_fall"])
	ChecklistProbe.fight(s, data, "bandit_captain", true)
	var captain := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_array(_ids(FeatureRules.reaction_list(s, data, captain))).contains(["parry"])
