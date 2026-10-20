extends "res://tools/playtest/playtest_base.gd"
## Interface and debts playtest (python tools/godot_playtest.py --scenario debts), v0.7.7: the sheet shows what each
## item is and the carried weight; taking off the mail takes five minutes; the smith's goods show their numbers and
## how they compare; Second Wind pinned to a message goes in one turn with the words; no «Одна жизнь» yet.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	step("no «Одна жизнь» before M5", find(screen(), "death_mode_one_life") == null)
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var game := screen()

	# The sheet: item numbers, weight; the mail off takes minutes.
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	await frames(3)
	var mail: Control = find(sheet, "ItemInfo_" + str(s.character["equipped"]["armor"]))
	step("the worn mail tells its AC", mail != null and _text_of(mail).contains("КД"), _text_of(mail).left(120) if mail != null else "")
	var weight: Label = find(sheet, "CarriedWeight")
	step("carried weight", weight != null and weight.text.contains("фнт"), weight.text if weight != null else "")
	await shot("sheet_gear")
	var minute := s.minute
	await press(find(sheet, "Unequip_armor"))
	await frames(2)
	step("taking the mail off takes 5 minutes", s.minute - minute == 5, "%d → %d" % [minute, s.minute])
	step("info: the chat line", true, _last_effect(s))
	await shot("sheet_unequipped")
	await press(find(sheet, "CloseSheetButton"))

	# The smith's goods.
	for room: String in ["brod-square", "brod-smithy"]:
		var exit: Button = find(game, "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var trade: Button = find(game, "Trade_npc_smith")
	if step("the smith trades", trade != null and not trade.disabled):
		await press(trade)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var panel: Control = find(game, "TradePanel")
		var sword: Label = find(panel, "TradeItemStats_longsword")
		step("a sword on sale shows its numbers", sword != null and sword.text.contains("1к8"), sword.text if sword != null else "")
		var shirt: Label = find(panel, "TradeItemStats_chain_shirt")
		step("the chain shirt compares with what is worn", shirt != null and shirt.text.contains("→"), shirt.text if shirt != null else "")
		await shot("trade_stats")
		await press(find(game, "LeaveButton"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)

	# Second Wind pinned to the words: one turn.
	s.character["hp"] = int(s.character["max_hp"]) - 6
	gs.attach("feature", "second_wind")
	await frames(3)
	step("the chip shows what is pinned", find(game, "AttachName") != null)
	await shot("attached")
	var turns := s.turn_counter
	game.get("input").text = "Перевязываю рану и оглядываю кузницу"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	# The stub master may hit the hero afterwards (its random effects) — so the chat order is checked, not HP.
	var at := -1
	for i in s.chat.size():
		if str(s.chat[i]["kind"]) == GameSession.KIND_PLAYER and str(s.chat[i].get("text", "")).begins_with("Перевязываю"):
			at = i
	var before: Dictionary = s.chat[at - 1] if at > 0 else {}
	step("the cast goes right before the words, no turn of its own", str(before.get("kind", "")) == GameSession.KIND_EFFECT
		and " ".join(before.get("lines", [])).contains("Второе дыхание"), str(before))
	step("Second Wind spent", FeatureUses.left(s.character, node("Catalog").data, "second_wind") == 0)
	step("info: turns", true, "%d → %d (the stub may add a «downed» turn)" % [turns, s.turn_counter])
	step("the chip is gone", gs.attached.is_empty() and find(game, "AttachName") == null)
	await shot("after_attached")


func _text_of(n: Node) -> String:
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out


func _last_effect(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i].get("lines", []))
	return ""
