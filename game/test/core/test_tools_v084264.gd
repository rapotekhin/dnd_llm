extends GdUnitTestSuite
## The tools on the engine's roads (roadmap v0.8.4.26.4): an instrument in the show's Performance, a gaming set in a
## contest and its cheating, a healer's kit as Spare the Dying with ten charges, a basic poison on the blade, a disguise
## kit as Disguise Self with the kit's Deception as the DC, a forgery kit as a way of a letter, the tools of the way, the
## artisans' recipes, clay and stone gathered.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(tools: Array = []) -> GameSession:
	var s := ChecklistProbe.session(data)
	var c := s.character
	c["tools"] = tools.duplicate()
	c["skill_profs"] = []
	for t: Variant in tools:
		Gear.give(s, data, Being.HERO, str(t), 1)
	CharacterRules.refresh(c, data, s.items)
	return s


func test_an_instrument_goes_into_the_show() -> void:
	var s := _hero(["lute"])
	var spec := BackgroundRules.perform_check(s, data)
	assert_str(str(spec["tool"])).is_equal("lute")
	assert_int(int(BackgroundRules.tool_check(s.character, data, "lute", "performance")["bonus"])).is_greater(0)
	assert_bool(BackgroundRules.perform_check(_hero(), data).has("tool")).is_false()


func test_a_gaming_set_helps_the_cheat_too() -> void:
	var k := ContestRules.kind(data, "dice")
	assert_str(str(ContestRules.hero_params(data, k, true)["tool"])).is_equal("dice_set")
	assert_str(str(ContestRules.hero_params(data, k, true)["skill"])).is_equal("sleight_of_hand")


func test_a_healers_kit_stabilizes_a_fallen_ally_and_spends_a_use() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "healers_kit", 1)
	ItemRules.belt_put(s.character, data, s.items, "healers_kit")
	var a := ChecklistProbe.fight(s, data, "goblin", false, "ally")
	a["hp"] = 0
	a["status"] = "down"
	var p := CombatRules.player(s)
	ChecklistProbe.turn(s, data, p)
	var act := Acts.one("item_spell")
	assert_str(act.can(s, data, p, str(a["id"]), {"item": "healers_kit"})).is_empty()
	act.go(s, data, p, str(a["id"]), {"item": "healers_kit"})
	assert_bool(bool(CombatRules.saves_of(s, a)["stable"])).is_true()
	var d := ItemRules.def_of(data["items"], s.items, "healers_kit")
	assert_int(ItemRules.charges_left(s.character, d, "healers_kit")).is_equal(9)


func test_a_poison_coats_a_blade_once() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "poison_basic_vial", 1)
	ItemRules.belt_put(c, data, s.items, "poison_basic_vial")
	assert_str(ItemRules.can_use(c, data, s.items, "poison_basic_vial")).is_empty()
	ItemRules.use(c, data, s.items, "poison_basic_vial", s.rng, s)
	assert_int(Gear.count(s, data, Being.HERO, "poison_basic_vial")).is_equal(0)
	assert_array(SpellEffects.hit_extras(c, {}, "bludgeoning")).is_empty()
	var x := SpellEffects.hit_extras(c, {}, "piercing")
	assert_str(str(x[0]["save"])).is_equal("con")
	assert_int(int(x[0]["dc"])).is_equal(10)
	assert_array(SpellEffects.hit_extras(c, {}, "piercing")).is_empty()


func test_a_disguise_kit_lays_disguise_self_with_its_own_dc() -> void:
	var s := _hero(["disguise_kit"])
	var c := s.character
	ItemRules.belt_put(c, data, s.items, "disguise_kit")
	var clock := TimeRules.abs_minute(s)
	ItemRules.use(c, data, s.items, "disguise_kit", s.rng, s)
	assert_int(TimeRules.abs_minute(s) - clock).is_greater_equal(30)
	assert_bool(Guise.of(c).is_empty()).is_false()
	assert_str(Guise.face(c)).is_empty()  # the master names it, as for the spell
	assert_int(int(Guise.of(c)["dc"])).is_greater(0)
	assert_int(Gear.count(s, data, Being.HERO, "disguise_kit")).is_equal(1)
	assert_str(Acts.one("use_item").why(s, data, {"id": "hero"}, "", {"item": "disguise_kit"})).is_equal("COMBAT_ITEM_CANT")


