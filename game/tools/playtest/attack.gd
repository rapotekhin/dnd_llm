extends "res://tools/playtest/playtest_base.gd"
## Attacking an NPC (python tools/godot_playtest.py --scenario attack), v0.7.22.16: «Напасть» on an NPC of the tavern
## starts the fight at once, the NPC caught off guard; knocked out, it lies as a creature — searched, and it wakes up
## and the assault is known; a Fire Bolt pinned to the words at another NPC starts the fight by itself, the spell the
## first blow; that one knocked out is finished off — a murder.


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
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var here := s.npcs_here(data["world"], s.room_id)
	var first := "npc_serving" if here.has("npc_serving") else here[0]
	var attack: Button = find(screen(), "Attack_" + first)
	if not step("the «Напасть» button by the NPC", attack != null and not attack.disabled, str(here)):
		return
	await shot("people")
	await press(attack)
	if not step("the fight at once", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await frames(3)
	var fid := CombatRules.fighter_of_npc(s, first)
	step("caught off guard, the hero first", bool(CombatRules.fighter(s, fid).get("surprised", false)) and str(s.combat["order"][0]) == CombatRules.PLAYER,
		str(s.combat.get("start_lines", s.combat.get("log", []))))
	await shot("fight")
	await _knock_out(gs, s, data, fid)
	var c := _creature_of(s, first)
	step("knocked out — a creature of the room, not a person of the scene", not c.is_empty() and not s.npcs_here(data["world"], s.room_id).has(first))
	var game := screen()
	step("search and finish buttons", find(game, "Creature_search_" + str(c.get("id", ""))) != null and find(game, "Creature_finish_" + str(c.get("id", ""))) != null)
	step("no attack on the helpless", find(game, "Creature_attack_" + str(c.get("id", ""))) == null)
	await shot("knocked_out")
	await press(find(game, "Creature_search_" + str(c.get("id", ""))))
	await frames(3)
	step("searched", _chat(s).contains("Обыскан"), _chat(s))
	var woke := TimeRules.advance(s, data, 120)
	node("EventBus").state_changed.emit()
	await frames(3)
	var known := s.crimes.any(func(cr: Dictionary) -> bool: return str(cr.get("kind")) == "assault" and bool(cr["known"]))
	step("woke up, the assault is known", s.npcs_here(data["world"], s.room_id).has(first) and known, " · ".join(woke))
	await shot("woke")

	# A Fire Bolt at another NPC: the engine starts the fight, the spell is the first blow.
	s.crimes = []
	s.wanted = {}
	s.arrest = ""
	var second := ""
	for id: String in s.npcs_here(data["world"], s.room_id):
		if id != first:
			second = id
	if not step("another NPC here", not second.is_empty()):
		return
	node("EventBus").state_changed.emit()
	await frames(3)
	gs.attach("spell", "fire_bolt", 0, second)
	gs.submit("Огненный снаряд в него!")
	if not step("the pinned spell started the fight", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await frames(3)
	step("the spell went first", _chat(s).contains("Огненный снаряд по"), _chat(s))
	await shot("spell_opening")
	await _knock_out(gs, s, data, CombatRules.fighter_of_npc(s, second))
	var c2 := _creature_of(s, second)
	if step("the second one knocked out", not c2.is_empty()):
		await press(find(screen(), "Creature_finish_" + str(c2["id"])))
		await frames(3)
		step("finished off — a murder", s.dead_npcs.has(second) and s.crimes.any(func(cr: Dictionary) -> bool: return str(cr.get("kind")) == "murder"), _chat(s))
		await shot("finished")


## Knocks the foe out by a melee blow of the engine and ends the fight by the «Продолжить» button.
func _knock_out(gs: Node, s: GameSession, data: Dictionary, fid: String) -> void:
	var f := CombatRules.fighter(s, fid)
	f["col"] = int(CombatRules.player(s)["col"])
	s.combat["nonlethal"] = true
	s.combat["melee_strike"] = true
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, f, 999, lines)
	s.combat.erase("melee_strike")
	CombatRules.after_player_action(s, data)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	await frames(3)


func _creature_of(s: GameSession, npc_id: String) -> Dictionary:
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		if str(c.get("npc_id", "")) == npc_id:
			return c
	return {}


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 4)):
		out.append(str(e.get("text", " · ".join(e.get("lines", [])))))
	return " | ".join(out).left(400)
