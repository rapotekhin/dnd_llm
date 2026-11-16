extends GdUnitTestSuite
## v0.8.4.43: the hotbar as in BG3 — cells go into their kind's section, stay where they were dragged, come back to
## their slot, leave the bar when dragged off; the dividers move columns between sections.


func _keys(sec: Dictionary) -> Array:
	return (sec["slots"] as Array).filter(func(k: String) -> bool: return k != "")


func _of(out: Array, kind: String) -> Dictionary:
	for sec: Dictionary in out:
		if str(sec["kind"]) == kind:
			return sec
	return {}


func test_new_cells_go_to_their_kind() -> void:
	var st := {}
	var out := HotbarLayout.place(st, "fight", {"Do_dash": "common", "Cast_fire_bolt": "class", "Item_potion": "items"}, 12)
	assert_int(out.size()).is_equal(4)  # v0.8.4.44.9: the empty «Пассивные» keeps one column to drop into
	assert_array(_keys(out[0])).contains_exactly(["Do_dash"])
	assert_array(_keys(_of(out, "class"))).contains_exactly(["Cast_fire_bolt"])
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
	assert_bool((_of(out, "class")["slots"] as Array).has("Do_dash")).is_true()  # the dash went where the bolt was


func test_an_absent_act_keeps_its_slot() -> void:
	var st := {}
	HotbarLayout.place(st, "fight", {"Do_dash": "common", "Item_scroll": "items"}, 8)
	var out := HotbarLayout.place(st, "fight", {"Do_dash": "common"}, 8)
	assert_array(_keys(_of(out, "items"))).is_empty()  # no items now — an empty column (v0.8.4.44.9)
	out = HotbarLayout.place(st, "fight", {"Do_dash": "common", "Item_scroll": "items"}, 8)
	assert_str(str(_of(out, "items")["slots"][0])).is_equal("Item_scroll")


func test_a_hidden_cell_is_off_until_dragged_back() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class"}
	HotbarLayout.place(st, "fight", cells, 8)
	HotbarLayout.hide(st, "fight", "Cast_fire_bolt")
	var out := HotbarLayout.place(st, "fight", cells, 8)
	assert_array(_keys(_of(out, "class"))).is_empty()
	HotbarLayout.move(st, "fight", "Cast_fire_bolt", 0, HotbarLayout.at(1, 0))
	out = HotbarLayout.place(st, "fight", cells, 8)
	assert_str(str(out[0]["slots"][1])).is_equal("Cast_fire_bolt")


func test_a_divider_moves_columns() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class"}
	var out := HotbarLayout.place(st, "fight", cells, 10)
	var a := int(out[0]["cols"])
	HotbarLayout.shift(st, "fight", 0, 2)
	out = HotbarLayout.place(st, "fight", cells, 10)
	assert_int(int(out[0]["cols"])).is_equal(a + 2)
	var cols := 0
	for sec: Dictionary in out:
		cols += int(sec["cols"])
	assert_int(cols).is_equal(10)  # the whole bar, empty sections' columns too (v0.8.4.44.9)


func test_rows() -> void:
	var st := {}
	HotbarLayout.set_rows(st, 9)
	assert_int(HotbarLayout.rows(st)).is_equal(HotbarLayout.MAX_ROWS)
	var out := HotbarLayout.place(st, "peace", {"LookButton": "common"}, 5)
	assert_int((out[0]["slots"] as Array).size()).is_equal(int(out[0]["cols"]) * HotbarLayout.MAX_ROWS)


## A spell or a feature dragged from the sheet is the bar's own cell, by one key in a fight and out of it (v0.8.4.43.14).
func test_a_sheet_key_is_a_cell_of_the_bar() -> void:
	assert_str(ActionBar.cell_key("spell:fire_bolt")).is_equal("spell:fire_bolt")
	assert_str(ActionBar.cell_key("Cast_fire_bolt")).is_equal("spell:fire_bolt")
	assert_str(ActionBar.cell_key("Pin_spell_fire_bolt")).is_equal("spell:fire_bolt")
	assert_str(ActionBar.cell_key("Feature_second_wind")).is_equal("feature:second_wind")
	assert_str(ActionBar.cell_key("Pin_item_rope_hempen_50_feet")).is_equal("item:rope_hempen_50_feet")
	assert_str(ActionBar.cell_key("Item_potion_of_healing")).is_equal("item:potion_of_healing")
	assert_str(ActionBar.cell_key("Do_dash")).is_equal("Do_dash")
	var st := {}
	var cells := {"Do_dash": "common", "spell:fire_bolt": "class", "spell:shield": "class"}
	HotbarLayout.place(st, "fight", cells, 10)
	HotbarLayout.move(st, "fight", ActionBar.cell_key("spell:shield"), 0, 0)
	var out := HotbarLayout.place(st, "fight", cells, 10)
	assert_str(str(out[0]["slots"][0])).is_equal("spell:shield")
	assert_bool(str(out[0]["slots"]).contains("Do_dash") or str(out[1]["slots"]).contains("Do_dash")).is_true()


