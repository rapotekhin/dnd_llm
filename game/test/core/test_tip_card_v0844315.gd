extends GdUnitTestSuite
## v0.8.4.43.15, the author's findings on 0.8.4.43.8 «Подсказка у курсора»: the card's title is the name of the act, the
## ability or the thing, not the line of its tooltip; a card is one width and a long text is cut with «the right button
## pins it»; the right button pins an icon's card so it stays when the cursor goes, on the same one again lets it go; a
## thing's right button pins its card and still opens its menu; the rests tell what they give.


func after_test() -> void:
	var pinned := DetailsPanel.pinned_card()
	if pinned != null:
		pinned.unpin()


func _rmb(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c._gui_input(ev)


func _cell(name_text: String, tip: String, body := "") -> IconSlot:
	var c := IconSlot.make("acts/grapple", name_text)
	c.tooltip_text = tip
	c.tip_body = body
	add_child(c)
	return auto_free(c) as IconSlot


func test_the_title_is_the_name_not_the_tooltip_s_line() -> void:
	var c := _cell("Захват", "Вместо одной атаки: Атлетика против Атлетики или Акробатики врага рядом.")
	assert_str(c.card_title(c.tooltip_text)).is_equal("Захват")
	assert_str(c.card_line(c.tooltip_text)).is_equal("Вместо одной атаки: Атлетика против Атлетики или Акробатики врага рядом.")
	var card := c._make_custom_tooltip(c.tooltip_text) as Control
	auto_free(card)
	assert_str((card.find_child("TipTitle", true, false) as Label).text).is_equal("Захват")


func test_a_tooltip_that_begins_with_the_name_does_not_say_it_twice() -> void:
	var c := _cell("Огненный снаряд", "Огненный снаряд\nПопадание 65%")
	assert_str(c.card_line(c.tooltip_text)).is_equal("Попадание 65%")
	c.tip_title = "Огненный снаряд"
	c.text = "1 действие · 120 футов"  # a book's cell keeps its line in the text: the hooked name wins
	assert_str(c.card_title(c.tooltip_text)).is_equal("Огненный снаряд")


func test_a_long_text_is_cut_and_says_the_right_button_pins_it() -> void:
	var card := DetailsPanel.tip_card("Длинное", "", "Очень длинное описание. ".repeat(120))
	# cut already as it is made: a tooltip takes its size when it comes up
	assert_float((card.find_child("TipText", true, false) as RichTextLabel).custom_minimum_size.y).is_equal(DetailsPanel.CARD_MAX_BODY)
	add_child(card)
	auto_free(card)
	await await_idle_frame()
	await await_idle_frame()
	var body := card.find_child("TipText", true, false) as RichTextLabel
	assert_float(body.custom_minimum_size.y).is_equal(DetailsPanel.CARD_MAX_BODY)
	assert_bool((card.find_child("DetailsMore", true, false) as Label).visible).is_true()
	assert_float(card.get_combined_minimum_size().y).is_less(DetailsPanel.CARD_MAX_BODY + 140)
	var short := DetailsPanel.tip_card("Короткое", "", "Две строки.")
	add_child(short)
	auto_free(short)
	await await_idle_frame()
	assert_bool((short.find_child("DetailsMore", true, false) as Label).visible).is_false()


func test_the_right_button_pins_an_icon_s_card_and_again_lets_it_go() -> void:
	var c := _cell("Благословение", "Благословение", "До трёх существ добавляют к броскам атаки и спасброскам к4.")
	_rmb(c)
	var pinned := DetailsPanel.pinned_card()
	assert_object(pinned).is_not_null()
	assert_str(pinned.pinned()).is_equal("Благословение")
	assert_str(pinned.body()).contains("к4")
	_rmb(c)
	assert_object(DetailsPanel.pinned_card()).is_null()


func test_another_icon_takes_the_pinned_card() -> void:
	var a := _cell("Рывок", "Рывок", "Удвоенная скорость до конца хода.")
	var b := _cell("Уклонение", "Уклонение", "Атаки по вам с помехой.")
	_rmb(a)
	_rmb(b)
	assert_str(DetailsPanel.pinned_card().pinned()).is_equal("Уклонение")


func test_a_thing_s_right_button_pins_its_card_and_opens_its_menu() -> void:
	var cell := ItemCell.of("items/dagger", "dagger", 1, {"from": "things"})
	cell.tip_title = "Кинжал"
	cell.tooltip_text = "Кинжал"
	cell.tip_body = "1к4 колющего"
	var opened := [false]
	cell.on_menu = func(_c: Control) -> void: opened[0] = true
	add_child(cell)
	auto_free(cell)
	_rmb(cell)
	assert_bool(opened[0]).is_true()
	assert_str(DetailsPanel.pinned_card().pinned()).is_equal("Кинжал")


func test_the_rests_and_the_wait_say_what_they_give() -> void:
	for k: String in ["SHORT_REST_TIP", "LONG_REST_TIP", "WAIT_TIP", "DETAILS_MORE"]:
		assert_str(tr(k)).is_not_equal(k)
