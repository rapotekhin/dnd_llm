extends "res://tools/playtest/playtest_base.gd"
## Smoke playtest: menu → new game (creation: random character) → enter turn → action with engine.check →
## option → character sheet (tabs, unequip / equip) → trade with the innkeeper (deal panel, buy, haggle, switch
## to talk and back without a turn, leave) → map, journal, long rest → the temple quest → level-up → save to slot 1 → exit to menu → continue → the chat is
## restored. Needs a running llm_server (stub turn is enough).


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
	step("new game screen", screen_is("NewGameScreen"))
	await tap("dm_style_literary")
	await shot("new_game")
	await tap("NextButton")
	step("creation screen", screen_is("CreationScreen"))
	await shot("creation_start")
	await tap("RandomButton")
	var start: Button = find(screen(), "StartButton")
	step("random character is complete", start != null and start.visible and not start.disabled)
	await shot("creation_random")
	await press(start)

	var entered := await wait_until(func() -> bool: return screen_is("GameScreen") and gs.has_session() and not gs.is_busy(), 30.0)
	if not step("enter turn finished", entered):
		await shot("enter_failed")
		return
	step("narration in chat", _count(gs, GameSession.KIND_DM) == 1, "chat %d entries" % gs.session.chat.size())
	step("world and style in the game", gs.session.world_id == "frontier" and gs.session.settings["dm_style"] == "literary",
		"%s / %s" % [gs.session.world_id, gs.session.settings.get("dm_style")])
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

	await _sheet(gs, game)
	await _trade(gs, game)
	await _map_journal_rest(gs, game)
	await _quest_level_up(gs, game)

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

	await _budget_settings()

func _sheet(gs: Node, game: Control) -> void:
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	step("sheet opens", sheet.visible)
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await shot("sheet_tab_%d" % i)
	var c: Dictionary = gs.session.character
	var weapon := str(c["equipped"]["main_hand"])
	if not weapon.is_empty():
		var ac_before := int(c["ac"])
		await press(find(sheet, "Unequip_main_hand"))
		step("unequip the weapon", str(gs.session.character["equipped"]["main_hand"]).is_empty() and int(gs.session.character["ac"]) == ac_before)
		var again: Button = find(sheet, "Equip_main_hand_" + weapon)
		if step("equip button for the weapon", again != null and not again.disabled):
			await press(again)
			step("weapon back in hand", str(gs.session.character["equipped"]["main_hand"]) == weapon)
	await key(KEY_ESCAPE)
	step("Esc closes the sheet", not sheet.visible and not find_all(game, "PauseMenu")[0].visible)


