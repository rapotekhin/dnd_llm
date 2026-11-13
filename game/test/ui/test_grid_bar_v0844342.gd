extends GdUnitTestSuite
## v0.8.4.43.42, the author: «в торговле боковые колонки узкие: значки фильтров переносятся в три ряда, а поле поиска
## обрезано» — a grid of things too narrow for its filters beside the search puts them on a line of their own with the
## search, the sort and its order under them; a wide one keeps them in one row by their share of the width.

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
	GameState.session = s


func after_test() -> void:
	GameState.session = kept


## Things of the catalog of many groups, one of each.
func _things(n: int) -> Dictionary:
	var out := {}
	for id: String in data["items"]["catalog"]:
		if out.size() < n and not str(data["items"]["catalog"][id].get("name", "")).is_empty():
			out[id] = 1
	return out


func _grid(width: float) -> ItemGrid:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var grid := ItemGrid.new("Inv", "Item_", 6)
	host.add_child(grid)
	grid.size = Vector2(width, 600)
	grid.show_items(_things(200))
	return grid


func _settle() -> void:
	for i in 3:
		await await_idle_frame()


func _icons(grid: ItemGrid) -> Array[Node]:
	return (grid.find_child("InvFilters", true, false) as Control).get_children()


func _beside(grid: ItemGrid) -> bool:
	return grid.find_child("InvControls", true, false).get_parent() != grid.find_child("InvBar", true, false)


func test_a_narrow_grid_puts_the_search_under_its_filters() -> void:
	var grid := _grid(340)
	await _settle()
	assert_int(_icons(grid).size()).is_greater(3)
	assert_bool(_beside(grid)).override_failure_message("the search beside the filters in 340 px").is_false()
	var filters := grid.find_child("InvFilters", true, false) as Control
	var search := grid.find_child("InvSearch", true, false) as Control
	assert_float(search.get_global_rect().position.y).is_greater_equal(filters.get_global_rect().end.y)
	assert_float(search.size.x).is_greater_equal(120.0)
	assert_float(grid.get_combined_minimum_size().x).is_less_equal(340.0)  # the window not widened by the row


func test_a_wide_grid_keeps_them_in_one_row_with_no_icon_wrapped() -> void:
	var grid := _grid(900)
	await _settle()
	assert_bool(_beside(grid)).override_failure_message("the search under the filters in 900 px").is_true()
	var ys := {}
	for b: Node in _icons(grid):
		ys[int((b as Control).global_position.y)] = true
	assert_int(ys.size()).override_failure_message("the filters wrapped onto %d lines" % ys.size()).is_equal(1)
	var search := grid.find_child("InvSearch", true, false) as Control
	var first := _icons(grid)[0] as Control
	assert_float(absf(search.get_global_rect().position.y - first.get_global_rect().position.y)).is_less(first.size.y)


## In one line the filters take their share of the width, not a minimum: the row never holds the grid wider than a
## line of its own would (the cells' columns are another matter: they follow the width the window gives).
func test_the_row_in_one_line_does_not_hold_the_grid_wide() -> void:
	var grid := _grid(900)
	await _settle()
	assert_bool(_beside(grid)).is_true()
	var widest := 0.0  # the filters' own minimum: one icon, they may wrap
	for b: Node in _icons(grid):
		widest = maxf(widest, (b as Control).get_combined_minimum_size().x)
	var most := (grid.find_child("InvControls", true, false) as Control).get_combined_minimum_size().x + 4.0 + widest
	var bar := grid.find_child("InvBar", true, false) as Control
	assert_float(bar.get_combined_minimum_size().x).override_failure_message("the row's minimum %d past %d" % [bar.get_combined_minimum_size().x, most]).is_less_equal(most + 1.0)
