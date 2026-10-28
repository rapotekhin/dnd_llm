extends GdUnitTestSuite
## The empty boxes of «Своя жизнь» (v0.7.39.1): recipes behind the skills of «Ремесло», the direction «Артефакция»
## with its templates (+1, elemental blades, scrolls, potions, wondrous things by a formula) and its arcane dust;
## the pack's own dishes; followers fed from the hero's things; the work of an organization.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _smith() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	var c := s.character
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["gold_cp"] = 50000
	s.room_id = "brod-smithy"
	s.minute = 12 * 60
	return s


func _skill(c: Dictionary, dir: String, skill: String) -> void:
	DevelopmentRules.state(c, dir)["xp"] = 1200
	(DevelopmentRules.state(c, dir)["skills"] as Array).append(skill)


func test_a_martial_weapon_asks_the_forging_skill() -> void:
	var s := _smith()
	s.character["inventory"]["iron_bar"] = 4
	assert_str(CraftRules.why_not(s, data, "dagger")).is_empty()
	assert_str(CraftRules.why_not(s, data, "shortsword")).is_equal("CRAFT_NO_SKILL")
	assert_str(", ".join(CraftRules.skills_missing(s.character, data, CraftRules.recipe(s, data, "shortsword")))).contains("Ковка одноручного оружия")
	_skill(s.character, "craft", "weaponsmith")
	assert_str(CraftRules.why_not(s, data, "shortsword")).is_empty()


func test_a_finished_thing_grows_the_craft() -> void:
	var s := _smith()
	s.character["inventory"]["iron_bar"] = 1
	CraftRules.start(s, data, "dagger")
	var lines := CraftRules.worked(s, data, 4 * 60)
	assert_str("\n".join(lines)).contains("Ремесло: +")
	assert_int(DevelopmentRules.xp(s.character, "craft")).is_greater(0)


func test_brisk_hands_shorten_the_work() -> void:
	var s := _smith()
	var r := CraftRules.recipe(s, data, "dagger")
	assert_int(CraftRules.work_minutes(s.character, data, r)).is_equal(240)
	_skill(s.character, "craft", "brisk")
	assert_int(CraftRules.work_minutes(s.character, data, r)).is_equal(180)


func test_a_plus_one_weapon_from_a_carried_one_and_the_dust() -> void:
	var s := _smith()
	assert_array(CraftRules.known(s, data).filter(func(id: String) -> bool: return id.begins_with("tpl:"))).is_empty()
	_skill(s.character, "artifice", "enchant_weapon")
	assert_array(CraftRules.known(s, data)).not_contains(["tpl:enchant_weapon:dagger_plus_1"])  # no dagger to enchant
	s.character["inventory"]["dagger"] = 1
	assert_array(CraftRules.known(s, data)).contains(["tpl:enchant_weapon:dagger_plus_1"])
	var r := CraftRules.recipe(s, data, "tpl:enchant_weapon:dagger_plus_1")
	assert_dict(r["materials"]).is_equal({"dagger": 1, "arcane_dust": 8})
	assert_str(str(r["tool"])).is_equal("smiths_tools")
	_skill(s.character, "artifice", "dust_saver")
	assert_int(int(CraftRules.recipe(s, data, "tpl:enchant_weapon:dagger_plus_1")["materials"]["arcane_dust"])).is_equal(6)
	s.character["inventory"]["arcane_dust"] = 6
	assert_str(CraftRules.why_not(s, data, "tpl:enchant_weapon:dagger_plus_1")).is_empty()
	CraftRules.start(s, data, "tpl:enchant_weapon:dagger_plus_1")
	var lines := CraftRules.worked(s, data, 60 * 60)
	assert_str("\n".join(lines)).contains("Артефакция: +")
	var made := (s.character["inventory"] as Dictionary).keys().filter(func(k: String) -> bool: return k.begins_with("dagger_plus_1") or str(s.items.get(k, {}).get("base", "")) == "dagger_plus_1")
	assert_array(made).is_not_empty()


func test_an_elemental_blade_asks_its_forging_skill_too() -> void:
	var s := _smith()
	_skill(s.character, "artifice", "enchant_weapon")
	_skill(s.character, "artifice", "elemental")
	s.character["inventory"]["shortsword"] = 1
	var id := "tpl:elemental:shortsword:fire_damage"
	assert_array(CraftRules.known(s, data)).contains([id])
	var r := CraftRules.recipe(s, data, id)
	assert_array(r["skills"]).contains(["artifice:elemental", "craft:weaponsmith"])
	assert_str(str(r["name"])).contains("огненный")
	s.character["inventory"]["arcane_dust"] = 8
	assert_str(CraftRules.why_not(s, data, id)).is_equal("CRAFT_NO_SKILL")
	_skill(s.character, "craft", "weaponsmith")
	CraftRules.start(s, data, id)
	assert_array(s.items[str(r["output"])]["properties"]).contains(["fire_damage"])


func test_a_scroll_of_a_known_spell_checks_arcana() -> void:
	var s := TestUtils.new_session()
	s.character["spells"] = {"known": ["magic_missile"]}
	_skill(s.character, "artifice", "scribe")
	var id := "tpl:scroll:spell_scroll_magic_missile"
	assert_array(CraftRules.known(s, data)).contains([id])
	assert_array(CraftRules.known(s, data)).not_contains(["tpl:scroll:spell_scroll_fire_bolt"])
	var r := CraftRules.recipe(s, data, id)
	assert_bool(CraftRules.needs_tool(r)).is_false()
	assert_str(CraftRules.check_label(data, r)).is_equal(CraftRules.tr_skill(data, "arcana"))


