extends "res://tools/playtest/playtest_base.gd"
## The card at the cursor (python tools/godot_playtest.py --scenario tip_card, v0.8.4.43.15), the author's findings on
## 0.8.4.43.8: the rests tell what they give; a thing's right button pins its card and opens its menu; in a fight
## «Захват» has its name on top; a long spell's card is one size with «the right button pins it»; the right button pins
## it so it stays when the cursor goes, and lets it go again. A tooltip of Godot does not come up in the playtest's
## window, so the card an icon makes for it (`_make_custom_tooltip`) is set where the tooltip stands.
## v0.8.4.43.56, «Карточка в карточке»: the hero's «Концентрация: Зловонное облако» on its portrait — not pinned its card
## says that pinning it reaches the links; pinned, the cursor (real mouse motions over its lines) on the spell's name in its
## title and in its source line shows the spell's card beside it, it stays while the cursor is over on it and goes when the
## cursor leaves both; in a fight Bane on the wolf in the wolf's card links Bane's card the same way.

var _hovered: Control
var _by_signal: RichTextLabel  # the label whose link's signal the playtest gave (`_onto_link`)
var _by_ref := ""


func run() -> void:
	var gs := node("GameState")
	node("SaveManager").hotbar = {}
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	s.settings["needs"] = false
	still_sky(s)
	s.minute = 10 * 60
	s.room_id = "pushcha-edge"
	node("EventBus").state_changed.emit()
	await frames(8)
	var bar := screen().get_tree().get_first_node_in_group("hotbar") as Control

	# The rests.
	var short := find(bar, "ShortRestButton") as IconSlot
	var rest := find(bar, "RestButton") as IconSlot
	if step("the rests on the bar", short != null and rest != null):
		var card := short._make_custom_tooltip(short.tooltip_text) as Control
		step("«Короткий отдых»: its name on top, what it gives under it", _title(card) == tr("BTN_SHORT_REST") and _text(card).contains(tr("SHORT_REST_TIP")),
			"%s / %s" % [_title(card), _text(card)])
		card.free()
		card = rest._make_custom_tooltip(rest.tooltip_text) as Control
		step("«Долгий отдых»: its name on top, what it gives under it", _title(card) == rest.text and _text(card).contains(tr("LONG_REST_TIP")), _title(card))
		card.free()
		await _hover(rest)
		step("the long rest's card at the cursor", _shown_tip() != null and _title(_shown_tip()) == rest.text)
		await shot("tip_long_rest")
		await _unhover()

	# A thing: the right button pins its card and opens its menu.
	(screen().get("input") as Control).release_focus()
	await frames(2)
	await key(KEY_I)
	var sheet: Control = find(screen(), "CharacterSheet")
	if step("the character window", sheet != null and sheet.visible):
		await frames(4)
		var grid: Control = find(sheet, "InvGrid")
		var cells: Array = grid.find_children("Item_*", "", true, false) if grid != null else []
		var cell: Control = cells[0] if not cells.is_empty() else null
		if step("a thing in the grid", cell != null):
			_rmb(cell)
			await frames(4)
			var pinned := DetailsPanel.pinned_card()
			var menu := screen().find_child("ActsMenu*", true, false) as Control
			var menus := root.find_children("*", "Popup", true, false).filter(func(m: Node) -> bool: return (m as Window).visible)
			step("its card pinned with its name", pinned != null and pinned.pinned() == str(cell.get("tip_title")), pinned.pinned() if pinned != null else "нет")
			step("and its menu at the cursor", not menus.is_empty() or (menu != null and menu.visible), str(menus.size()))
			await shot("item_pinned_with_menu")
			for m: Node in menus:
				(m as Window).hide()
			_rmb(cell)
			await frames(2)
			step("the right button again lets it go", DetailsPanel.pinned_card() == null)
			for m: Node in root.find_children("*", "Popup", true, false):  # it opened the menu again: closed
				(m as Window).hide()
		sheet.visible = false
		await frames(2)

	# Card in card: the hero's concentration on Stinking Cloud on its portrait.
	s.character["concentration"] = "stinking_cloud"
	node("EventBus").state_changed.emit()
	await frames(6)
	var party := find(screen(), "Party")
	var conc := find(party, "Chip_concentration") as IconSlot if party != null else null
	if step("«Концентрация: Зловонное облако» on the hero's portrait", conc != null):
		await _hover(conc)
		var tip := _shown_tip()
		var more := tip.find_child("DetailsMore", true, false) as Label if tip != null else null
		step("not pinned, its card says the right button reaches what is lit", more != null and more.visible and more.text == tr("DETAILS_LINKS"),
			more.text if more != null else "нет")
		await shot("status_card_links")
		await _unhover()
		_rmb(conc)
		await frames(4)
		var pinned := DetailsPanel.pinned_card()
		if step("its card pinned", pinned != null and pinned.title() == "Концентрация: Зловонное облако", pinned.title() if pinned != null else "нет"):
			var linked := await _onto_link(pinned, "DetailsTitle", "Зловонное облако")
			step("the cursor on «Зловонное облако» in its name: the spell's card beside it", linked != null and linked.title() == "Зловонное облако"
				and (linked.position.x >= pinned.get_global_rect().end.x or linked.get_global_rect().end.x <= pinned.position.x),
				(linked.title() if linked != null else "нет") + _how())
			step("the spell's card says what it is", linked != null and linked.body().contains("Заклинание 3 круга"), linked.body().left(80) if linked != null else "")
			await shot("card_in_card")
			if linked != null:
				_off_link()
				await _move_to(linked.get_global_rect().get_center())
				await frames(50)  # longer than the moment it waits for the cursor
				step("the cursor over on the spell's card: it stays", pinned.linked_card() != null)
				await _move_to(Vector2(40, 40))
				step("off the link and off its card: it goes", await wait_until(func() -> bool: return pinned.linked_card() == null, 3.0))
			var by_text := await _onto_link(pinned, "DetailsText", "Зловонное облако")
			step("«Источник: Зловонное облако» in its text shows the same card", by_text != null and by_text.title() == "Зловонное облако",
				(by_text.title() if by_text != null else "нет") + _how())
			_off_link()
			await _move_to(Vector2(40, 40))
			pinned.unpin()
			await frames(2)
	s.character["concentration"] = ""
	node("EventBus").state_changed.emit()
	await frames(2)

	# The fight.
	gs.start_combat([{"monster": "wolf", "beside": true}])
	if not step("a fight with a wolf", await wait_until(func() -> bool: return _my_turn(gs, s), 120.0)):
		return
	bar = screen().get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "combat")
	await frames(6)
	var grapple := find(bar, "Do_grapple") as IconSlot
	if step("«Захват» on the bar", grapple != null):
		step("its card says its name on top", grapple.card_title(grapple.tooltip_text) == Acts.one("grapple").title(), grapple.card_title(grapple.tooltip_text))
		await _hover(grapple)
		var tip := _shown_tip()
		step("shown at the cursor: «Захват», what it does under it", tip != null and _title(tip) == Acts.one("grapple").title(), _title(tip) if tip != null else "нет")
		await shot("tip_grapple")
		await _unhover()
	bar.call("set_filter", "class")
	await frames(6)
	var longest: IconSlot = null
	for c: Node in bar.find_children("Cast_*", "IconSlot", true, false):
		if (c as IconSlot).is_visible_in_tree() and (longest == null or (c as IconSlot).tip_body.length() > longest.tip_body.length()):
			longest = c as IconSlot
	if step("a spell with a long description", longest != null and longest.tip_body.length() > 400, longest.name if longest != null else ""):
		await _hover(longest)
		var tip := _shown_tip()
		var cut := tip != null and (tip.find_child("DetailsMore", true, false) as Label).visible
		step("its card one size: the text cut with «правая кнопка — закрепить»", cut and tip.size.y < DetailsPanel.CARD_MAX_BODY + DetailsPanel.CARD_ICON + 200, str(tip.size) if tip != null else "нет")
		await shot("tip_long_spell")
		await _unhover()
		_rmb(longest)
		await frames(4)
		await _move_to(Vector2(40, 40))  # the cursor away
		await frames(10)
		var pinned := DetailsPanel.pinned_card()
		step("pinned it stays when the cursor goes", pinned != null and pinned.visible and pinned.pinned() == longest.card_title(longest.tooltip_text))
		var body := pinned.find_child("DetailsText", true, false) as RichTextLabel if pinned != null else null
		step("and its text scrolls", body != null and body.scroll_active, str(body.get_content_height()) if body != null else "")
		await shot("spell_pinned")
		var lock := pinned.find_child("DetailsUnpin", true, false) as Button if pinned != null else null
		if lock != null:
			lock.pressed.emit()
			await frames(2)
		step("the lock lets it go", DetailsPanel.pinned_card() == null)

	# Card in card in a creature's card: Bane on the wolf links Bane's card.
	var wolf_id: String = CombatRules.enemies(s)[0]
	ConditionRules.add_effect(CombatRules.fighter(s, wolf_id), {"condition": "", "ends": {}, "source": {"kind": "spell", "id": "bane", "name": "Бедствие"}})
	node("EventBus").card_requested.emit(wolf_id)
	await frames(6)
	var view := find(screen(), "CardView") as Control
	var bane: Node = find(view, "CardStatus_Бедствие") if view != null else null
	var cell := bane.find_children("*", "IconSlot", true, false)[0] as IconSlot if bane != null else null
	if step("the wolf's card shows Bane among its statuses", cell != null):
		_rmb(cell)
		await frames(4)
		var pinned := DetailsPanel.pinned_card()
		var linked: DetailsPanel = null
		if pinned != null:
			linked = await _onto_link(pinned, "DetailsText", "Бедствие")
		step("pinned, «Бедствие» in its source line shows the spell's card", linked != null and linked.title() == "Бедствие" and linked.body().contains("Заклинание 1 круга"),
			(linked.title() if linked != null else "нет") + _how())
		await shot("creature_status_card_in_card")
		_off_link()
		await _move_to(Vector2(40, 40))
		if pinned != null:
			pinned.unpin()
	if view != null:
		view.visible = false


