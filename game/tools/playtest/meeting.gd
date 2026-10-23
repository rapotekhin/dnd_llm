extends "res://tools/playtest/playtest_base.gd"
## Meetings and captivity (python tools/godot_playtest.py --scenario meeting), v0.7.22.12: the hero sneaks onto the
## woodcutters' trail — the wolves do not notice, there is no fight, «Напасть врасплох» starts it with them caught
## off guard; then a captivity: the escape buttons, a successful break free, the captors lurk unaware.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_rogue_damir")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var game := screen()
	s.room_id = "pushcha-edge"
	s.visited.append("pushcha-edge")
	s.character["skills"]["stealth"] = 40  # nobody notices this one
	s.sneaking = true
	node("EventBus").state_changed.emit()
	await frames(3)
	var exit: Button = find(game, "Exit_pushcha-trail")
	if not step("the way to the wolves", exit != null and not exit.disabled):
		return
	await press(exit)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("no fight from the doorway", s.mode != GameSession.MODE_COMBAT and not EncounterRules.lurking(s, "pushcha-trail").is_empty(), _chat(s))
	var attack: Button = find(screen(), "Encounter_attack")
	step("the attack-by-surprise button", attack != null and not attack.disabled)
	step("the wolves cannot be talked to", find(screen(), "Encounter_persuasion") != null and find(screen(), "Encounter_persuasion").disabled)
	await shot("unseen")
	if attack != null:
		await press(attack)
		await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)
		await frames(3)
		var caught := CombatRules.enemies(s).all(func(id: String) -> bool: return bool(CombatRules.fighter(s, id).get("surprised", false)))
		step("the fight — the wolves caught off guard", CombatRules.active(s) and caught, str(s.combat.get("start_lines", [])))
		await shot("surprise")
		s.combat = {}
		s.mode = GameSession.MODE_EXPLORATION
		node("EventBus").navigate.emit("game", {})
		await frames(5)

	# A captivity: bound by bandits in the hall of the outpost yard.
	s.room_id = "outpost-yard"
	s.encounters_done.append("yard_dead")
	EncounterRules.capture(s, [{"monster": "bandit", "name": "Разбойник", "count": 1}], "", "outpost-road")
	node("EventBus").state_changed.emit()
	await frames(5)
	game = screen()
	var out_exit: Button = find(game, "Exit_outpost-road")
	step("captive: the exits are shut", out_exit != null and out_exit.disabled)
	var free: Button = find(game, "Escape_athletics")
	step("the escape buttons", free != null and find(game, "Escape_sleight") != null and find(game, "Escape_talk") != null)
	await shot("captive")
	s.character["skills"]["athletics"] = 40
	if free != null:
		await press(free)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	step("broke free", not EncounterRules.captive(s), _chat(s))


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 4)):
		out.append(str(e.get("text", " · ".join(e.get("lines", [])))))
	return " | ".join(out).left(300)
