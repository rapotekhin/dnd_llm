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
