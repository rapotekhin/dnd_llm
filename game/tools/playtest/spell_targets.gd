extends "res://tools/playtest/playtest_base.gd"
## Spell targets (python tools/godot_playtest.py --scenario spell_targets), v0.7.50.1: Branko with two allies against
## goblins: Bless armed by its button, the ally, the second ally and the hero picked by «Выбрать», each once.
## Then Fireball at a goblin beside an ally: the ally is burnt.


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
	var sp: Dictionary = s.character["spells"]
	sp["always"] = ["bless", "fireball"]
	s.character["level"] = 5
	s.character["slots_max"] = [4, 3, 2, 0, 0]
	Stock.fill_slots(s.character)
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	s.room_id = "pushcha-hollow"
	gs.start_combat([{"monster": "goblin"}, {"monster": "goblin"}], {"encounter": "t_targets", "room_from": "pushcha-trail",
		"allies": [{"monster": "guard", "name": "Влада", "beside": true}, {"monster": "scout", "name": "Ждан", "beside": true}]})
	if not step("the fight", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 120.0)):
		return
	await frames(3)
	for foe_id: String in CombatRules.enemies(s):  # the allies' blows must not end the fight before the hero's next turn
		var f := CombatRules.fighter(s, foe_id)
		f["hp"] = 200
		f["max_hp"] = 200
	var ids := CombatRules.allies(s)
	var cast: Button = find(screen(), "Cast_bless")
	if not step("«Благословение» on the Spells tab", cast != null):
		return
	await press(cast)
	await frames(3)
	var pick: Button = find(screen(), "Pick_" + ids[0])
	var me: Button = find(screen(), "Pick_" + CombatRules.PLAYER)
	if not step("friends get «Выбрать»: the hero too", pick != null and me != null and not pick.disabled):
		return
	await shot("pick_first")
	await press(pick)
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	step("the first ally is blessed, two left", (SpellEffects.boon(CombatRules.fighter(s, ids[0]), "die") != null) and int(CombatRules.volley(s).get("left", 0)) == 2)
	var used: Button = find(screen(), "Pick_" + ids[0])
	step("the same one cannot be picked again", used != null and used.disabled)
	await shot("pick_next")
	await press(find(screen(), "Pick_" + ids[1]))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	await press(find(screen(), "Pick_" + CombatRules.PLAYER))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	step("all three blessed, no more picks", CombatRules.volley(s).is_empty() and (SpellEffects.boon(CombatRules.fighter(s, ids[1]), "die") != null)
		and ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless"))
	await shot("blessed")
	await press(find(screen(), "EndTurnButton"))
	if not step("the hero's next turn", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 120.0)):
		return
	await frames(3)
	var foe: String = CombatRules.enemies(s)[0]
	var friend := CombatRules.fighter(s, ids[1])
	FightGrid.put(friend, FightGrid.free_near(s, node("Catalog").data, FightGrid.cell(CombatRules.fighter(s, foe)), 1))
	var hp_before := int(friend["hp"])
	var was := Stock.spent(s.character, "slot_3")
	if not step("«Огненный шар» ready on the Spells tab", await wait_until(func() -> bool:
			var b: Button = find(screen(), "Cast_fireball")
			return b != null and not b.disabled, 30.0)):
		return
	await press(find(screen(), "Cast_fireball"))
	await frames(3)
	await press(find(screen(), "Foe_" + foe))
	await frames(3)
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	step("the ally is burnt by the hero's Fireball", int(friend["hp"]) < hp_before and Stock.spent(s.character, "slot_3") == was + 1)
	await shot("fireball_after")
