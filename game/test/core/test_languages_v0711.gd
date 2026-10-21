extends GdUnitTestSuite
## «Правила 5e: языки, предыстории, инструменты» (roadmap v0.7.11): who understands the hero, social checks and the
## parley without a common tongue, «Понимание языков», secret signs; the people of the hero's past, an acolyte's temple,
## an outlander's forage and way, an entertainer's show; tools in checks.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	s.character["hp"] = int(s.character["max_hp"])
	return s


# --- languages ---------------------------------------------------------------------------------------


func test_hero_languages_with_the_secret_ones() -> void:
	var rogue := _hero("rogue_damir").character
	assert_array(LanguageRules.hero(rogue)).contains(["common", "thieves_cant"])
	assert_array(LanguageRules.hero(_hero("druid_olha").character)).contains(["druidic"])
	assert_str(LanguageRules.name_of(data, "thieves_cant")).is_equal("Воровской жаргон")


func test_npc_languages_by_people() -> void:
	assert_array(LanguageRules.npc(data, {"race": "дварф"})).contains_exactly(["common", "dwarvish"])
	assert_array(LanguageRules.npc(data, {"race": "полуэльфийка"})).contains_exactly(["common", "elvish"])
	assert_array(LanguageRules.npc(data, {"race": "человек", "languages": ["orc"]})).contains_exactly(["orc"])


func test_monster_languages_from_the_srd_line() -> void:
	assert_array(LanguageRules.monster(data, "goblin")["speaks"]).contains(["common", "goblin"])
	assert_array(LanguageRules.monster(data, "gnoll")["speaks"]).contains_exactly(["gnoll"] if data["misc"]["languages"].has("gnoll") else [])
	assert_array(LanguageRules.monster(data, "bandit")["speaks"]).contains(["common"])
	assert_array(LanguageRules.monster(data, "wolf")["speaks"]).is_empty()
	assert_bool(LanguageRules.monster(data, "dretch")["telepathy"]).is_true()


func test_undercommon_is_not_common() -> void:
	for id: String in data["monsters"]:
		var line := str(data["monsters"][id].get("languages", "")).to_lower()
		if line.contains("undercommon") and not line.replace("undercommon", "").contains("common"):
			assert_array(LanguageRules.monster(data, id)["speaks"]).not_contains(["common"])
			return


func test_no_common_tongue_closes_words() -> void:
	var c := _hero("fighter_aira").character
	var stranger := {"race": "человек", "languages": ["giant"]}
	assert_bool(LanguageRules.npc_understands(c, data, stranger)).is_false()
	assert_dict(LanguageRules.check_gate(c, data, "persuasion", false)).contains_keys(["auto_fail"])
	assert_dict(LanguageRules.check_gate(c, data, "deception", false)).contains_keys(["auto_fail"])
	assert_dict(LanguageRules.check_gate(c, data, "intimidation", false)).contains_keys(["disadvantage"])
	assert_dict(LanguageRules.check_gate(c, data, "insight", false)).is_empty()
	assert_dict(LanguageRules.check_gate(c, data, "persuasion", true)).is_empty()


func test_comprehend_languages_bridges_the_tongue() -> void:
	var s := _hero("wizard_yalika")
	var stranger := {"race": "человек", "languages": ["giant"]}
	ConditionRules.add_effect(s.character, {"condition": "", "understand_all": true, "ends": ConditionRules.ends_for(s, data, "hour"),
		"source": {"kind": "spell", "id": "comprehend_languages", "name": "Понимание языков"}})
	assert_bool(LanguageRules.npc_understands(s.character, data, stranger)).is_true()


func test_parley_by_words_needs_a_tongue() -> void:
	var s := _hero("fighter_aira")
	CombatRules.start(s, data, [{"monster": "gnoll", "col": 2}], {})
	s.mode = GameSession.MODE_COMBAT
	assert_bool(CombatRules.parley_understood(s, data)).is_false()
	assert_str(CombatRules.can_parley(s, data, "persuasion")).is_equal("COMBAT_NO_LANGUAGE")
	assert_str(CombatRules.can_parley(s, data, "intimidation")).is_empty()
	var g := _hero("fighter_aira")
	CombatRules.start(g, data, [{"monster": "goblin", "col": 2}], {})
	assert_bool(CombatRules.parley_understood(g, data)).is_true()


func test_secret_signs_only_for_the_initiated() -> void:
	var rogue := _hero("rogue_damir")
	var room: Dictionary = data["world"]["rooms"]["brod-square"]
	assert_bool(TurnSnapshot.hooks(rogue, data, room).any(func(h: Variant) -> bool: return str(h).contains("воровской знак"))).is_true()
	var fighter := _hero("fighter_aira")
	assert_bool(TurnSnapshot.hooks(fighter, data, room).any(func(h: Variant) -> bool: return str(h).contains("воровской знак"))).is_false()
	var druid := _hero("druid_olha")
	assert_bool(TurnSnapshot.hooks(druid, data, data["world"]["rooms"]["pushcha-glade"]).any(func(h: Variant) -> bool:
		return str(h).contains("друидическая"))).is_true()


func test_snapshot_shows_languages_and_ties() -> void:
	var s := _hero("fighter_aira")
	var sheet := TurnSnapshot.character_sheet(s, data)
	assert_array(sheet["languages"]).contains(["Общий"])
	assert_str(str(sheet["background_feature"])).contains("солдат")
	var captain: Dictionary = data["world"]["npcs"]["npc_captain"]
	assert_str(BackgroundRules.tie_text(s.character, data, captain)).is_not_empty()
	assert_str(BackgroundRules.tie_text(_hero("wizard_yalika").character, data, captain)).is_empty()


