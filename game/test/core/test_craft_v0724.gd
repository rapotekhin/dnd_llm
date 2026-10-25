extends GdUnitTestSuite
## Crafting (v0.7.24): recipes known by a tool's proficiency, learned for pay or from a book; materials spent at the
## start, the work in shifts with the progress kept, the quality by the check's margin; salvage, gathering, hides of
## beasts and the master's recipe.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _smith() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	var c := s.character
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["gold_cp"] = 5000
	s.room_id = "brod-smithy"
	s.minute = 12 * 60
	return s


func test_recipes_by_the_tool_and_learned_ones_hidden() -> void:
	var s := _smith()
	var known := CraftRules.known(s, data)
	assert_array(known).contains(["dagger", "smelt_iron", "shortsword"])
	assert_array(known).not_contains(["longsword", "chain_shirt", "leather_armor"])
	TradeRules.buy_service(s, data, "npc_smith", "teach_longsword")
	assert_array(CraftRules.known(s, data)).contains(["longsword"])
	assert_int(int(s.character["gold_cp"])).is_equal(3000)
	assert_array(TradeRules.targets(s, data, "teach_longsword")).is_empty()


func test_a_book_teaches_while_carried() -> void:
	var s := _smith()
	s.character["tools"].append("herbalism_kit")
	assert_array(CraftRules.known(s, data)).not_contains(["healing_potion"])
	s.character["inventory"]["herbalist_notes"] = 1
	assert_array(CraftRules.known(s, data)).contains(["healing_potion"])


func test_start_needs_the_tool_the_station_and_the_materials() -> void:
	var s := _smith()
	assert_str(CraftRules.why_not(s, data, "dagger")).is_equal("CRAFT_NO_MATERIALS")
	s.character["inventory"]["iron_bar"] = 2
	assert_str(CraftRules.why_not(s, data, "dagger")).is_empty()
	s.room_id = "brod-square"
	assert_str(CraftRules.why_not(s, data, "dagger")).is_equal("CRAFT_NO_STATION")
	s.room_id = "brod-smithy"
	s.character["inventory"].erase("smiths_tools")
	assert_str(CraftRules.why_not(s, data, "dagger")).is_equal("CRAFT_NO_TOOL")


func test_work_in_shifts_keeps_the_progress_and_pays_the_rent() -> void:
	var s := _smith()
	s.character["inventory"]["iron_bar"] = 2
	CraftRules.start(s, data, "shortsword")
	assert_int(int(s.character["inventory"].get("iron_bar", 0))).is_equal(0)
	assert_str(CraftRules.why_not(s, data, "dagger")).is_equal("CRAFT_BUSY")
	var mins := CraftRules.shift_minutes(s, data, 8)
	assert_int(mins).is_equal(480)
	var lines := CraftRules.worked(s, data, mins)
	assert_str(" ".join(lines)).contains("Плата за горн")
	assert_int(int(s.character["gold_cp"])).is_equal(5000 - 80)
	assert_int(CraftRules.progress(s.character)).is_equal(80)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_int(CraftRules.progress(back.character)).is_equal(80)
	assert_int(CraftRules.shift_minutes(s, data, 8)).is_equal(120)
	CraftRules.worked(s, data, 120)
	assert_bool(CraftRules.project(s.character).is_empty()).is_true()
	var swords := (s.character["inventory"] as Dictionary).keys().filter(func(id: String) -> bool:
		return id == "shortsword" or str(ItemRules.def_of(data["items"], s.items, id).get("base", "")) == "shortsword")
	assert_array(swords).has_size(1)


func test_quality_by_the_margin() -> void:
	assert_str(str(CraftRules.tier_for(data, -7)["id"])).is_equal("poor")
	assert_str(str(CraftRules.tier_for(data, -2)["id"])).is_equal("normal")
	assert_str(str(CraftRules.tier_for(data, 0)["id"])).is_equal("normal")
	assert_str(str(CraftRules.tier_for(data, 6)["id"])).is_equal("good")
	assert_str(str(CraftRules.tier_for(data, 12)["id"])).is_equal("excellent")


func test_an_excellent_sword_hits_better_a_crude_one_worse() -> void:
	var s := _smith()
	var good := CraftRules.make_output(s, data, "shortsword", 1, CraftRules.tier_by_id(data, "excellent"))
	var bad := CraftRules.make_output(s, data, "shortsword", 1, CraftRules.tier_by_id(data, "poor"))
	var gd := ItemRules.def_of(data["items"], s.items, str(good["id"]))
	assert_str(str(gd["name"])).contains("отличная работа")
	assert_int(int(gd["value_cp"])).is_equal(2000)
	assert_bool(gd.has("weapon")).is_true()
	var c := s.character
	var plain := int(CombatRules.weapon_profile(c, data, s.items, "shortsword")["to_hit"])
	assert_int(int(CombatRules.weapon_profile(c, data, s.items, str(good["id"]))["to_hit"])).is_equal(plain + 1)
	assert_int(int(CombatRules.weapon_profile(c, data, s.items, str(bad["id"]))["to_hit"])).is_equal(plain - 1)