## v0.8.4.43.49, the author: «группы как карты из колоды, как в BG3. Граница, сдвинутая вправо, задвигает следующую группу
## под себя. Иконка, оказавшаяся под соседней группой, прячется на своём месте, а не переезжает в другую клетку».
func _screen(out: Array) -> Dictionary:  # key → [the column of the bar, the row] of every icon in sight
	var seen := {}
	var start := 0
	for sec: Dictionary in out:
		var cols := int(sec["cols"])
		for j in (sec["slots"] as Array).size():
			var k := str(sec["slots"][j])
			if k != "":
				seen[k] = [start + j % cols, j / cols]
		start += cols
	return seen


## v0.8.4.43.51, the author: «словно линия-разделитель между группами — это край карты в колоде… все иконки прикреплены к
## своим позициям и просто смещаются, когда выдвигают или задвигают их группу».
func test_a_divider_is_the_edge_of_the_card_on_its_right() -> void:
	var st := {}
	var cells := {"Do_a": "common", "Do_b": "common", "Do_c": "common", "spell:x": "class", "spell:y": "class", "spell:z": "class", "spell:w": "class"}
	var before := _screen(HotbarLayout.place(st, "fight", cells, 8))
	assert_int(before.size()).is_equal(7)
	HotbarLayout.shift(st, "fight", 0, 1)  # the edge to the right: the spells go with it, none hidden, none left behind
	var after := _screen(HotbarLayout.place(st, "fight", cells, 8))
	assert_int(after.size()).is_equal(7)
	for k: String in after:
		var moved: Array = [int(before[k][0]) + (1 if k.begins_with("spell:") else 0), before[k][1]]
		assert_array(after[k]).override_failure_message("%s: %s → %s" % [k, before[k], after[k]]).is_equal(moved)
	HotbarLayout.shift(st, "fight", 0, -1)
	assert_dict(_screen(HotbarLayout.place(st, "fight", cells, 8))).is_equal(before)  # and back
	var common := int(HotbarLayout.place(st, "fight", cells, 8)[0]["cols"])
	HotbarLayout.shift(st, "fight", 0, 1 - common)  # to the left as far as it goes: the common card one column wide
	var left := _screen(HotbarLayout.place(st, "fight", cells, 8))
	for k: String in before:
		if k.begins_with("spell:"):  # the spells' first icons at the edge, as before
			assert_array(left[k]).is_equal([int(before[k][0]) + 1 - common, before[k][1]])
		elif int(before[k][0]) == 0:
			assert_array(left[k]).is_equal(before[k])
		else:
			assert_bool(left.has(k)).override_failure_message(k + " is under the spells' card").is_false()
	HotbarLayout.shift(st, "fight", 0, 99)  # to the right as far as it goes: the spells' card one column, the rest past the end
	var laid := HotbarLayout.place(st, "fight", cells, 8)
	var right := _screen(laid)
	var edge := 0  # the spells' card starts where the cards before it end (the empty ones after it keep a column, v0.8.4.44.9)
	for sec: Dictionary in laid:
		if str(sec["kind"]) == "class":
			break
		edge += int(sec["cols"])
	assert_int(int(_of(laid, "class")["cols"])).is_equal(1)
	for k: String in ["spell:x", "spell:y"]:
		assert_array(right[k]).is_equal([edge, before[k][1]])
	assert_bool(right.has("spell:z") or right.has("spell:w")).is_false()
	HotbarLayout.shift(st, "fight", 0, -99)
	HotbarLayout.shift(st, "fight", 0, common - 1)
	assert_dict(_screen(HotbarLayout.place(st, "fight", cells, 8))).is_equal(before)  # every icon in its column of its card


