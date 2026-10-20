extends GdUnitTestSuite
## 5e rules to the end (roadmap v0.6.0): feature uses, casting with slots and concentration, conditions in checks,
## short rest, consumables, 0 HP outside combat, prepared spells of the day, trader goods only through trade.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""


func _preset(id: String) -> Dictionary:
	for p: Dictionary in data["presets"]:
		if p["id"] == id:
			return CharacterBuilder.build_preset(p, data)
	return {}


func _session(preset_id: String) -> GameSession:
	var s := TestUtils.new_session()
	s.character = GameSession.normalized_character(_preset(preset_id))
	CharacterRules.refresh(s.character, data)
	return s


func test_fighter_feature_uses_and_their_rests() -> void:
	var s := _session("fighter_aira")
	var c := s.character
	assert_array(FeatureUses.owned(c, data)).contains(["second_wind"])
	c["hp"] = 2
	var lines := FeatureUses.use(c, data, "second_wind", 1, s.rng)
	assert_int(c["hp"]).is_greater(2)
	assert_str(" ".join(lines)).contains("осталось 0")
	assert_str(FeatureUses.can_use(c, data, "second_wind", 1)).contains("короткого")
	assert_str(FeatureUses.resolve(c, data, "Второе дыхание")).is_equal("second_wind")
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_int(FeatureUses.left(c, data, "second_wind")).is_equal(1)


func test_bard_inspiration_by_charisma_until_a_long_rest() -> void:
	var c := _preset("bard_yas")
	var n := maxi(1, CharacterRules.mod(int(c["abilities"]["cha"])))
	assert_int(FeatureUses.max_uses(c, data, "bardic_inspiration")).is_equal(n)
	assert_str(FeatureUses.recharge(c, data, "bardic_inspiration")).is_equal("long")


func test_casting_spends_the_lowest_slot_and_keeps_concentration() -> void:
	var c := _preset("wizard_yalika")
	var cantrip := str(c["spells"]["cantrips"][0])
	assert_int(SpellRules.check(c, data, cantrip, 0)["slot"]).is_equal(0)
	var spell := str(c["spells"]["prepared"][0])
	var chk := SpellRules.check(c, data, spell, 0)
	assert_int(chk["slot"]).is_equal(1)
	SpellRules.cast(c, data, chk["spell_id"], 1)
	assert_int(SpellRules.slots_left(c, 1)).is_equal(1)
	SpellRules.cast(c, data, chk["spell_id"], 1)
	assert_str(str(SpellRules.check(c, data, spell, 0).get("reason", ""))).contains("не осталось ячеек")
	var unknown := "fireball"
	assert_str(str(SpellRules.check(c, data, unknown, 0).get("reason", ""))).contains("не подготовлено")
	c["spells"]["prepared"].append("detect_magic")  # a concentration spell
	c["slots_used"] = [0, 0, 0, 0, 0]
	SpellRules.cast(c, data, "detect_magic", 1)
	assert_str(c["concentration"]).is_equal("detect_magic")


func test_conditions_give_disadvantage_or_auto_fail_and_end_with_rests() -> void:
	var s := _session("fighter_aira")
	var c := s.character
	ConditionRules.add(c, "poisoned", "short_rest")
	var mods := ConditionRules.check_mods(c, data, {"skill": "perception"})
	assert_array(mods["disadvantage"]).contains(["poisoned"])
	var rng := RandomNumberGenerator.new()
	for i in 50:
		rng.seed = i
		var r := CheckEngine.roll(data["rules"], rng, {"skill": "perception", "dc_tier": "easy", "disadvantage_reason": "отравлен"}, 0, "c")
		assert_int(r["nat"]).is_equal(mini(r["rolls"][0], r["rolls"][1]))
	var both := CheckEngine.roll(data["rules"], rng, {"skill": "perception", "dc_tier": "easy", "advantage_reason": "свет", "disadvantage_reason": "отравлен"}, 0, "c")
	assert_array(both["rolls"]).has_size(1)
	ConditionRules.add(c, "paralyzed", "long_rest")
	assert_array(ConditionRules.check_mods(c, data, {"save": "dex"})["auto_fail"]).contains(["paralyzed"])
	var fail := CheckEngine.roll(data["rules"], rng, {"save": "dex", "dc_tier": "very_easy", "auto_fail_reason": "парализован"}, 30, "c")
	assert_bool(fail["success"]).is_false()
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_bool(ConditionRules.has(c, "poisoned")).is_false()
	assert_bool(ConditionRules.has(c, "paralyzed")).is_true()


func test_short_rest_spends_hit_dice_twice_a_day() -> void:
	var s := _session("fighter_aira")
	var c := s.character
	c["hp"] = 1
	assert_str(ExplorationRules.can_short_rest(s, data)).is_empty()
	ExplorationRules.short_rest(s, data, 5, s.rng)
	assert_int(c["hit_dice_used"]).is_equal(1)  # level 1 has one die
	assert_int(c["hp"]).is_greater_equal(1)
	ExplorationRules.short_rest(s, data, 1, s.rng)
	assert_int(c["hit_dice_used"]).is_equal(1)
	assert_str(ExplorationRules.can_short_rest(s, data)).is_equal("REST_SHORT_LIMIT")
	s.room_id = "brod-temple"
	ExplorationRules.long_rest(s, data)
	assert_int(s.short_rests).is_equal(0)


