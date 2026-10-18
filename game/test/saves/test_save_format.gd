extends GdUnitTestSuite
## SaveFormat: build, check (unreadable / too new), migrations step by step, fixtures of every version load.

const FIXTURES := "res://test/fixtures/saves/"


func test_build_has_version_meta_and_session() -> void:
	var data := SaveFormat.build(TestUtils.session_with_chat(), "0.4.0", "2026-10-18T12:00:00", 500)
	assert_int(data["save_version"]).is_equal(SaveFormat.SAVE_VERSION)
	assert_str(data["game_version"]).is_equal("0.4.0")
	assert_int(data["meta"]["turns"]).is_equal(2)
	assert_str(SaveFormat.check(data)).is_empty()


func test_check_rejects_garbage_and_newer_saves() -> void:
	assert_str(SaveFormat.check(null)).is_equal(SaveFormat.ERR_UNREADABLE)
	assert_str(SaveFormat.check({"save_version": 1})).is_equal(SaveFormat.ERR_UNREADABLE)
	assert_str(SaveFormat.check({"save_version": 0, "session": {}})).is_equal(SaveFormat.ERR_UNREADABLE)
	assert_str(SaveFormat.check({"save_version": SaveFormat.SAVE_VERSION + 1, "session": {}})).is_equal(SaveFormat.ERR_TOO_NEW)


func test_migrate_runs_each_step_in_order() -> void:
	var data := {"save_version": SaveFormat.SAVE_VERSION, "session": {}}
	SaveFormat.migrate(data)
	assert_int(data["save_version"]).is_equal(SaveFormat.SAVE_VERSION)
	# A save one version behind gets exactly the one step.
	var steps: Array[int] = []
	var saved := SaveFormat.MIGRATIONS.duplicate()
	SaveFormat.MIGRATIONS[SaveFormat.SAVE_VERSION - 1] = func(d: Dictionary, _ctx: Dictionary) -> void:
		steps.append(SaveFormat.SAVE_VERSION - 1)
		d["session"]["migrated"] = true
	var old := {"save_version": SaveFormat.SAVE_VERSION - 1, "session": {}}
	SaveFormat.migrate(old)
	assert_array(steps).is_equal([SaveFormat.SAVE_VERSION - 1])
	assert_int(old["save_version"]).is_equal(SaveFormat.SAVE_VERSION)
	assert_bool(old["session"]["migrated"]).is_true()
	SaveFormat.MIGRATIONS = saved


func test_every_fixture_loads() -> void:
	var files := Array(DirAccess.get_files_at(FIXTURES)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	assert_array(files).is_not_empty()
	var d := TestUtils.data()
	for f: String in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + f))
		assert_str(SaveFormat.check(data)).override_failure_message(f).is_empty()
		SaveFormat.migrate(data, _ctx())
		var s := GameSession.from_dict(data["session"])
		CharacterRules.refresh(s.character, d, s.items)
		assert_str(s.world_id).override_failure_message(f).is_equal("frontier")
		assert_bool(d["world"]["rooms"].has(s.room_id)).override_failure_message(f).is_true()
		assert_int(s.chat.size()).override_failure_message(f).is_greater(0)
		assert_str(s.room_id).override_failure_message(f).is_not_empty()
		assert_int(s.character["max_hp"]).override_failure_message(f).is_greater(0)
		assert_str(s.character["class"]).override_failure_message(f).is_not_empty()


## Saves before v3 had no character sheet: they are refused with a clear message (decision of v0.5.0).
func test_saves_before_v3_are_refused() -> void:
	for f: String in ["save_v1.json", "save_v2.json"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves_old/" + f))
		assert_str(SaveFormat.check(data)).override_failure_message(f).is_equal(SaveFormat.ERR_TOO_OLD)


func _ctx() -> Dictionary:
	return {"world": WorldPack.load_bundle("res://data/worlds/frontier", "builtin")}


## A 0.5.0 game (prototype tavern) keeps the character and the chat and starts over in the start pack.
func test_v3_save_moves_into_the_start_world() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "save_v3.json"))
	var chat_before: int = data["session"]["chat"].size()
	SaveFormat.migrate(data, _ctx())
	assert_int(data["save_version"]).is_equal(SaveFormat.SAVE_VERSION)
	var s := GameSession.from_dict(data["session"])
	assert_str(s.world_id).is_equal("frontier")
	assert_str(s.room_id).is_equal(TestUtils.START_ROOM)
	assert_str(s.settings["dm_style"]).is_equal("classic")
	assert_str(s.character["name"]).is_equal("Айра")
	assert_int(s.chat.size()).is_equal(chat_before)
	assert_dict(s.attitudes).is_empty()


## The newest fixture is the save of a fresh start session with a short chat; regenerate it only on purpose.
func test_current_fixture_matches_the_current_layout() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "save_v%d.json" % SaveFormat.SAVE_VERSION))
	var fresh := SaveFormat.build(TestUtils.session_with_chat(), "0.5.0", "2026-10-18T12:00:00", 500)
	assert_array(data["session"].keys()).contains_exactly_in_any_order(fresh["session"].keys())
	assert_array(data["session"]["character"].keys()).contains_exactly_in_any_order(fresh["session"]["character"].keys())
