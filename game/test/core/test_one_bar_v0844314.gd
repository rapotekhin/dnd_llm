extends GdUnitTestSuite
## v0.8.4.43.14, the author: «вся эта панель должна быть идентична как в бою, так и вне боя. Как в BG3». One layout of the
## hotbar for a fight and the world, a section «Боевые» of the fight's acts, a spell in the same slot whether it is cast or
## pinned to the words; the bar of two layouts keeps its world's arrangement; a width the player gave by a divider is not
## forgotten by a bar too narrow for it once; a divider let go snaps to the nearest column.


func _kinds(out: Array) -> Array:
	return out.map(func(sec: Dictionary) -> String: return str(sec["kind"]))


func test_one_layout_with_the_fight_s_section() -> void:
	var st := {}
	var out := HotbarLayout.place(st, HotbarLayout.BAR, {"spell:fire_bolt": "class", "Do_dash": "combat", "LookButton": "common"}, 12)
	assert_array(_kinds(out)).is_equal(["common", "combat", "class", "items", "deeds", "passive"])  # an empty one keeps a column (v0.8.4.44.9)
	assert_bool((HotbarLayout.KINDS[HotbarLayout.BAR] as Array).has("combat")).is_true()


func test_a_spell_stays_in_its_slot_in_a_fight_and_out_of_it() -> void:
	var st := {}
	var peace := {HotbarLayout.key_of("Pin_spell_bless"): "class", HotbarLayout.key_of("Pin_spell_fire_bolt"): "class", "LookButton": "common"}
	var laid := HotbarLayout.place(st, HotbarLayout.BAR, peace, 12)
	HotbarLayout.move(st, HotbarLayout.BAR, "spell:fire_bolt", _kinds(laid).find("class"), 0)  # the bolt first in its section
	var fight := {HotbarLayout.key_of("Cast_bless"): "class", HotbarLayout.key_of("Cast_fire_bolt"): "class", "Do_dash": "combat", "LookButton": "common"}
	var out := HotbarLayout.place(st, HotbarLayout.BAR, fight, 12)
	var cls: Dictionary = out[_kinds(out).find("class")]
	assert_str(str(cls["slots"][0])).is_equal("spell:fire_bolt")


func test_the_bar_of_two_layouts_keeps_its_world_s_arrangement() -> void:
	var st := {"rows": 3, "modes": {"peace": {"sections": [{"kind": "class", "cols": 3, "slots": ["Pin_spell_fire_bolt", "", "Pin_feature_second_wind"]}],
		"hidden": ["Pin_item_rope_hempen_50_feet"]}}}
	var md := HotbarLayout.mode(st, HotbarLayout.BAR)
	var cls: Dictionary = (md["sections"] as Array).filter(func(sec: Dictionary) -> bool: return str(sec["kind"]) == "class")[0]
	assert_str(str(cls["grid"][0][0])).is_equal("spell:fire_bolt")  # each in its column and row (v0.8.4.43.49)
	assert_str(str(cls["grid"][2][0])).is_equal("feature:second_wind")
	assert_array(md["hidden"]).is_equal(["item:rope_hempen_50_feet"])
	assert_int((md["sections"] as Array).size()).is_equal((HotbarLayout.KINDS[HotbarLayout.BAR] as Array).size())
	assert_int(HotbarLayout.rows(st)).is_equal(3)


func test_a_width_set_by_a_divider_outlives_a_narrow_bar() -> void:
	var st := {}
	var cells := {"Do_dash": "combat", "LookButton": "common", "spell:fire_bolt": "class"}
	var out := HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	var a := int(out[0]["cols"])
	HotbarLayout.shift(st, HotbarLayout.BAR, 0, 1)  # the neighbour keeps one column: as far as it gives
	out = HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	assert_int(int(out[0]["cols"])).is_equal(a + 1)
	out = HotbarLayout.place(st, HotbarLayout.BAR, cells, 3)  # the window made narrow for a moment: the empty ones give way
	assert_array(_kinds(out)).is_equal(["common", "combat", "class"])
	assert_int(int(out[0]["cols"]) + int(out[1]["cols"]) + int(out[2]["cols"])).is_equal(3)
	out = HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	assert_int(int(out[0]["cols"])).is_equal(a + 1)  # the player's width back


