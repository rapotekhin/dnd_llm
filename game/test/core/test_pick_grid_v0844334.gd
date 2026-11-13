extends GdUnitTestSuite
## v0.8.4.43.34, the author: the creation and the level-up as in BG3 — a list «pick N of these» as icons with «Выбрано n из
## m» and the row of the picked ones (`PickGrid`), a race by its face and a class by its sign in rows, a feature's card
## telling the spells it gives.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _spells(ids: Array) -> Array:
	return ids.map(func(id: String) -> Dictionary:
		return {"id": id, "label": str(data["spells"][id]["name"]), "ref": "spells/" + id, "card": CardInfo.spell(data, id)})


func test_the_count_and_the_row_of_picked_ones() -> void:
	var g: PickGrid = auto_free(PickGrid.make("Заговоры — выберите 2:", _spells(["fire_bolt", "light", "mage_hand"]), 2, ["light"]))
	var count := g.find_child("PickCount", true, false) as Label
	assert_str(count.text).is_equal("Выбрано 1 из 2")
	var chosen := g.find_child("Chosen", true, false) as HBoxContainer
	assert_int(chosen.get_child_count()).is_equal(2)  # the picked one and one empty cell
	assert_object(g.find_child("Chosen_light", true, false)).is_not_null()
	var tile := g.find_child("Pick_light", true, false) as IconSlot
	assert_bool(tile.button_pressed).is_true()
	assert_str(tile.tip_title).is_equal(str(data["spells"]["light"]["name"]))
	assert_bool(tile.card.is_empty()).is_false()  # its card at the cursor


func test_a_pick_adds_and_a_full_list_closes_the_rest() -> void:
	var got: Array = []
	var g: PickGrid = auto_free(PickGrid.make("", _spells(["fire_bolt", "light", "mage_hand"]), 2, ["light"]))
	g.changed.connect(func(next: Array) -> void: got.assign(next))
	(g.find_child("Pick_fire_bolt", true, false) as IconSlot).button_pressed = true
	assert_array(got).contains_exactly(["light", "fire_bolt"])
	var full: PickGrid = auto_free(PickGrid.make("", _spells(["fire_bolt", "light", "mage_hand"]), 2, ["light", "fire_bolt"]))
	assert_bool((full.find_child("Pick_mage_hand", true, false) as IconSlot).disabled).is_true()
	assert_str((full.find_child("PickCount", true, false) as Label).theme_type_variation).is_equal(UiTheme.OK_LABEL)


func test_a_single_pick_switches_and_a_picked_one_is_taken_back() -> void:
	var got: Array = []
	var g: PickGrid = auto_free(PickGrid.make("", _spells(["fire_bolt", "light"]), 1, ["light"]))
	g.changed.connect(func(next: Array) -> void: got.assign(next))
	assert_object(g.find_child("Chosen", true, false)).is_null()  # one pick: the lit icon is enough
	(g.find_child("Pick_fire_bolt", true, false) as IconSlot).button_pressed = true
	assert_array(got).contains_exactly(["fire_bolt"])
	var two: PickGrid = auto_free(PickGrid.make("", _spells(["fire_bolt", "light"]), 2, ["light"]))
	two.changed.connect(func(next: Array) -> void: got.assign(next))
	(two.find_child("Chosen_light", true, false) as IconSlot).pressed.emit()
	assert_array(got).is_empty()


func test_blocked_and_named() -> void:
	var g: PickGrid = auto_free(PickGrid.make("", _spells(["fire_bolt", "light"]), 2, [], [], ["light"], "Check_"))
	var blocked := g.find_child("Check_light", true, false) as IconSlot
	assert_bool(blocked.disabled).is_true()
	assert_str(blocked.tip_body).contains("Уже выбран")
	var names := g.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(names).contains([str(data["spells"]["fire_bolt"]["name"])])  # its name under the icon


func test_spells_by_circle_have_their_headings() -> void:
	var opts := _spells(["light", "magic_missile"])
	opts[0]["group"] = "Заговор"
	opts[1]["group"] = "1 круг"
	var g: PickGrid = auto_free(PickGrid.make("", opts, 2, []))
	var names := g.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_array(names).contains(["Заговор", "1 круг"])


func test_rows_by_picture_and_name() -> void:
	var picked: Array = []
	var grid: GridContainer = auto_free(PickGrid.rows([{"id": "fighter", "label": "Воин", "ref": "classes/fighter"}, {"id": "wizard", "label": "Волшебник", "ref": "classes/wizard"}],
		"wizard", "Pick_", func(id: String) -> void: picked.append(id)))
	var b := grid.find_child("Pick_fighter", true, false) as Button
	assert_str(b.text).is_equal("Воин")
	assert_bool((grid.find_child("Pick_wizard", true, false) as Button).button_pressed).is_true()
	b.pressed.emit()
	assert_array(picked).contains_exactly(["fighter"])


func test_a_class_and_a_subclass_by_their_sign() -> void:
	var look := IconRules.of(data, {}, "classes/fighter")
	assert_str(str(look["path"])).ends_with("features/second_wind.png")
	assert_bool(bool(look["framed"])).is_true()
	assert_str(str(IconRules.of(data, {}, "subclasses/evocation")["path"])).ends_with("features/sculpt_spells.png")


func test_a_feature_card_tells_the_spell_it_gives() -> void:
	var card := CardInfo.feature(data, "eldritch_invocation_armor_of_shadows")
	assert_bool((card["notes"] as Array).any(func(n: String) -> bool: return n.contains(str(data["spells"]["mage_armor"]["name"])) and n.contains("без ячейки"))).is_true()
