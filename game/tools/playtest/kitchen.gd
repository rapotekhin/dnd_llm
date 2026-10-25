extends "res://tools/playtest/playtest_base.gd"
## The kitchen (python tools/godot_playtest.py --scenario kitchen), v0.7.25: meat and vegetables bought from the
## innkeeper, a roast and a stew cooked at a campfire on the trail by a hero without cook's utensils, the stew eaten
## by «Поесть», mushrooms and berries gathered in the glade, meat spoiled after two days on the road.


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
	var c := s.character
	c["gold_cp"] = 2000
	s.room_id = "brod-tavern-hall"
	s.minute = 10 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	if await _trade(gs, "npc_innkeeper"):
		var panel: Control = find(screen(), "TradePanel")
		var meat: Button = find(panel, "Buy_raw_meat")
		var veg: Button = find(panel, "Buy_vegetables")
		var grain: Button = find(panel, "Buy_grain")
		step("the innkeeper sells meat, vegetables and grain", meat != null and veg != null and grain != null)
		if meat != null and veg != null and grain != null:
			for id: String in ["raw_meat", "vegetables", "grain"]:  # the panel rebuilds after each press
				await press(find(screen(), "Buy_" + id))
			await shot("innkeeper_produce")
			await press(find(panel, "DealButton"))
			await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
			step("bought", int(c["inventory"].get("raw_meat", 0)) == 1 and int(c["inventory"].get("vegetables", 0)) == 1)
		await _leave(gs)

	s.room_id = "pushcha-trail"
	node("EventBus").state_changed.emit()
	await frames(3)
	var craft_btn: Button = find(screen(), "CraftButton")
	if not step("«Ремесло» for a hero who only cooks", craft_btn != null):
		return
	await press(craft_btn)
	await frames(4)
	var win: Control = find(screen(), "CraftView")
	step("the roast and the stew, not the hunter's stew", find(win, "Recipe_roast_meat") != null and find(win, "Recipe_stew") != null
		and find(win, "Recipe_hunters_stew") == null)
	var start: Button = find(win, "CraftStart_roast_meat")
	step("a campfire on the trail will do", start != null and not start.disabled, start.tooltip_text if start != null else "")
	await shot("recipes_at_the_fire")
	await press(start)
	await frames(3)
	await press(find(win, "CraftWork_1"))
	await frames(4)
	step("the roast is done in half an hour", int(c["inventory"].get("roast_meat", 0)) >= 1, _last_effects(s))
	await press(find(win, "CraftStart_stew"))
	await frames(3)
	await press(find(win, "CraftWork_1"))
	await frames(4)
	step("two bowls of stew", int(c["inventory"].get("stew", 0)) >= 1, _last_effects(s))
	await shot("cooked")
	win.visible = false
	await frames(2)

	NeedRules.set_value(s, data, "food", 30.0)
	c["inventory"]["rations"] = 2
	node("EventBus").state_changed.emit()
	await frames(3)
	var eat: Button = find(screen(), "EatButton")
	if step("«Поесть»", eat != null and not eat.disabled):
		await press(eat)
		await frames(3)
		step("the dishes eaten before the rations", int(c["inventory"].get("rations", 0)) == 2, _last_effects(s))
	await shot("ate")

	s.room_id = "pushcha-glade"
	c["skills"]["survival"] = 20
	node("EventBus").state_changed.emit()
	await frames(3)
	var forage: Button = find(screen(), "Gather_forage")
	if step("«Собрать грибы и ягоды» in the glade", forage != null and not forage.disabled):
		await press(forage)
		await frames(3)
		forage = find(screen(), "Gather_forage")
		if int(c["inventory"].get("mushrooms", 0)) + int(c["inventory"].get("berries", 0)) == 0 and forage != null and not forage.disabled:
			await press(forage)  # a natural 1 fails anyway; the spot gives two tries a day
			await frames(3)
		step("found something", int(c["inventory"].get("mushrooms", 0)) + int(c["inventory"].get("berries", 0)) > 0, _last_effects(s))
	await shot("forage")

	c["inventory"]["raw_meat"] = 2
	FoodRules.tick(s, data)
	var lines := TimeRules.advance(s, data, 2 * 1440)
	gs._add(GameSession.effect_entry(lines))
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the meat spoiled on the road", int(c["inventory"].get("spoiled_food", 0)) >= 2 and not c["inventory"].has("raw_meat"), " · ".join(lines))
	await shot("spoiled")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""


func _trade(gs: Node, npc: String) -> bool:
	var trade: Button = find(screen(), "Trade_" + npc)
	if not step("trade with " + npc, trade != null and not trade.disabled):
		await shot("no_trade_" + npc)
		return false
	await press(trade)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	return true


func _leave(gs: Node) -> void:
	var leave: Button = find(screen(), "LeaveButton")
	if leave != null:
		await press(leave)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(2)