func _notable_met(s: GameSession) -> String:
	for npc: String in data["world"]["npcs"]:
		var room := ReputationRules.home_room(data, npc)
		if LetterRules.notable(s, data, npc) and not room.is_empty() and room != s.room_id:
			s.visited.append(room)
			if LetterRules.recipients(s, data).has(npc):
				return npc
	return ""


func test_a_forgery_kit_makes_a_recommendation_in_anothers_hand() -> void:
	var s := _hero(["forgery_kit"])
	var by := _notable_met(s)
	assert_str(by).is_not_empty()
	assert_array(LetterRules.ways(s, data, "")).contains(["forgery_kit"])
	assert_array(LetterRules.purposes_of(data, "forgery_kit")).is_equal(["recommend"])
	assert_str(LetterRules.send_why(s, data, "", by, "ties", "Прошу принять подателя сего.", "forgery_kit")).is_not_empty()
	assert_str(LetterRules.send_why(s, data, "", by, "recommend", "Прошу принять подателя сего.", "forgery_kit")).is_empty()
	var lines := LetterRules.send(s, data, "", by, "recommend", "Прошу принять подателя сего.", "forgery_kit")
	assert_str(" ".join(lines)).contains("Подделано")
	var item := ""
	for id: String in s.character["inventory"]:
		if int(ItemRules.def_of(data["items"], s.items, id).get("forged", 0)) > 0:
			item = id
	assert_str(item).is_not_empty()
	assert_str(LetterRules.recommender(s, data, [by])).is_empty()  # never fools the one whose hand it fakes
	s.items[item]["seen"] = {"reader": true}
	assert_str(LetterRules.recommender(s, data, ["reader"], true)).is_not_empty()
	s.items[item]["seen"] = {"reader": false}
	assert_str(LetterRules.recommender(s, data, ["reader"], true)).is_empty()


func test_the_tools_of_the_way_shorten_it_outside_settlements() -> void:
	var wild := ""
	for rid: String in data["world"]["rooms"]:
		if not WorldView.new(data["world"]).flag(rid, "lit"):
			wild = rid
			break
	assert_int(BackgroundRules.travel_minutes(_hero(), data, 100, wild)).is_equal(100)
	assert_int(BackgroundRules.travel_minutes(_hero(["navigators_tools"]), data, 100, wild)).is_equal(75)
	var carried := _hero()
	Gear.give(carried, data, Being.HERO, "cartographers_tools", 1)
	assert_int(BackgroundRules.travel_minutes(carried, data, 100, wild)).is_equal(100)  # carried, not known


func test_every_artisans_tool_has_its_recipes() -> void:
	for tool: String in ["brewers_supplies", "calligraphers_supplies", "cobblers_tools", "glassblowers_tools", "jewelers_tools", "masons_tools",
			"cartographers_tools", "painters_supplies", "potters_tools", "tinkers_tools", "weavers_tools", "poisoners_kit"]:
		var s := _hero([tool])
		var mine := CraftRules.known(s, data).filter(func(r: String) -> bool: return CraftRules.tool_of(CraftRules.recipe(s, data, r)) == tool)
		assert_array(mine).override_failure_message(tool).is_not_empty()
		assert_bool((data["rules"]["craft"]["tools"] as Dictionary).has(tool)).override_failure_message(tool).is_true()


func test_clay_by_the_river_and_stone_beside_the_ore() -> void:
	var s := _hero()
	s.room_id = "mine-gallery"
	assert_array(CraftRules.gather_here(s, data)).contains(["ore", "stone"])
	for rid: String in data["world"]["rooms"]:
		if SceneRules.tags(s, data["world"], rid).has("fish"):
			s.room_id = rid
			break
	assert_array(CraftRules.gather_here(s, data)).contains(["clay", "sand"])
