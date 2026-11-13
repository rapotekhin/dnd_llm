extends GdUnitTestSuite
## v0.8.4.43.38, the author: «есть тесты что будет, если у нас больше предметов чем ячеек в сетке? И тоже самое про
## заклинания и умения?» — more things, spells, features or hotbar cells than a grid has room for: every one of them is
## there, the list grows by rows and scrolls, the window stays on the screen; a few things leave empty cells down to the
## list's bottom (the trade, «сетку предметов вниз продлить»).

var data: Dictionary
var kept: GameSession


func before_test() -> void:
	data = TestUtils.data()
	kept = GameState.session
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "sorcerer_zlata":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	GameState.session = s


func after_test() -> void:
	GameState.session = kept


## `n` things of the catalog, one of each.
func _things(n: int) -> Dictionary:
	var out := {}
	for id: String in data["items"]["catalog"]:
		if out.size() < n and not str(data["items"]["catalog"][id].get("name", "")).is_empty():
			out[id] = 1
	return out


## A grid of things in a box of `box` pixels, its things shown.
func _grid(box: Vector2, inv: Dictionary) -> ItemGrid:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var grid := ItemGrid.new("Inv", "Item_", 6)
	host.add_child(grid)
	grid.size = box
	grid.show_items(inv)
	return grid


func _sheet() -> CharacterSheet:
	var sheet: CharacterSheet = auto_free(UiScenes.open(CharacterSheet.SCENE))
	add_child(sheet)
	return sheet


## The window's frame stays on the screen whatever it holds.
func _on_screen(sheet: CharacterSheet) -> void:
	var panel := sheet.get("_panel") as Control
	var screen := sheet.get_viewport_rect()
	assert_bool(screen.encloses(panel.get_global_rect())).override_failure_message("%s past %s" % [panel.get_global_rect(), screen]).is_true()


func test_more_things_than_cells_grow_the_grid_by_rows_and_scroll() -> void:
	var inv := _things(60)
	var grid := _grid(Vector2(480, 420), inv)
	await await_idle_frame()
	await await_idle_frame()
	var cells := grid.find_child("InvCells", true, false) as GridContainer
	assert_int(cells.get_children().filter(func(c: Node) -> bool: return c is ItemCell).size()).is_equal(inv.size())
	for id: String in inv:
		assert_object(cells.get_node_or_null("Item_" + id)).override_failure_message(id).is_not_null()
	assert_int(cells.get_child_count() % cells.columns).is_equal(0)  # whole rows
	var list := grid.find_child("InvList", true, false) as ScrollContainer
	assert_float(list.custom_minimum_size.y).is_equal(grid.min_rows * (grid.cell_side + 4.0))  # the window does not grow
	assert_float(cells.get_combined_minimum_size().y).is_greater(list.size.y)  # the rest a scroll away


func test_a_few_things_leave_empty_cells_down_to_the_list_s_bottom() -> void:
	var grid := _grid(Vector2(480, 760), _things(3))
	await await_idle_frame()
	await await_idle_frame()
	var cells := grid.find_child("InvCells", true, false) as GridContainer
	var list := grid.find_child("InvList", true, false) as ScrollContainer
	var rows := cells.get_child_count() / cells.columns
	assert_int(rows).is_equal(int((list.size.y + 4.0) / (grid.cell_side + 4.0)))
	assert_int(rows).is_greater(grid.min_rows)
	assert_float(cells.get_combined_minimum_size().y).is_less_equal(list.size.y)  # no scroll for nothing


func test_more_things_than_the_inventory_holds_keep_the_window_on_the_screen() -> void:
	var added := _things(90)
	for id: String in added:
		GameState.session.character["inventory"][id] = 1
	var sheet := _sheet()
	sheet.open_tab(0)
	await await_idle_frame()
	await await_idle_frame()
	var grid := sheet.find_child("InvGrid", true, false) as ItemGrid
	var cells := sheet.find_child("InvCells", true, false) as GridContainer
	assert_int(cells.get_children().filter(func(c: Node) -> bool: return c is ItemCell).size()).is_equal(grid.shown.size())
	assert_int(grid.shown.size()).is_greater_equal(added.size())  # what is worn is on the doll, the rest all here
	_on_screen(sheet)


func test_more_spells_than_a_row_wrap_and_the_book_scrolls() -> void:
	var c := GameState.session.character
	var many: Array = []
	for id: String in data["spells"]:
		var lv := SpellRules.level_of(data, id)
		if lv >= 1 and lv <= 5:  # every spell of the circles the book shows
			many.append(id)
	c["spells"]["known"] = many
	var sheet := _sheet()
	sheet.open_tab(1)
	await await_idle_frame()
	await await_idle_frame()
	for id: String in many:
		assert_object(sheet.find_child("Spell_" + id, true, false)).override_failure_message(id).is_not_null()
	var flow := (sheet.find_child("Circle_1", true, false) as Node).get_child(1) as HFlowContainer
	var lines := {}
	for cell: Control in flow.get_children():
		lines[int(cell.position.y)] = true
	assert_int(lines.size()).is_greater(1)  # the circle's spells wrap onto more lines, never widen the window
	var book := sheet.find_child("BookPage", true, false) as ScrollContainer
	assert_float(book.get_v_scroll_bar().max_value).is_greater(book.size.y)  # the rest a scroll away
	_on_screen(sheet)


func test_more_features_than_the_column_holds_scroll_in_it() -> void:
	var c := GameState.session.character
	var ids: Array = []
	for id: String in data["classes"]["features"]:
		if ids.size() < 40 and not (data["classes"]["features"][id] as Dictionary).has("options"):
			ids.append(id)
	c["features"] = ids
	var sheet := _sheet()
	sheet.open_tab(0)
	await await_idle_frame()
	await await_idle_frame()
	for id: String in ids:
		assert_object(sheet.find_child("Feature_" + id, true, false)).override_failure_message(id).is_not_null()
	var page := sheet.find_child("SheetPage", true, false) as ScrollContainer
	assert_float(page.get_v_scroll_bar().max_value).is_greater(page.size.y)
	_on_screen(sheet)


func test_more_cells_than_the_bar_has_room_for_keep_every_one_a_wheel_away() -> void:
	var st := {}
	var cells := {}
	for i in 30:
		cells["spell:s%d" % i] = "class"
	var out := HotbarLayout.place(st, HotbarLayout.BAR, cells, 4, "peace")
	assert_int(int(out[0]["cols"])).is_equal(4)
	var slots: Array = out[0]["slots"]
	for k: String in cells:
		assert_bool(slots.has(k)).override_failure_message(k).is_true()
	assert_int(slots.size()).is_equal(32)  # 8 rows of 4: the bar shows its 2, the rest a wheel away