## v0.8.4.44.16: widths set on a wider bar no longer hold every divider still on a narrower one.
func test_a_divider_moves_on_a_bar_narrower_than_the_widths_set() -> void:
	var st := {}
	var cells := {"Do_dash": "combat", "LookButton": "common", "spell:fire_bolt": "class"}
	HotbarLayout.place(st, HotbarLayout.BAR, cells, 30)
	HotbarLayout.shift(st, HotbarLayout.BAR, 0, 8)  # wide: the first section takes 8 more
	HotbarLayout.shift(st, HotbarLayout.BAR, 1, 5)
	var out := HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)  # the bar narrower than the widths kept
	var before := int(out[0]["cols"])
	HotbarLayout.shift(st, HotbarLayout.BAR, 0, -1)
	out = HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	assert_int(int(out[0]["cols"])).is_equal(before - 1)
	assert_int(out.reduce(func(n: int, sec: Dictionary) -> int: return n + int(sec["cols"]), 0)).is_equal(12)
	HotbarLayout.shift(st, HotbarLayout.BAR, 1, 1)
	var again := HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	assert_int(int(again[1]["cols"])).is_equal(int(out[1]["cols"]) + 1)


## v0.8.4.44.19: as far as every section on the side it goes to keeps one column — not its neighbour alone.
func test_a_divider_reaches_as_far_as_each_side_keeps_one_column() -> void:
	var st := {}
	var out := HotbarLayout.place(st, HotbarLayout.BAR, {"Do_dash": "combat", "LookButton": "common"}, 10)
	var left := int(out[0]["cols"])
	var right := 0
	for j in range(1, out.size()):
		right += int(out[j]["cols"]) - 1
	assert_int(HotbarLayout.reach(st, HotbarLayout.BAR, 0, 99)).is_equal(right)
	assert_int(HotbarLayout.reach(st, HotbarLayout.BAR, 0, -99)).is_equal(1 - left)
	assert_int(HotbarLayout.reach(st, HotbarLayout.BAR, out.size(), 2)).is_equal(0)


## v0.8.4.44.19 (the author: «менять размер групп, двигая за вертикальные линии, становится нельзя в бою»): a companion's
## bar in a fight — one wide card and the rest of one column each. A divider between two of one column moves: the card
## at its edge pushes the next, as an edge of the deck, and the wide one gives; its icons stay in their columns.
func test_a_divider_between_cards_of_one_column_pushes_the_wide_one() -> void:
	var st := {"rows": 2, "modes": {"bar:x": {"hidden": [], "sections": [
		{"kind": "combat", "cols": 7, "width": 7, "fixed": true, "grid": []},
		{"kind": "class", "cols": 1, "width": 1, "fixed": true, "grid": []},
		{"kind": "items", "cols": 1, "width": 1, "fixed": true, "grid": []},
		{"kind": "passive", "cols": 1, "width": 1, "fixed": true, "grid": []}]}}}
	var widths := func() -> Array: return (HotbarLayout.mode(st, "bar:x")["sections"] as Array).map(func(sec: Dictionary) -> int: return int(sec["cols"]))
	assert_int(HotbarLayout.reach(st, "bar:x", 1, -99)).is_equal(-6)  # the wide one gives up to six
	assert_int(HotbarLayout.reach(st, "bar:x", 1, 99)).is_equal(0)  # those on the right are one column each
	HotbarLayout.shift(st, "bar:x", 1, -2)  # the class|items edge two to the left: items two wider, combat two narrower
	assert_array(widths.call()).is_equal([5, 1, 3, 1])
	HotbarLayout.shift(st, "bar:x", 0, 2)  # the combat|class edge back to the right: class wider, items gives back
	assert_array(widths.call()).is_equal([7, 1, 1, 1])
	HotbarLayout.shift(st, "bar:x", 2, -3)
	assert_array(widths.call()).is_equal([4, 1, 1, 4])
	var out := HotbarLayout.place(st, "bar:x", {"Do_dash": "combat"}, 10)  # kept: the player's widths
	assert_array(out.map(func(sec: Dictionary) -> int: return int(sec["cols"]))).is_equal([4, 1, 1, 4])


