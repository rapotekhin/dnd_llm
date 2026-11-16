extends GdUnitTestSuite
## v0.8.4.44.4, the seven halls of the tutorial's cave (docs/design/systems/tutorial/description.md): each hall is drawn of
## its own chunk, which the generator never takes for another place; the pack lays the chest, the dead and the captives;
## «Найти выход» is the hero's from the first moment; a trap of DC 2 is found only by the search and the second by nothing;
## the fifth hall's step brings the whole party to the 2nd level; the pack lowers the social DC by its own numbers.

const QUEST := "find_the_exit"

var dream: Dictionary


func before_test() -> void:
	dream = WorldPack.apply_rules(TestUtils.base(), WorldPack.load_bundle("res://data/worlds/tutorial", "builtin"))


func _at(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.world_id = "tutorial"
	s.room_id = room
	s.visited = [room] as Array[String]
	return s


func test_a_named_chunk_is_taken_only_by_its_name() -> void:
	var lib: Dictionary = dream["layouts"]
	var named: Array = (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool: return bool(c.get("named", false))).map(func(c: Dictionary) -> String: return str(c["id"]))
	assert_array(named).contains_exactly(["dream_1", "dream_2", "dream_3", "dream_4", "dream_5", "dream_6", "dream_7"])
	for size: String in ["small", "medium", "large", "cave"]:
		for sd: int in 6:
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			var got := LayoutGen.candidates(lib, {"kind": "cave", "role": "hall", "size": size, "tags": ["cave"], "marks": []}, rng)
			assert_bool(got.any(func(c: Dictionary) -> bool: return named.has(str(c["id"])))).is_false()


func test_each_hall_is_drawn_of_its_own_chunk_with_its_one_way_on() -> void:
	for i: int in range(1, 8):
		var room := "dream-%d" % i
		var s := _at(room)
		var map := LayoutRules.map_of(s, dream, room)
		assert_str(str(map["picks"][room]["chunk"])).is_equal("dream_%d" % i)
		var ways: Array = (map["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(e["room"]) == room)
		assert_array(ways.map(func(e: Dictionary) -> String: return str(e["to"]))).is_equal([] if i == 7 else ["dream-%d" % (i + 1)])


func test_the_quest_of_the_first_moment_and_its_halls() -> void:
	var s := _at("dream-1")
	var lines := QuestRules.begin(s, dream)
	assert_int(int(s.quests_active.get(QUEST, -1))).is_equal(0)
	assert_array(lines).contains(["Новое задание: Найти выход"])
	assert_array(QuestRules.begin(s, dream)).is_empty()  # once
	s.visited.append("dream-2")
	s.visited.append("dream-3")
	QuestRules.advance(s, dream)
	assert_int(int(s.quests_active[QUEST])).is_equal(2)
	var frontier := TestUtils.data()
	assert_array(QuestRules.begin(TestUtils.new_session(), frontier)).is_empty()  # the Mark has no such quest


func test_the_chest_of_the_first_hall_stands_in_its_niche() -> void:
	var s := _at("dream-1")
	PropRules.ensure(s, dream, "dream-1")
	var p := PropRules.find(s, "dream-1", "f_chest")
	assert_dict(p["contents"]).is_equal({"healing_potion": 2, "silver_ring": 1, "figurine": 1})
	assert_int(int(p["coins_cp"])).is_equal(1500)
	var map := LayoutRules.map_of(s, dream, "dream-1")
	var niche := Vector2i(-1, -1)
	for m: Dictionary in map["marks"]:
		if str(m["name"]) == "niche":
			niche = Vector2i(int(m["x"]), int(m["y"]))
	var chest: Array = MapSpots.of(s, dream, map).filter(func(t: Dictionary) -> bool: return str(t["ref"]) == "prop:f_chest")
	assert_array(chest).has_size(1)
	assert_int(WalkRules.distance(Vector2i(int(chest[0]["x"]), int(chest[0]["y"])), niche)).is_less_equal(1)


func test_the_first_trap_is_found_only_by_a_search_of_its_own_dc() -> void:
	var s := _at("dream-1")
	var sec: Dictionary = ExplorationRules.secrets(dream["world"], "dream-1")[0]
	assert_bool(ExplorationRules.noticed_passively(sec)).is_false()
	assert_int(ExplorationRules.search_dc(s, dream, "dream-1")).is_equal(2)
	assert_array(ExplorationRules.active_reveal(s, dream["world"], ExplorationRules.SEARCH_SKILL, 4)).has_size(1)
	assert_int(ExplorationRules.search_dc(s, dream, "dream-1")).is_equal(int(dream["rules"]["dc_tiers"]["medium"]))  # nothing left
	assert_array(ExplorationRules.found_traps(s, dream["world"], "dream-1")).has_size(1)


func test_the_second_trap_is_found_by_nothing_and_springs() -> void:
	var s := _at("dream-2")
	var sec: Dictionary = ExplorationRules.secrets(dream["world"], "dream-2")[0]
	assert_bool(ExplorationRules.findable(sec)).is_false()
	assert_bool(ExplorationRules.noticed_passively(sec)).is_false()
	assert_int(ExplorationRules.search_dc(s, dream, "dream-2")).is_equal(int(dream["rules"]["dc_tiers"]["medium"]))
	assert_array(ExplorationRules.active_reveal(s, dream["world"], ExplorationRules.SEARCH_SKILL, 40)).is_empty()
	assert_dict(ExplorationRules.trap_on_exit(s, dream["world"], "dream-2", "dream-3")).is_not_empty()
	var hp := int(s.character["hp"])
	var lines := ExplorationRules.spring_trap(s, dream, "dream-2", sec)
	assert_str(lines[0]).starts_with("Ловушка!")
	assert_int(int(s.character["hp"])).is_less(hp)


func test_the_dead_of_the_halls_carry_what_the_pack_gives() -> void:
	var s := _at("dream-2")
	CreatureRules.seed(s, dream, "dream-2")
	var body: Dictionary = CreatureRules.here(s, "dream-2")[0]
	assert_str(str(body["state"])).is_equal(CreatureRules.DEAD)
	assert_dict(body["contents"]).is_equal({"leather_armor": 1, "shortsword": 1, "shield": 1})
	var s3 := _at("dream-3")
	CreatureRules.seed(s3, dream, "dream-3")
	var archer: Array = CreatureRules.here(s3, "dream-3").filter(func(c: Dictionary) -> bool: return str(c.get("pack_row", "")) == "archer")
	assert_dict(archer[0]["contents"]).contains_keys(["shortbow", "arrows", "quiver", "longsword", "chain_shirt"])


func test_the_bound_fighter_has_nothing_on_him_and_goes_along_when_untied() -> void:
	var s := _at("dream-3")
	CreatureRules.seed(s, dream, "dream-3")
	var npc := "npc_dream_fighter"
	assert_bool(s.held_as_creature(npc)).is_true()
	var gear := Gear.of(s, dream, npc)
	assert_dict(gear["inventory"]).is_empty()
	assert_dict(gear["equipped"]).is_empty()
	assert_int(Ledger.balance(s, npc)).is_equal(0)
	assert_str(str(GrowthRules.row(dream, npc).get("class", ""))).is_equal("fighter")
	CreatureRules.act(s, dream, npc, "untie")
	assert_bool(Being.follows(s, npc)).is_true()


func test_the_cleric_is_guarded_by_the_goblins_and_talked_into_it_at_dc_2() -> void:
	var s := _at("dream-4")
	CreatureRules.seed(s, dream, "dream-4")
	var npc := "npc_dream_cleric"
	assert_str(CreatureRules.can(s, npc, "untie", dream)).is_equal("CREATURE_GUARDED")
	s.encounters_done.append("dream_goblins")
	assert_str(CreatureRules.can(s, npc, "untie", dream)).is_empty()
	CreatureRules.act(s, dream, npc, "untie")
	assert_bool(Being.follows(s, npc)).is_false()  # she does not join by herself
	assert_int(int(SocialRules.dc(s, dream, npc, "persuasion", "easy")["dc"])).is_equal(2)
	assert_int(int(SocialRules.dc(s, TestUtils.data(), "npc_innkeeper", "persuasion", "very_easy")["dc"])).is_greater_equal(5)  # the Mark's floor


func test_the_pack_s_own_numbers_are_checked() -> void:
	assert_int(int(dream["rules"]["social"]["dc_min"])).is_equal(2)
	assert_int(int(TestUtils.data()["rules"]["social"]["dc_min"])).is_equal(5)
	var base := TestUtils.base()
	assert_array(WorldPack._numbers_ok({"social": {"dc_min": 2}}, base["rules"], "n")).is_empty()
	assert_array(WorldPack._numbers_ok({"social": {"no_such": 2}}, base["rules"], "n")).has_size(1)
	assert_array(WorldPack._numbers_ok({"social": {"dc_min": "два"}}, base["rules"], "n")).has_size(1)
	assert_array(Catalog.bundle("tutorial").get("errors", ["нет пакета"])).is_empty()


func test_the_fifth_hall_brings_the_whole_party_to_the_second_level() -> void:
	for party: int in [1, 4]:
		var s := _at("dream-5")
		s.settings["party"] = party
		s.character["xp"] = 120  # the goblins' share
		for npc: String in ["npc_dream_fighter", "npc_dream_cleric"]:
			FollowRules.apply(s, {"follow_npc": npc, "on": true, "room": ""})
		Being.of(s, "npc_dream_cleric")["xp"] = 50
		s.quests_active[QUEST] = 4
		s.encounters_done.append("dream_guards")
		var lines := QuestRules.advance(s, dream)
		var need := LevelUp.xp_for(dream, 2)
		assert_int(int(s.character["xp"])).is_equal(need)
		assert_bool(LevelUp.can_level_up(s.character, dream)).is_true()
		for npc: String in ["npc_dream_fighter", "npc_dream_cleric"]:
			assert_int(int(Being.view(s, npc)["xp"])).is_equal(need)
			assert_bool(GrowthRules.ready(s, dream, npc)).is_true()
		assert_int(int(s.quests_active[QUEST])).is_equal(5)
		assert_bool(lines.any(func(l: String) -> bool: return l.contains("готов к новому уровню"))).is_true()
