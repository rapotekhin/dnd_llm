extends "res://tools/playtest/playtest_base.gd"
## The fight's view and a foe's menu (python tools/godot_playtest.py --scenario fight_view), v0.8.4.3: a cleric by a goblin:
## a hover names the foe and moves nothing, a click opens its acts and does nothing by itself, the range of a spell from the
## hero, a zoom that a spell does not take back, a watcher at the edge looks inward.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	gs.start_combat([{"monster": "goblin", "name": "Гоблин", "x": 1, "y": 1}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy(), 60.0)
	await frames(3)
	s.character["hp"] = 500
	var field: Control = find(screen(), "Field")
	var id: String = CombatRules.enemies(s)[0]
	var foe := CombatRules.fighter(s, id)
	var hero := FightGrid.cell(CombatRules.player(s))
	var g := FightGrid.grid(s, data)
	for cell: Vector2i in SightRules.look(s, data, FightGrid.map(s, data), hero):
		if WalkRules.distance(cell, hero) in range(3, 7) and FightGrid.walkable(g, cell) and FightGrid.clear(g, hero, cell) and not FightGrid.bodies(s).has(cell):
			FightGrid.put(foe, cell)
			break
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(4)
	var at := FightGrid.cell(foe)

	field.call("zoom", 2.0, field.size / 2.0)
	field.call("emit_signal", "cell_hovered", at)
	await frames(3)
	var view: Array = [field.call("tile"), field.call("corner")]
	var hint: Label = find(screen(), "Hint")
	step("a hover says the name alone", hint.text == str(foe["name"]), hint.text)

	var money := CombatRules.economy(s).duplicate()
	await click_cell(at)
	var menu: PopupMenu = find(screen(), "FoeMenu")
	step("a click opens its acts", menu != null and menu.visible)
	step("and does nothing by itself", FightGrid.cell(CombatRules.player(s)) == hero and CombatRules.economy(s).hash() == money.hash())
	var tabs: Array = _texts(menu)
	step("lists by the tabs, not one long window", tabs.has(tr("COMBAT_TAB_WEAPONS")) and tabs.has(tr("COMBAT_TAB_SPELLS")) and tabs.has(tr("COMBAT_TAB_COMMON")), str(tabs))
	var weapons: PopupMenu = find(menu, "List_" + tr("COMBAT_TAB_WEAPONS"))
	var blow := _line(weapons, "Булава")
	step("the blade out of reach walks up, not grey (v0.8.4.43.51)", blow >= 0 and not weapons.is_item_disabled(blow), weapons.get_item_tooltip(blow) if blow >= 0 else "")
	var magic: PopupMenu = find(menu, "List_" + tr("COMBAT_TAB_SPELLS"))
	var circles: Array = _texts(magic)
	step("the spells inside by circles", circles.has(tr("DETAILS_CANTRIP")) and circles.has(tr("DETAILS_CIRCLE").format({"n": 1})), str(circles))
	var first: PopupMenu = find(magic, "List_" + tr("DETAILS_CIRCLE").format({"n": 1}))
	step("a heal is not offered at a foe", _line(first, str(data["spells"]["cure_wounds"]["name"])) < 0, str(_texts(first)))
	await shot("foe_menu")
	menu.hide()

	var strike: Button = find(screen(), "Attack_melee")  # v0.8.4.43.51: the way the hero walks up to strike, dashed
	if step("«Атака» on the bar", strike != null):
		await press(strike)
		await frames(2)
		field.call("emit_signal", "cell_hovered", at)
		await frames(3)
		var way: Array = field.get("way")
		step("a hover over the foe dashes the way up", way.size() > 1 and bool(field.get("dashed")) and way[0] == hero, "%s %s" % [way, field.get("dashed")])
		step("and the hint says how far", hint.text.contains("подойдёт на"), hint.text)
		await shot("walk_up")
		find(screen(), "FightUi").call("cancel")
		await frames(3)
		field.call("emit_signal", "cell_hovered", at)
		await frames(2)
		step("no way once let go", (field.get("way") as Array).is_empty() and FightGrid.cell(CombatRules.player(s)) == hero)
	var cast: Button = find(screen(), "Cast_sacred_flame")
	if step("a spell at a range on the tab", cast != null):
		await press(cast)
		await frames(3)
		var reach: Dictionary = field.get("reach")
		var far := int(data["spells"]["sacred_flame"]["range_ft"]) / 5
		step("its range shown from the hero", reach.has(at) and reach.keys().all(func(c: Vector2i) -> bool: return WalkRules.distance(c, hero) <= far), str(reach.size()))
		await shot("range")
		find(screen(), "FightUi").call("cancel")
		await frames(3)
		step("gone with the pick", (field.get("reach") as Dictionary).is_empty())
	await click_cell(at)
	menu = find(screen(), "FoeMenu")
	var tricks: PopupMenu = find(find(menu, "List_" + tr("COMBAT_TAB_SPELLS")), "List_" + tr("DETAILS_CANTRIP"))
	var flame := _line(tricks, str(data["spells"]["sacred_flame"]["name"]))
	if step("the flame in the foe's menu", flame >= 0 and not tricks.is_item_disabled(flame), tricks.get_item_tooltip(flame) if flame >= 0 else ""):
		tricks.id_pressed.emit(tricks.get_item_id(flame))
		menu.hide()
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("the spell went", int(CombatRules.economy(s).get("action", 1)) == 0)
		step("the map stays where the player left it", field.call("tile") == view[0] and field.call("corner") == view[1], "%s → %s" % [view, field.call("corner")])
	await shot("after_spell")


func _texts(list: PopupMenu) -> Array:
	var out: Array = []
	for i: int in list.item_count:
		out.append(list.get_item_text(i))
	return out


## The line of `list` that holds `text`, -1 — none.
func _line(list: PopupMenu, text: String) -> int:
	for i: int in list.item_count:
		if list.get_item_text(i).contains(text):
			return i
	return -1