# --- backgrounds -------------------------------------------------------------------------------------


func test_ties_warm_the_people_of_the_past() -> void:
	var s := _hero("fighter_aira")
	var names := BackgroundRules.apply_ties(s, data)
	assert_bool(names.is_empty()).is_false()
	var plain := _hero("wizard_yalika")
	assert_int(s.attitude("npc_captain")).is_equal(plain.attitude("npc_captain") + 1)
	assert_int(s.attitude("npc_innkeeper")).is_equal(plain.attitude("npc_innkeeper"))


func test_acolyte_rests_free_in_a_temple() -> void:
	var s := _hero("cleric_branko")
	s.room_id = "brod-temple"
	var place := ExplorationRules.rest_place(data["world"], s.room_id, s, data)
	assert_bool(place.is_empty()).is_false()
	assert_int(int(place["cost_cp"])).is_equal(0)
	# A temple where nobody rents a bed: only an acolyte sleeps there.
	var world: Dictionary = data["world"].duplicate(true)
	world["rooms"]["brod-temple"].erase("safe")
	var d := data.duplicate()
	d["world"] = world
	assert_int(int(ExplorationRules.rest_place(world, s.room_id, s, d)["cost_cp"])).is_equal(0)
	var other := _hero("fighter_aira")
	other.room_id = "brod-temple"
	assert_bool(ExplorationRules.rest_place(world, other.room_id, other, d).is_empty()).is_true()


func test_entertainer_show_pays_and_lodges() -> void:
	var s := _hero("bard_yas")
	s.room_id = "brod-tavern-hall"
	assert_str(BackgroundRules.can_perform(s, data)).is_empty()
	var gold := int(s.character["gold_cp"])
	var lines := BackgroundRules.performed(s, data, 21, true)
	assert_int(int(s.character["gold_cp"])).is_equal(gold + int(data["rules"]["backgrounds"]["_perform"]["great_cp"]))
	assert_int(lines.size()).is_equal(2)
	assert_int(int(ExplorationRules.rest_place(data["world"], "brod-tavern-upstairs", s, data)["cost_cp"])).is_equal(0)
	assert_str(BackgroundRules.can_perform(s, data)).is_equal("PERFORM_DONE_TODAY")
	s.room_id = "pushcha-edge"
	assert_str(BackgroundRules.can_perform(s, data)).is_equal("PERFORM_NO_STAGE")


func test_outlander_forages_and_walks_faster_outside_town() -> void:
	var s := _hero("barbarian_urga")
	s.room_id = "pushcha-edge"
	s.encounters_done.append_array(_all_encounters())
	(s.character["inventory"] as Dictionary).erase("rations")
	for id: String in ExplorationRules.camp_food(s.character, data).keys():
		(s.character["inventory"] as Dictionary).erase(id)
	assert_bool(BackgroundRules.can_forage(s, data)).is_true()
	assert_str(ExplorationRules.camp_error(s, data, {"forage": 1})).is_empty()
	var plain := _hero("fighter_aira")
	plain.room_id = "pushcha-edge"
	assert_str(ExplorationRules.camp_error(plain, data, {"forage": 1})).is_equal("REST_NO_FOOD")
	assert_int(BackgroundRules.travel_minutes(s, data, 60, "pushcha-trail")).is_equal(45)
	assert_int(BackgroundRules.travel_minutes(s, data, 60, "brod-square")).is_equal(60)
	assert_int(BackgroundRules.travel_minutes(plain, data, 60, "pushcha-trail")).is_equal(60)
	s.room_id = "brod-square"
	assert_bool(BackgroundRules.can_forage(s, data)).is_false()


func _all_encounters() -> Array:
	var out: Array = []
	for r: String in data["world"]["rooms"]:
		var enc: Dictionary = data["world"]["rooms"][r].get("encounter", {})
		if not enc.is_empty():
			out.append(str(enc.get("id", "")))
	return out


# --- tools -------------------------------------------------------------------------------------------


func test_thieves_tools_are_a_must_for_a_lock() -> void:
	var c := _hero("rogue_damir").character
	var fx := BackgroundRules.tool_check(c, data, "thieves_tools", "sleight_of_hand")
	assert_str(str(fx["auto_fail"])).is_empty()
	assert_str(str(fx["advantage"])).is_not_empty()  # skilled in Sleight of Hand and the tools: advantage (XGtE)
	(c["inventory"] as Dictionary).erase("thieves_tools")
	assert_str(str(BackgroundRules.tool_check(c, data, "thieves_tools", "sleight_of_hand")["auto_fail"])).is_not_empty()


func test_tool_proficiency_without_the_skill_gives_the_bonus() -> void:
	var c := _hero("fighter_aira").character
	c["tools"] = ["herbalism_kit"]
	c["inventory"]["herbalism_kit"] = 1
	var fx := BackgroundRules.tool_check(c, data, "herbalism_kit", "nature")
	assert_int(int(fx["bonus"])).is_equal(CharacterRules.prof_bonus(c, data))
	c["tools"] = []
	assert_int(int(BackgroundRules.tool_check(c, data, "herbalism_kit", "nature")["bonus"])).is_equal(0)
