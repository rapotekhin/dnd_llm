extends "res://tools/playtest/playtest_base.gd"
## Monster traits in a live fight (python tools/godot_playtest.py --scenario traits), v0.8.4.27.1: a swarm of rats comes
## into the hero's square and bites there, drawn small in its corner; a click on the shared square opens the swarm's acts;
## a sea hag's look frightens the hero.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	gs.start_combat([{"monster": "swarm_of_rats", "name": "Рой крыс", "x": 1, "y": 1}, {"monster": "sea_hag", "name": "Морская карга", "x": 2, "y": 1}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	Cheats.toggle(s.character, "god")
	var data: Dictionary = node("Catalog").data
	var rats := {}
	var start := FightGrid.cell(CombatRules.player(s))
	var g := FightGrid.grid(s, data)
	var near: Array[Vector2i] = []
	for cell: Vector2i in SightRules.look(s, data, FightGrid.map(s, data), start):
		if WalkRules.distance(cell, start) in range(2, 4) and FightGrid.walkable(g, cell) and FightGrid.clear(g, start, cell) and not FightGrid.bodies(s).has(cell):
			near.append(cell)
	for id: String in CombatRules.enemies(s):  # beside the hero, in sight: they come at once
		var f := CombatRules.fighter(s, id)
		FightGrid.put(f, near.pop_front())
		if str(f.get("monster")) == "swarm_of_rats":
			rats = f
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	var feared := false
	var bitten := false
	for i: int in 8:
		await wait_until(func() -> bool: return (CombatRules.is_player_turn(s) or not CombatRules.active(s)) and not gs.is_busy(), 60.0)
		feared = feared or ConditionRules.has(s.character, "frightened")
		bitten = bitten or JSON.stringify(s.chat.slice(-40)).contains("Укусы")
		if FightGrid.cell(rats) == FightGrid.cell(CombatRules.player(s)) and bitten:
			break
		var end: Button = find(screen(), "EndTurnButton")
		if end != null and not end.disabled:
			await press(end)
	var hero := FightGrid.cell(CombatRules.player(s))
	step("the swarm stands in the hero's square", FightGrid.cell(rats) == hero, "%s / %s" % [FightGrid.cell(rats), hero])
	step("and has bitten", bitten)
	await frames(4)
	var field: Control = find(screen(), "Field")
	field.call("zoom", 2.0, field.size / 2.0)
	await frames(3)
	await shot("swarm_in_square")
	await click_cell(hero)
	var menu: PopupMenu = find(screen(), "FoeMenu")
	step("a click on the shared square opens the swarm's acts", menu != null and menu.visible)
	await shot("swarm_menu")
	if menu != null:
		menu.hide()
	step("the hag's look frightens the hero, or the hero stood it", feared or (SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return z.has("spared"))),
		" ".join(SpellEffects.zones(s).map(func(z: Dictionary) -> String: return str(z["name"]))))
