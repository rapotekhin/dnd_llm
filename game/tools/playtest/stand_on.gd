extends "res://tools/playtest/playtest_base.gd"
## Standing on a body or a thing (python tools/godot_playtest.py --scenario stand_on), v0.8.4.42.20, the author: «не могу
## кастануть на себя заклинание, если стою на предмете… не могу пойти на предмет… где лежит труп, туда тоже не могу встать».
## In a fight a plain click at a body opens it, Shift + a click walks onto its square, a heal at the hero's square there goes
## to the hero, not the body; after the fight Shift + a click stands the hero on the body's square on the map.


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
	gs.start_combat([{"monster": "goblin", "name": "Гоблин"}, {"monster": "goblin", "name": "Гоблин"}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy(), 60.0)
	await frames(3)
	s.character["hp"] = 500
	var ids: Array = CombatRules.enemies(s)
	var dead := CombatRules.fighter(s, str(ids[0]))
	var hero := FightGrid.cell(CombatRules.player(s))
	var g := FightGrid.grid(s, data)
	var spot := FightGrid.NONE
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if FightGrid.walkable(g, hero + d) and not FightGrid.bodies(s).has(hero + d):
			spot = hero + d
			break
	if not step("a square beside the hero", spot != FightGrid.NONE):
		return
	FightGrid.put(dead, spot)
	dead["status"] = "dead"
	dead["hp"] = 0
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(4)

	step("the body's square is on the hero's way", (find(screen(), "Field").get("routes") as Dictionary).has(spot))
	await click_cell(spot)
	step("a plain click at the body does not walk", FightGrid.cell(CombatRules.player(s)) == hero)
	var menu: Node = find(screen(), "FoeMenu")
	if menu != null:
		menu.hide()
	await _shift(true)
	await click_cell(spot)
	await _shift(false)
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(6)
	step("Shift + a click walks onto the body's square", FightGrid.cell(CombatRules.player(s)) == spot, str(FightGrid.cell(CombatRules.player(s))))
	await shot("on_the_body")

	s.character["hp"] = int(s.character["max_hp"]) - 6
	var hp: int = s.character["hp"]
	var cure: Button = find(screen(), "Cast_cure_wounds")
	if step("Cure Wounds on the tab", cure != null):
		await press(cure)
		await frames(3)
		await click_cell(spot)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("the heal at the hero's square goes to the hero, not the body", int(s.character["hp"]) > hp, "%d → %d" % [hp, int(s.character["hp"])])
	await shot("healed")

	var other := CombatRules.fighter(s, str(ids[1]))
	other["status"] = "dead"
	other["hp"] = 0
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var lines := CombatRules.after_player_action(s, data)
	step("both goblins down", str(s.combat.get("outcome", "")) == "victory", str(lines))
	gs.call("_combat_outcome") if gs.has_method("_combat_outcome") else null
	var finish: Array = [null]
	await wait_until(func() -> bool:
		finish[0] = find(screen(), "FinishCombat")
		return finish[0] != null and finish[0].is_visible_in_tree(), 30.0)
	if not step("the fight won", finish[0] != null):
		return
	await press(finish[0])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	await frames(6)
	var field: Control = find(screen(), "Field")
	var at := Vector2i(-1, -1)
	var ref := ""
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		var cell: Vector2i = field.call("cell_of", "cr:" + str(c["id"]))
		if str(c["state"]) == CreatureRules.DEAD and cell.x >= 0 and cell != field.call("hero_cell"):
			at = cell
			ref = "cr:" + str(c["id"])
	if not step("a body on the map", at.x >= 0, str(CreatureRules.here(s, s.room_id).map(func(c: Dictionary) -> String: return str(c["state"])))):
		return
	await click_cell(at)
	await wait_until(func() -> bool: return not field.call("walking"), 20.0)
	await frames(4)
	step("a plain click walks up to it, not onto it", field.call("hero_cell") != at, "%s / %s" % [field.call("hero_cell"), at])
	screen().call("_close_menu")
	for w: Node in screen().find_children("*", "ModalFrame", true, false):  # the left button searched it: its window shut
		(w as Control).visible = false
	await _shift(true)
	await click_cell(at)
	await _shift(false)
	await wait_until(func() -> bool: return not field.call("walking"), 20.0)
	await frames(6)
	step("Shift + a click stands the hero on the body's square", field.call("hero_cell") == at, "%s / %s (%s)" % [field.call("hero_cell"), at, ref])
	await shot("map_on_the_body")


func _shift(down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.physical_keycode = KEY_SHIFT
	key.pressed = down
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await frames(2)
