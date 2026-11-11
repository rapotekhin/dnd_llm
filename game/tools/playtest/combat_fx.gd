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
	gs.start_combat([{"monster": "wolf", "count": 2, "name": "Волк"}], {})
	if not step("the combat screen", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy(), 60.0)):
		return
	await frames(5)
	var s: GameSession = gs.session
	var foe := str(CombatRules.enemies(s)[0])
	var cases := [["hit", foe], ["heal", CombatRules.PLAYER], ["dodge", foe], ["crit", CombatRules.PLAYER], ["spell", foe]]
	for c: Array in cases:
		var n := find(screen(), "Turn_" + str(c[1])) as Control
		if not step("the chip of " + str(c[1]), n != null):
			continue
		CombatFx.play(n, str(c[0]))
		await frames(4)  # mid-way
		await shot(str(c[0]))
		await frames(30)
	CombatRules.player(s)["hidden"] = true
	node("EventBus").state_changed.emit()
	await frames(5)
	var me := find(find(screen(), "Party"), "Portrait_hero") as Control  # the party column (v0.8.4.43.10)
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
	var atk := find(screen(), "Attack_main") as Button
	step("the action buttons stay on tabs, without numbers in the text", atk != null and not atk.text.begins_with("1 · ")
		and find(screen(), "Filter_class") != null, atk.text if atk != null else "")  # the hotbar's kind tabs (v0.8.4.43.1)
	await _map_anims(s, foe)


## The animations on the map (v0.8.4.23): the token with a sword and a shield, then a still of every kind mid-way — strikes,
## spells, outcomes, misses and moves — and a real blow played by the engine's event.
func _map_anims(s: GameSession, foe: String) -> void:
	var data: Dictionary = node("Catalog").data
	var gs := node("GameState")
	s.character["equipped"]["main_hand"] = "longsword"
	s.character["equipped"]["shield"] = "shield"
	node("EventBus").state_changed.emit()
	await frames(5)
	var field = find(screen(), "Field")
	var anims = find(screen(), "FightAnims")
	if not step("the animations' layer on the map", field != null and anims != null):
		return
	field.zoom(5.0, field.cell_point(FightGrid.cell(CombatRules.player(s))))  # close: the stills are read by eye
	await frames(2)
	var me: Dictionary = {}
	for f: Dictionary in field.fighters:
		if str(f["id"]) == CombatRules.PLAYER:
			me = f
	step("the hero's token shows a sword and a shield", str(me.get("gear", {}).get("sprite", "")) == "sword" and bool(me.get("gear", {}).get("shield", false)), str(me.get("gear", {})))
	var wolf_gear: Dictionary = {}
	for f: Dictionary in field.fighters:
		if str(f["id"]) == foe:
			wolf_gear = f["gear"]
	step("a wolf's token has nothing in its paws", str(wolf_gear.get("sprite", "x")).is_empty(), str(wolf_gear))
	await shot("token_sword_shield")
	var by := FightGrid.tag(FightGrid.cell(CombatRules.player(s)))
	var to := FightGrid.tag(FightGrid.cell(CombatRules.fighter(s, foe)))
	var cells: Array = []
	var aim := FightGrid.cell(CombatRules.fighter(s, foe))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			cells.append(FightGrid.tag(aim + Vector2i(dx, dy)))
	var base := {"by": CombatRules.PLAYER, "to": foe, "by_at": by, "to_at": to, "n": 3, "cells": cells}
	var looks := {"swing": {"sprite": "sword", "dtype": "slashing"}, "thrust": {"sprite": "polearm", "dtype": "piercing"},
		"smash": {"sprite": "blunt", "dtype": "bludgeoning"}, "shot": {"sprite": "bow", "proj": "arrow"}, "throw": {"sprite": "axe"},
		"overshoot": {"proj": "arrow"}, "undershoot": {"proj": "bolt"}, "bolt": {"dtype": "fire"}, "beam": {"dtype": "force"},
		"burst": {"dtype": "fire"}, "cone": {"dtype": "fire"}, "line": {"dtype": "lightning"}, "zone": {"dtype": "poison"},
		"touch": {"dtype": "heal"}, "impact": {"dtype": "slashing"}, "crit": {"dtype": "radiant"}}
	var shown := 0
	for kind: String in data["anims"]["kinds"]:
		var row: Dictionary = data["anims"]["kinds"][kind]
		if str(row["group"]) == "state":
			continue
		var phases: Array = row["phases"]
		var main := 0
		for i in phases.size():
			if str(phases[i]["phase"]) in ["hit", "travel"]:
				main = i
				break
		var a: Variant = anims.hold(base.merged(looks.get(kind, {}), true), kind, main, 0.55)
		if a == null:
			step("a still of " + kind, false)
			continue
		await frames(2)
		await shot("anim_" + kind)
		shown += 1
	anims.clear()
	step("every kind but the states has a still", shown == 41, str(shown))
	# A real blow: the engine's event played by the player at the normal speed.
	anims.speed = 1.0
	gs.combat_delay = 0.6
	var e := AnimRules.blow(s, data, CombatRules.player(s), CombatRules.fighter(s, foe), Attack.blade(s, data, CombatRules.player(s)))
	AnimRules.result(s, data, e, CombatRules.fighter(s, foe), "miss")
	anims.play(AnimRules.take(s))
	await frames(6)
	step("the engine's blow plays on the map", anims.busy() and anims.get_child_count() > 0)
	await shot("anim_live_blow")
	await wait_until(func() -> bool: return not anims.busy(), 5.0)
	step("the blow ends and its animation is gone", not anims.busy())
