extends "res://tools/playtest/playtest_base.gd"
## Allies in a fight (python tools/godot_playtest.py --scenario allies), v0.7.22.22: a follower told to wait and led
## again by the buttons, a summoned owl let go and called again, then the burrow of the Ash Priest with the two
## militia, the follower and the owl on the hero's side; a few rounds go by, the allies strike on their own.


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
	s.followers.append("npc_mercenary")
	node("EventBus").state_changed.emit()
	await frames(3)
	var stay: Button = find(screen(), "Follower_stay_npc_mercenary")
	if step("the follower's buttons", stay != null and find(screen(), "Follower_let_go_npc_mercenary") != null):
		await shot("follower")
		await press(stay)
		await frames(3)
		step("waits here", not s.followers.has("npc_mercenary") and str(s.npc_at.get("npc_mercenary", "")) == "brod-square")
		var lead: Button = find(screen(), "Follower_lead_npc_mercenary")
		if step("«Вести с собой» for one left here", lead != null):
			await press(lead)
			await frames(3)
			step("goes with the hero again", s.followers.has("npc_mercenary"))

	AllyRules.summon(s, data, "find_familiar")
	node("EventBus").state_changed.emit()
	await frames(3)
	var dismiss: Button = find(screen(), "Dismiss_" + str(s.summons[0]["id"]))
	if step("the owl with the hero, «Отпустить»", dismiss != null):
		await shot("summon")
		await press(dismiss)
		await frames(3)
		step("let go", s.summons.is_empty())
	AllyRules.summon(s, data, "find_familiar")

	var enc: Dictionary = data["world"]["rooms"]["pushcha-burrow"]["encounter"]
	s.room_id = "pushcha-burrow"
	s.encounters_done.append("burrow_priest")
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	gs.start_combat(enc["enemies"], {"encounter": "burrow_priest", "room_from": "pushcha-glade", "allies": enc["allies"], "parley": "hard"})
	if not step("the burrow fight", await wait_until(func() -> bool:
			return screen_is("CombatScreen") and not gs.is_busy() and CombatRules.is_player_turn(s), 120.0)):
		return
	await frames(3)
	var ids := CombatRules.allies(s, false)
	step("four allies: the militia, the follower, the owl", ids.size() == 4, str(ids.map(func(id: String) -> String: return CombatRules.fighter(s, id)["name"])))
	step("their chips on the field", ids.all(func(id: String) -> bool: return find(screen(), "Foe_" + id) != null))
	await shot("burrow")
	for i in 3:
		var end: Button = find(screen(), "EndTurnButton")
		if end == null or not str(s.combat.get("outcome", "")).is_empty():
			break
		await press(end)
		await wait_until(func() -> bool: return (CombatRules.is_player_turn(s) or not str(s.combat.get("outcome", "")).is_empty()) and not gs.is_busy(), 120.0)
		await frames(3)
	var log := "\n".join(s.combat.get("log", []))
	step("the allies strike on their own", ids.any(func(id: String) -> bool: return log.contains(str(CombatRules.fighter(s, id)["name"]) + " —")), log.right(600))
	await shot("rounds")
