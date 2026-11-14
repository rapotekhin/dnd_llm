extends "res://tools/playtest/playtest_base.gd"
## Surfaces a damage leaves (python tools/godot_playtest.py --scenario surfaces), v0.8.4.43.45: puddles beside the hero,
## lightning over one — water under current, radiance over another — blessed water, an imp's fire on the dry floor —
## hellfire, cold over the current — ice that ends it (v0.8.4.43.47); each drawn as the map's second layer, whole and close up;
## a round later the current is gone. As in BG3 and Divinity (v0.8.4.43.62): a puddle reacts whole — the spark on one square
## runs through all of it, the cold freezes all of it, fire on one square of oil lights all of it — and the cleric's Sacred Flame
## goes at a bare square of water by a click, blessing the whole puddle.


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
	var pools := _pools(s, data, FightGrid.cell(hero), 6)
	if not step("room for six puddles apart beside the hero", pools.size() == 6, "%d" % pools.size()):
		return
	var spark: Array[Vector2i] = pools[0]
	var holy: Array[Vector2i] = pools[1]
	var dry: Array[Vector2i] = pools[2]
	var frost: Array[Vector2i] = pools[3]
	var oil: Array[Vector2i] = pools[4]
	var click: Array[Vector2i] = pools[5]
	var lines: Array[String] = []
	for pool: Array[Vector2i] in [spark, holy, frost, click]:
		for at: Vector2i in pool:
			FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)
	for at: Vector2i in oil:
		FightField.splash(s, data, at, {"liquid": "oil"}, "Масло", lines)
	FightField.lands(s, data, "lightning", [spark[0]] as Array[Vector2i], hero, lines)
	FightField.lands(s, data, "radiant", [holy[1]] as Array[Vector2i], hero, lines)
	FightField.lands(s, data, "fire", dry, {"id": "imp_x", "monster": "imp"}, lines)
	FightField.lands(s, data, "lightning", [frost[0]] as Array[Vector2i], hero, lines)
	FightField.lands(s, data, "cold", [frost[2]] as Array[Vector2i], hero, lines)  # ice ends the current (v0.8.4.43.47), all of it
	FightField.lands(s, data, "fire", [oil[0]] as Array[Vector2i], hero, lines)
	var looks := {}
	for v: Dictionary in SpellEffects.zone_view(s, data):
		looks[str(v["name"])] = str((v.get("look", {}) as Dictionary).get("ground", ""))
	step("water under current", looks.get("Вода под током", "") == "electric_water", str(looks))
	step("blessed water", looks.get("Освящённая вода", "") == "blessed_water")
	step("hellfire", looks.get("Адский огонь", "") == "hellfire")
	step("ice", looks.get("Лёд", "") == "ice")
	step("the spark on one square runs through the whole puddle", _all(spark, _under(s, "electric_water")), str(_under(s, "electric_water")))
	step("the radiance on one square blesses the whole puddle", _all(holy, _under(s, "blessed_water")))
	step("the cold on one square freezes the whole puddle and ends its current", _all(frost, _under(s, "ice"))
		and not frost.any(func(at: Vector2i) -> bool: return _under(s, "electric_water").has(FightGrid.tag(at))))
	step("fire on one square of oil lights all of it", _all(oil, (s.combat["fires"] as Dictionary).keys()), str(s.combat["fires"]))
	step("the lines tell it", " · ".join(lines).contains("Вода под током"), " · ".join(lines))

	# Sacred Flame at a bare square of water by a click: the cleric's spell of one target, as in BG3.
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	var flame: Button = find(screen(), "Cast_sacred_flame")
	if step("Sacred Flame on the bar", flame != null and not flame.disabled):
		await press(flame)
		await frames(3)
		var log_n: int = (s.combat.get("log", []) as Array).size()
		await click_cell(click[1])
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		var said := " | ".join((s.combat.get("log", []) as Array).slice(log_n))
		step("a click on a bare square of water casts Sacred Flame there and blesses the whole puddle", _all(click, _under(s, "blessed_water")),
			said.left(300))
	# A flask of water from the belt onto the burning oil by the items tab's button (v0.8.4.43.63): the fire there is out.
	s.character["inventory"]["empty_flask"] = 1
	var filled := Thing.nth(s.character, "empty_flask", 0)  # drawn full at a well
	filled["pints"] = 1.0
	filled["liquid"] = "water"
	ItemRules.belt_put(s.character, data, s.items, "empty_flask")
	hero["points"] = CombatRules.fresh_points(s, data, hero)
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	find(screen(), "FightUi").call("set_filter", "COMBAT_TAB_ITEMS")
	await frames(2)
	var flask: Button = find(screen(), "Item_empty_flask")
	if step("the flask of water is at hand in the fight", flask != null and not flask.disabled and (flask.text + flask.tooltip_text).contains("вода"),
		(flask.text + " | " + flask.tooltip_text) if flask != null else "нет"):
		await press(flask)
		await frames(3)
		await click_cell(oil[1])
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("the flask thrown at the burning oil puts the fire out there", not (s.combat["fires"] as Dictionary).has(FightGrid.tag(oil[1]))
			and FightField.douses_at(s, data, oil[1]), str(s.combat["fires"]))
		step("the flask broke", int(s.character["inventory"].get("empty_flask", 0)) == 0)
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	var field: Control = find(screen(), "Field")
	field.call("zoom", 2.0, field.size / 2.0)
	await frames(3)
	await shot("surfaces_on_the_map")
	field.call("zoom", 12.0, field.call("cell_point", holy[1]))
	await frames(6)
	await shot("surfaces_close")
	field.call("zoom", -12.0, field.size / 2.0)
	await frames(3)
	field.call("zoom", 12.0, field.call("cell_point", frost[1]))
	await frames(6)
	await shot("ice_close")
	field.call("zoom", -12.0, field.size / 2.0)
	await frames(3)
	field.call("zoom", 12.0, field.call("cell_point", oil[1]))
	await frames(6)
	await shot("oil_burning_close")
	s.combat["round"] = int(s.combat.get("round", 1)) + 1
	SpellEffects.zones_expire(s)
	step("the current goes after its round", not SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "electric_water"))
	step("the blessing stays", SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "blessed_water"))


