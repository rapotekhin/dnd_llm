extends "res://tools/playtest/playtest_base.gd"
## Smoke playtest: menu → new game (enter turn) → action with engine.check → option → save to slot 1 →
## exit to menu → continue → the chat is restored. Needs a running llm_server (stub turn is enough).


func run() -> void:
	var backend := node("Backend")
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return backend.is_ready(), 20.0), backend.config.describe()):
		await shot("menu_offline")
		return
	await shot("menu")
	var new_game: Button = find(screen(), "NewGameButton")
	if not step("menu has «Новая игра»", new_game != null):
		return
	await press(new_game)

	var entered := await wait_until(func() -> bool: return screen_is("GameScreen") and gs.has_session() and not gs.is_busy(), 30.0)
	if not step("enter turn finished", entered):
		await shot("enter_failed")
		return
	step("narration in chat", _count(gs, GameSession.KIND_DM) == 1, "chat %d entries" % gs.session.chat.size())
	await shot("game_enter")

	var game: Control = screen()
	game.get("input").text = "осматриваю комнату"
	game.get("send_button").pressed.emit()
	# Checked in the same frame: the stub master may answer within a couple of frames.
	step("input locked while the master thinks", gs.is_busy() and not game.get("input").editable)
	var acted := await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("action turn finished", acted)
	step("engine.check card in chat", _count(gs, GameSession.KIND_CHECK) == 1 and find_all(game, "CheckCard").size() == 1)
	step("options shown", gs.session.options.size() > 0, str(gs.session.options))
	await shot("game_action_check")

	if gs.session.options.size() > 0:
		var opt := find_button_by_text(game, gs.session.options[0])
		if step("option button exists", opt != null):
			await press(opt)
			step("option turn finished", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
			await shot("game_option")

	await key(KEY_ESCAPE)
	var pause: Control = find_all(game, "PauseMenu")[0]
	step("Esc opens the pause menu", pause.visible)
	await shot("pause")
	await press(find_button_by_text(pause, "Сохранить"))
	step("save slots screen", screen_is("SlotsScreen"))
	await shot("save_slots")
	await press(find(screen(), "slot_1"))
	step("saved to slot 1 and back in game", node("SaveManager").has_slot("slot_1") and screen_is("GameScreen"))

	var chat_size: int = gs.session.chat.size()
	await key(KEY_ESCAPE)
	await press(find_button_by_text(screen(), "Выйти в главное меню"))
	step("back in the menu", screen_is("MainMenu") and not gs.has_session())
	var cont: Button = find(screen(), "ContinueButton")
	if not step("menu offers «Продолжить»", cont != null):
		return
	await shot("menu_continue")
	await press(cont)
	step("continue restores the chat", screen_is("GameScreen") and gs.has_session() and gs.session.chat.size() == chat_size,
		"%d / %d entries" % [gs.session.chat.size() if gs.has_session() else -1, chat_size])
	await shot("game_restored")


func _count(gs: Node, kind: String) -> int:
	return gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()
