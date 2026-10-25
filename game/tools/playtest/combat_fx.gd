extends "res://tools/playtest/playtest_base.gd"
## Combat animations (python tools/godot_playtest.py --scenario combat_fx), v0.7.22.14: a fight starts, then each
## effect of CombatFx plays on a chip and a screenshot catches it mid-way — a hit (red), a heal (green), a dodge (a
## step aside), the hero hidden (grey haze).


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	gs.start_combat([{"monster": "wolf", "count": 2, "name": "Волк", "col": 1}], {})
	if not step("the combat screen", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await frames(5)
	var s: GameSession = gs.session
	var foe := str(CombatRules.enemies(s)[0])
	var cases := [["hit", foe], ["heal", CombatRules.PLAYER], ["dodge", foe], ["crit", CombatRules.PLAYER], ["spell", foe]]
	for c: Array in cases:
		var n := find(screen(), "Foe_" + str(c[1])) as Control
		if not step("the chip of " + str(c[1]), n != null):
			continue
		CombatFx.play(n, str(c[0]))
		await frames(4)  # mid-way
		await shot(str(c[0]))
		await frames(30)
	CombatRules.player(s)["hidden"] = true
	node("EventBus").state_changed.emit()
	await frames(5)
	var me := find(screen(), "Foe_" + CombatRules.PLAYER) as Control
	step("the hidden hero is grey", me != null and me.modulate.a < 0.9, str(me.modulate) if me != null else "")
	await shot("hidden")

	# Floating numbers (v0.7.22.30, П9): the foe loses HP — «−5» rises over its chip and goes.
	CombatRules.player(s)["hidden"] = false
	var f := CombatRules.fighter(s, foe)
	f["hp"] = int(f["hp"]) - 5
	node("EventBus").state_changed.emit()
	await frames(3)
	var num := find(screen(), "FxNumber") as Label
	step("a damage number over the foe", num != null and num.text == "−5", num.text if num != null else "")
	await shot("number")
	await wait_until(func() -> bool: return find(screen(), "FxNumber") == null, 3.0)
	step("the number is gone", find(screen(), "FxNumber") == null)
	var queue := find(screen(), "Turn_" + CombatRules.current(s))
	step("the turn queue as portraits, the current one first", queue != null and queue.get_index() == 1)
	step("the hotbar numbers its buttons", (find(screen(), "Attack_main") as Button).text.begins_with("1 · "), (find(screen(), "Attack_main") as Button).text)
