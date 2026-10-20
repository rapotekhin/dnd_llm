extends GdUnitTestSuite
## Interface and debts (roadmap v0.7.7): what an item is (ItemInfo), the minutes of armour, carrying capacity,
## attacks of opportunity by 5e, grapple and shove, the attitude range from the rules.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.combat_playing = false


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func _fight(s: GameSession, foes: Array) -> void:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT


# --- items --------------------------------------------------------------------------------------------------


func test_a_weapon_and_armour_tell_their_numbers() -> void:
	var s := _session()
	var sword := "\n".join(ItemInfo.lines(s.character, data, s.items, "longsword"))
	assert_str(sword).contains("1к8").contains("1к10").contains("фнт.")
	var mail := "\n".join(ItemInfo.lines(s.character, data, s.items, "chain_mail"))
	assert_str(mail).contains("КД 16").contains("Сила 13").contains("Скрытности")
	var plus := "\n".join(ItemInfo.lines(s.character, data, s.items, "longsword_plus_1"))
	assert_str(plus).contains("+1")
	for id: String in ["longsword", "chain_mail", "shield", "longbow", "healing_potion", "backpack", "cloak_of_protection", "thieves_tools"]:
		assert_str("\n".join(ItemInfo.lines(s.character, data, s.items, id))).not_contains("ITEM_").not_contains("RARITY_")


func test_a_potion_says_what_it_heals_and_gear_has_its_description() -> void:
	var s := _session()
	assert_str("\n".join(ItemInfo.lines(s.character, data, s.items, "healing_potion"))).contains("2к4+2")
	assert_str("\n".join(ItemInfo.lines(s.character, data, s.items, "thieves_tools"))).contains("замков")


func test_not_trained_with_it_and_how_it_compares() -> void:
	var wiz := _session("wizard_yalika")
	assert_str(ItemInfo.proficiency_line(wiz.character, data["items"]["catalog"]["chain_mail"], "chain_mail")).is_not_empty()
	var s := _session()
	s.character["equipped"]["armor"] = ""
	CharacterRules.refresh(s.character, data)
	var cmp := ItemInfo.compare(s.character, data, s.items, "chain_mail")
	assert_str(cmp).contains("→ %d" % (16 + (2 if not str(s.character["equipped"].get("shield", "")).is_empty() else 0) + _defense(s)))
	assert_str(ItemInfo.compare(s.character, data, s.items, "greatsword")).contains("Атака").contains("2к6")
	assert_str(ItemInfo.compare(s.character, data, s.items, str(s.character["equipped"]["main_hand"]))).is_empty()  # the one in hand


func _defense(s: GameSession) -> int:
	for f: Variant in s.character.get("features", []):
		if str(f).ends_with("fighting_style_defense"):
			return 1
	return 0


# --- gear takes time ----------------------------------------------------------------------------------------


func test_armour_takes_minutes_by_its_weight() -> void:
	assert_int(CharacterRules.gear_minutes(data, {}, {"armor": ""}, {"armor": "chain_mail"})).is_equal(10)
	assert_int(CharacterRules.gear_minutes(data, {}, {"armor": "chain_mail"}, {"armor": ""})).is_equal(5)
	assert_int(CharacterRules.gear_minutes(data, {}, {"armor": "chain_mail"}, {"armor": "leather_armor"})).is_equal(5 + 1)
	assert_int(CharacterRules.gear_minutes(data, {}, {"main_hand": ""}, {"main_hand": "longsword"})).is_equal(0)


func test_undressing_by_words_takes_time_and_armour_cannot_change_in_a_fight() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var minute := s.minute
	var r := engine.validate(s, data, "t1", {"kind": "equip", "slot": "all"})
	assert_bool(bool(r["accepted"])).is_true()
	engine.apply(s, "t1", [str(r["effect_id"])])
	assert_str(str(s.character["equipped"]["armor"])).is_empty()
	assert_int(s.minute - minute).is_equal(5)  # chain mail off
	var f := _session()
	_fight(f, [{"monster": "goblin", "col": 0}])
	var refused := engine.validate(f, data, "t2", {"kind": "equip", "slot": "shield", "item_id": "shield"})
	assert_bool(bool(refused["accepted"])).is_false()


# --- carrying -----------------------------------------------------------------------------------------------


func test_every_ready_made_hero_carries_their_kit() -> void:
	for p: Dictionary in data["presets"]:
		var s := _session(str(p["id"]))
		assert_bool(CharacterRules.overloaded(s.character, data, s.items)).override_failure_message(str(p["id"])).is_false()


func test_too_much_weight_stops_the_hero() -> void:
	var s := _session("wizard_yalika")
	assert_int(CharacterRules.capacity(s.character, data)).is_equal(CharacterRules.ability(s.character, "str") * 15)
	s.character["inventory"]["chain_mail"] = 4
	assert_bool(CharacterRules.overloaded(s.character, data, s.items)).is_true()


# --- attacks of opportunity, grapple, shove ----------------------------------------------------------------


