extends GdUnitTestSuite
## Adventure systems (roadmap v0.6.3): time of day (parts, midnight, rests, closed shops, darkness), quests with
## steps closed by engine facts, traps and caches, SRD magic items, the save.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


# --- time of day ----------------------------------------------------------------------------------


func test_parts_of_the_day_and_midnight() -> void:
	var s := _session()
	assert_str(TimeRules.part(s, data)).is_equal("morning")
	assert_str(TimeRules.clock(s)).is_equal("08:00")
	s.minute = 1300
	assert_str(TimeRules.part(s, data)).is_equal("evening")
	var lines := TimeRules.advance(s, data, 200)  # 21:40 → 01:00 next day
	assert_int(s.day).is_equal(2)
	assert_int(s.minute).is_equal(60)
	assert_str(TimeRules.part(s, data)).is_equal("night")
	assert_str("\n".join(lines)).contains("Наступил день 2")


func test_moving_takes_minutes_and_travel_takes_an_hour() -> void:
	var s := _session()
	TimeRules.on_move(s, data, "brod-tavern-hall", "brod-square")
	assert_int(s.minute).is_equal(490)
	TimeRules.on_move(s, data, "brod-gate", "pushcha-edge")
	assert_int(s.minute).is_equal(550)


func test_a_long_rest_ends_in_the_morning_and_counts_the_day_once() -> void:
	var s := _session()
	s.minute = 23 * 60
	s.day = 1
	ExplorationRules.long_rest(s, data)
	TimeRules.after_long_rest(s, data, 23 * 60)
	assert_int(s.day).is_equal(2)
	assert_int(s.minute).is_equal(420)
	s.minute = 120  # after midnight: the day already turned
	ExplorationRules.long_rest(s, data)
	TimeRules.after_long_rest(s, data, 120)
	assert_int(s.day).is_equal(2)


func test_night_closes_the_shops_and_the_wild_is_dark_without_light() -> void:
	var s := _session()
	assert_bool(TimeRules.shops_closed(s, data)).is_false()
	s.minute = 23 * 60
	assert_bool(TimeRules.shops_closed(s, data)).is_true()
	s.room_id = "brod-square"
	assert_bool(TimeRules.dark(s, data)).is_false()  # the town is lit
	s.room_id = "pushcha-edge"
	s.character["inventory"].erase("torch")
	assert_bool(TimeRules.dark(s, data)).is_true()
	assert_int(TimeRules.passive_penalty(s, data)).is_equal(5)
	s.sneaking = true
	assert_int(TimeRules.passive_penalty(s, data)).is_equal(10)
	s.character["inventory"]["torch"] = 1
	assert_bool(TimeRules.dark(s, data)).is_false()
	s.character["inventory"].erase("torch")
	(s.character["traits"] as Array).append("darkvision")
	assert_bool(TimeRules.dark(s, data)).is_false()


# --- quests with steps ----------------------------------------------------------------------------


func test_a_quest_is_taken_at_the_giver_and_closed_by_facts_and_a_button() -> void:
	var s := _session()
	var world: Dictionary = data["world"]
	s.room_id = "brod-square"
	assert_array(QuestRules.offers_here(s, world)).not_contains(["drogin_amulet"])
	s.room_id = "mine-entrance"
	assert_array(QuestRules.offers_here(s, world)).contains(["drogin_amulet"])
	assert_array(XpRules.quests_here(s, world)).not_contains(["drogin_amulet"])  # not a one-button quest
	var lines := QuestRules.accept(s, data, "drogin_amulet")
	assert_str(lines[0]).contains("Амулет пропавшего")
	assert_int(int(s.quests_active["drogin_amulet"])).is_equal(0)
	assert_array(QuestRules.advance(s, data)).is_empty()  # not found yet
	s.revealed["mine-flooded"] = ["amulet"]
	var xp := int(s.character["xp"])
	var step := QuestRules.advance(s, data)
	assert_str("\n".join(step)).contains("сделано")
	assert_int(int(s.character["xp"])).is_equal(xp + 50)
	assert_str(QuestRules.current(s, world, "drogin_amulet")["text"]).contains("Отдать")
	assert_str(QuestRules.can_talk(s, world, "drogin_amulet")).is_equal("QUEST_NEEDS_ITEM")
	s.character["inventory"]["amulet"] = 1
	assert_str(QuestRules.can_talk(s, world, "drogin_amulet")).is_empty()
	var gold := int(s.character["gold_cp"])
	var done := QuestRules.talk(s, data, "drogin_amulet")
	assert_str("\n".join(done)).contains("Задание выполнено")
	assert_bool(s.quests_done.has("drogin_amulet")).is_true()
	assert_bool(s.quests_active.has("drogin_amulet")).is_false()
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 2500)
	assert_int(s.attitude("npc_prospector")).is_equal(1)
	assert_bool(s.character["inventory"].has("amulet")).is_false()