func test_warlock_slots_come_back_on_a_short_rest() -> void:
	var s := _session("warlock_fiber")
	s.character["slots_used"] = [1, 0, 0, 0, 0]
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_array(s.character["slots_used"]).is_equal([0, 0, 0, 0, 0])


func test_effects_cast_condition_use_feature_and_item() -> void:
	var s := _session("wizard_yalika")
	var fx := EffectEngine.new()
	var spell := str(s.character["spells"]["prepared"][0])
	var r1 := fx.validate(s, data, "t-1", {"kind": "cast", "spell": spell})
	var r2 := fx.validate(s, data, "t-1", {"kind": "cast", "spell": spell})
	assert_bool(r1["accepted"] and r2["accepted"]).is_true()
	var r3 := fx.validate(s, data, "t-1", {"kind": "cast", "spell": spell})
	assert_bool(r3["accepted"]).is_false()  # two slots of circle 1, both reserved
	fx.apply(s, "t-1", [r1["effect_id"]])
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(1)
	fx.player_turns["t-2"] = true  # the hero brought it on (v0.7.8: otherwise a save)
	var cond := fx.validate(s, data, "t-2", {"kind": "condition", "condition": "frightened", "duration": "short_rest", "reason": "страшный сон", "cause": "player"})
	fx.apply(s, "t-2", [cond["effect_id"]])
	assert_bool(ConditionRules.has(s.character, "frightened")).is_true()
	assert_bool(fx.validate(s, data, "t-3", {"kind": "condition", "condition": "drunk"})["accepted"]).is_false()
	s.character["inventory"]["healing_potion"] = 1
	s.character["hp"] = 1
	var use := fx.validate(s, data, "t-4", {"kind": "use_item", "item_id": "healing_potion"})
	assert_bool(fx.validate(s, data, "t-4", {"kind": "use_item", "item_id": "healing_potion"})["accepted"]).is_false()
	fx.apply(s, "t-4", [use["effect_id"]])
	assert_int(s.character["hp"]).is_greater_equal(5)
	assert_bool(s.character["inventory"].has("healing_potion")).is_false()
	assert_bool(fx.validate(s, data, "t-5", {"kind": "use_item", "item_id": "rope"})["accepted"]).is_false()
	assert_bool(fx.validate(s, data, "t-5", {"kind": "use_feature", "feature": "Ярость"})["accepted"]).is_false()
	var ar := fx.validate(s, data, "t-6", {"kind": "use_feature", "feature": "arcane_recovery"})
	assert_bool(ar["accepted"]).is_true()


func test_trader_goods_are_bought_only_in_trade() -> void:
	var s := TestUtils.new_session()
	var fx := EffectEngine.new()
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = TestUtils.INNKEEPER
	assert_str(str(fx.validate(s, data, "t-1", {"kind": "give_item", "item_id": "ale"}).get("reason", ""))).contains("торговл")
	assert_bool(fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": -10})["accepted"]).is_true()  # a tip or a bribe
	s.npc_id = TestUtils.SERVING
	assert_bool(fx.validate(s, data, "t-2", {"kind": "give_item", "item_id": "ale"})["accepted"]).is_true()


func test_zero_hp_outside_combat_is_a_knock_out() -> void:
	var s := TestUtils.new_session()
	GameState.start(s)
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = TestUtils.INNKEEPER
	s.character["hp"] = 0
	assert_str(GameState._apply_result(s, "t-1", {"narration": "удар"})).is_equal("downed")
	assert_int(s.character["hp"]).is_equal(1)
	assert_str(s.mode).is_equal(GameSession.MODE_EXPLORATION)


func test_a_cleric_prepares_spells_once_after_a_long_rest() -> void:
	var c := _preset("cleric_branko")
	assert_str(SpellRules.can_prepare(c, data, 1)).is_equal("PREP_ALREADY_TODAY")
	var p := SpellRules.prepare_pool(c, data)
	var pick: Array = (p["pool"] as Array).slice(0, int(p["count"]))
	assert_str(SpellRules.prepare_error(c, data, 2, pick)).is_empty()
	assert_str(SpellRules.prepare_error(c, data, 2, pick.slice(1))).is_equal("PREP_ERR_COUNT")
	SpellRules.prepare(c, pick, 2)
	assert_array(c["spells"]["prepared"]).is_equal(pick)
	assert_str(SpellRules.can_prepare(c, data, 2)).is_equal("PREP_ALREADY_TODAY")
	assert_str(SpellRules.can_prepare(_preset("fighter_aira"), data, 2)).is_equal("PREP_NOT_PREPARER")


func test_new_fields_survive_a_save() -> void:
	var s := _session("fighter_aira")
	FeatureUses.use(s.character, data, "second_wind", 1, s.rng)
	ConditionRules.add(s.character, "poisoned", "short_rest")
	s.short_rests = 1
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_dict(back.character["resources_used"]).is_equal({"second_wind": 1})
	assert_array(back.character["conditions"]).is_equal(["poisoned"])
	assert_dict(back.character["effects"][0]["ends"]).is_equal({"rest": "short"})
	assert_int(back.short_rests).is_equal(1)


func test_a_tiefling_casts_thaumaturgy_from_infernal_legacy() -> void:
	var c := _preset("warlock_fiber")
	if not (c["traits"] as Array).has("infernal_legacy"):
		c["traits"].append("infernal_legacy")
		CharacterRules.refresh(c, data)
	assert_array(c["spells"]["cantrips"]).contains(["thaumaturgy"])
	assert_int(SpellRules.check(c, data, "Чудотворство", 0).get("slot", -1)).is_equal(0)
