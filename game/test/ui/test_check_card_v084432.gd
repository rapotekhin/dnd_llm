extends GdUnitTestSuite
## v0.8.4.43.2: what a check found wraps inside the chat's column. A fixed 520 px under a narrower chat sent the chat's
## scroll into a layout loop and Godot down (signal 11, the «unseen» playtest after a Perception check at the gate).


func test_a_found_thing_asks_no_width_of_its_own() -> void:
	var card: CheckCard = auto_free(CheckCard.new({"skill": "perception", "nat": 16, "bonus": 3, "total": 19, "dc": 15,
		"success": true, "revealed": ["царапины на воротах шли снизу вверх: зверь стоял на задних лапах и был выше человека"]}))
	add_child(card)
	assert_int(card.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	var found: Label = card.get_child(0).get_child(1)
	assert_float(found.get_combined_minimum_size().x).is_less(100.0)  # it wraps to what the chat gives


func test_a_plain_check_stays_its_own_size() -> void:
	var card: CheckCard = auto_free(CheckCard.new({"skill": "perception", "nat": 4, "bonus": 3, "total": 7, "dc": 15, "success": false}))
	add_child(card)
	assert_int(card.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