## The author: «новые заклинания и умения встают в первую свободную видимую клетку своей группы, а не в конец».
func test_a_new_spell_takes_the_first_free_slot_in_sight() -> void:
	var st := {"rows": 2, "modes": {"fight": {"hidden": [], "sections": [{"kind": "class", "cols": 2, "width": 2, "fixed": true, "skip": 0,
		"grid": [["spell:a", "spell:b", "", ""], ["spell:c", "", "", ""], ["spell:old", "", "", ""]]}]}}}
	var out := HotbarLayout.place(st, "fight", {"spell:a": "class", "spell:b": "class", "spell:c": "class", "spell:d": "class", "Do_dash": "common"}, 4)
	var cls: Dictionary = out.filter(func(sec: Dictionary) -> bool: return str(sec["kind"]) == "class")[0]
	assert_int(int(cls["cols"])).is_equal(2)
	assert_array(cls["slots"]).is_equal(["spell:a", "spell:c", "spell:b", "spell:d"])  # in the free slot of the second row


## «−» takes a row off: its icons are hidden where they stand, the bar never scrolls, «+» shows them again.
func test_a_row_taken_off_hides_its_icons_in_their_place() -> void:
	var st := {}
	var cells := {"Do_a": "common", "Do_b": "common", "Do_c": "common", "Do_d": "common"}
	var before := _screen(HotbarLayout.place(st, "fight", cells, 2))
	HotbarLayout.set_rows(st, 1)
	var out := HotbarLayout.place(st, "fight", cells, 2)
	assert_int((out[0]["slots"] as Array).size()).is_equal(2)  # one row of the bar, no more
	var seen := _screen(out)
	for k: String in seen:
		assert_array(seen[k]).is_equal(before[k])
	HotbarLayout.set_rows(st, 2)
	assert_dict(_screen(HotbarLayout.place(st, "fight", cells, 2))).is_equal(before)


## A bar laid in rows of its columns before v0.8.4.43.49 keeps each icon in its column and row.
func test_a_bar_of_rows_becomes_a_card_of_columns() -> void:
	var st := {"modes": {"fight": {"hidden": [], "sections": [{"kind": "class", "cols": 3, "slots": ["spell:x", "", "spell:y", "spell:z"]}]}}}
	var cls: Dictionary = HotbarLayout.mode(st, "fight")["sections"][0]
	assert_str(str(cls["grid"][0][0])).is_equal("spell:x")
	assert_str(str(cls["grid"][2][0])).is_equal("spell:y")
	assert_str(str(cls["grid"][0][1])).is_equal("spell:z")


## v0.8.4.44.9 (the author: «я удалил из группы все иконки — и группа пропала!»): a section emptied by hand keeps one
## column and its tab to drop into; on a bar too narrow for it the sections with cells come first.
func test_an_emptied_section_keeps_a_column_but_gives_way_on_a_narrow_bar() -> void:
	var st := {}
	var cells := {"Do_dash": "common", "Cast_fire_bolt": "class"}
	HotbarLayout.place(st, HotbarLayout.BAR, cells, 12, "peace")
	HotbarLayout.hide(st, HotbarLayout.BAR, "Cast_fire_bolt")
	var out := HotbarLayout.place(st, HotbarLayout.BAR, cells, 12, "peace")
	assert_int(int(_of(out, "class").get("cols", 0))).is_greater_equal(1)
	var many := {}
	for i in 10:
		many["spell:s%d" % i] = "class"
	out = HotbarLayout.place({}, HotbarLayout.BAR, many, 4, "peace")
	assert_int(out.size()).is_equal(1)
	assert_int(int(out[0]["cols"])).is_equal(4)


## v0.8.4.44.9 (the author: «у его своя панель тулбар должна быть, у нас она не общая»): each hero and each companion
## its own layout; past KEPT the oldest is dropped.
func test_a_layout_of_its_own_for_each_hero_and_companion() -> void:
	var s := GameSession.new()
	s.character = {"name": "Аира", "class": "fighter"}
	var hero := HotbarLayout.layout_of(s, Sheet.HERO)
	assert_str(hero).is_equal("bar:Аира|fighter")
	assert_str(HotbarLayout.layout_of(s, {"npc_id": "npc_dream_fighter"})).is_equal("bar:npc_dream_fighter")
	var st := {}
	HotbarLayout.place(st, hero, {"spell:fire_bolt": "class"}, 8)
	HotbarLayout.hide(st, hero, "spell:fire_bolt")
	var other := HotbarLayout.place(st, "bar:Бранко|cleric", {"spell:fire_bolt": "class"}, 8)
	assert_array(_keys(_of(other, "class"))).contains_exactly(["spell:fire_bolt"])  # hidden on Aira's, not on Branko's
	for i in HotbarLayout.KEPT + 5:
		HotbarLayout.mode(st, "bar:h%d|x" % i)
	assert_int((st["modes"] as Dictionary).size()).is_equal(HotbarLayout.KEPT)
