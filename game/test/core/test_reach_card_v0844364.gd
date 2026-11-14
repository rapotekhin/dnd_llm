extends GdUnitTestSuite
## v0.8.4.43.64, the author's two notes of 2026-11-14:
## — «у выбора чародея почему-то иконка супер маленькая»: a row of a pick (`PickGrid.rows`) wraps its name, so its icon
##   keeps the row's whole height however long the name («Наследие драконьей крови»): an expanded icon of Godot's Button
##   gets only the width a name on one line leaves;
## — «когда я смещаю мышку на не закреплённое окно и перехожу ровно с иконки на это окно — оно не должно закрываться»: an
##   icon's card at the cursor is the one card of icons unpinned (no tooltip of Godot), and any unpinned card at the
##   cursor takes the cursor once it came over onto it from its thing, stays there, and a moment after it left both goes.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	var c := DetailsPanel.icon_card()
	if c != null:
		c.unpin()
		c.visible = false
	DetailsPanel._mouse = Vector2(-1, -1)


func _cell(name_text: String, tip: String, body: String, at: Vector2) -> IconSlot:
	var c := IconSlot.make("acts/grapple", name_text)
	c.tooltip_text = tip
	c.tip_body = body
	add_child(c)
	c.position = at
	return auto_free(c) as IconSlot


func test_a_row_wraps_its_name_so_its_icon_keeps_its_size() -> void:
	var subs: Dictionary = data["classes"]["subclasses"]
	var opts: Array = []
	for id: String in subs:
		opts.append({"id": id, "label": str(subs[id]["name"]), "ref": "subclasses/" + id})
	var grid := auto_free(PickGrid.rows(opts, "", "Pick_", func(_id: String) -> void: pass)) as GridContainer
	for b: Button in grid.get_children():
		assert_int(b.autowrap_mode).override_failure_message(b.name).is_equal(TextServer.AUTOWRAP_WORD_SMART)
		assert_bool(b.expand_icon).override_failure_message(b.name).is_true()
		assert_float(b.get_combined_minimum_size().x).override_failure_message(b.name).is_equal(PickGrid.ROW.x)  # a name never widens it


func test_every_class_s_subclass_has_a_picture_of_a_feature() -> void:
	var shared: Dictionary = data["icons"]["shared"]
	for k: String in data["classes"]["classes"]:
		for sub: Variant in data["classes"]["classes"][k].get("subclasses", []):
			var by := str(shared.get("subclasses/" + str(sub), ""))
			assert_str(by).override_failure_message("%s/%s" % [k, sub]).starts_with("features/")
			assert_bool((data["classes"]["features"] as Dictionary).has(by.get_file())).override_failure_message(by).is_true()


func test_an_icon_s_card_is_the_one_card_of_icons_unpinned_with_its_line() -> void:
	var c := _cell("Захват", "Захват\nАтлетика против Атлетики", "Вместо одной атаки.", Vector2(40, 40))
	assert_str(c._get_tooltip(Vector2.ZERO)).is_empty()  # no tooltip of Godot
	c.show_card()
	var card := DetailsPanel.icon_card()
	assert_object(card).is_not_null()
	assert_object(DetailsPanel.pinned_card()).is_null()
	assert_str(card.title()).is_equal("Захват")
	assert_str((card.find_child("DetailsLine", true, false) as Label).text).is_equal("Атлетика против Атлетики")
	assert_str(card.body()).is_equal("Вместо одной атаки.")


func test_the_cursor_come_over_onto_the_card_is_taken_by_it_and_stays() -> void:
	var a := _cell("Рывок", "Рывок", "Удвоенная скорость до конца хода.", Vector2(40, 40))
	DetailsPanel._mouse = a.get_global_rect().get_center()
	a.show_card()
	var card := DetailsPanel.icon_card()
	await await_idle_frame()
	var r := card.get_global_rect()
	var b := _cell("Уклонение", "Уклонение", "Атаки по вам с помехой.", r.position + Vector2(20, 20))  # an icon under the card
	# on its icon (where the card stands over it too) the cursor goes through to the icon
	card._reach()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# over onto the card: it takes the cursor, the icon under it is not hovered through it
	DetailsPanel._mouse = r.get_center() + Vector2(0, 30)
	card._reach()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	b.show_card()
	assert_str(card.title()).is_equal("Рывок")
	assert_bool(card._still_wanted()).is_true()  # the moment after the cursor left the icon
	card._away_at = Time.get_ticks_msec() - DetailsPanel.REACH_MS - 1
	assert_bool(card._still_wanted()).is_false()  # off both for longer: it goes
	# back on its icon: it lets the cursor through again and does not move
	var at := card.position
	DetailsPanel._mouse = a.get_global_rect().get_center()
	card._reach()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	a.show_card()
	assert_vector(card.position).is_equal(at)


func test_the_right_button_on_the_reached_card_pins_it_where_it_stands() -> void:
	var a := _cell("Благословение", "Благословение", "До трёх существ добавляют к броскам к4.", Vector2(40, 40))
	a.show_card()
	var card := DetailsPanel.icon_card()
	var at := card.position
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	card._gui_input(ev)
	assert_object(DetailsPanel.pinned_card()).is_not_null()
	assert_str(DetailsPanel.pinned_card().pinned()).is_equal("Благословение")
	assert_vector(card.position).is_equal(at)


func test_a_press_on_the_icon_lets_its_card_go() -> void:
	var a := _cell("Рывок", "Рывок", "Удвоенная скорость.", Vector2(40, 40))
	a.show_card()
	assert_object(DetailsPanel.icon_card()).is_not_null()
	a.button_down.emit()
	assert_object(DetailsPanel.icon_card()).is_null()


func test_with_no_room_under_the_cursor_the_card_stands_above_it() -> void:
	var screen := get_viewport().get_visible_rect().size
	var a := _cell("Рывок", "Рывок", "Удвоенная скорость до конца хода. ".repeat(6), Vector2(100, screen.y - 60))
	DetailsPanel._mouse = Vector2(110, screen.y - 30)
	a.show_card()
	var card := DetailsPanel.icon_card()
	card._place()
	assert_float(card.position.y + card.size.y).is_less_equal(screen.y - 30)


func test_a_row_s_card_waits_while_the_cursor_is_on_it() -> void:
	var p := DetailsPanel.new(Vector2.ZERO, true)
	add_child(p)
	auto_free(p)
	var one := Button.new()
	var two := Button.new()
	for b: Button in [one, two]:
		add_child(b)
		auto_free(b)
	p.hook(one, "Человек", "Раса без особых черт.")
	p.hook(two, "Эльф", "Тёмное зрение.")
	DetailsPanel._mouse = Vector2(5, 5)
	one.mouse_entered.emit()
	await await_idle_frame()  # a hover is told at the frame's end, when the cursor's motion reached the cards
	assert_str(p.title()).is_equal("Человек")
	p._shown = one  # its row hovered and the card up, as the cursor is on it (no cursor in a test)
	p.visible = true
	p._away_at = -1
	DetailsPanel._mouse = p.get_global_rect().get_center()  # the cursor over on the card, a row under it
	assert_bool(p._covers(two)).is_true()
	two.mouse_entered.emit()
	await await_idle_frame()
	assert_str(p.title()).is_equal("Человек")