func test_steps_done_before_taking_close_at_once_and_the_snapshot_shows_the_step() -> void:
	var s := _session()
	s.room_id = "mine-entrance"
	s.revealed["mine-flooded"] = ["amulet"]
	QuestRules.accept(s, data, "drogin_amulet")
	assert_int(int(s.quests_active["drogin_amulet"])).is_equal(1)
	var snap := TurnSnapshot.build(s, data, 4000)
	var q: Array = snap["quests"].filter(func(x: Dictionary) -> bool: return x["id"] == "drogin_amulet")
	assert_str(q[0]["step"]).contains("Отдать")
	assert_str(snap["scene"]["time_of_day"]).is_equal("утро, 08:00")


# --- traps and caches -----------------------------------------------------------------------------


func test_a_trap_guards_its_exit_and_springs_once() -> void:
	var s := _session()
	var world: Dictionary = data["world"]
	var trap := ExplorationRules.trap_on_exit(s, world, "mine-gallery", "mine-deep")
	assert_str(str(trap.get("id", ""))).is_equal("deadfall")
	assert_dict(ExplorationRules.trap_on_exit(s, world, "mine-gallery", "mine-flooded")).is_empty()
	assert_array(ExplorationRules.found_traps(s, world, "mine-gallery")).is_empty()
	s.character["hp"] = 100
	s.character["max_hp"] = 100
	var lines := ExplorationRules.spring_trap(s, data, "mine-gallery", trap)
	assert_str(lines[0]).contains("Ловушка!")
	assert_int(int(s.character["hp"])).is_less(100)
	assert_dict(ExplorationRules.trap_on_exit(s, world, "mine-gallery", "mine-deep")).is_empty()


func test_found_traps_are_offered_and_disarming_needs_tools() -> void:
	var s := _session()
	var world: Dictionary = data["world"]
	s.revealed["mine-gallery"] = ["deadfall"]
	assert_array(ExplorationRules.found_traps(s, world, "mine-gallery")).has_size(1)
	s.character["inventory"].erase("thieves_tools")
	assert_str(ExplorationRules.disarm_bonus(s.character)["disadvantage_reason"]).contains("инструментов")
	var r := _session("rogue_damir")
	r.character["inventory"]["thieves_tools"] = 1
	var db := ExplorationRules.disarm_bonus(r.character)
	assert_str(db["disadvantage_reason"]).is_empty()
	assert_int(db["bonus"]).is_greater_equal(CharacterRules.mod(int(r.character["abilities"]["dex"])) + int(r.character["prof_bonus"]))
	ExplorationRules.disarm_trap(s, "mine-gallery", ExplorationRules.trap_on_exit(s, world, "mine-gallery", "mine-deep"))
	assert_array(ExplorationRules.found_traps(s, world, "mine-gallery")).is_empty()


func test_a_found_cache_gives_its_loot_once() -> void:
	var s := _session()
	assert_array(ExplorationRules.take_caches(s, data, "mine-deep")).is_empty()
	s.revealed["mine-deep"] = ["wall"]
	var lines := ExplorationRules.take_caches(s, data, "mine-deep")
	assert_str(lines[0]).contains("Плащ, свойства неизвестны")  # magic comes unidentified (v0.7.12)
	assert_int(int(s.character["inventory"]["unk_cloak_of_protection"])).is_equal(1)
	assert_array(ExplorationRules.take_caches(s, data, "mine-deep")).is_empty()


func test_passive_perception_loses_the_darkness_penalty() -> void:
	var world: Dictionary = data["world"]
	var s := _session()
	s.character["passive_perception"] = 13
	assert_array(ExplorationRules.enter_room(s, world, "mine-gallery", 5)).is_empty()
	var t := _session()
	t.character["passive_perception"] = 13
	assert_array(ExplorationRules.enter_room(t, world, "mine-gallery", 0)).is_not_empty()


