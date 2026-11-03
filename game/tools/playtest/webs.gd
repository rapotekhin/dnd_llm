extends "res://tools/playtest/playtest_base.gd"
## Webs in a live fight (python tools/godot_playtest.py --scenario webs), v0.8.4.27.3: a giant spider comes into the fight
## among its webs, drawn on the map; the hero stands in a web, is held at the start of the turn and gets «Вырваться»;
## the spider walks its webs freely.


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
	var data: Dictionary = node("Catalog").data
	gs.start_combat([{"monster": "giant_spider", "name": "Гигантский паук", "beside": true}], {"sneak": true, "stealth_total": 99})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight") and CombatRules.is_player_turn(s) and not gs.is_busy(), 30.0)):
		return
	Cheats.toggle(s.character, "god")
	var spider := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var webs := SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == "web")
	var cells: Array[Vector2i] = FightGrid.zone_cells(s, data, webs[0]) if not webs.is_empty() else ([] as Array[Vector2i])
	step("the spider stands among its webs", cells.size() > 1 and FightGrid.in_cells(spider, cells), "%d squares" % cells.size())
	var hero := CombatRules.player(s)
	var free := cells.filter(func(at: Vector2i) -> bool: return not FightGrid.bodies(s).has(at))
	if not step("a web square free for the hero", not free.is_empty()):
		return
	FightGrid.put(hero, free[0])
	webs[0]["dc"] = 99  # the hero fails its save
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	var field: Control = find(screen(), "Field")
	field.call("zoom", 2.0, field.size / 2.0)
	await frames(3)
	await shot("webs_on_the_map")
	await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy() and not gs.combat_playing, 60.0)
	step("the hero is held by the web", ConditionRules.has(s.character, "restrained"))
	step("the spider is not", not ConditionRules.has(spider, "restrained"))
	await frames(3)
	var tab: Button = find_button_by_text(screen(), "Общие")
	if tab != null:
		await press(tab)
	var escape: Button = find_button_by_text(screen(), "Вырваться")
	step("«Вырваться» is there", escape != null and escape.visible)
	await shot("held_in_the_web")
