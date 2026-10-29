extends "res://tools/playtest/playtest_base.gd"
## The arena (python tools/godot_playtest.py --scenario arena), v0.7.45: «Арена» at Gordey in the ring by the North
## Gate — the rule «до сдачи», enlisted; the bout of the day with a bet on oneself fought by the buttons, the hero's
## blows only knock out and nobody dies; Insight and a bet on the day's bout of two fighters; the blood pit asks
## «Точно?»; the harvest's tournament opens on its day; a duel with Bruno by the contest window.

const RING := "brod-arena-ring"
const MASTER := "npc_arena_master"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	c["gold_cp"] = 5000
	s.settings["needs"] = false
	s.minute = 12 * 60
	await _go(gs, "brod-square")
	await _go(gs, "brod-gate")
	await _go(gs, RING)

	var win := await _open_arena(MASTER)
	if win == null:
		return
	var rule: Label = find(win, "ArenaRule")
	step("the rule shown at enlisting", rule != null and rule.text.contains("до сдачи"), rule.text if rule != null else "")
	await shot("arena_enlist")
	await press(find(win, "ArenaEnlist"))
	await frames(3)
	step("enlisted for the fee", ArenaRules.enlisted(s, "brod-arena") and int(c["gold_cp"]) == 5000 - int(ArenaRules.cfg(data)["fee_cp"]), Money.format(int(c["gold_cp"])))
	var opp: Label = find(win, "ArenaOpponent")
	var odds: Label = find(win, "ArenaOdds")
	step("the opponent and the odds", opp != null and odds != null and odds.text.contains("%"), "%s | %s" % [opp.text if opp != null else "", odds.text if odds != null else ""])
	var spin: SpinBox = find(win, "ArenaBetSelf")
	spin.value = 1.0
	await frames(2)
	await shot("arena_bout")
	var gold_before := int(c["gold_cp"])
	await press(find(win, "ArenaFight"))
	if not step("the bout starts", await wait_until(func() -> bool: return screen_is("CombatScreen") and CombatRules.active(s), 30.0)):
		return
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	var nl: CheckButton = find(screen(), "NonlethalToggle")
	step("knocking out only, by the rule", nl != null and nl.disabled and nl.button_pressed)
	step("the bet left the purse", int(c["gold_cp"]) == gold_before - 100, Money.format(int(c["gold_cp"])))
	await shot("arena_fight")
	var outcome := await _fight(gs, s)
	step("the bout ended, nobody died", outcome in ["victory", "arena_lost"], outcome)
	await shot("arena_end")
	await _finish(gs)
	var r := ArenaRules.rec(s, "brod-arena")
	step("the bout counted", int(r.get("wins", 0)) + int(r.get("losses", 0)) == 1, str(r))
	step("info: after the bout", true, "%s, HP %d/%d, gold %s, fame %d" % [outcome, c["hp"], c["max_hp"], Money.format(int(c["gold_cp"])), ReputationRules.points(s, "brod")])
	await shot("arena_after")

	win = await _open_arena(MASTER)
	if win == null:
		return
	var card: Label = find(win, "ArenaCard")
	step("the bout of the day to bet on", card != null and card.text.contains("против"), card.text if card != null else "")
	await press(find(win, "ArenaInsight"))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	step("Insight rolled with a card", s.chat.any(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK and str(e.get("skill", "")) == "insight"))
	var bet: SpinBox = find(win, "ArenaBetCard")
	bet.value = 2.0
	await frames(2)
	var g := int(c["gold_cp"])
	await press(find(win, "ArenaBet_a"))
	await frames(3)
	step("the bet played out", int(c["gold_cp"]) != g, "%s → %s" % [Money.format(g), Money.format(int(c["gold_cp"]))])
	step("the master told it", await wait_until(func() -> bool: return not gs.is_busy(), 60.0))
	await shot("arena_bet")
	win.visible = false

	await _go(gs, "brod-pit")
	win = await _open_arena("npc_pit_master")
	if win != null:
		rule = find(win, "ArenaRule")
		step("the blood pit's rule", rule != null and rule.text.contains("до смерти"), rule.text if rule != null else "")
		await press(find(win, "ArenaEnlist"))
		await frames(2)
		node("SaveManager").confirm_risky = true  # the playtest profile runs with the questions off
		await press(find(win, "ArenaFight"))
		await frames(3)
		var box: Node = node("GameState").get_tree().root.get_node_or_null("ConfirmBox")
		step("«Точно?» before the pit", box != null and CombatRules.active(s) == false)
		await shot("arena_pit_confirm")
		if box != null:
			await press(find(box, "ConfirmNo"))
			await frames(3)
		node("SaveManager").confirm_risky = false
		step("no fight after «Отмена»", not CombatRules.active(s) and screen_is("GameScreen"))
		if is_instance_valid(win):
			win.visible = false

	await _go(gs, RING)
	while s.day < 11:
		TimeRules.advance(s, data, 1440 - s.minute + 12 * 60)
		s.rested_at = TimeRules.abs_minute(s)
		s.awake_saves = 0
	c["hp"] = int(c["max_hp"])
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the tourney day", s.flags.has("tourney"), CalendarRules.text(data["world"], s.day))
	win = await _open_arena(MASTER)
	if win != null:
		var t: Label = find(win, "ArenaTourney")
		var tb: Button = find(win, "ArenaTourneyFight")
		step("the tournament in the window", t != null and tb != null and not tb.disabled, t.text if t != null else "")
		await shot("arena_tourney")
		win.visible = false

	await _go(gs, "brod-gate")
	await _go(gs, "brod-square")
	await _go(gs, "brod-tavern-hall")
	s.minute = 19 * 60
	s.pockets["npc_innkeeper"] = [{"id": "k1", "name": "Кошель", "item_id": "", "cp": 2000, "qty": 1, "worn": false, "dc": 12}]
	c["hp"] = int(c["max_hp"])
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_innkeeper")
	var play: Button = find(screen(), "Contest_npc_innkeeper")
	if not step("«Сыграть» at Bruno", play != null and not play.disabled):
		return
	await press(play)
	await frames(3)
	var cw: Control = find(screen(), "ContestView")
	var kinds: OptionButton = find(cw, "ContestKinds")
	for i in kinds.item_count:
		if str(kinds.get_item_metadata(i)) == "bout":
			kinds.select(i)
			kinds.item_selected.emit(i)
	await frames(3)
	var co: Label = find(cw, "ContestOdds")
	step("the duel's estimate", co != null and co.text.contains("Поединок"), co.text if co != null else "")
	await shot("duel_setup")
	await press(find(cw, "ContestPlay"))
	if step("the duel is a fight", await wait_until(func() -> bool: return screen_is("CombatScreen") and CombatRules.active(s), 30.0)):
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var o := await _fight(gs, s)
		step("the duel ended without a death", o in ["victory", "arena_lost"], o)
		await _finish(gs)
		step("the stake settled", ContestRules.state(s).is_empty() and not s.dead_npcs.has("npc_innkeeper"), Money.format(int(c["gold_cp"])))
		await shot("duel_after")


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("walked to %s" % to, gs.go(to))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)


