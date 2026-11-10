extends GdUnitTestSuite
## v0.8.4.43: the hotbar as in BG3 — cells go into their kind's section, stay where they were dragged, come back to
## their slot, leave the bar when dragged off; the dividers move columns between sections.


func _keys(sec: Dictionary) -> Array:
	return (sec["slots"] as Array).filter(func(k: String) -> bool: return k != "")


func test_new_cells_go_to_their_kind() -> void:
	var st := {}
	var out := HotbarLayout.place(st, "fight", {"Do_dash": "common", "Cast_fire_bolt": "class", "Item_potion": "items"}, 12)
	assert_int(out.size()).is_equal(3)
	assert_array(_keys(out[0])).contains_exactly(["Do_dash"])
	assert_array(_keys(out[1])).contains_exactly(["Cast_fire_bolt"])
	var cols := 0
	for sec: Dictionary in out:
		cols += int(sec["cols"])
		assert_int((sec["slots"] as Array).size()).is_equal(int(sec["cols"]) * 2)  # two rows of slots, empty ones too
	assert_int(cols).is_equal(12)  # the whole bar


func test_a_moved_cell_stays_and_swaps() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Do_dodge": "common", "Cast_fire_bolt": "class"}
	HotbarLayout.place(st, "fight", cells, 10)
	HotbarLayout.move(st, "fight", "Cast_fire_bolt", 0, 0)  # onto the dash
	var out := HotbarLayout.place(st, "fight", cells, 10)
	assert_str(str(out[0]["slots"][0])).is_equal("Cast_fire_bolt")
	assert_bool((out[1]["slots"] as Array).has("Do_dash")).is_true()  # the dash went where the bolt was


func test_an_absent_act_keeps_its_slot() -> void:
	var st := {}
	HotbarLayout.place(st, "fight", {"Do_dash": "common", "Item_scroll": "items"}, 8)
	var out := HotbarLayout.place(st, "fight", {"Do_dash": "common"}, 8)
	assert_int(out.size()).is_equal(1)  # no items now — no section
	out = HotbarLayout.place(st, "fight", {"Do_dash": "common", "Item_scroll": "items"}, 8)
	assert_str(str(out[1]["slots"][0])).is_equal("Item_scroll")


func test_a_hidden_cell_is_off_until_dragged_back() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class"}
	HotbarLayout.place(st, "fight", cells, 8)
	HotbarLayout.hide(st, "fight", "Cast_fire_bolt")
	var out := HotbarLayout.place(st, "fight", cells, 8)
	assert_int(out.size()).is_equal(1)
	HotbarLayout.move(st, "fight", "Cast_fire_bolt", 0, 3)
	out = HotbarLayout.place(st, "fight", cells, 8)
	assert_str(str(out[0]["slots"][3])).is_equal("Cast_fire_bolt")


func test_a_divider_moves_columns() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class"}
	var out := HotbarLayout.place(st, "fight", cells, 10)
	var a := int(out[0]["cols"])
	HotbarLayout.shift(st, "fight", 0, 2)
	out = HotbarLayout.place(st, "fight", cells, 10)
	assert_int(int(out[0]["cols"])).is_equal(a + 2)
	assert_int(int(out[0]["cols"]) + int(out[1]["cols"])).is_equal(10)


func test_rows() -> void:
	var st := {}
	HotbarLayout.set_rows(st, 9)
	assert_int(HotbarLayout.rows(st)).is_equal(HotbarLayout.MAX_ROWS)
	var out := HotbarLayout.place(st, "peace", {"LookButton": "common"}, 5)
	assert_int((out[0]["slots"] as Array).size()).is_equal(5 * HotbarLayout.MAX_ROWS)


## A spell or a feature dragged from the sheet is the bar's own cell: a cast in a fight, a pin out of it.
func test_a_sheet_key_is_a_cell_of_the_bar() -> void:
	assert_str(ActionBar.cell_key("spell:fire_bolt", true)).is_equal("Cast_fire_bolt")
	assert_str(ActionBar.cell_key("spell:fire_bolt", false)).is_equal("Pin_spell_fire_bolt")
	assert_str(ActionBar.cell_key("feature:second_wind", true)).is_equal("Feature_second_wind")
	assert_str(ActionBar.cell_key("Do_dash", true)).is_equal("Do_dash")
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class", "Cast_shield": "class"}
	HotbarLayout.place(st, "fight", cells, 10)
	HotbarLayout.move(st, "fight", ActionBar.cell_key("spell:shield", true), 0, 0)
	var out := HotbarLayout.place(st, "fight", cells, 10)
	assert_str(str(out[0]["slots"][0])).is_equal("Cast_shield")
	assert_bool(str(out[0]["slots"]).contains("Do_dash") or str(out[1]["slots"]).contains("Do_dash")).is_true()
