extends GdUnitTestSuite
## Safety and keyboard (roadmap v0.7.22.27): keys as in BG3 from game.json with the player's own, a question before
## an irreversible act with «больше не показывать», the quick slot and the slot's preview.

var _keys: Dictionary
var _confirm: bool
var _path: String


func before_test() -> void:
	_keys = SaveManager.keys.duplicate()
	_confirm = SaveManager.confirm_risky
	_path = SaveManager.settings_path
	SaveManager.settings_path = "user://test_controls_settings.cfg"  # never the player's own settings


func after_test() -> void:
	SaveManager.keys = _keys
	SaveManager.confirm_risky = _confirm
	SaveManager.settings_path = _path
	DirAccess.remove_absolute("user://test_controls_settings.cfg")
	Hotkeys.apply(_keys)


func _pressed(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func test_keys_go_into_the_input_map_by_place() -> void:
	Hotkeys.apply({})
	assert_bool(_pressed(KEY_I).is_action("inventory")).is_true()
	assert_bool(_pressed(KEY_SPACE).is_action("end_turn")).is_true()
	assert_bool(_pressed(KEY_0).is_action("action_10")).is_true()
	Hotkeys.apply({"inventory": "B"})
	assert_bool(_pressed(KEY_B).is_action("inventory")).is_true()
	assert_bool(_pressed(KEY_I).is_action("inventory")).is_false()
	assert_str(Hotkeys.tip("Карта", "map", {})).is_equal("Карта [M]")


func test_a_key_of_the_same_place_clashes() -> void:
	assert_str(Hotkeys.clash("inventory", "M", {})).is_equal("map")
	assert_str(Hotkeys.clash("inventory", "Escape", {})).is_equal("pause_menu")  # Esc is everywhere
	assert_str(Hotkeys.clash("option_1", "1", {})).is_empty()  # the fight's «1» never meets the game screen's
	assert_str(Hotkeys.clash("end_turn", "1", {})).is_equal("action_1")


func test_the_question_runs_the_act_only_on_yes() -> void:
	SaveManager.confirm_risky = true
	var host := auto_free(Control.new()) as Control
	add_child(host)
	var done := [0]
	var box := ConfirmBox.ask(host, "Напасть?", "Это нападение.", "Напасть", func() -> void: done[0] += 1)
	await await_idle_frame()
	assert_bool(box.never.button_pressed).is_false()  # «больше не показывать» is off by default
	box.yes.pressed.emit()
	assert_int(done[0]).is_equal(1)
	assert_bool(SaveManager.confirm_risky).is_true()


func test_never_again_turns_the_questions_off() -> void:
	SaveManager.confirm_risky = true
	var host := auto_free(Control.new()) as Control
	add_child(host)
	var done := [0]
	var box := ConfirmBox.ask(host, "Добить?", "Это убийство.", "Добить", func() -> void: done[0] += 1)
	await await_idle_frame()
	box.never.button_pressed = true
	box.yes.pressed.emit()
	assert_bool(SaveManager.confirm_risky).is_false()
	ConfirmBox.ask(host, "Добить?", "Это убийство.", "Добить", func() -> void: done[0] += 1)  # no box now
	assert_int(done[0]).is_equal(2)


func test_no_on_the_question_does_nothing() -> void:
	SaveManager.confirm_risky = true
	var host := auto_free(Control.new()) as Control
	add_child(host)
	var done := [0]
	var box := ConfirmBox.ask(host, "Сдаться?", "Плен.", "Сдаться", func() -> void: done[0] += 1)
	await await_idle_frame()
	box.never.button_pressed = true
	(box.find_child("ConfirmNo", true, false) as Button).pressed.emit()
	assert_int(done[0]).is_equal(0)
	assert_bool(SaveManager.confirm_risky).is_true()  # «больше не показывать» counts only with «yes»


func test_the_quick_slot_and_the_preview() -> void:
	assert_array(SaveManager.all_slots()).contains([SaveManager.QUICKSAVE])
	assert_array(SaveManager.manual_slots()).not_contains([SaveManager.QUICKSAVE])  # «Сохранить» lists only the manual ones
	var s := TestUtils.new_session()
	s.day = 4
	var meta: Dictionary = SaveManager.build_save(s)["meta"]
	assert_int(int(meta["day"])).is_equal(4)
	assert_int(int(meta["level"])).is_equal(1)
	assert_str(str(meta["place"])).is_not_empty()
	assert_str(str(meta["class"])).is_not_empty()
