extends GdUnitTestSuite
## CharacterBuilder: steps per race / class, validation of each step, the final character, random characters.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_catalog_covers_the_srd() -> void:
	assert_int(data["races"]["races"].size()).is_equal(9)
	assert_int(data["classes"]["classes"].size()).is_equal(12)
	assert_int(data["backgrounds"].size()).is_greater_equal(6)
	for id: String in data["classes"]["classes"]:
		var k: Dictionary = data["classes"]["classes"][id]
		assert_str(str(k["name"])).override_failure_message(id).is_not_equal(str(k["name_en"]))  # translated
		assert_int(k["levels"].size()).is_equal(5)
	for id: String in data["spells"]:
		assert_int(int(data["spells"][id]["level"])).is_less_equal(3)


func test_every_referenced_item_and_feature_exists() -> void:
	var items: Dictionary = data["items"]["catalog"]
	var feats: Dictionary = data["classes"]["features"]
	for id: String in data["classes"]["classes"]:
		var k: Dictionary = data["classes"]["classes"][id]
		for lv: String in k["levels"]:
			for f: Variant in k["levels"][lv]["features"]:
				assert_bool(feats.has(f)).override_failure_message("%s: feature %s" % [id, f]).is_true()
		for set: Dictionary in k["equipment_choices"]:
			for alt: Dictionary in set["alternatives"]:
				for e: Dictionary in alt["items"]:
					assert_bool(items.has(e["id"])).override_failure_message("%s: item %s" % [id, e["id"]]).is_true()
				for p: Dictionary in alt["picks"]:
					assert_array(CharacterBuilder.pick_options(data, p)).override_failure_message("%s: pick %s" % [id, p]).is_not_empty()
	for id: String in data["backgrounds"]:
		for e: Dictionary in data["backgrounds"][id]["equipment"]:
			assert_bool(items.has(e["id"])).override_failure_message("%s: item %s" % [id, e["id"]]).is_true()


func test_class_steps_wait_for_the_class() -> void:
	var ch := CharacterBuilder.empty_choices()
	for step: String in ["skills", "equipment"]:
		assert_array(CharacterBuilder.errors(ch, data, step)).is_equal(["CC_ERR_PICK_CLASS"])


func test_steps_follow_the_choices() -> void:
	var ch := CharacterBuilder.empty_choices()
	ch["race"] = "human"
	ch["class"] = "fighter"
	var steps := CharacterBuilder.steps(ch, data)
	assert_array(steps).not_contains(["subrace", "subclass", "spells"])
	assert_array(steps).contains(["features"])  # Fighting Style
	ch["race"] = "dwarf"
	ch["class"] = "cleric"
	steps = CharacterBuilder.steps(ch, data)
	assert_array(steps).contains(["subrace", "subclass", "spells"])
	ch["class"] = "paladin"  # no spells at level 1
	assert_array(CharacterBuilder.steps(ch, data)).not_contains(["spells", "subclass"])


func test_point_buy() -> void:
	var ch := CharacterBuilder.empty_choices()
	assert_int(CharacterBuilder.point_cost(ch, data)).is_equal(0)
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).contains(["CC_ERR_POINTS_LEFT"])
	ch["base_abilities"] = {"str": 15, "dex": 15, "con": 15, "int": 8, "wis": 8, "cha": 8}
	assert_int(CharacterBuilder.point_cost(ch, data)).is_equal(27)
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).is_empty()
	ch["base_abilities"]["int"] = 9
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).contains(["CC_ERR_POINTS_OVER"])
	ch["base_abilities"]["int"] = 16
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).contains(["CC_ERR_ABILITY_RANGE"])


func test_half_elf_choices() -> void:
	var ch := CharacterBuilder.empty_choices()
	ch["race"] = "half_elf"
	ch["class"] = "rogue"
	ch["background"] = "criminal"
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).contains(["CC_ERR_ABILITY_CHOICE"])
	ch["ability_choice"] = ["dex", "dex"]
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).contains(["CC_ERR_ABILITY_CHOICE"])
	ch["ability_choice"] = ["dex", "con"]
	assert_array(CharacterBuilder.errors(ch, data, "abilities")).not_contains(["CC_ERR_ABILITY_CHOICE"])
	assert_dict(CharacterBuilder.final_abilities(ch, data)).contains_key_value("cha", 10)
	assert_int(CharacterBuilder.final_abilities(ch, data)["dex"]).is_equal(9)
	var rc := CharacterBuilder.race_skill_choice(ch, data)
	assert_int(rc["choose"]).is_equal(2)
	assert_array(rc["from"]).not_contains(["deception", "stealth"])  # already from the criminal background
	assert_int(CharacterBuilder.expertise_count(ch, data)).is_equal(2)
	assert_int(CharacterBuilder.language_count(ch, data)).is_equal(1)


