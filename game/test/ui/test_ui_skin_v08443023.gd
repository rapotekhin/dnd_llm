extends GdUnitTestSuite
## v0.8.4.43.23: the interface's frames drawn in the lines style are laid over the theme as StyleBoxTexture by the rows
## of `frames` (data/icons.json); the content margins stay those of the flat style, and a file not drawn — the art is not
## in git — leaves the flat style as it was.


func _frames() -> Dictionary:
	return Catalog.load_all()["icons"]["frames"]


func test_every_slot_names_a_file_and_every_file_a_part() -> void:
	var f := _frames()
	for slot: String in f["slots"]:
		assert_bool(f["files"].has(str(f["slots"][slot]))).override_failure_message(slot).is_true()
		assert_bool(slot.contains("/")).is_true()
	for file: String in f["files"]:
		assert_bool(f["parts"].has(str(f["files"][file]["part"]))).override_failure_message(file).is_true()


func test_a_frame_keeps_its_corners_and_the_flat_styles_margins() -> void:
	var img := Image.create(100, 40, false, Image.FORMAT_RGBA8)
	var flat := StyleBoxFlat.new()
	flat.set_content_margin_all(10)
	flat.content_margin_left = 14
	var b := UiTheme.frame_box(ImageTexture.create_from_image(img), {"cut": 76, "scale": 0.15}, flat)
	assert_float(b.texture_margin_left).is_equal(11.0)  # 76 drawn px at 0.15
	assert_float(b.texture_margin_bottom).is_equal(11.0)
	assert_float(b.content_margin_left).is_equal(14.0)
	assert_float(b.content_margin_top).is_equal(10.0)
	var card := UiTheme.frame_box(ImageTexture.create_from_image(img), {"cut": 40, "scale": 0.4, "pad": 6}, flat)
	assert_float(card.content_margin_top).is_equal(16.0)  # the card's line stands 7 px inside: the text keeps off it


func test_no_drawn_file_leaves_the_flat_style() -> void:
	var theme := Theme.new()
	var flat := StyleBoxFlat.new()
	theme.set_stylebox("normal", "Button", flat)
	var f := _frames().duplicate(true)
	f["root"] = "res://no_such_folder/"
	assert_int(UiTheme.skin(theme, f)).is_equal(0)
	assert_object(theme.get_stylebox("normal", "Button")).is_same(flat)
	assert_object(UiTheme.frame({}, "button")).is_null()


func test_a_variation_takes_the_margins_of_its_base() -> void:
	var theme := Theme.new()
	var flat := StyleBoxFlat.new()
	flat.set_content_margin_all(9)
	theme.set_stylebox("hover", "Button", flat)
	theme.set_type_variation("AccentButton", "Button")
	assert_object(UiTheme._style_of(theme, "hover", "AccentButton")).is_same(flat)