func test_a_stack_changes_its_count_by_quality() -> void:
	var s := _smith()
	assert_int(int(CraftRules.make_output(s, data, "arrows", 20, CraftRules.tier_by_id(data, "good"))["qty"])).is_equal(30)
	assert_int(int(CraftRules.make_output(s, data, "arrows", 20, CraftRules.tier_by_id(data, "poor"))["qty"])).is_equal(10)


func test_salvage_gives_half_the_materials() -> void:
	var s := _smith()
	s.character["inventory"]["shortsword"] = 1
	s.character["inventory"]["dagger"] = 1
	assert_dict(CraftRules.salvage_yield(s, data, "shortsword")).is_equal({"iron_bar": 1})
	assert_dict(CraftRules.salvage_yield(s, data, "dagger")).is_equal({"iron_bar": 1})
	assert_dict(CraftRules.salvage_yield(s, data, "scale_mail")).is_equal({"iron_bar": 5})
	CraftRules.salvage(s, data, "shortsword")
	assert_int(int(s.character["inventory"].get("iron_bar", 0))).is_equal(1)
	assert_bool(s.character["inventory"].has("shortsword")).is_false()
	var worn := str(s.character["equipped"].get("main_hand", ""))
	if not worn.is_empty():
		assert_array(CraftRules.salvageable(s, data)).not_contains([worn])


func test_gathering_ore_in_the_mine_spends_the_spot() -> void:
	var s := _smith()
	s.room_id = "mine-gallery"
	assert_array(CraftRules.gather_here(s, data)).is_equal(["ore"])
	s.room_id = "brod-square"
	assert_array(CraftRules.gather_here(s, data)).is_empty()
	s.room_id = "mine-gallery"
	var got := 0
	for i in 2:
		assert_str(CraftRules.gather_why(s, data, "ore")).is_empty()
		CraftRules.gather(s, data, "ore")
	got = int(s.character["inventory"].get("iron_ore", 0))
	assert_str(CraftRules.gather_why(s, data, "ore")).is_equal("GATHER_SPENT")
	s.day += 1
	assert_str(CraftRules.gather_why(s, data, "ore")).is_empty()
	assert_int(got).is_between(0, 6)


func test_a_dead_wolf_leaves_a_hide() -> void:
	assert_int(CraftRules.hides(data, data["monsters"]["wolf"])).is_equal(1)
	assert_int(CraftRules.hides(data, data["monsters"]["goblin"])).is_equal(0)


func test_the_master_makes_a_recipe_the_hero_learns() -> void:
	var s := _smith()
	var engine := EffectEngine.new()
	var bad := engine.validate(s, data, "t-1", {"kind": "recipe", "tool": "weavers_tools", "hours": 2, "dc_tier": "easy",
		"materials": [{"item_id": "rope", "qty": 1}], "output_id": "hunting_trap"})
	assert_bool(bool(bad["accepted"])).is_false()
	assert_str(str(bad["reason"])).contains("не владеет")
	var dear := engine.validate(s, data, "t-1", {"kind": "recipe", "tool": "smiths_tools", "hours": 1, "dc_tier": "easy",
		"materials": [{"item_id": "iron_bar", "qty": 1}], "output_id": "chain_shirt"})
	assert_bool(bool(dear["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "recipe", "tool": "smiths_tools", "station": "forge", "hours": 2, "dc_tier": "medium",
		"materials": [{"item_id": "iron_bar", "qty": 1}], "output": {"name": "Железный силок", "item_type": "gear", "rarity": "common", "value_cp": 60,
		"description": "Петля из кованой проволоки на мелкого зверя."}})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var mine := CraftRules.known(s, data).filter(func(id: String) -> bool: return CraftRules.recipe_name(s, data, id) == "Железный силок")
	assert_array(mine).has_size(1)
	assert_int(int(CraftRules.recipe(s, data, mine[0])["dc"])).is_equal(15)
	assert_str(ItemRules.display_name(data["items"], s.items, str(CraftRules.recipe(s, data, mine[0])["output"]))).is_equal("Железный силок")


func test_the_master_sees_the_craft() -> void:
	var s := _smith()
	var snap := TurnSnapshot.build(s, data, 1000)
	assert_str(str(snap["character"]["craft"])).contains("Кинжал")
