extends "res://tools/playtest/playtest_base.gd"
## The roll's breakdown on hover (python tools/godot_playtest.py --scenario roll_parts), v0.7.39.5: a check card of
## the stub master's Perception and a line of effects with a Stealth roll among people; the mouse over each shows
## the dice, every labelled part and the total — in the chat only (the hover text; a native tooltip shows it).


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
	var game := screen()
	game.get("input").text = "Осматриваю зал"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	var cards := find_all(game, "CheckCard")
	if not step("a check card in the chat", not cards.is_empty()):
		return
	var card: Control = cards[-1]
	var tip := str(card.tooltip_text)
	step("the card's breakdown names the ability and the total", tip.contains("к20") and tip.contains(RollParts.ability_name("wis")) and tip.contains("против Сл"), tip)
	await shot("card")

	s.room_id = "brod-tavern-hall"  # people to sneak past
	node("EventBus").state_changed.emit()
	await frames(3)
	gs.set_sneaking(true)
	await frames(6)
	var line: Control = null
	for l: Node in game.find_children("*", "RichTextLabel", true, false):
		if not str((l as Control).tooltip_text).is_empty() and str((l as Control).tooltip_text).contains(TranslationServer.translate("SKILL_STEALTH")):
			line = l
	if not step("the sneaking line carries its Stealth roll", line != null, str(s.chat[-1])):
		return
	step("its breakdown names the dice and the parts", str(line.tooltip_text).contains("к20") and str(line.tooltip_text).contains(RollParts.ability_name("dex")), str(line.tooltip_text))
	await shot("line")
	step("no part without a name", RollParts.unlabeled == 0, str(RollParts.unlabeled))