## `n` puddles of three squares in a row beside `from`, free and walked, none touching another or a water of the map, so
## each reacts as a body of its own.
func _pools(s: GameSession, data: Dictionary, from: Vector2i, n: int) -> Array:
	var g := FightGrid.grid(s, data)
	var taken := FightGrid.bodies(s)
	var out: Array = []
	var near := {}
	for dy: int in range(-6, 7):
		for dx: int in range(1, 12):
			var row: Array[Vector2i] = []
			var ok := true
			for i in 3:
				var at := from + Vector2i(dx + i, dy)
				if not FightGrid.walkable(g, at) or taken.has(at) or near.has(at) or FightField.douses_at(s, data, at):
					ok = false
				for d: Vector2i in WalkRules.DIRS:
					if FightField.douses_at(s, data, at + d):
						ok = false
				row.append(at)
			if not ok or not FightGrid.reaches(s, data, CombatRules.player(s), row[1]):
				continue
			out.append(row)
			for at: Vector2i in row:
				for d: Vector2i in [Vector2i.ZERO] + WalkRules.DIRS:
					near[at + d] = true
			if out.size() == n:
				return out
	return out


func _under(s: GameSession, spell: String) -> Array:
	var out: Array = []
	for z: Dictionary in SpellEffects.zones(s):
		if str(z["spell"]) == spell:
			out.append_array(z["cells"])
	return out


func _all(cells: Array[Vector2i], keys: Array) -> bool:
	return cells.all(func(at: Vector2i) -> bool: return keys.has(FightGrid.tag(at)))
