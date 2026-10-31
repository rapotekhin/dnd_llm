extends GdUnitTestSuite
## Every scene under res://ui: it opens, has the nodes its script needs, and shows the game no examples (ADR-0013).


func _scenes(dir: String = "res://ui") -> Array[String]:
	var out: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_scenes(dir.path_join(sub)))
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() == "tscn":
			out.append(dir.path_join(f))
	return out


func test_every_scene_has_its_nodes() -> void:
	var scenes := _scenes()
	assert_bool(scenes.size() >= 3).is_true()
	for path: String in scenes:
		var root: Node = auto_free(UiScenes.open(path))
		assert_bool(root.has_method("required")).override_failure_message(path).is_true()
		var wanted: Dictionary = root.call("required")
		for node_path: String in wanted:
			var node := root.get_node_or_null(node_path)
			assert_object(node).override_failure_message("%s: %s" % [path, node_path]).is_not_null()
			assert_bool(node.is_class(wanted[node_path])).override_failure_message(node_path).is_true()


func test_examples_never_reach_the_game() -> void:
	for path: String in _scenes():
		var root: Node = auto_free(UiScenes.open(path))
		for node: Node in root.find_children("*", "", true, false):
			assert_bool(node.is_in_group(UiScenes.SAMPLE_GROUP)).override_failure_message(node.name).is_false()


func test_a_window_takes_its_title_and_width_from_the_scene() -> void:
	var window: FaithPanel = auto_free(UiScenes.open(FaithPanel.SCENE))
	add_child(window)
	assert_float(window.width).is_equal(720.0)
	assert_str(window.title.text).is_equal("FAITH_TITLE")
	assert_str(window.close_x.name).is_equal("CloseFaithButton")


func test_a_lost_node_is_a_stand_in() -> void:
	var frame: ModalFrame = auto_free(UiScenes.open(ModalFrame.FRAME_SCENE))
	var lost := frame.get_node("%ModalTitle")
	lost.get_parent().remove_child(lost)
	lost.free()
	frame.setup("Заголовок", 640.0)
	assert_str(frame.title.text).is_equal("Заголовок")
	assert_object(frame.title.get_parent()).is_same(frame)


func test_a_window_keeps_its_api() -> void:
	var frame: ModalFrame = auto_free(ModalFrame.make("Заголовок", 700.0))
	assert_str(frame.title.text).is_equal("Заголовок")
	assert_int(frame.body.get_child_count()).is_equal(0)
	assert_bool(frame.footer.visible).is_false()
	assert_bool(frame.note.visible).is_false()
	frame.add_button("Да", func() -> void: pass, true)
	assert_bool(frame.footer.visible).is_true()
	frame.set_note("Нельзя")
	assert_bool(frame.note.visible).is_true()


func test_the_project_theme_has_its_looks() -> void:
	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	for look: String in [UiTheme.TITLE, UiTheme.HEADING, UiTheme.MUTED_LABEL, UiTheme.WARN_LABEL, UiTheme.SIDE,
			UiTheme.ACCENT_BUTTON, UiTheme.DANGER_BUTTON, UiTheme.DM_TEXT + UiTheme.RICH]:
		assert_bool(not theme.get_type_variation_base(look).is_empty()).override_failure_message(look).is_true()
