extends "res://tools/playtest/playtest_base.gd"
## The card at the cursor (python tools/godot_playtest.py --scenario tip_card, v0.8.4.43.15), the author's findings on
## 0.8.4.43.8: the rests tell what they give; a thing's right button pins its card and opens its menu; in a fight
## «Захват» has its name on top; a long spell's card is one size with «the right button pins it»; the right button pins
## it so it stays when the cursor goes, and lets it go again. A tooltip of Godot does not come up in the playtest's
## window, so the card an icon makes for it (`_make_custom_tooltip`) is set where the tooltip stands.

var _hovered: Control


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
		step("its card one size: the text cut with «правая кнопка — закрепить»", cut and tip.size.y < DetailsPanel.CARD_MAX_BODY + 200, str(tip.size) if tip != null else "нет")
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


func _move_to(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	root.push_input(e)
	await frames(2)


## The card of a tooltip shown now.
func _shown_tip() -> Control:
	return _hovered if is_instance_valid(_hovered) else null


func _title(card: Control) -> String:
	var l := card.find_child("TipTitle", true, false) as Label
	return l.text if l != null else ""


func _text(card: Control) -> String:
	var l := card.find_child("TipText", true, false) as RichTextLabel
	return l.text if l != null else ""
