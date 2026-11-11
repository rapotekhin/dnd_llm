extends "res://tools/playtest/playtest_base.gd"
## Trade as in BG3 (python tools/godot_playtest.py --scenario trade), v0.8.4.43.12, the author's findings on 0.8.4.43.8:
## the deal in the middle is two columns of cells — what the hero takes beside the smith's goods, what it gives beside
## its own things; things go there by a drag; a stack asks how many by a slider (7 arrows of 20); a drag back takes one
## out; each deal is the engine's at once, no master's turn; closing the panel is one master's turn of the whole visit.


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
	var game := screen()
	s.character["inventory"]["arrows"] = 20
	s.character["gold_cp"] = 5000
	node("EventBus").state_changed.emit()
	for room: String in ["brod-square", "brod-smithy"]:
		var exit: Button = find(game, "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await stage("npc:npc_smith")
	var open: Button = find(game, "Trade_npc_smith")
	if not step("the smith trades", open != null and not open.disabled):
		return
	await press(open)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var panel: Control = find(game, "TradePanel")
	var buy: Control = find(panel, "OfferBuyGrid")
	var sell: Control = find(panel, "OfferSellGrid")
	step("the deal is two columns of cells: the trader's side and the hero's", panel.visible and buy != null and sell != null
		and buy.get_parent().get_parent().get_index() < sell.get_parent().get_parent().get_index())
	step("the deal's columns have no filters", buy != null and not (find(buy, "OfferBuyBar") as Control).visible)
	await shot("trade_open")

	# The hero's 20 arrows dragged onto its column: the slider asks how many.
	var sent: Array = []  # the master's turns asked from now on: [kind, input]
	node("EventBus").turn_started.connect(func(_id: String) -> void: sent.append([str(gs.get("_last_kind")), str(gs.get("_last_input"))]))
	var arrows: Control = find(panel, "Sell_arrows")
	step("a stack dragged into the deal asks how many", await drag(arrows, sell) and find(panel, "QtyBox") != null)
	var slider: HSlider = find(panel, "QtySlider")
	var spin: SpinBox = find(panel, "QtySpin")
	step("the slider and the number: all 20 at first", slider != null and spin != null and int(slider.max_value) == 20 and int(spin.value) == 20)
	if slider != null:
		slider.value = 7
		await frames(2)
		step("the slider moves the number", int(spin.value) == 7, str(spin.value))
		await shot("trade_slider")
		await press(find(panel, "QtyOk"))
		await frames(3)
	var cart: Dictionary = panel.get("cart")
	step("7 arrows of 20 in the deal", int(cart["sell"].get("arrows", 0)) == 7 and find(panel, "Unsell_arrows") != null
		and int((find(panel, "Sell_arrows") as ItemCell).qty) == 13, str(cart))

	# The smith's one longsword dragged onto the hero's take: one thing, no question.
	step("one thing dragged goes without a question", await drag(find(panel, "Buy_longsword"), buy) and find(panel, "QtyBox") == null
		and int(cart["buy"].get("longsword", 0)) == 1, str(cart))
	step("the trader's thing never goes to the hero's column", not await drag(find(panel, "Buy_shortsword"), sell))
	# Two arrows dragged back out of the deal.
	await drag(find(panel, "Unsell_arrows"), find(panel, "YoursGrid"))
	var spin2: SpinBox = find(panel, "QtySpin")
	if step("back out of the deal asks too", spin2 != null and int(spin2.max_value) == 7):
		spin2.value = 2
		await press(find(panel, "QtyOk"))
		await frames(3)
	step("5 arrows left in the deal", int(cart["sell"].get("arrows", 0)) == 5, str(cart))
	var sums: Label = find(panel, "TradeSellSum")
	step("each column with its sum", sums != null and sums.text.begins_with("на "), sums.text if sums != null else "")
	await shot("trade_columns")

	var gold: int = s.character["gold_cp"]
	await press(find(panel, "DealButton"))
	step("the deal made by the engine, no master's turn", not gs.is_busy() and sent.is_empty()
		and int(s.character["inventory"].get("arrows", 0)) == 15 and int(s.character["inventory"].get("longsword", 0)) >= 1
		and s.character["gold_cp"] != gold, "%d → %d cp" % [gold, s.character["gold_cp"]])
	# A second deal: bolts by the slider, then the haggle — still no turn.
	await drag(find(panel, "Buy_crossbow_bolt"), buy)
	var spin3: SpinBox = find(panel, "QtySpin")
	if spin3 != null:
		spin3.value = 10
		await press(find(panel, "QtyOk"))
		await frames(3)
	await press(find(panel, "DealButton"))
	var haggle: Button = find(panel, "HaggleButton")
	if haggle != null and not haggle.disabled:
		await press(haggle)
	step("two deals and a haggle, no master's turn", not gs.is_busy() and sent.is_empty()
		and int(s.character["inventory"].get("crossbow_bolt", 0)) >= 10, str(s.character["inventory"].get("crossbow_bolt", 0)))
	await shot("trade_deals")

	# Closing the panel: one master's turn of the whole visit.
	await press(find(panel, "TradeToTalk"))
	var told: String = sent[0][1] if sent.size() == 1 else ""
	step("closing the trade is one master's turn of the visit", sent.size() == 1 and str(sent[0][0]) == "deal"
		and told.contains("Стрелы ×5") and told.contains("Арбалетный болт ×10") and told.contains("Торг: ") and told.contains("Всего за торговлю"), told)
	step("the turn told", await wait_until(func() -> bool: return not gs.is_busy(), 60.0))
	await shot("trade_told")
	await press(find(game, "TradeToggle"))
	await press(find(game, "TradeToggle"))
	step("nothing done since — no turn", sent.size() == 1, str(sent))
	await press(find(game, "TradeToggle"))
	await press(find(panel, "Buy_dagger"))  # one more deal, then «Уйти» straight from the window
	await press(find(panel, "DealButton"))
	await press(find(panel, "TradeLeave"))
	var gone: String = sent[1][1] if sent.size() == 2 else ""
	step("left from the window: the visit goes with the way back", s.mode == GameSession.MODE_EXPLORATION and sent.size() == 2
		and str(sent[1][0]) == "resume" and gone.contains("закончил торговлю, торговец — ") and gone.contains("Кинжал"), gone)
	step("the way back told", await wait_until(func() -> bool: return not gs.is_busy(), 60.0))
	await shot("trade_left")