func test_a_wondrous_thing_by_the_formula_in_a_book() -> void:
	var s := TestUtils.new_session()
	var id := "tpl:wondrous:cloak_of_protection"
	assert_array(CraftRules.known(s, data)).not_contains([id])
	s.character["inventory"]["wondrous_formulary"] = 1
	assert_array(CraftRules.known(s, data)).contains([id])
	assert_str(CraftRules.why_not(s, data, id)).is_equal("CRAFT_NO_SKILL")


func test_a_magic_thing_breaks_into_arcane_dust() -> void:
	var s := _smith()
	s.character["inventory"]["dagger_plus_1"] = 1
	var got := CraftRules.salvage_yield(s, data, "dagger_plus_1")
	assert_int(int(got.get("arcane_dust", 0))).is_equal(4)
	assert_int(int(CraftRules.salvage_yield(s, data, "dagger").get("arcane_dust", 0))).is_equal(0)
	var lines := CraftRules.salvage(s, data, "dagger_plus_1")
	assert_str("\n".join(lines)).contains("Артефакция: +")


func test_identifying_and_the_course_grow_artifice() -> void:
	var s := TestUtils.new_session()
	ItemRules.found(s.character, data, s.items, "cloak_of_protection")
	ItemRules.identify(s.character, data, s.items)
	assert_int(DevelopmentRules.xp(s.character, "artifice")).is_equal(10)
	var lines := StudyRules.grant(s, data, "artifice_basics")
	assert_str("\n".join(lines)).contains("Артефакция: +60")


func test_the_pack_dishes_feed_and_are_taught_at_the_tavern() -> void:
	assert_int(int(data["rules"]["hero_effects"]["camp"]["food"].get("pushcha_pie", 0))).is_equal(3)
	assert_array(data["world"]["npcs"]["npc_innkeeper"]["services"]).contains(["teach_pushcha_pie", "teach_sbiten"])
	var s := TestUtils.new_session()
	s.character["tools"] = ["cooks_utensils"]
	assert_array(CraftRules.known(s, data)).not_contains(["pushcha_pie"])
	CraftRules.learn(s, data, "pushcha_pie")
	assert_array(CraftRules.known(s, data)).contains(["pushcha_pie"])


func _with_follower() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = true
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	FollowRules.apply(s, {"follow_npc": "npc_innkeeper", "on": true, "room": ""})
	return s


func test_a_follower_eats_from_the_heros_things() -> void:
	var s := _with_follower()
	s.character["inventory"]["rations"] = 2
	var lines := TimeRules.advance(s, data, 25 * 60)
	assert_str("\n".join(lines)).contains("Бруно Хмель поел")
	assert_int(int(s.follower_fed["npc_innkeeper"]["hungry"])).is_equal(0)


func test_an_unfed_follower_goes_home() -> void:
	var s := _with_follower()
	for id: String in NeedRules.food_items(s.character, data):
		s.character["inventory"].erase(id)
	var att := s.attitude("npc_innkeeper")
	var lines := TimeRules.advance(s, data, 25 * 60)
	assert_str("\n".join(lines)).contains("голоден")
	assert_int(s.attitude("npc_innkeeper")).is_equal(att - 1)
	lines = TimeRules.advance(s, data, 24 * 60)
	assert_str("\n".join(lines)).contains("ушёл домой")
	assert_bool(s.followers.has("npc_innkeeper")).is_false()


func test_a_long_rest_feeds_the_followers() -> void:
	var s := _with_follower()
	s.follower_fed["npc_innkeeper"] = {"at": TimeRules.abs_minute(s) - 2000, "hungry": 1}
	FollowRules.rested(s)
	assert_int(int(s.follower_fed["npc_innkeeper"]["hungry"])).is_equal(0)
	assert_int(int(s.follower_fed["npc_innkeeper"]["at"])).is_equal(TimeRules.abs_minute(s))


func test_the_work_of_an_organization_asks_a_membership() -> void:
	var s := TestUtils.new_session()
	s.room_id = str(data["world"]["npcs"]["npc_drover"].get("room_id", "brod-gate"))
	var req := JobRules.requirements(s, data, "caravan_guard")
	assert_bool(req.any(func(r: Dictionary) -> bool: return str(r["text"]).contains("Обозная артель") and not bool(r["ok"]))).is_true()
	OrgRules._st(s.character, "drovers")["joined"] = s.day
	req = JobRules.requirements(s, data, "caravan_guard")
	assert_bool(req.all(func(r: Dictionary) -> bool: return bool(r["ok"]) or not str(r["text"]).contains("артель"))).is_true()
	assert_array(OrgRules.jobs_of(s, data, "drovers")).contains(["caravan_guard"])


func test_a_convoy_shift_may_end_in_a_fight_and_a_bad_pickpocket_is_caught() -> void:
	var s := TestUtils.new_session()
	data["world"]["jobs"]["caravan_guard"]["fight"]["chance"] = 1.0
	OrgRules._st(s.character, "drovers")["joined"] = s.day
	JobRules.state(s.character)["caravan_guard"] = {"rank": 0, "good": 0, "shifts": 0}
	var r := JobRules.shift(s, data, "caravan_guard", 8 * 60)
	assert_int((r["fight"] as Array).size()).is_equal(2)
	data["world"]["jobs"]["pickpocket"]["dc"] = 99  # the roll fails: caught
	OrgRules._st(s.character, "night_rats")["joined"] = s.day
	JobRules.state(s.character)["pickpocket"] = {"rank": 0, "good": 0, "shifts": 0}
	var before := s.crimes.size()
	JobRules.shift(s, data, "pickpocket", 4 * 60)
	assert_int(s.crimes.size()).is_equal(before + 1)
	assert_str(str(s.crimes[-1]["kind"])).is_equal("pickpocket")
