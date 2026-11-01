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
	var menu: Control = find(screen(), "ThingMenu")
	step("a click opens its acts", menu.visible)
	step("and does nothing by itself", FightGrid.cell(CombatRules.player(s)) == hero and CombatRules.economy(s).hash() == money.hash())
	var blow: Button = find(menu, "FoeAct_Attack_main")
	step("the blade out of reach is grey with why", blow != null and blow.disabled and not blow.tooltip_text.is_empty(), blow.tooltip_text if blow else "")
	step("a heal is not offered at a foe", find(menu, "FoeAct_Cast_cure_wounds") == null)
	await shot("foe_menu")
	menu.visible = false

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
	var flame: Button = find(menu, "FoeAct_Cast_sacred_flame")
	if step("the flame in the foe's menu", flame != null and not flame.disabled, flame.tooltip_text if flame else ""):
		await press(flame)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("the spell went", int(CombatRules.economy(s).get("action", 1)) == 0)
		step("the map stays where the player left it", field.call("tile") == view[0] and field.call("corner") == view[1], "%s → %s" % [view, field.call("corner")])
	await shot("after_spell")
