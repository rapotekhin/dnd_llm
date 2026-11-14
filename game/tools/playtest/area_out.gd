extends "res://tools/playtest/playtest_base.gd"
## An area out of a fight (python tools/godot_playtest.py --scenario area_out), v0.8.4.43.55, the author's roadmap «Область
## вне боя»: «огненный шар в клетку, а не в человека, — задетые начинают бой». A wizard of level 5 in the tavern's hall with a
## follower pins Fireball on the hotbar: the mouse over a square lights its area and names who it catches; a square with only
## the hero and its follower is refused; an empty square far off — the spell is cast, no fight; the right button lets it go;
## a click on a person — the fight with all it caught, the follower beside the hero, the Fireball the first blow.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_wizard_yalika")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.room_id = "pushcha-trail"  # nobody lives there and no foe lurks now: the hero's own alone
	while int(s.character["level"]) < 5:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
	var sp: Dictionary = s.character["spells"]
	sp["always"] = (sp.get("always", []) as Array) + ["fireball"]
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	(s.character["features"] as Array).erase(str(CombatRules.cfg(data)["friendly_fire"]["sculpt"]["feature"]))  # the fire for all
	CharacterRules.refresh(s.character, data, s.items)
	Stock.fill_slots(s.character)
	s.character["hp"] = int(s.character["max_hp"])
	for id: String in ["npc_veteran", "npc_mercenary"]:  # the hero's friends stay out of the fight (v0.7.22.18)
		s.shift_attitude(id, 6, data)
	FollowRules.apply(s, {"follow_npc": "npc_veteran", "on": true})
	node("EventBus").state_changed.emit()
	await frames(4)
	var field: Control = find(screen(), "Field")
	var hint: Label = find(screen(), "Hint")
	var bar := screen().get_tree().get_first_node_in_group("hotbar") as Control
	var toasts: Array[String] = []
	node("EventBus").message.connect(func(t: String) -> void: toasts.append(t))
	if not step("Fireball on the hotbar", await _pin(bar)):
		return
	step("pinned as an area", gs.area_pinned() == "fireball")
	step("the line under the map tells what next, no toast over the bar", hint.visible and toasts.is_empty(), "%s | %s" % [hint.text, str(toasts)])
	await shot("pinned")

	# Only the hero and its follower: refused, nothing spent.
	var hero: Vector2i = field.call("hero_cell")
	field.call("emit_signal", "cell_hovered", hero)
	await frames(2)
	var lit: Dictionary = field.get("blast")
	step("the mouse over a square lights the area", lit.size() > 9 and lit.has(hero), str(lit.size()))
	step("the line under the map names the hero and the follower, nobody else", hint.visible and hint.text.contains(str(s.character["name"])) and hint.text.contains("Орвин")
		and (gs.area_aim(hero)["caught"] as Array).all(func(t: Dictionary) -> bool: return str(t["side"]) == "hero"), hint.text)
	await shot("own_area")
	var slots := SpellRules.slots_left(s.character, 3)
	await click_cell(hero)
	step("only the hero's own — refused, no fight, no slot", not CombatRules.active(s) and SpellRules.slots_left(s.character, 3) == slots and gs.area_pinned() == "fireball")

	# An empty square far off: a cast as from the sheet, no fight.
	var empty := _empty_square(gs, s, data, hero)
	if step("an empty square in range", empty != FightGrid.NONE):
		field.call("emit_signal", "cell_hovered", empty)
		await frames(2)
		step("nobody caught there", hint.text.ends_with("—"), hint.text)
		await click_cell(empty)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		step("cast without a fight: a slot spent, the pin gone", not CombatRules.active(s) and SpellRules.slots_left(s.character, 3) == slots - 1 and gs.area_pinned().is_empty(),
			"slots %d → %d" % [slots, SpellRules.slots_left(s.character, 3)])
		await shot("empty_cast")

	# The tavern's hall: a square whose fire takes a person and the follower — the area lit, then let go by the right button.
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(6)
	slots = SpellRules.slots_left(s.character, 3)
	if not step("Fireball pinned again", await _pin(bar)):
		return
	var aim := _fire_square(gs, s, data)
	if not step("a square with a person and the follower in its fire", aim.x >= 0):
		return
	var who: String = (gs.area_aim(aim)["caught"] as Array).filter(func(t: Dictionary) -> bool: return str(t["side"]) == "other")[0]["name"]
	field.call("emit_signal", "cell_hovered", aim)
	await frames(2)
	var a: Dictionary = gs.area_aim(aim)
	var caught: Array = (a["caught"] as Array).filter(func(t: Dictionary) -> bool: return str(t["side"]) == "other")
	step("the area names the person and the follower", (field.get("blast") as Dictionary).has(aim) and hint.text.contains(who) and hint.text.contains("Орвин"), hint.text)
	await shot("area_preview")
	field.cell_right.emit(aim)
	await frames(3)
	step("the right button lets the area go", gs.area_pinned().is_empty() and (field.get("blast") as Dictionary).is_empty())
	await _pin(bar)
	field.call("emit_signal", "cell_hovered", aim)
	await frames(2)

	# The click: the fight with all it caught, the Fireball first.
	var said: Array[String] = []
	node("EventBus").combat_lines.connect(func(l: Array[String]) -> void: said.append_array(l))
	toasts.clear()
	await click_cell(aim)
	if not step("the fight at once", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy(), 60.0)):
		return
	step("no refusal said by the click", toasts.is_empty(), str(toasts))
	await frames(3)
	var in_fight := {}
	for id: String in s.combat.get("fighters", []):
		in_fight[str(CombatRules.fighter(s, id).get("npc_id", id))] = CombatRules.fighter(s, id)
	var missing := caught.filter(func(t: Dictionary) -> bool: return not in_fight.has(str(t["id"])))
	step("everyone caught is in the fight", missing.is_empty() and not caught.is_empty(), "%s; caught %s" % [str(missing.map(func(t: Dictionary) -> String: return str(t["name"]))), str(caught.size())])
	step("the hero first, a slot of the 3rd circle spent", str(s.combat["order"][0]) == CombatRules.PLAYER and SpellRules.slots_left(s.character, 3) == slots - 1,
		"slots %d → %d" % [slots, SpellRules.slots_left(s.character, 3)])
	var log := " · ".join(said)
	step("the Fireball the first blow, the caught saved", log.contains("Огненный шар: " + who) or _hurt(in_fight, caught), log.left(600))
	var friend: Dictionary = in_fight.get("npc_veteran", {})
	step("the follower in the fight on the hero's side", str(friend.get("side", "")) == "ally", str(friend))
	step("the follower took the fire", log.contains("Огненный шар: " + str(friend.get("name", "—"))), log.left(600))
	await shot("fight")


