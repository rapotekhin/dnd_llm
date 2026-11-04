extends GdUnitTestSuite
## Out of the game and the master's words (roadmap v0.8.4.28.4): `rules.off` takes items, monsters and class features with
## no mechanic out of the base at load (Catalog.cut) — the files keep them; the spells of `rules.spellcasting.by_master`
## stay, are never a turn's act for anybody and say so in their text.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_what_is_off_is_not_in_the_game_but_stays_in_the_files() -> void:
	var off: Dictionary = data["rules"]["off"]
	for id: String in off["monsters"]:
		assert_bool(data["monsters"].has(id)).override_failure_message(id).is_false()
		assert_bool(TestUtils.uncut("monsters", id).is_empty()).override_failure_message(id).is_false()
	for id: String in off["items"]:
		assert_bool(data["items"]["catalog"].has(id)).is_false()
	for keep: String in ["mule", "mage", "archmage", "wolf"]:
		assert_bool(data["monsters"].has(keep)).is_true()


func test_a_warlock_cannot_pick_an_invocation_that_is_off() -> void:
	var off: Array = data["rules"]["off"]["features"]
	for id: String in off:
		assert_bool(data["classes"]["features"].has(id)).is_false()
	for f: Dictionary in data["classes"]["features"].values():
		for id: Variant in f.get("options", {}).get("from", []):
			assert_bool(off.has(id)).override_failure_message(str(id)).is_false()


func test_a_spell_of_the_master_is_no_act_of_a_fight_for_anybody() -> void:
	var s := ChecklistProbe.session(data)
	var acolyte := ChecklistProbe.fight(s, data, "acolyte")
	var p := CombatRules.player(s)
	var cast: Act = Acts.one("cast")
	assert_str(cast.target_why(s, data, p, str(p["id"]), "thaumaturgy")).is_equal("COMBAT_SPELL_BY_MASTER")
	assert_bool(MonsterRules.castable(data, acolyte).any(func(o: Dictionary) -> bool: return str(o["id"]) == "thaumaturgy")).is_true()
	var spells: Array = cast.offers(s, data, acolyte, [p]).map(func(o: Dictionary) -> String: return str(o.get("how", {}).get("spell", "")))
	assert_array(spells).not_contains(["thaumaturgy"])
	assert_str(cast.target_why(s, data, p, str(acolyte["id"]), "fire_bolt")).is_not_equal("COMBAT_SPELL_BY_MASTER")


func test_the_text_of_a_spell_of_the_master_says_so() -> void:
	var line := TranslationServer.translate("DETAILS_BY_MASTER")
	for id: String in data["rules"]["spellcasting"]["by_master"]:
		assert_bool(data["spells"].has(id)).override_failure_message(id).is_true()
		assert_str(DetailsPanel.spell_text(data, id)).contains(line)
	assert_str(DetailsPanel.spell_text(data, "fire_bolt")).not_contains(line)


func test_a_mule_carries_a_size_larger_by_its_own_trait() -> void:
	var cr := {"monster": "mule"}
	var row: Dictionary = PropertyRules.animal_cfg(data, "mule")
	assert_bool(row.has("burden")).is_false()
	assert_float(MountRules.capacity(data, cr)).is_equal(420.0)  # Str 14 × 15 × 2 (large for a medium one)
