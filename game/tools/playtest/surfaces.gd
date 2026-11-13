extends "res://tools/playtest/playtest_base.gd"
## Surfaces a damage leaves (python tools/godot_playtest.py --scenario surfaces), v0.8.4.43.45: puddles beside the hero,
## lightning over one — water under current, radiance over another — blessed water, an imp's fire on the dry floor —
## hellfire; each drawn as the map's second layer, whole and close up; a round later the current is gone.


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
	gs.start_combat([{"monster": "zombie", "name": "Зомби"}], {"sneak": true, "stealth_total": 99})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight") and CombatRules.is_player_turn(s) and not gs.is_busy(), 30.0)):
		return
	Cheats.toggle(s.character, "god")
	var hero := CombatRules.player(s)
	var g := FightGrid.grid(s, data)
	var free: Array[Vector2i] = []
	var at0 := FightGrid.cell(hero)
	for dy: int in range(-3, 4):
		for dx: int in range(1, 8):
			var at := at0 + Vector2i(dx, dy)
			if FightGrid.walkable(g, at) and not FightGrid.bodies(s).has(at):
				free.append(at)
	if not step("room beside the hero", free.size() >= 9, "%d squares" % free.size()):
		return
	var lines: Array[String] = []
	for at: Vector2i in free.slice(0, 6):
		FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)
	FightField.react(s, data, "lightning", free.slice(0, 3) as Array[Vector2i], hero, lines)
	FightField.react(s, data, "radiant", free.slice(3, 6) as Array[Vector2i], hero, lines)
	FightField.react(s, data, "fire", free.slice(6, 9) as Array[Vector2i], {"id": "imp_x", "monster": "imp"}, lines)
	var looks := {}
	for v: Dictionary in SpellEffects.zone_view(s, data):
		looks[str(v["name"])] = str((v.get("look", {}) as Dictionary).get("ground", ""))
	step("water under current", looks.get("Вода под током", "") == "electric_water", str(looks))
	step("blessed water", looks.get("Освящённая вода", "") == "blessed_water")
	step("hellfire", looks.get("Адский огонь", "") == "hellfire")
	step("the lines tell it", " · ".join(lines).contains("Вода под током"), " · ".join(lines))
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	var field: Control = find(screen(), "Field")
	field.call("zoom", 2.0, field.size / 2.0)
	await frames(3)
	await shot("surfaces_on_the_map")
	field.call("zoom", 12.0, field.call("cell_point", free[4]))
	await frames(6)
	await shot("surfaces_close")
	s.combat["round"] = int(s.combat.get("round", 1)) + 1
	SpellEffects.zones_expire(s)
	step("the current goes after its round", not SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "electric_water"))
	step("the blessing stays", SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "blessed_water"))
