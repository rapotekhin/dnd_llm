extends GdUnitTestSuite
## v0.8.4.44.5, the window of a screen of teaching (HintBox): no «✕»; «Продолжить», or «Проснуться» alone for the dream's
## end; the window never covers what its arrow points to.


func _box(row: Dictionary, at: Rect2) -> HintBox:
	var box: HintBox = auto_free(UiScenes.open(HintBox.SCENE))
	box.row = row
	box.set("_aim", func() -> Rect2: return at)
	add_child(box)
	box.size = Vector2(1600, 900)
	return box


func test_continue_or_wake_and_no_cross() -> void:
	var box := _box({"id": "a", "title": "Ходьба", "text": "Щёлкните по карте."}, Rect2())
	await await_idle_frame()
	assert_bool(box.close_x.visible).is_false()
	assert_str(box.title.text).is_equal("Ходьба")
	assert_bool((box.find_child("HintContinue", true, false) as Button).visible).is_true()
	assert_bool((box.find_child("WakeButton", true, false) as Button).visible).is_false()
	var wake := _box({"id": HintRules.WAKE, "text": "Проснитесь.", "button": HintRules.WAKE}, Rect2())
	await await_idle_frame()
	assert_bool((wake.find_child("HintContinue", true, false) as Button).visible).is_false()
	assert_bool((wake.find_child("WakeButton", true, false) as Button).visible).is_true()


func test_the_window_leaves_its_target_in_sight() -> void:
	var at := Rect2(700, 380, 200, 140)  # just where a centred window would stand
	var box := _box({"id": "a", "text": "Нажмите сюда."}, at)
	for i in 6:
		await await_idle_frame()
	var panel := box.find_child("ModalPanel", true, false) as Control
	var shown := Rect2(panel.position, panel.size)
	assert_bool(box.target().has_area()).is_true()
	assert_bool(shown.intersects(box.target().grow(HintBox.PAD))).is_false()
	assert_bool(Rect2(Vector2.ZERO, box.size).encloses(shown)).is_true()
	var done := [false]
	box.done.connect(func() -> void: done[0] = true)
	(box.find_child("HintContinue", true, false) as Button).pressed.emit()
	assert_bool(done[0]).is_true()