## A square of floor in range whose Fireball takes a person of the room and the follower, the hero if it must. (-1, -1) — none.
func _fire_square(gs: Node, s: GameSession, data: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var map := WalkRules.view(s, data)
	for t: Dictionary in MapSpots.standing(s, data):
		if str(t["kind"]) != "npc" or str(t["side"]) != "other":
			continue
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				var c := Vector2i(int(t["x"]) + dx, int(t["y"]) + dy)
				if not WalkRules.passable(map, data["layouts"], c):
					continue
				var a: Dictionary = gs.area_aim(c)
				var ids: Array = (a["caught"] as Array).map(func(x: Dictionary) -> String: return str(x["id"]))
				if not str(a["why"]).is_empty() or not ids.has("npc_veteran") or not ids.has(str(t["id"])):
					continue
				if not ids.has(Being.HERO):
					return c
				best = c
	return best


## Fireball pressed on the hotbar's class section, as a player pins it. True — pinned.
func _pin(bar: Control) -> bool:
	var cell := find(bar, "Pin_spell_fireball") as BaseButton
	if cell == null:
		return false
	cell.button_pressed = true
	await press(cell)
	await frames(2)
	return node("GameState").area_pinned() == "fireball"


## A free square 9 to 30 squares from the hero where the area catches nobody and may go: away from everyone who stands
## here, then checked by the area itself.
func _empty_square(gs: Node, s: GameSession, data: Dictionary, hero: Vector2i) -> Vector2i:
	var map := WalkRules.view(s, data)
	var stand: Array = MapSpots.standing(s, data).map(func(t: Dictionary) -> Vector2i: return Vector2i(int(t["x"]), int(t["y"])))
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var c := Vector2i(x, y)
			if not WalkRules.distance(c, hero) in range(9, 30) or not WalkRules.passable(map, data["layouts"], c) 					or stand.any(func(p: Vector2i) -> bool: return WalkRules.distance(p, c) < 6):
				continue
			var a: Dictionary = gs.area_aim(c)
			if str(a["why"]).is_empty() and (a["caught"] as Array).is_empty():
				return c
	return FightGrid.NONE


## Some of the caught lost hit points (or fell) by the opening.
func _hurt(in_fight: Dictionary, caught: Array) -> bool:
	return caught.any(func(t: Dictionary) -> bool:
		var f: Dictionary = in_fight.get(str(t["id"]), {})
		return not f.is_empty() and (int(f.get("hp", 0)) < int(f.get("max_hp", 0)) or str(f.get("status")) != "active"))