func _my_turn(gs: Node, s: GameSession) -> bool:
	return screen_is("fight") and not gs.is_busy() and not gs.combat_playing and CombatRules.player_can_act(s)


func _rmb(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = c.get_global_rect().get_center()
	ev.global_position = ev.position
	c._gui_input(ev)


## The card `c` makes for its tooltip, set over it where the tooltip stands.
func _hover(c: Control) -> void:
	if is_instance_valid(_hovered):
		_hovered.queue_free()
	var card := (c as IconSlot)._make_custom_tooltip(c.tooltip_text) as Control
	card.top_level = true
	card.z_index = 60
	screen().add_child(card)
	await frames(4)
	var r := c.get_global_rect()
	card.position = Vector2(clampf(r.position.x, 0, 1600 - card.size.x), maxf(0.0, r.position.y - card.size.y - 8))
	_hovered = card
	await frames(2)


func _unhover() -> void:
	if is_instance_valid(_hovered):
		_hovered.queue_free()
	_hovered = null
	await frames(2)


## The cursor onto `word` in `pinned`'s `node_name` text (its line by the text, its place by the font) until the card of its
## link comes up beside it; null — none did. A RichTextLabel finds its link under the window's own cursor: the playtest's
## window stands on a hidden desktop with no cursor of its own (tool_base.run_unseen), so where the label does not answer
## the motion by itself its own signal is given, as the cursor on the link gives it, and `_by_signal` says so.
func _onto_link(pinned: DetailsPanel, node_name: String, word: String) -> DetailsPanel:
	_by_signal = null
	var rt := pinned.find_child(node_name, true, false) as RichTextLabel
	var parsed := rt.get_parsed_text() if rt != null else ""
	var at := parsed.find(word)
	if at < 0:
		return null
	var line := rt.get_character_line(at)
	var first := at
	while first > 0 and rt.get_character_line(first - 1) == line:
		first -= 1
	var top := float(rt.get_line_offset(line))
	var bottom := float(rt.get_line_offset(line + 1)) if line + 1 < rt.get_line_count() else float(rt.get_content_height())
	var font := rt.get_theme_font("normal_font")
	var px := rt.get_theme_font_size("normal_font_size")
	var before := font.get_string_size(parsed.substr(first, at - first), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var mid := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / 2.0
	var r := rt.get_global_rect()
	await _move_to(Vector2(r.position.x + before + mid, r.position.y + (top + bottom) / 2.0), 3)
	if pinned.linked_card() == null:
		var ref := ""
		for l: Dictionary in (pinned.get("_card") as Dictionary).get("refs", []):
			if str(l["text"]) == word:
				ref = str(l["ref"])
		rt.meta_hover_started.emit(ref)
		_by_signal = rt
		_by_ref = ref
		await frames(3)
	return pinned.linked_card()


## The cursor off the link: the label's signal too when it was given by `_onto_link`.
func _off_link() -> void:
	if _by_signal != null and is_instance_valid(_by_signal):
		_by_signal.meta_hover_ended.emit(_by_ref)
	_by_signal = null


func _how() -> String:
	return " (сигнал ссылки: у скрытого рабочего стола нет курсора)" if _by_signal != null else " (курсором)"


## The real cursor to `at` (the canvas's own coordinates, the window is the base size scaled) and its motion to the window.
func _move_to(at: Vector2, wait := 2) -> void:
	Input.warp_mouse(root.get_final_transform() * at)
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	root.push_input(e, true)
	await frames(wait)


## The card of a tooltip shown now.
func _shown_tip() -> Control:
	return _hovered if is_instance_valid(_hovered) else null


func _title(card: Control) -> String:
	var l := card.find_child("TipTitle", true, false) as Label
	return l.text if l != null else ""


func _text(card: Control) -> String:
	var l := card.find_child("TipText", true, false) as RichTextLabel
	return l.text if l != null else ""