func _trade(gs: Node, game: Control) -> void:
	var npc := "npc_innkeeper"
	var trade: Button = find(game, "Trade_" + npc)
	if not step("trade button for the innkeeper", trade != null and not trade.disabled):
		return
	await press(trade)
	step("trade greeting turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	var panel: Control = find(game, "TradePanel")
	step("deal panel in trade mode", gs.session.mode == GameSession.MODE_TRADE and panel.visible)
	step("partner card", find(game, "PartnerCard").visible)
	await shot("trade_open")
	var gold: int = gs.session.character["gold_cp"]
	var had: int = gs.session.character["inventory"].get("ale", 0)
	await press(find(panel, "Buy_ale"))
	await press(find(panel, "Buy_ale"))
	var total: Label = find(panel, "TradeTotal")
	step("cart total", total.text.contains("8 мм"), total.text)
	await shot("trade_cart")
	await press(find(panel, "DealButton"))
	step("deal turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	var m: Dictionary = gs.session.merchants[npc]
	step("deal made by the engine", gs.session.character["gold_cp"] == gold - 8 and gs.session.character["inventory"].get("ale", 0) == had + 2
		and int(m["stock"]["ale"]) == 38, "%d → %d cp, stock %d" % [gold, gs.session.character["gold_cp"], m["stock"]["ale"]])
	await shot("trade_deal")
	var haggle: Button = find(panel, "HaggleButton")
	if step("haggle button", haggle != null and not haggle.disabled, haggle.text if haggle else ""):
		var checks := _count(gs, GameSession.KIND_CHECK)
		await press(haggle)
		step("haggle turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
		step("haggle check card", _count(gs, GameSession.KIND_CHECK) == checks + 1 and haggle.disabled,
			"haggle %d%%, failed day %d" % [m["haggle_pct"], m["haggle_failed_day"]])
		await shot("trade_haggle")
	var turns: int = gs.session.turn_counter
	var options: Array = gs.session.options.duplicate()
	await press(find(game, "TradeToggle"))
	step("to talk without a turn (B33)", gs.session.mode == GameSession.MODE_SOCIAL and not panel.visible
		and gs.session.turn_counter == turns and gs.session.options == options)
	await press(find(game, "TradeToggle"))
	step("back to the deal panel", gs.session.mode == GameSession.MODE_TRADE and panel.visible and gs.session.turn_counter == turns)
	await press(find(game, "LeaveButton"))
	step("left the merchant", gs.session.mode == GameSession.MODE_EXPLORATION and await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	step("haggle ends with the visit", int(m["haggle_pct"]) == 0)


func _map_journal_rest(gs: Node, game: Control) -> void:
	await press(find(game, "MapButton"))
	var map: Control = find(game, "MapView")
	step("map opens", map.visible)
	await shot("map")
	await key(KEY_ESCAPE)
	await press(find(game, "JournalButton"))
	var journal: Control = find(game, "JournalView")
	step("journal opens", journal.visible)
	await shot("journal")
	await key(KEY_ESCAPE)
	step("Esc closes map and journal", not map.visible and not journal.visible)
	var up: Button = find(game, "Exit_brod-tavern-upstairs")
	if not step("exit upstairs", up != null and not up.disabled):
		return
	await press(up)
	step("upstairs enter turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	var rest: Button = find(game, "RestButton")
	if not step("rest button in a safe room", rest != null and not rest.disabled):
		return
	var gold: int = gs.session.character["gold_cp"]
	await press(rest)
	step("rest turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	step("a new day, paid for the room", gs.session.day == 2 and gs.session.character["gold_cp"] == gold - 50,
		"day %d, %d → %d cp" % [gs.session.day, gold, gs.session.character["gold_cp"]])
	await shot("after_rest")


func _quest_level_up(gs: Node, game: Control) -> void:
	for room: String in ["brod-tavern-hall"]:
		var back: Button = find(game, "Exit_" + room)
		if not step("walk to " + room, back != null and not back.disabled):
			return
		await press(back)
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var take: Button = find(game, "QuestTake_letter_to_ilva")
	if not step("Bruno gives the letter", take != null and not take.disabled):
		return
	await press(take)
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("the letter is in the pack", int(gs.session.character["inventory"].get("bruno_letter", 0)) == 1)
	for room: String in ["brod-square", "brod-temple"]:
		var exit: Button = find(game, "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var quest: Button = find(game, "QuestStep_letter_to_ilva")
	if not step("quest button in the temple", quest != null and not quest.disabled):
		return
	await press(quest)
	step("quest turn", await wait_until(func() -> bool: return not gs.is_busy(), 30.0))
	step("quest done, experience", gs.session.quests_done.has("letter_to_ilva") and int(gs.session.character["xp"]) == 300)
	await shot("quest_done")
	var lv: Button = find(game, "LevelUpButton")
	if not step("level-up button", lv != null and not lv.disabled):
		return
	await press(lv)
	var view: Control = find(game, "LevelUpView")
	step("level-up screen", view.visible)
	await shot("level_up")
	var confirm: Button = find(view, "LevelUpConfirm")
	if confirm.disabled:  # a class with picks at level 2: take the first offers
		view.set("picks", LevelUp.default_picks(gs.session.character, node("Catalog").data))
		view.call("_rebuild")
		await frames(2)
		await shot("level_up_picked")
	var hp: int = gs.session.character["max_hp"]
	await press(confirm)
	step("level 2", int(gs.session.character["level"]) == 2 and int(gs.session.character["max_hp"]) > hp and not view.visible,
		"%s, HP %d → %d" % [gs.session.character["class"], hp, gs.session.character["max_hp"]])
	await shot("level_2")


func _count(gs: Node, kind: String) -> int:
	return gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()


## v0.7.3: the daily spending limit on the master tab of the settings (the test server has its own data dir).
func _budget_settings() -> void:
	node("EventBus").navigate.emit("settings", {"back": "game", "tab": 1})  # SettingsScreen.TAB_MASTER (its class does not compile from a -s script)
	await frames(5)
	var status: Label = find(screen(), "BudgetStatus")
	step("budget shown in the settings", await wait_until(func() -> bool: return status != null and tr("OPT_BUDGET_UNKNOWN") != status.text and not status.text.is_empty(), 10.0),
		status.text if status != null else "")
	var edit: LineEdit = find(screen(), "BudgetEdit")
	(find(screen(), "BudgetOff") as CheckBox).button_pressed = false
	var want := "%d.50" % randi_range(2, 99)  # a fresh value: the test server keeps its limit between runs
	edit.text = want.replace(".", ",")
	await press(find(screen(), "BudgetSave"))
	step("budget set to " + want, await wait_until(func() -> bool: return status.text.contains("$" + want), 10.0), status.text)
	await shot("settings_budget")