func test_a_divider_let_go_mid_cell_snaps_to_the_nearest_column() -> void:
	var step := ActionBar.CELL + ActionBar.GAP
	assert_int(ActionBar.snap(step * 0.4)).is_equal(0)
	assert_int(ActionBar.snap(step * 0.6)).is_equal(1)
	assert_int(ActionBar.snap(-step * 1.6)).is_equal(-2)


func test_a_gathering_spot_has_its_own_thing_s_icon() -> void:
	var data := Catalog.data
	assert_str(IconRules.button(data, "Gather_herbs")).is_equal("items/herbs")
	assert_str(IconRules.button(data, "Gather_timber")).is_equal("items/timber")
	assert_str(IconRules.button(data, "Gather_forage")).is_equal("items/mushrooms")
	assert_str(IconRules.button(data, "Gather_nowhere")).is_equal("ui/gather")
	assert_str(IconRules.button(data, "LookButton")).is_equal("ui/look")


func test_the_fight_s_acts_of_the_bar_are_acts() -> void:
	var acts: Array = CombatRules.cfg(Catalog.data)["bar"]["acts"]
	assert_bool(acts.is_empty()).is_false()
	for id: Variant in acts:
		assert_object(Acts.one(str(id))).is_not_null()
		assert_str(Acts.one(str(id)).tab()).is_equal("common")


func test_a_drop_on_a_tab_of_one_kind_goes_right_after_its_last_cell() -> void:
	var st := {}
	var cells := {"Gather_herbs": "deeds", "Gather_timber": "deeds", "CraftButton": "deeds", "LookButton": "common"}
	var out := HotbarLayout.place(st, HotbarLayout.BAR, cells, 12)
	var at := _kinds(out).find("deeds")
	var slots: Array = out[at]["slots"]
	var first := str(slots[0])
	HotbarLayout.move(st, HotbarLayout.BAR, first, at, HotbarLayout.at(11, 1), true)  # far past the cells, on the tab's whole width
	var md := HotbarLayout.mode(st, HotbarLayout.BAR)
	var deeds: Dictionary = (md["sections"] as Array).filter(func(sec: Dictionary) -> bool: return str(sec["kind"]) == "deeds")[0]
	assert_str(str(deeds["grid"][1][1])).is_equal(first)  # after the other two column by column (v0.8.4.43.49), in sight
	HotbarLayout.move(st, HotbarLayout.BAR, "Gather_herbs", at, HotbarLayout.at(4, 1))  # the whole bar's drop keeps its slot
	assert_str(str(deeds["grid"][4][1])).is_equal("Gather_herbs")


func test_a_section_is_as_wide_in_a_fight_as_out_of_it() -> void:
	var st := {}
	var peace := {"LookButton": "common", "Do_dash": "combat", "Do_dodge": "combat", "spell:bless": "class"}
	var fight := peace.duplicate()
	for k: String in ["Do_flee", "Do_inspect", "Parley_persuasion", "Do_surrender", "Attack_unarmed", "Do_help"]:
		fight[k] = "combat"
	var a := HotbarLayout.place(st, HotbarLayout.BAR, peace, 12, "peace")
	var b := HotbarLayout.place(st, HotbarLayout.BAR, fight, 12, "fight")
	var c := HotbarLayout.place(st, HotbarLayout.BAR, peace, 12, "peace")
	assert_array(c.map(func(sec: Dictionary) -> int: return int(sec["cols"]))).is_equal(b.map(func(sec: Dictionary) -> int: return int(sec["cols"])))
	assert_int(int(b[1]["cols"])).is_greater(int(a[1]["cols"]) - 1)
