extends GdUnitTestSuite
## Diseases (v0.7.23.1): caught on a failed save, hidden while incubating, shown for days with symptoms, passing
## by the clock; cured by herbs (only some), magic, the healers' services, Lay on Hands; foul water, a sick NPC,
## a monster's bite and the master's effect as sources.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	NeedRules.state(s, data)
	return s


## Hours pass in half days, the hero kept fed and rested: only the disease acts.
func _later(s: GameSession, hours: int) -> Array[String]:
	var lines: Array[String] = []
	while hours > 0:
		var step := mini(hours, 12)
		lines.append_array(TimeRules.advance(s, data, step * 60))
		s.rested_at = TimeRules.abs_minute(s)
		hours -= step
	return lines


func test_a_disease_hides_then_shows_then_passes() -> void:
	var s := _session()
	s.settings["needs"] = false  # six days: no hunger here
	var max_hp := int(s.character["max_hp"])
	DiseaseRules.contract(s, data, "rot_fever")
	assert_bool(DiseaseRules.sick(s.character, "rot_fever")).is_true()
	assert_array(DiseaseRules.active(s.character)).is_empty()  # incubating: no chip yet
	var lines := _later(s, 25)
	assert_str(" ".join(lines)).contains("Гнилая лихорадка")
	assert_array(DiseaseRules.active(s.character)).contains(["rot_fever"])
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_true()
	assert_int(int(s.character["max_hp"])).is_equal(max_hp - 4)
	var chip := ConditionRules.shown(s, data).filter(func(e: Dictionary) -> bool: return str(e["name"]).begins_with("Болезнь"))
	assert_str(str(chip[0]["text"])).contains("Жар")
	_later(s, 5 * 24 + 1)
	assert_array(DiseaseRules.active(s.character)).is_empty()
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_false()
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(int(s.character["max_hp"])).is_equal(max_hp)


func test_a_failed_save_infects_and_a_good_one_does_not() -> void:
	var s := _session()
	var lines := DiseaseRules.expose(s, data, "sewer_plague", 40, "Гнилая вода")
	assert_str(" ".join(lines)).contains("провал")
	assert_str(" ".join(lines)).not_contains("Чума")  # the save is told, the disease is not
	assert_bool(DiseaseRules.sick(s.character, "sewer_plague")).is_true()
	assert_array(DiseaseRules.expose(s, data, "sewer_plague", 40, "Гнилая вода")).is_empty()  # already caught


func test_weak_saves_and_thirst_of_the_plague() -> void:
	var s := _session()
	DiseaseRules.contract(s, data, "sewer_plague")
	s.day += 2  # the clock jumps past the incubation, then the water is full
	NeedRules.set_value(s, data, "water", 100.0)
	DiseaseRules.tick(s, data)
	assert_array(ConditionRules.check_mods(s.character, data, {"save": "con"})["disadvantage"]).contains(["disease"])
	assert_array(ConditionRules.check_mods(s.character, data, {"save": "dex"})["disadvantage"]).not_contains(["disease"])
	assert_float(NeedRules.value(s, data, "water")).is_equal_approx(60.0, 0.5)


func test_herbs_cure_only_their_diseases_magic_cures_any() -> void:
	var s := _session()
	DiseaseRules.contract(s, data, "rot_fever")
	DiseaseRules.contract(s, data, "sewer_plague")
	_later(s, 37)
	assert_array(DiseaseRules.curable(s, data, "herbs")).is_equal(["sewer_plague"])
	var lines := DiseaseRules.cure(s, data, "herbs")
	assert_str(" ".join(lines)).contains("травы не берут: Гнилая лихорадка")
	assert_array(DiseaseRules.active(s.character)).is_equal(["rot_fever"])
	ConditionRules.cure(s, data, data["rules"]["hero_effects"]["spell_cures"]["lesser_restoration"], {"kind": "spell", "name": "Малое восстановление"})
	assert_array(DiseaseRules.active(s.character)).is_empty()
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_false()


func test_the_remedy_cures_even_before_it_shows() -> void:
	var s := _session()
	DiseaseRules.contract(s, data, "cackle_fever")
	s.character["inventory"]["herbal_remedy"] = 1
	assert_str(ItemRules.can_use(s.character, data, s.items, "herbal_remedy")).is_empty()
	ItemRules.use(s.character, data, s.items, "herbal_remedy", s.rng, s)
	assert_bool(DiseaseRules.sick(s.character, "cackle_fever")).is_false()


