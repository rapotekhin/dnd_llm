extends GdUnitTestSuite
## SaveFormat: build, check (unreadable, too new, too old), the fixture of this version loads.

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


func test_only_this_version_loads() -> void:
	assert_str(SaveFormat.check({"save_version": SaveFormat.SAVE_VERSION - 1, "session": {}})).is_equal(SaveFormat.ERR_TOO_OLD)
	assert_str(SaveFormat.check({"save_version": SaveFormat.SAVE_VERSION, "session": {}})).is_empty()


func test_the_fixture_loads() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "save_v%d.json" % SaveFormat.SAVE_VERSION))
	assert_str(SaveFormat.check(data)).is_empty()
	var d := TestUtils.data()
	var s := GameSession.from_dict(data["session"])
	CharacterRules.refresh(s.character, d, s.items)
	assert_str(s.world_id).is_equal("frontier")
	assert_bool(d["world"]["rooms"].has(s.room_id)).is_true()
	assert_int(s.chat.size()).is_greater(0)
	assert_int(s.character["max_hp"]).is_greater(0)
	assert_str(s.character["class"]).is_not_empty()


## The newest fixture is the save of a fresh start session with a short chat; regenerate it only on purpose.
func test_current_fixture_matches_the_current_layout() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "save_v%d.json" % SaveFormat.SAVE_VERSION))
	var fresh := SaveFormat.build(TestUtils.session_with_chat(), "0.5.0", "2026-10-18T12:00:00", 500)
	assert_array(data["session"].keys()).contains_exactly_in_any_order(fresh["session"].keys())
	assert_array(data["session"]["beings"]["p"]["sheet"].keys()).contains_exactly_in_any_order(fresh["session"]["beings"]["p"]["sheet"].keys())
