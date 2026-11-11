extends GdUnitTestSuite
## The description as a card at the cursor (v0.8.4.43.3, as in BG3): a floating panel takes no place in its column,
## shows only a text with a body, takes no click until pinned by the right button, then holds with its lock.


func _rmb(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c.gui_input.emit(ev)


func _card() -> DetailsPanel:
	var card := DetailsPanel.new(Vector2(0, 120), true)
	add_child(card)
	return auto_free(card) as DetailsPanel


func test_a_card_is_no_part_of_its_column_and_hides_a_hint() -> void:
	var card := _card()
	assert_bool(card.top_level).is_true()
	assert_bool(card.visible).is_false()
	card.show_text("Подсказка", "")  # a hint without a body: nothing at the cursor
	assert_bool(card.visible).is_false()
	card.show_text("Щит", "КД +5")
	assert_bool(card.visible).is_true()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)  # the cursor reaches what is under it


func test_the_right_button_pins_the_card_and_the_lock_lets_it_go() -> void:
	var card := _card()
	var a := Button.new()
	add_child(a)
	auto_free(a)
	card.hook(a, "Щит", "КД +5")
	_rmb(a)
	assert_str(card.pinned()).is_equal("Щит")
	assert_bool(card.visible).is_true()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)  # pinned: its text is selected and scrolled
	var lock := card.find_child("DetailsUnpin", true, false) as Button
	assert_bool(lock.visible).is_true()
	lock.pressed.emit()
	assert_str(card.pinned()).is_empty()
	assert_bool(lock.visible).is_false()


func test_a_docked_panel_stays_in_its_column() -> void:
	var panel := auto_free(DetailsPanel.new()) as DetailsPanel
	assert_bool(panel.top_level).is_false()
	assert_bool(panel.floating).is_false()