func test_dragonborn_and_fighting_style_options() -> void:
	var ch := CharacterBuilder.empty_choices()
	ch["race"] = "dragonborn"
	ch["class"] = "fighter"
	var ids: Array = CharacterBuilder.feature_choices(ch, data).map(func(f: Dictionary) -> String: return f["id"])
	assert_array(ids).contains_exactly_in_any_order(["fighter_fighting_style", "draconic_ancestry"])
	assert_array(CharacterBuilder.errors(ch, data, "features")).contains(["CC_ERR_FEATURES"])
	ch["options"] = {"fighter_fighting_style": ["fighter_fighting_style_archery"], "draconic_ancestry": ["draconic_ancestry_blue"]}
	assert_array(CharacterBuilder.errors(ch, data, "features")).is_empty()


func test_equipment_step_needs_every_choice_and_valid_picks() -> void:
	var ch := TestUtils.preset_choices()
	assert_array(CharacterBuilder.errors(ch, data, "equipment")).is_empty()
	ch["equipment"][1]["picks"] = ["dagger"]  # a simple weapon where a martial one is asked
	assert_array(CharacterBuilder.errors(ch, data, "equipment")).contains(["CC_ERR_EQUIPMENT"])
	ch["equipment"].pop_back()
	assert_array(CharacterBuilder.errors(ch, data, "equipment")).contains(["CC_ERR_EQUIPMENT"])


func test_the_start_preset_is_complete() -> void:
	assert_bool(CharacterBuilder.complete(TestUtils.preset_choices(), data)).is_true()
	var c := TestUtils.character()
	assert_str(c["name"]).is_equal("Айра")
	assert_array(c["features"]).contains(["fighter_fighting_style", "fighter_fighting_style_defense", "second_wind"])
	assert_str(c["equipped"]["armor"]).is_equal("chain_mail")
	assert_str(c["equipped"]["main_hand"]).is_equal("longsword")
	assert_int(c["inventory"]["handaxe"]).is_equal(2)
	assert_array(c["languages"]).contains_exactly_in_any_order(["common", "dwarvish"])


func test_cleric_domain_spells_are_always_prepared() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 400:
		rng.seed = seed_value
		var ch := CharacterBuilder.random_choices(data, rng)
		if ch["class"] != "cleric":
			continue
		var c := CharacterBuilder.build(ch, data)
		assert_str(c["subclass"]).is_equal("life")
		assert_array(c["spells"]["always"]).contains(["bless", "cure_wounds"])
		assert_array(c["armor_profs"]).contains(["heavy"])  # Life domain bonus proficiency
		return
	fail("no cleric in 400 random characters")


func test_random_characters_are_complete_for_every_class() -> void:
	var rng := RandomNumberGenerator.new()
	var classes := {}
	for seed_value in 300:
		rng.seed = seed_value
		var ch := CharacterBuilder.random_choices(data, rng)
		for step: String in CharacterBuilder.steps(ch, data):
			assert_array(CharacterBuilder.errors(ch, data, step)).override_failure_message("seed %d, %s, step %s" % [seed_value, ch["class"], step]).is_empty()
		var c := CharacterBuilder.build(ch, data)
		classes[c["class"]] = true
		assert_int(c["max_hp"]).override_failure_message("seed %d" % seed_value).is_greater(0)
		assert_int(c["ac"]).override_failure_message("seed %d" % seed_value).is_greater_equal(10)
		assert_dict(c["inventory"]).override_failure_message("seed %d" % seed_value).is_not_empty()
		assert_str(c["name"]).is_not_empty()
	assert_int(classes.size()).is_equal(12)


func test_random_is_deterministic_by_seed() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 77
	b.seed = 77
	assert_dict(CharacterBuilder.random_choices(data, a)).is_equal(CharacterBuilder.random_choices(data, b))
