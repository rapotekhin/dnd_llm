extends "res://tools/playtest/playtest_base.gd"
## Contests (python tools/godot_playtest.py --scenario contest), v0.7.40: «Сыграть» at Bruno, dice for coins rolled
## round by round to the end, the master told the end; cards with a cheat; the master's own game (knife throwing)
## offered by `contest` opens the window on its kind.

const NPC := "npc_innkeeper"


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
	s.minute = 19 * 60
	s.room_id = "brod-tavern-hall"
	s.pockets[NPC] = [{"id": "k1", "name": "Кошель", "item_id": "", "cp": 2000, "qty": 1, "worn": false, "dc": 12}]
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_" + NPC)
	var play: Button = find(screen(), "Contest_" + NPC)
	if not step("«Сыграть» at Bruno", play != null and not play.disabled, play.tooltip_text if play != null else "нет кнопки"):
		await shot("no_contest")
		return
	await press(play)
	await frames(4)
	var win: Control = find(screen(), "ContestView")
	var odds: Label = find(win, "ContestOdds")
	step("the window shows both bonuses and the chance", win.visible and odds != null and odds.text.contains("%"), odds.text if odds != null else "")
	await shot("contest_setup")
	await press(find(win, "ContestPlay"))
	await frames(3)
	if not step("dice for coins on the table", not ContestRules.state(s).is_empty(), str(c.get("contest", {}))):
		return
	step("the stake left the purse", int(c["gold_cp"]) < 5000, str(c["gold_cp"]))
	await shot("contest_game")
	var checks_before := s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK).size()
	for i in 12:
		if ContestRules.state(s).is_empty():
			break
		await press(find(win, "ContestRoll"))
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		await frames(2)
	var checks := s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK).size() - checks_before
	step("rounds rolled to the end, a card each", ContestRules.state(s).is_empty() and checks >= 2, "%d rounds" % checks)
	step("the master told the end", await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		and s.chat.any(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_DM))
	step("info: gold after the dice", true, Money.format(int(c["gold_cp"])))
	await shot("contest_dice_done")

	# Cards with a cheat: either the round is the hero's or Bruno catches it.
	win.visible = false
	await press(find(screen(), "Contest_" + NPC))
	await frames(3)
	var kinds: OptionButton = find(win, "ContestKinds")
	for i in kinds.item_count:
		if str(kinds.get_item_metadata(i)) == "cards":
			kinds.select(i)
			kinds.item_selected.emit(i)
	await frames(3)
	await press(find(win, "ContestPlay"))
	await frames(3)
	var cheat: Button = find(win, "ContestCheat")
	if step("«Жульничать» in cards", cheat != null and not cheat.disabled):
		await press(cheat)
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		await frames(3)
		var caught := bool(ContestRules._day(s, NPC).get("caught", false))
		step("info: the cheat", true, "пойман — %s" % ", ".join(s.npc_memory.get(NPC, [])) if caught else "раунд: %s" % str(ContestRules.state(s)))
		await shot("contest_cheat")
		if not ContestRules.state(s).is_empty():
			var give: Button = find(win, "ContestForfeit")
			await press(give)
			await frames(2)
	win.visible = false

	# The master's own game: knife throwing, a day later and the grudge forgotten.
	s.day += 1
	s.attitudes.erase(NPC)
	var fx: EffectEngine = gs.effects
	var r := fx.validate(s, data, "ct-1", {"kind": "contest", "npc_id": NPC, "new_kind": {"name": "Метание ножей", "check": {"skill": "sleight_of_hand"}, "wins": 3}})
	if step("the master's own game accepted", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		fx.apply(s, "ct-1", [r["effect_id"]])
		node("EventBus").turn_finished.emit("ct-1", true)
		await frames(4)
		kinds = find(win, "ContestKinds")
		step("the window opens on the master's game", win.visible and kinds != null and kinds.get_item_text(kinds.selected) == "Метание ножей",
			kinds.get_item_text(kinds.selected) if kinds != null else "")
		await shot("contest_offer")
