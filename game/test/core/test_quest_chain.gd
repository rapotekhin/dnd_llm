extends GdUnitTestSuite
## The captain's chain (roadmap v0.6.4): a step of two parts in any order, a report that opens the burrow, the finale
## encounter, the choice at the menhir (both branches), closed exits, the pack checks and the save.

const QID := "ash_over_the_march"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func _taken() -> GameSession:
	var s := _session()
	s.room_id = "brod-gate"
	QuestRules.accept(s, data, QID)
	return s


func test_the_burrow_opens_by_the_found_burrow_or_the_report() -> void:
	var world: Dictionary = data["world"]
	var s := _session()
	assert_array(ExplorationRules.open_exits(s, world, "pushcha-hollow")).not_contains(["pushcha-burrow"])
	s.revealed["pushcha-hollow"] = ["burrow"]
	assert_array(ExplorationRules.open_exits(s, world, "pushcha-hollow")).contains(["pushcha-burrow"])
	var t := _session()
	t.flags.append("burrow_known")
	assert_array(ExplorationRules.open_exits(t, world, "pushcha-hollow")).contains(["pushcha-burrow"])


func test_the_master_cannot_move_through_a_closed_exit() -> void:
	var s := _session()
	s.room_id = "pushcha-hollow"
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "move", "room_id": "pushcha-burrow"})
	assert_bool(r["accepted"]).is_false()


func test_the_two_parts_close_in_any_order_and_are_announced_once() -> void:
	var world: Dictionary = data["world"]
	var s := _taken()
	assert_str(QuestRules.step_text(s, world, QID)).contains("склеп Серой заставы")
	s.encounters_done.append("deep_ghoul")  # the mine first
	var lines := QuestRules.advance(s, data)
	assert_str("\n".join(lines)).contains("старая выработка шахты — сделано")
	assert_int(int(s.quests_active[QID])).is_equal(0)
	assert_str(QuestRules.step_text(s, world, QID)).contains("✓ старая выработка шахты")
	assert_array(QuestRules.advance(s, data)).is_empty()  # announced once
	s.encounters_done.append("crypt_commandant")
	lines = QuestRules.advance(s, data)
	assert_str("\n".join(lines)).contains("склеп Серой заставы — сделано")
	assert_int(int(s.quests_active[QID])).is_equal(1)
	assert_dict(s.quest_parts).is_empty()


func test_the_report_opens_the_burrow_and_the_finale_closes_the_step() -> void:
	var world: Dictionary = data["world"]
	var s := _taken()
	s.encounters_done.append_array(["crypt_commandant", "deep_ghoul"])
	QuestRules.advance(s, data)
	assert_str(QuestRules.can_talk(s, world, QID)).is_empty()  # the captain is at the gate
	var gold := int(s.character["gold_cp"])
	QuestRules.talk(s, data, QID)
	assert_bool(s.flags.has("burrow_known")).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 3000)
	assert_int(s.attitude("npc_captain")).is_equal(1)
	assert_array(ExplorationRules.open_exits(s, world, "pushcha-hollow")).contains(["pushcha-burrow"])
	s.encounters_done.append("burrow_priest")
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[QID])).is_equal(3)
	s.room_id = "brod-gate"
	assert_array(QuestRules.choices_here(s, world)).is_empty()
	s.room_id = "pushcha-glade"
	assert_array(QuestRules.choices_here(s, world)).is_empty()  # the stone not understood yet (v0.7.22.13)
	s.revealed["pushcha-glade"] = ["runes"]
	assert_array(QuestRules.choices_here(s, world)).has_size(2)


func _at_the_menhir() -> GameSession:
	var s := _taken()
	s.encounters_done.append_array(["crypt_commandant", "deep_ghoul"])
	QuestRules.advance(s, data)
	QuestRules.talk(s, data, QID)
	s.encounters_done.append("burrow_priest")
	QuestRules.advance(s, data)
	s.room_id = "pushcha-glade"
	s.revealed["pushcha-glade"] = ["runes"]  # the stone understood (v0.7.22.13)
	return s


func test_restoring_the_menhir_blesses_and_the_captain_pays_at_the_end() -> void:
	var world: Dictionary = data["world"]
	var s := _at_the_menhir()
	assert_str(QuestRules.can_choose(s, world, QID, "restore")).is_empty()
	var lines := QuestRules.choose(s, data, QID, "restore")
	assert_str(lines[0]).contains("Восстановить")
	assert_bool(s.flags.has("menhir_restored")).is_true()
	assert_int(int(s.character["inventory"]["potion_of_greater_healing"])).is_equal(2)
	assert_int(s.attitude("npc_hermit")).is_equal(2)
	assert_array(QuestRules.choices_here(s, world)).is_empty()
	s.room_id = "brod-gate"
	var gold := int(s.character["gold_cp"])
	QuestRules.talk(s, data, QID)
	assert_bool(s.quests_done.has(QID)).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 5000)


func test_taking_the_power_gives_the_dagger_and_cools_the_hermit() -> void:
	var s := _at_the_menhir()
	QuestRules.choose(s, data, QID, "power")
	assert_bool(s.flags.has("menhir_power")).is_true()
	assert_bool(s.flags.has("menhir_restored")).is_false()
	assert_int(int(s.character["inventory"]["dagger_plus_1"])).is_equal(1)
	assert_int(s.attitude("npc_hermit")).is_equal(-2)
	assert_int(s.attitude("npc_priestess")).is_equal(-1)


func test_a_choice_step_without_choices_is_rejected() -> void:
	var b := WorldPack.load_bundle("res://data/worlds/frontier", "builtin")
	(b["world"]["quests"][QID]["steps"][3] as Dictionary).erase("choices")
	assert_str("\n".join(WorldPack.validate(b, TestUtils.base()))).contains(QID)
	var c := WorldPack.load_bundle("res://data/worlds/frontier", "builtin")
	c["world"]["rooms"]["pushcha-hollow"]["closed_exits"]["pushcha-burrow"]["when"] = {"talk": "npc_hermit"}
	assert_str("\n".join(WorldPack.validate(c, TestUtils.base()))).contains("closed_exits")


func test_quest_parts_survive_the_save_and_v11_migrates() -> void:
	var s := _taken()
	s.encounters_done.append("deep_ghoul")
	QuestRules.advance(s, data)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_array(back.quest_parts[QID]).is_equal([1])
	var v11: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v11.json"))
	SaveFormat.migrate(v11, {})
	assert_dict(v11["session"]["quest_parts"]).is_empty()
