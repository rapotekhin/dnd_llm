extends "res://tools/playtest/playtest_base.gd"
## «Социальный режим 2.0» playtest (python tools/godot_playtest.py --scenario social), v0.7.15: a discount the
## merchant gave by words shows in the deal panel and lowers the prices; the people remember it.


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
	var game := screen()
	var exit: Button = find(game, "Exit_brod-square")
	if not step("walk to the square", exit != null and not exit.disabled):
		return
	await press(exit)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)

	# v0.7.15.2: the merchant gave a discount by words (the effect npc_discount — here straight into the state).
	var item := ""
	for id: String in TradeRules.merchant(s, data, "npc_merchant")["stock"]:
		if item.is_empty() or TradeRules.buy_price(s, data, "npc_merchant", id) > TradeRules.buy_price(s, data, "npc_merchant", item):
			item = id
	var full := TradeRules.buy_price(s, data, "npc_merchant", item)
	SocialRules.grant_discount(s, data, {"discount": "npc_merchant", "pct": 20, "until_day": s.day + 6})
	var trade: Button = find(game, "Trade_npc_merchant")
	if step("the merchant trades", trade != null and not trade.disabled):
		await press(trade)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var deal: Label = find(game, "DealState")
		step("the deal panel shows the discount", deal != null and deal.visible and deal.text.contains("Скидка 20%"), deal.text if deal != null else "")
		var now := TradeRules.buy_price(s, data, "npc_merchant", item)
		step("the price is lower", now < full, "%d → %d" % [full, now])
		await shot("discount")
		await press(find(game, "LeaveButton"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the merchant remembers it", " ".join(s.memory_of("npc_merchant")).contains("скидку 20%"), " ".join(s.memory_of("npc_merchant")))
