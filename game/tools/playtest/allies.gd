extends "res://tools/playtest/playtest_base.gd"
## Allies in a fight (python tools/godot_playtest.py --scenario allies), v0.7.22.22: a follower told to wait and led
## again by the buttons, a summoned owl let go and called again, then the burrow of the Ash Priest with the two
## militia, the follower and the owl on the hero's side; a few rounds go by, the militia strike on their own (the follower
## and the owl are the player's in their turns, v0.8.4.43.11: ended by «Конец хода» here).


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
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_mercenary")  # v0.7.22.23: the acts under the name
	var stay: Button = find(screen(), "Follower_stay_npc_mercenary")
	if step("the follower's buttons", stay != null and find(screen(), "Follower_let_go_npc_mercenary") != null):
		await shot("follower")
		await press(stay)
		await frames(3)
		step("waits here", not Being.follows(s, "npc_mercenary") and str(Being.view(s, "npc_mercenary").get("at", "")) == "brod-square")
		var lead: Button = find(screen(), "Follower_lead_npc_mercenary")
		if step("«Вести с собой» for one left here", lead != null):
			await press(lead)
			await frames(3)
			step("goes with the hero again", Being.follows(s, "npc_mercenary"))
	# v0.8.4.42.2: its share of experience past the threshold — the player raises its level by a button
	var lv := GrowthRules.level(s, data, "npc_mercenary")
	GrowthRules.gain(s, data, "npc_mercenary", LevelUp.xp_for(data, lv + 1) - LevelUp.xp_for(data, lv))
	step("the follower waits for its level", GrowthRules.level(s, data, "npc_mercenary") == lv and GrowthRules.ready(s, data, "npc_mercenary"))
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_mercenary")
	var grow: Button = find(screen(), "Grow_npc_mercenary")
	if step("«Новый уровень» at the follower", grow != null and not grow.disabled):
		await shot("follower_grow")
		await press(grow)
		await frames(3)
		step("its level rose by the button", GrowthRules.level(s, data, "npc_mercenary") == lv + 1 and find(screen(), "Grow_npc_mercenary") == null)

	AllyRules.summon(s, data, "find_familiar")
	node("EventBus").state_changed.emit()
	await frames(3)
	await stage("summon:" + str(AllyRules.called(s)[0]["id"]))  # v0.8.4.43.4: the owl's portrait — its menu
	var dismiss: Button = find(screen(), "Dismiss_" + str(AllyRules.called(s)[0]["id"]))
	if step("the owl with the hero, «Отпустить»", dismiss != null):
		await shot("summon")
		await press(dismiss)
		await frames(3)
		step("let go", AllyRules.called(s).is_empty())
	AllyRules.summon(s, data, "find_familiar")

	var enc: Dictionary = data["world"]["rooms"]["pushcha-burrow"]["encounter"]
	s.room_id = "pushcha-burrow"
	s.encounters_done.append("burrow_priest")
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	gs.start_combat(enc["enemies"], {"encounter": "burrow_priest", "room_from": "pushcha-glade", "allies": [{"monster": "scout", "name": "Ждан из ополчения"}, {"monster": "guard", "name": "Влада из ополчения"}], "parley": "hard"})
	await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and not CombatRules.actor(s).is_empty(), 120.0)
	if not step("the burrow fight", await hero_turn(120.0)):
		return
	await frames(3)
	var ids := CombatRules.allies(s, false)
	step("four allies: the militia, the follower, the owl", ids.size() == 4, str(ids.map(func(id: String) -> String: return CombatRules.fighter(s, id)["name"])))
	step("their chips on the field", ids.all(func(id: String) -> bool: return find(screen(), "Turn_" + id) != null))
	await shot("burrow")
	var names: Array = ids.map(func(id: String) -> String: return str(CombatRules.fighter(s, id)["name"]))
	var said: Array[String] = []  # the fight may end within the rounds: its log goes with it
	node("EventBus").combat_lines.connect(func(l: Array[String]) -> void: said.append_array(l))
	for i in 3:
		var end: Button = find(screen(), "EndTurnButton")
		if end == null or not str(s.combat.get("outcome", "")).is_empty():
			break
		await press(end)
		await hero_turn(120.0)
		await frames(3)
	var log := "\n".join(said)
	step("the militia strike on their own", names.any(func(n: String) -> bool: return said.any(func(l: String) -> bool: return l.begins_with(n))), log.right(600))
	await shot("rounds")