func test_a_foe_strikes_once_a_round_and_only_when_it_can() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_bool(CombatRules.can_react(s, data, f)).is_true()
	f["reacted"] = true
	assert_bool(CombatRules.can_react(s, data, f)).is_false()
	f["reacted"] = false
	for cond: String in ["incapacitated", "charmed", "blinded", "paralyzed"]:
		(f["conditions"] as Array).append(cond)
		assert_bool(CombatRules.can_react(s, data, f)).override_failure_message(cond).is_false()
		(f["conditions"] as Array).erase(cond)
	(f["conditions"] as Array).append("prone")
	assert_bool(CombatRules.can_react(s, data, f)).is_true()  # a prone foe still strikes
	(f["conditions"] as Array).erase("prone")
	s.character["concentration"] = "invisibility"
	assert_bool(CombatRules.can_react(s, data, f)).is_false()  # it does not see the hero


func test_leaving_spends_the_reaction() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	var lines := CombatRules.player_move(s, data, 1)
	assert_str(" ".join(lines)).contains("вдогонку")
	assert_bool(bool(CombatRules.fighter(s, CombatRules.enemies(s)[0]).get("reacted", false))).is_true()


func test_grapple_holds_until_the_hero_walks_off_and_shove_knocks_down() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	var id: String = CombatRules.enemies(s)[0]
	var f := CombatRules.fighter(s, id)
	(f["conditions"] as Array).append("incapacitated")  # it does not resist: the contest is won
	assert_str(CombatRules.can_grapple(s, data, id)).is_empty()
	CombatRules.grapple(s, data, id, false)
	assert_array(f["conditions"]).contains(["grappled"])
	(f["conditions"] as Array).erase("incapacitated")
	f["reacted"] = true
	CombatRules.player_move(s, data, 1)
	assert_array(f["conditions"]).not_contains(["grappled"])
	var t := _session()
	_fight(t, [{"monster": "goblin", "col": 0}])
	var g := CombatRules.fighter(t, CombatRules.enemies(t)[0])
	(g["conditions"] as Array).append("stunned")
	CombatRules.grapple(t, data, str(g["id"]), true)
	assert_array(g["conditions"]).contains(["prone"])


func test_a_foe_two_sizes_larger_cannot_be_grappled() -> void:
	var s := _session()
	_fight(s, [{"monster": "ogre", "col": 0}])
	assert_str(CombatRules.can_grapple(s, data, CombatRules.enemies(s)[0])).is_empty()  # large: one size up
	var halfling := _session("rogue_damir")
	if CombatRules.hero_size(halfling, data) == "small":
		_fight(halfling, [{"monster": "ogre", "col": 0}])
		assert_str(CombatRules.can_grapple(halfling, data, CombatRules.enemies(halfling)[0])).is_equal("COMBAT_TOO_BIG")


# --- attitude range -----------------------------------------------------------------------------------------


func test_attitude_stays_in_the_rules_range() -> void:
	var s := _session()
	s.shift_attitude("npc_innkeeper", 10, data)
	assert_int(s.attitude("npc_innkeeper")).is_equal(int(data["rules"]["attitude_range"][1]))
	s.shift_attitude("npc_innkeeper", -20, data)
	assert_int(s.attitude("npc_innkeeper")).is_equal(int(data["rules"]["attitude_range"][0]))


# --- v0.7.7 fixes: the opening strike, everything can be pinned -------------------------------------------


func test_a_pinned_spell_that_starts_the_fight_lands_first_on_the_caught_npc() -> void:
	var s := _session("wizard_yalika")
	GameState.session = s
	(s.character["slots_used"] as Array)[0] = 1  # the slot spent with the words
	var foes := [{"monster": "acolyte", "name": "Сестра Илва", "npc_id": "npc_priestess", "col": 0}]
	var lines := CombatRules.start(s, data, foes, {"opening": {"npc_id": "npc_priestess"}})
	s.mode = GameSession.MODE_COMBAT
	assert_str(CombatRules.current(s)).is_equal(CombatRules.PLAYER)
	var id := CombatRules.fighter_of_npc(s, "npc_priestess")
	var f := CombatRules.fighter(s, id)
	assert_bool(bool(f.get("surprised", false))).is_true()
	assert_str(" ".join(lines)).contains("без предупреждения")
	var hp := int(f["hp"])
	var strike := GameState._opening_strike({"spell": "magic_missile", "slot": 1, "npc_id": "npc_priestess"})
	assert_str(" ".join(strike)).contains("Волшебная стрела")
	assert_int(int(f["hp"])).is_less(hp)
	assert_int(int((s.character["slots_used"] as Array)[0])).is_equal(1)  # spent once, not twice


func test_features_and_any_item_can_be_pinned() -> void:
	var s := _session()
	GameState.session = s
	var kinds := {}
	for ch: Dictionary in GameState.attach_choices():
		kinds[str(ch["kind"])] = int(kinds.get(str(ch["kind"]), 0)) + 1
	assert_bool(kinds.has("feature")).is_true()  # Second Wind
	assert_bool(kinds.has("item_note")).is_true()  # the rope, the bedroll…
	var spent := GameState._spend({"kind": "item_note", "id": "chain_mail"})
	assert_str(" ".join(spent["lines"])).contains("Кольчуга")
	assert_str(str(spent["facts"])).contains("chain_mail")
