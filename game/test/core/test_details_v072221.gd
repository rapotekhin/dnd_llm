extends GdUnitTestSuite
## One description panel (roadmap v0.7.22.21, the author's fixes check #3, #20): hover shows, the right button pins and
## unpins, the lock unpins, a pin survives a rebuild of the rows; a spell's text names its school.


func _rmb(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c.gui_input.emit(ev)


func test_the_right_button_pins_and_unpins() -> void:
	var panel := auto_free(DetailsPanel.new()) as DetailsPanel
	var a := auto_free(Button.new()) as Button
	var b := auto_free(Button.new()) as Button
	panel.hook(a, "Щит", "КД +5")
	panel.hook(b, "Огненный снаряд", "1к10 огня")
	a.mouse_entered.emit()
	assert_str(panel.title()).is_equal("Щит")
	_rmb(a)
	assert_str(panel.pinned()).is_equal("Щит")
	assert_bool(a.modulate == Color.WHITE).is_false()
	b.mouse_entered.emit()
	assert_str(panel.title()).is_equal("Щит")  # pinned: hovering another does not change it
	_rmb(b)
	assert_str(panel.title()).is_equal("Огненный снаряд")  # the right button on another pins that one
	assert_bool(a.modulate == Color.WHITE).is_true()
	_rmb(b)
	assert_str(panel.pinned()).is_empty()  # on the pinned one again — unpinned
	a.mouse_entered.emit()
	assert_str(panel.title()).is_equal("Щит")


func test_the_lock_unpins_and_a_pin_survives_a_rebuild() -> void:
	var panel := auto_free(DetailsPanel.new()) as DetailsPanel
	var a := auto_free(Button.new()) as Button
	panel.hook(a, "Щит", "КД +5")
	_rmb(a)
	var again := auto_free(Button.new()) as Button
	panel.hook(again, "Щит", "КД +5")  # the rows were rebuilt
	assert_bool(again.modulate == Color.WHITE).is_false()
	(panel.find_child("DetailsUnpin", true, false) as Button).pressed.emit()
	assert_str(panel.pinned()).is_empty()
	assert_bool(again.modulate == Color.WHITE).is_true()


func test_a_spell_names_its_school() -> void:
	var data := TestUtils.data()
	assert_str(DetailsPanel.spell_text(data, "fire_bolt")).contains("Воплощение")
	assert_bool(UiTheme.SCHOOL_COLORS.has(str(data["spells"]["fire_bolt"]["school_id"]))).is_true()
