extends "res://tools/playtest/playtest_base.gd"
## The fight on the grid (python tools/godot_playtest.py --scenario grid), v0.8.4: a fight on the map of the tavern by clicks:
## a walk, a door shut, barred and unbarred, a jump, oil on a square set alight, a crate pushed, a way out with a foe after
## the hero to the next map.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	gs.start_combat([{"monster": "goblin", "name": "Гоблин", "x": 1, "y": 1}], {})
	if not step("the fight is on the map", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy(), 60.0)
	await frames(3)
	s.character["hp"] = 500
	await shot("start")
	var p := CombatRules.player(s)
	var goal := _stop(s, data)
	var moved_from := FightGrid.cell(p)
	await click_cell(goal)
	step("a click walks the hero", await wait_until(func() -> bool: return FightGrid.cell(p) != moved_from and not gs.is_busy(), 10.0), FightGrid.tag(FightGrid.cell(p)))
	await _door(s, data)
	await _jump(s, data)
	await _fire(s, data)
	await _crate(s, data)
	await _flee(s, data)


## A square the walk reaches, a step or two away.
func _stop(s: GameSession, data: Dictionary) -> Vector2i:
	var routes := CombatRules.hero_routes(s, data)
	for at: Vector2i in FightGrid.stops(s, CombatRules.player(s), routes):
		if int(routes[at][0]) >= 1:
			return at
	return FightGrid.cell(CombatRules.player(s))


func _fresh(s: GameSession) -> void:
	var e := CombatRules.economy(s)
	e["action"] = 1
	e["move"] = 6
	e["walked"] = 2
	node("EventBus").state_changed.emit()
	await frames(3)
	find(screen(), "FightUi").call("set_filter", "COMBAT_TAB_COMMON")
	await frames(3)


func _door(s: GameSession, data: Dictionary) -> void:
	var m := FightGrid.map(s, data)
	if not step("the map has a door", not (m["doors"] as Array).is_empty()):
		return
	var d: Dictionary = m["doors"][0]
	var door := Vector2i(int(d["x"]), int(d["y"]))
	var g := FightGrid.grid(s, data)
	for way: Vector2i in WalkRules.DIRS:
		if FightGrid.walkable(g, door + way) and FightGrid.flags_at(g, door + way) & FightGrid.DOOR == 0 and not FightGrid.bodies(s, CombatRules.PLAYER).has(door + way):
			FightGrid.put(CombatRules.player(s), door + way)
			break
	s.combat["doors"][FightGrid.tag(door)] = {"open": true}
	FightGrid.changed(s)
	await _fresh(s)
	await shot("door_open")
	var close: Button = find(screen(), "Act_door_close")
	if step("«Закрыть дверь» beside a door", close != null and not close.disabled):
		await press(close)
		step("the door is shut", FightGrid.shut(s, FightGrid.grid(s, data), door))
	await _fresh(s)
	var bar: Button = find(screen(), "Act_door_bar")
	if step("«Подпереть дверь»", bar != null and not bar.disabled):
		await press(bar)
		step("no way through it", FightGrid.fast(s, FightGrid.grid(s, data), door) and not CombatRules.hero_routes(s, data).has(door))
	await _fresh(s)
	var unbar: Button = find(screen(), "Act_door_unbar")
	if step("«Убрать подпорку»", unbar != null and not unbar.disabled):
		await press(unbar)
	await shot("door_done")


func _jump(s: GameSession, data: Dictionary) -> void:
	await _fresh(s)
	var jump: Button = find(screen(), "Do_jump")
	if not step("«Прыжок»", jump != null and not jump.disabled, jump.tooltip_text if jump != null else ""):
		return
	await press(jump)
	await frames(2)
	var squares := CombatRules.jump_squares(s, data)
	await shot("jump_squares")
	var to: Vector2i = squares.keys()[0]
	await click_cell(to)
	step("the hero jumped", FightGrid.cell(CombatRules.player(s)) == to, FightGrid.tag(to))


func _fire(s: GameSession, data: Dictionary) -> void:
	await _fresh(s)
	s.character["inventory"]["oil_flask"] = 2
	node("EventBus").state_changed.emit()
	await frames(3)
	find(screen(), "FightUi").call("set_filter", "COMBAT_TAB_ITEMS")
	await frames(3)
	var flask: Button = find(screen(), "Item_oil_flask")
	if not step("the flask on the items tab", flask != null and not flask.disabled):
		return
	await press(flask)
	await frames(2)
	var at := _stop(s, data)
	await click_cell(at)
	step("oil on the square", (s.combat.get("oil", {}) as Dictionary).has(FightGrid.tag(at)))
	var lines: Array[String] = []
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	node("EventBus").state_changed.emit()
	await frames(4)
	step("the oil burns as a zone", SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "fire"))
	await shot("fire")


func _crate(s: GameSession, data: Dictionary) -> void:
	var g := FightGrid.grid(s, data)
	var hero := FightGrid.cell(CombatRules.player(s))
	for way: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if FightGrid.walkable(g, hero + way) and FightGrid.walkable(g, hero + way * 2) and not FightGrid.bodies(s).has(hero + way) and not FightGrid.bodies(s).has(hero + way * 2):
			s.combat["blocks"][FightGrid.tag(hero + way)] = FightField._block(data, "barrel", "бочка")
			FightGrid.changed(s)
			await _fresh(s)
			await shot("barrel")
			var push: Button = find(screen(), "Act_block_push")
			if step("«Толкнуть вещь»", push != null and not push.disabled, push.tooltip_text if push != null else ""):
				await press(push)
				step("the barrel moved", (s.combat["blocks"] as Dictionary).has(FightGrid.tag(hero + way * 2)))
			return


func _flee(s: GameSession, data: Dictionary) -> void:
	var gs := node("GameState")
	var m := FightGrid.map(s, data)
	var open: Array = FightGrid.exits(s, data).filter(func(e: Dictionary) -> bool: return WayRules.blocked(s, data, str(e["room"]), str(e["to"])).is_empty())
	if not step("a way out of the place", not open.is_empty(), str(m["id"])):
		return
	var e: Dictionary = open[0]
	var way := Vector2i(int(e["ax"]), int(e["ay"]))
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(CombatRules.player(s), way)
	FightGrid.put(foe, FightGrid.free_near(s, data, way, 1))
	var room := s.room_id
	await _fresh(s)
	await shot("at_the_way_out")
	var flee: Button = find(screen(), "Do_flee")
	if not step("«Уйти» at a way out", flee != null and not flee.disabled, flee.tooltip_text if flee != null else ""):
		return
	await press(flee)
	await frames(4)
	step("the hero is in the next room, the fight goes on", s.room_id != room and CombatRules.active(s), s.room_id)
	await shot("next_map")
	for i: int in 6:
		if not (s.combat.get("chasers", []) as Array).is_empty() and CombatRules.is_player_turn(s):
			var end: Button = find(screen(), "EndTurnButton")
			if end != null and not end.disabled:
				await press(end)
			await wait_until(func() -> bool: return (CombatRules.is_player_turn(s) or not CombatRules.active(s)) and not gs.is_busy(), 30.0)
	step("the foe came through the same way", str(foe.get("status")) == "active", str(foe.get("status")))
	await shot("chased")