func _open_arena(npc: String) -> Control:
	await open_row("More_" + npc)
	var b: Button = find(screen(), "Arena_" + npc)
	if not step("«Арена» at %s" % npc, b != null and not b.disabled):
		await shot("no_arena_" + npc)
		return null
	await press(b)
	await frames(4)
	var win: Control = find(screen(), "ArenaView")
	step("the arena window", win != null and win.visible)
	return win


## The bout by the buttons: step in, attack, end the turn, until it ends. The outcome.
func _fight(gs: Node, s: GameSession) -> String:
	var data: Dictionary = node("Catalog").data
	var turns := 0
	while CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty() and turns < 40:
		if not await wait_until(func() -> bool: return (CombatRules.player_can_act(s) and not gs.is_busy()) or not str(s.combat.get("outcome", "")).is_empty() or gs.can_retry(), 120.0):
			break
		if gs.can_retry():
			gs.retry()
			continue
		if not str(s.combat.get("outcome", "")).is_empty():
			break
		turns += 1
		var foes := CombatRules.enemies(s)
		if foes.is_empty():
			break
		var near := foes[0]
		var dir := 1 if int(CombatRules.fighter(s, near)["col"]) > int(CombatRules.player(s)["col"]) else -1
		for i in 2:
			if CombatRules.cols_between(CombatRules.player(s), CombatRules.fighter(s, near)) == 0:
				break
			var mv: Button = find(screen(), "MoveRight" if dir > 0 else "MoveLeft")
			if mv == null or mv.disabled:
				break
			await press(mv)
		for i in 2:
			if not str(s.combat.get("outcome", "")).is_empty() or not CombatRules.can_attack(s, data, near).is_empty():
				break
			var atk: Button = find(screen(), "Attack_main")
			if atk == null or atk.disabled:
				break
			await press(atk)
			var card: Button = find(screen(), "Foe_" + near)
			if card == null or card.disabled:
				break
			await press(card)
		if CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty() and CombatRules.is_player_turn(s):
			var end: Button = find(screen(), "EndTurnButton")
			if end != null and not end.disabled:
				await press(end)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	await frames(4)
	return str(s.combat.get("outcome", "")) if CombatRules.active(s) else "?"


func _finish(gs: Node) -> void:
	var finish: Button = find(screen(), "FinishCombat")
	if step("results panel", finish != null and finish.is_visible_in_tree()):
		await press(finish)
		step("back in the game", await wait_until(func() -> bool: return screen_is("GameScreen"), 10.0))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
