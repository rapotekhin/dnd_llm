extends "res://tools/playtest/playtest_base.gd"
## Crafting (python tools/godot_playtest.py --scenario craft), v0.7.24: a fighter with smith's tools at Gunnar's forge —
## «Ремесло» on the panel, the window of recipes, a dagger forged in one shift, a sword begun and left half done,
## the dagger broken back into iron (the question first), ore dug in the mine, a lesson of the longsword bought.


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
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["inventory"]["iron_bar"] = 3
	c["gold_cp"] = 5000
	s.room_id = "brod-smithy"
	s.minute = 9 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var craft_btn: Button = find(screen(), "CraftButton")
	step("«Ремесло» on the panel", craft_btn != null)
	await shot("panel")
	if craft_btn == null:
		return
	await press(craft_btn)
	await frames(4)
	var win: Control = find(screen(), "CraftView")
	step("the craft window", win != null and win.visible)
	step("the dagger is a recipe, the longsword is not yet", find(win, "Recipe_dagger") != null and find(win, "Recipe_longsword") == null)
	await shot("window")

	await press(find(win, "CraftStart_dagger"))
	await frames(3)
	step("the work begun, the iron spent", not CraftRules.project(c).is_empty() and int(c["inventory"].get("iron_bar", 0)) == 2)
	await press(find(win, "CraftWork_8"))
	await frames(4)
	var daggers := (c["inventory"] as Dictionary).keys().filter(func(id: String) -> bool:
		return id == "dagger" or str(ItemRules.def_of(data["items"], s.items, id).get("base", "")) == "dagger")
	step("a dagger forged in one shift", daggers.size() == 1 and CraftRules.project(c).is_empty(), _last_effects(s))
	await shot("dagger_done")

	await press(find(win, "CraftStart_shortsword"))
	await frames(3)
	await press(find(win, "CraftWork_1"))
	await frames(4)
	step("a sword at 10%", CraftRules.progress(c) == 10, "%d%%" % CraftRules.progress(c))
	await shot("sword_in_hand")

	if daggers.size() == 1:
		var dagger := str(daggers[0])
		var sb: Button = find(win, "Salvage_" + dagger)
		if step("the dagger can be broken down", sb != null):
			node("SaveManager").confirm_risky = true
			await press(sb)
			await frames(3)
			var box := root.get_node_or_null("ConfirmBox")
			step("the question first", box != null)
			if box != null:
				await shot("salvage_confirm")
				await press(find(box, "ConfirmYes"))
				await frames(3)
			step("iron back", int(c["inventory"].get("iron_bar", 0)) == 1 and not c["inventory"].has(dagger), _last_effects(s))
	win.visible = false
	await frames(2)

	if await _trade(gs, "npc_smith"):
		var lesson: Button = find(screen(), "Service_teach_longsword")
		step("the smith teaches the longsword", lesson != null and not lesson.disabled, lesson.text if lesson != null else "")
		await shot("lesson_service")
		if lesson != null:
			await press(lesson)
			await frames(3)
		step("the longsword learned", CraftRules.known(s, data).has("longsword"))
		await _leave(gs)

	s.room_id = "mine-gallery"
	node("EventBus").state_changed.emit()
	await frames(3)
	var dig: Button = find(screen(), "Gather_ore")
	if step("«Добыть руду» in the mine", dig != null and not dig.disabled, dig.tooltip_text if dig != null else ""):
		await press(dig)
		await frames(3)
		step("a try at the ore", _last_effects(s).contains("Добыть руду"), _last_effects(s))
	await shot("ore")


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