# --- magic items ----------------------------------------------------------------------------------


func test_a_plus_one_weapon_hits_and_hurts_harder() -> void:
	var s := _session()
	var c := s.character
	var plain := CombatRules.weapon_profile(c, data, s.items, "longsword")
	var magic := CombatRules.weapon_profile(c, data, s.items, "longsword_plus_1")
	assert_int(magic["to_hit"]).is_equal(int(plain["to_hit"]) + 1)
	assert_int(magic["bonus"]).is_equal(int(plain["bonus"]) + 1)
	assert_str(magic["dice"]).is_equal(plain["dice"])
	# A master-made item on a base works the same (it had no weapon block before v0.6.3).
	s.items["gen_x"] = {"name": "Клинок Ольшанки", "item_type": "weapon", "base": "longsword", "properties": ["magic_plus1"], "generated": true}
	assert_int(CombatRules.weapon_profile(c, data, s.items, "gen_x")["to_hit"]).is_equal(int(magic["to_hit"]))


func test_magic_armor_and_a_carried_cloak_raise_ac_and_saves() -> void:
	var s := _session()
	var c := s.character
	c["inventory"]["chain_mail"] = 1
	c["inventory"]["chain_mail_plus_1"] = 1
	c["equipped"]["armor"] = "chain_mail"
	CharacterRules.refresh(c, data, s.items)
	var ac := int(c["ac"])
	var save := int(c["saves"]["wis"])
	c["equipped"]["armor"] = "chain_mail_plus_1"
	CharacterRules.refresh(c, data, s.items)
	assert_int(int(c["ac"])).is_equal(ac + 1)
	c["inventory"]["cloak_of_protection"] = 1
	c["equipped"]["cloak"] = "cloak_of_protection"  # v0.7.22.9: a cloak works on the shoulders
	CharacterRules.refresh(c, data, s.items)
	assert_int(int(c["ac"])).is_equal(ac + 1)  # v0.7.12: the cloak works only when attuned
	c["attuned"] = ["cloak_of_protection"]
	CharacterRules.refresh(c, data, s.items)
	assert_int(int(c["ac"])).is_equal(ac + 2)
	assert_int(int(c["saves"]["wis"])).is_equal(save + 1)


func test_boots_of_elvenkind_give_advantage_on_stealth() -> void:
	var s := _session()
	s.character["equipped"]["armor"] = ""
	s.character["inventory"]["boots_of_elvenkind"] = 1
	s.character["equipped"]["feet"] = "boots_of_elvenkind"  # v0.7.22.9: boots work on the feet
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).contains("Сапоги эльфов")


func test_greater_healing_is_a_consumable() -> void:
	var s := _session()
	s.character["inventory"]["potion_of_greater_healing"] = 1
	s.character["hp"] = 1
	assert_str(ItemRules.can_use(s.character, data, s.items, "potion_of_greater_healing")).is_empty()
	ItemRules.use(s.character, data, s.items, "potion_of_greater_healing", s.rng)
	assert_int(int(s.character["hp"])).is_greater_equal(mini(9, int(s.character["max_hp"])))


# --- the pack and the save ------------------------------------------------------------------------


func test_a_quest_step_with_two_conditions_is_rejected() -> void:
	var b := WorldPack.load_bundle("res://data/worlds/frontier", "builtin")
	b["world"]["quests"]["drogin_amulet"]["steps"][0]["when"]["room"] = "mine-deep"
	assert_str("\n".join(WorldPack.validate(b, TestUtils.base()))).contains("drogin_amulet")


func test_the_new_state_survives_the_save_and_v10_migrates() -> void:
	var s := _session()
	s.minute = 1234
	s.quests_active = {"drogin_amulet": 1}
	s.traps = {"mine-gallery:deadfall": "disarmed"}
	s.caches_taken.append("mine-deep:wall")
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_int(back.minute).is_equal(1234)
	assert_int(int(back.quests_active["drogin_amulet"])).is_equal(1)
	assert_dict(back.traps).is_equal(s.traps)
	assert_array(back.caches_taken).contains(["mine-deep:wall"])
	var v10: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v10.json"))
	SaveFormat.migrate(v10, {})
	assert_int(int(v10["session"]["minute"])).is_equal(480)
	assert_dict(v10["session"]["quests_active"]).is_empty()
