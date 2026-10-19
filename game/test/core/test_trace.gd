extends GdUnitTestSuite
## The session trace (v0.7.1): the state digest and the screen a control belongs to.


func test_the_digest_holds_what_a_playtest_review_needs() -> void:
	var s := TestUtils.new_session()
	var d: Dictionary = Trace._digest(s)
	for k: String in ["room", "day", "minute", "mode", "hp", "gold_cp", "xp", "level", "quests", "inventory", "sneaking"]:
		assert_bool(d.has(k)).is_true()


func test_a_control_is_traced_with_its_screen() -> void:
	var panel := TheftPanel.new()
	var b := Button.new()
	panel.add_child(b)
	assert_str(Trace._screen_of(b)).is_equal("TheftPanel")
	panel.free()


## The click must precede its consequences in the trace: the screen's own `pressed` handler runs first.
func test_a_click_is_written_before_what_it_causes() -> void:
	var path := "user://test_trace_order.jsonl"
	Trace._file = FileAccess.open(path, FileAccess.WRITE)
	var b := Button.new()
	b.text = "Go"
	b.pressed.connect(func() -> void: Trace._write({"ev": "chat", "entry": {"kind": "dm", "text": "done"}}))
	add_child(b)
	b.button_down.emit()
	b.pressed.emit()
	Trace._close()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert_int(lines.size()).is_equal(2)
	assert_str(str(JSON.parse_string(lines[0])["ev"])).is_equal("click")
	assert_str(str(JSON.parse_string(lines[1])["ev"])).is_equal("chat")
	b.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