func test_the_healers_see_a_disease_and_cure_it() -> void:
	var s := _session()
	assert_array(TradeRules.targets(s, data, "cure_disease")).is_empty()
	DiseaseRules.contract(s, data, "rot_fever")
	assert_array(TradeRules.targets(s, data, "cure_disease")).is_equal(["rot_fever"])
	assert_array(TradeRules.targets(s, data, "herbal_cure")).is_empty()  # magic rot: the herbalist cannot
	s.character["gold_cp"] = 5000
	TradeRules.buy_service(s, data, "npc_priestess", "cure_disease")
	assert_bool(DiseaseRules.sick(s.character, "rot_fever")).is_false()
	assert_int(int(s.character["gold_cp"])).is_equal(3500)


func test_lay_on_hands_spends_five_points_on_a_disease() -> void:
	var s := _session()
	DiseaseRules.contract(s, data, "rot_fever")
	_later(s, 25)
	var lines := FeatureUses.use(s.character, data, "lay_on_hands", 5, s.rng)
	assert_str(" ".join(lines)).contains("болезнь исцелена")
	assert_bool(DiseaseRules.sick(s.character, "rot_fever")).is_false()


func test_foul_water_and_a_filled_skin_risk_the_plague() -> void:
	var s := _session()
	s.room_id = "mine-flooded"
	assert_bool(NeedRules.water_here(s, data)).is_true()
	assert_bool(NeedRules.foul_here(s, data)).is_true()
	s.character["inventory"]["waterskin"] = 1
	s.character["vessels"] = {}
	NeedRules.fill(s, data)
	assert_bool(bool(VesselRules.carried(s.character, data)[0]["foul"])).is_true()
	s.room_id = "brod-square"
	assert_str(NeedRules.can_fill(s, data)).is_empty()  # the foul water is poured out for the clean
	NeedRules.fill(s, data)
	assert_bool(bool(VesselRules.carried(s.character, data)[0]["foul"])).is_false()


func test_a_sick_pilgrim_passes_it_on_once_a_day() -> void:
	var s := _session()
	s.room_id = "brod-herbalist"
	var first := DiseaseRules.contagion(s, data)
	assert_str(" ".join(first)).contains("Зараза от Тодор")
	assert_array(DiseaseRules.contagion(s, data)).is_empty()
	var snap := TurnSnapshot.build(s, data, 1000)
	var pilgrim: Array = (snap["scene"]["npcs"] as Array).filter(func(n: Dictionary) -> bool: return n["npc_id"] == "npc_sick_pilgrim")
	assert_str(str(pilgrim[0]["description"])).contains("Болен: хохочущая лихорадка, заразно")


func test_the_diseased_rat_bites_with_rot_fever() -> void:
	var bite: Dictionary = data["monsters"]["giant_rat_diseased"]["actions"][0]
	assert_str(str(bite["effect"]["disease"])).is_equal("rot_fever")
	assert_bool(bite.has("master_effect")).is_false()
	assert_str(MonsterRules.effect_text(data, bite)).contains("заражает: Гнилая лихорадка")


func test_the_master_infects_with_a_save_and_makes_a_new_disease() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var bad := engine.validate(s, data, "t-1", {"kind": "disease", "disease": "чёрная гниль", "reason": "укус", "save": {"ability": "con", "dc_tier": "easy"}})
	assert_bool(bool(bad["accepted"])).is_false()
	assert_str(str(bad["reason"])).contains("rot_fever")
	var r := engine.validate(s, data, "t-1", {"kind": "disease", "disease": "Болотная трясучка", "reason": "болотная вода",
		"save": {"ability": "con", "dc_tier": "nearly_impossible"}, "days": 2, "incubation_hours": 0, "symptoms": ["poisoned"], "weak_saves": ["dex"]})
	assert_bool(bool(r["accepted"])).is_true()
	assert_str(str(r["summary"])).not_contains("трясучка")
	engine.apply(s, "t-1", [r["effect_id"]])
	assert_array(DiseaseRules.active(s.character)).has_size(1)
	assert_str(str(ConditionRules.shown(s, data)[0]["name"])).contains("Болотная трясучка")


func test_the_diseases_survive_a_save() -> void:
	var s := _session()
	DiseaseRules.contract(s, data, "cackle_fever")
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_str(JSON.stringify(back.character["diseases"])).is_equal(JSON.stringify(s.character["diseases"]))
