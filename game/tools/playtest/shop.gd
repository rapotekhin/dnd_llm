extends "res://tools/playtest/playtest_base.gd"
## Own trade (python tools/godot_playtest.py --scenario shop), v0.7.29: the charter and a stall from the clerk, the
## stall on the square, rings put out and made cheaper, a shift behind the counter sells them, rope bought wholesale
## from Fern.


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
	var c := s.character
	c["gold_cp"] = 20000
	c["inventory"]["silver_ring"] = 6
	s.settings["needs"] = false
	s.room_id = "brod-townhall"
	s.minute = 10 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_clerk")
	var reg: Button = find(screen(), "ShopRegistry_npc_clerk")
	if not step("«Торговля» among the clerk's acts", reg != null and not reg.disabled):
		await shot("no_registry")
		return
	await press(reg)
	await frames(4)
	var win: Control = find(screen(), "ShopView")
	await press(find(win, "CharterBuy"))
	await frames(3)
	await press(find(win, "StallRent_7"))
	await frames(4)
	var vid := PropertyRules.rented(s, node("Catalog").data, "stall", "brod")
	step("the charter and the stall — an object of its own", ShopRules.has_charter(s, "brod") and not vid.is_empty(), _last_effects(s))
	await shot("registry")
	win.visible = false

	s.room_id = ShopRules.room_of(s, node("Catalog").data, vid)
	node("EventBus").state_changed.emit()
	await frames(3)
	var shop: Button = find(screen(), "ShopButton")
	if not step("«Лавка» on the panel at the stall", shop != null):
		await shot("no_shop")
		return
	await press(shop)
	await frames(4)
	await press(find(win, "ShelfPutAll_silver_ring"))
	await frames(3)
	await press(find(win, "PriceDown_silver_ring"))
	await frames(3)
	step("six rings on the shelf at 90%", int(ShopRules.venue(c, vid)["stock"].get("silver_ring", 0)) == 6 and ShopRules.price_pct(s, node("Catalog").data, vid, "silver_ring") == 90)
	await shot("shelf")
	var gold := int(c["gold_cp"])
	await press(find(win, "ShopShift"))
	await frames(6)
	step("a shift behind the counter", int(c["gold_cp"]) >= gold and int(ShopRules.venue(c, vid).get("shift_day", 0)) == s.day, _last_effects(s))
	await shot("after_shift")
	win.visible = false

	s.room_id = ReputationRules.home_room(node("Catalog").data, "npc_merchant")
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_merchant")
	var ws: Button = find(screen(), "Wholesale_npc_merchant")
	if step("«Опт» at Fern", ws != null):
		await press(ws)
		await frames(4)
		var had := int(c["inventory"].get("rope", 0))
		await press(find(win, "SupplyBuy_rope"))
		await frames(4)
		step("rope bought wholesale", int(c["inventory"].get("rope", 0)) == had + 5, _last_effects(s))
		await shot("wholesale")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
