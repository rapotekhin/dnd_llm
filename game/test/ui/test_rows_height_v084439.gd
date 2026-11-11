extends GdUnitTestSuite
## The ways out under «Выходы ▾» (the author's finding on 0.8.4.43.8, v0.8.4.43.9): up to five seen at once, sized by the
## rows as they are drawn — a fixed 38 px a row showed two and a half of three.


func _list(n: int) -> VBoxContainer:
	var list: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(list)
	for i in n:
		var b := Button.new()
		b.text = "→ Тёмная лощина %d" % i
		b.custom_minimum_size = Vector2(300, 34)
		list.add_child(b)
	return list


func test_every_row_fits_up_to_the_limit() -> void:
	var list := _list(3)
	var row := (list.get_child(0) as Control).get_combined_minimum_size().y
	var sep := list.get_theme_constant("separation")
	assert_float(UiParts.rows_height(list, SidePanel.EXITS_SHOWN)).is_equal(row * 3 + sep * 2)
	assert_float(row).is_greater_equal(34.0)  # the button's own font and margins, not a guess


func test_more_than_the_limit_scroll_under_five() -> void:
	var list := _list(8)
	var row := (list.get_child(0) as Control).get_combined_minimum_size().y
	var sep := list.get_theme_constant("separation")
	assert_int(SidePanel.EXITS_SHOWN).is_equal(5)
	assert_float(UiParts.rows_height(list, SidePanel.EXITS_SHOWN)).is_equal(row * 5 + sep * 4)
	assert_float(UiParts.rows_height(_list(0), SidePanel.EXITS_SHOWN)).is_equal(0.0)
