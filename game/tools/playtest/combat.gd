extends "res://tools/playtest/playtest_base.gd"
## Combat playtest (python tools/godot_playtest.py --scenario combat; --real for the real master): the ready-made
## fighter walks to the woodcutters' trail, the wolves attack (the pack encounter), the fight is played on the
## combat screen by its buttons — step in, attack, end the turn — until it ends; then the results (or the death
## screen) and back to the game. Screenshots of the screen at the start, mid-fight and at the end.
## GODOT_COMBAT_ROAD=1 (v0.6.2): sneaks to the road to the outpost instead — the mercenaries' ambush, the hit hint on
## hover, a parley by the button, the cultists coming grey at the edge.

const PATH: Array[String] = ["brod-square", "brod-gate", "pushcha-edge", "pushcha-trail"]
const ROAD_PATH: Array[String] = ["brod-square", "brod-gate", "outpost-road"]
var road := not OS.get_environment("GODOT_COMBAT_ROAD").is_empty()


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
	for room: String in (ROAD_PATH if road else PATH):
		if road and room == "outpost-road":
			var sneak: CheckButton = find(screen(), "SneakToggle")
			if step("sneak toggle", sneak != null and not sneak.disabled):
				sneak.button_pressed = true
				await frames(2)
				step("sneaking on", s_sneaking(gs))
		var exit: Button = find(screen(), "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy() or screen_is("CombatScreen"), 60.0)
	if not step("the wolves attack: combat screen", await wait_until(func() -> bool: return screen_is("CombatScreen"), 10.0)):
		await shot("no_combat")
		return
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	var s: GameSession = gs.session
	step("info: start", true, " | ".join(s.combat.get("log", [])) if not (s.combat.get("log", []) as Array).is_empty() else str(s.chat.slice(-3).map(func(e: Dictionary) -> String: return str(e.get("text", e.get("lines", ""))))))
	if not OS.get_environment("GODOT_COMBAT_HP").is_empty():  # to see the death saves and the death screen
		s.character["hp"] = int(OS.get_environment("GODOT_COMBAT_HP"))
		node("EventBus").state_changed.emit()
	await shot("combat_start")
	step("info: order", true, str(s.combat["order"].map(func(id: String) -> String: return "%s %d" % [s.combat["fighters"][id]["name"], s.combat["fighters"][id]["init"]])))
	var rounds := 0
	while CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty() and rounds < 40:
		if not await wait_until(func() -> bool: return (CombatRules.player_can_act(s) and not gs.is_busy()) or not str(s.combat.get("outcome", "")).is_empty() or gs.can_retry(), 120.0):
			break
		if gs.can_retry():
			gs.retry()
			continue
		if not str(s.combat.get("outcome", "")).is_empty():
			break
		rounds += 1
		await _player_turn(gs, s)
		if rounds == 2:
			await shot("combat_mid")
		if not (s.combat.get("incoming", []) as Array).is_empty() and not _incoming_shot:
			_incoming_shot = true
			step("reinforcements shown grey at the edge", find(screen(), "Incoming_%d" % int(s.combat["incoming"][0]["col"])) != null, str(s.combat["incoming"][0]["names"]))
			await shot("combat_incoming")
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	var outcome := str(s.combat.get("outcome", "")) if CombatRules.active(s) else "?"
	step("the fight ended", not outcome.is_empty(), "%s after %d turns, HP %d/%d" % [outcome, rounds, s.character["hp"], s.character["max_hp"]])
	await frames(5)
	await shot("combat_end")
	if outcome == "dead":
		step("death screen", await wait_until(func() -> bool: return screen_is("DeathScreen"), 60.0))
		await shot("death")
		return
	var finish: Button = find(screen(), "FinishCombat")
	if step("results panel", finish != null and finish.is_visible_in_tree(), str(s.combat.get("loot", []))):
		var xp: int = s.character["xp"]
		await press(finish)
		step("back in the game", await wait_until(func() -> bool: return screen_is("GameScreen"), 10.0) and s.mode == GameSession.MODE_EXPLORATION,
			"xp %d, encounters %s, room %s" % [xp, s.encounters_done, s.room_id])
		await shot("after_combat")
	_dump(s)


## The fighter's turn by the buttons: step toward the nearest wolf if none is in reach, attack while possible, end.
func _player_turn(gs: Node, s: GameSession) -> void:
	var game := screen()
	if not _hinted and not CombatRules.enemies(s).is_empty():
		_hinted = true
		var card: Button = find(game, "Foe_" + CombatRules.enemies(s)[0])
		if card != null:
			card.mouse_entered.emit()
			await frames(2)
			var hint: Label = find(game, "Hint")
			step("hit hint on hover", hint != null and (hint.text.contains("%") or hint.text.contains("Не достать")), hint.text if hint != null else "")
			await shot("combat_hint")
	if road and not _parleyed:
		_parleyed = true
		var pb: Button = find(game, "Parley_persuasion")
		if step("parley button", pb != null, "disabled" if pb != null and pb.disabled else ""):
			if not pb.disabled:
				await press(pb)
				step("info: parley", true, " | ".join((s.combat.get("log", []) as Array).slice(-3)))
				if not str(s.combat.get("outcome", "")).is_empty() or not CombatRules.player_can_act(s):
					return
	var pcol := int(CombatRules.player(s)["col"])
	var near := ""
	var best := 99
	for id: String in CombatRules.enemies(s):
		var d := absi(int(CombatRules.fighter(s, id)["col"]) - pcol)
		if d < best:
			best = d
			near = id
	if near.is_empty():
		return
	if best > 0:
		var dir := 1 if int(CombatRules.fighter(s, near)["col"]) > pcol else -1
		var mv: Button = find(game, "MoveRight" if dir > 0 else "MoveLeft")
		if mv != null and not mv.disabled:
			await press(mv)
		if absi(int(CombatRules.fighter(s, near)["col"]) - int(CombatRules.player(s)["col"])) > 0:
			var dash: Button = find(game, "Do_dash")
			if dash != null and not dash.disabled:
				await press(dash)
				var mv2: Button = find(screen(), "MoveRight" if dir > 0 else "MoveLeft")
				if mv2 != null and not mv2.disabled:
					await press(mv2)
	for i in 3:
		if not CombatRules.active(s) or not str(s.combat.get("outcome", "")).is_empty():
			return
		var target := ""
		for id: String in CombatRules.enemies(s):
			if CombatRules.can_attack(s, node("Catalog").data, id).is_empty():
				target = id
		if target.is_empty():
			break
		var atk: Button = find(screen(), "Attack_main")
		if atk == null or atk.disabled:
			break
		await press(atk)
		var card: Button = find(screen(), "Foe_" + target)
		if card == null or card.disabled:
			break
		await press(card)
	if CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty() and CombatRules.is_player_turn(s):
		var end: Button = find(screen(), "EndTurnButton")
		if end != null and not end.disabled:
			await press(end)


var _hinted := false
var _parleyed := false
var _incoming_shot := false


func s_sneaking(gs: Node) -> bool:
	return gs.session.sneaking


func _dump(s: GameSession) -> void:
	_report.append("----- chat -----")
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 30)):
		match str(e["kind"]):
			GameSession.KIND_DM:
				_report.append("МАСТЕР: " + str(e["text"]))
			GameSession.KIND_EFFECT:
				_report.append("ЭФФЕКТЫ: " + " · ".join(e["lines"]))
			GameSession.KIND_SYSTEM:
				_report.append("СИСТЕМА: " + str(e["key"]))
