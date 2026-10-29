extends "res://tools/playtest/playtest_base.gd"
## The master makes (python tools/godot_playtest.py --scenario master_makes), v0.7.39.4: the herbalist sells the kit of
## her kind; a greataxe the master puts on the smith's shelf; a greataxe recipe paid by the hours at the forge; a village
## made beyond the North Gate in one create_place — walked into, its people on the panel, its road on, the map.


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
	var fx: EffectEngine = gs.effects
	c["gold_cp"] = 20000
	s.settings["needs"] = false
	s.minute = 12 * 60

	for rid: String in data["world"]["rooms"]:
		if (data["world"]["rooms"][rid].get("npcs", []) as Array).has("npc_herbalist"):
			s.room_id = rid
	node("EventBus").state_changed.emit()
	await frames(3)
	if await _trade(gs, "npc_herbalist"):
		step("the herbalist sells the herbalism kit", find(screen(), "Buy_herbalism_kit") != null)
		await shot("herbalist_kit")
		await _leave(gs)

	s.room_id = "brod-smithy"
	node("EventBus").state_changed.emit()
	await frames(3)
	var r := fx.validate(s, data, "t-st", {"kind": "stock", "npc_id": "npc_smith", "item_id": "greataxe", "qty": 1})
	if step("the master puts a greataxe on the smith's shelf", bool(r["accepted"]), str(r.get("reason", r.get("summary", "")))):
		fx.apply(s, "t-st", [r["effect_id"]])
		node("EventBus").state_changed.emit()
		await frames(2)
		if await _trade(gs, "npc_smith"):
			step("the greataxe is for sale", find(screen(), "Buy_greataxe") != null)
			await shot("smith_greataxe")
			await _leave(gs)

	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	var rr := fx.validate(s, data, "t-rc", {"kind": "recipe", "tool": "smiths_tools", "station": "forge", "hours": 4, "dc_tier": "medium",
		"materials": [{"item_id": "iron_bar", "qty": 4}, {"item_id": "timber", "qty": 1}], "output_id": "greataxe"})
	if step("a greataxe recipe is accepted, its hours by the value", bool(rr["accepted"]), str(rr.get("summary", rr.get("reason", "")))):
		fx.apply(s, "t-rc", [rr["effect_id"]])
		node("EventBus").state_changed.emit()
		await frames(2)
		await press(find(screen(), "CraftButton"))
		await frames(4)
		var win: Control = find(screen(), "CraftView")
		var made := CraftRules.learned(c).filter(func(id: String) -> bool: return str(CraftRules.recipe(s, data, id).get("output", "")) == "greataxe")
		step("the recipe in the «Ремесло» window", not made.is_empty() and find(win, "Recipe_" + str(made[0]).validate_node_name()) != null)
		await shot("greataxe_recipe")
		win.visible = false
		await frames(2)

	s.room_id = "brod-gate"
	node("EventBus").state_changed.emit()
	await frames(3)
	fx.searched_places["t-vl"] = true
	var v := fx.validate(s, data, "t-vl", _village())
	if not step("a village in one create_place", bool(v["accepted"]), str(v.get("summary", v.get("reason", "")))):
		return
	fx.apply(s, "t-vl", [v["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var gate_exits: Array = s.generated["edge_exits"]["brod-gate"]
	var first := str(gate_exits[-1])
	var exit: Button = find(screen(), "Exit_" + first)
	if step("the village's road from the gate", exit != null and not exit.disabled):
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		step("the hero walks into the village", s.room_id == first, s.room_id)
		var guard := s.npcs_here(data["world"], s.room_id).filter(func(id: String) -> bool: return str(data["world"]["npcs"][id].get("name", "")) == "Гаврила Кол")
		step("its guard stands in the street", not guard.is_empty())
		step("the street keeps a road on", not WorldGen.open_edges(s, data, first).is_empty())
		await shot("village_street")
	await press(find(screen(), "MapButton"))
	await frames(5)
	await shot("village_map")


func _village() -> Dictionary:
	return {"kind": "create_place", "room_id": "brod-gate", "edge": 0, "new_location": true, "name": "Ракитное",
		"description": "Деревня за полями, у ракитника.", "terrain": "grassland", "settlement": "village",
		"rooms": [
			{"key": "street", "name": "Улица Ракитного", "description": "Пыльная улица меж плетней, колодец с журавлём.", "exits": ["inn", "house"],
				"open_edges": [{"text": "дорога дальше на север, к холмам", "terrain": ["hills"]}]},
			{"key": "inn", "name": "Корчма «Ракита»", "description": "Низкая корчма, лавки вдоль стен.", "indoor": true, "site": "inn", "exits": ["street"]},
			{"key": "house", "name": "Изба старосты Ракитного", "description": "Крепкая изба с резными наличниками.", "indoor": true, "site": "home", "public": false, "exits": ["street"]}],
		"sites": [{"key": "inn", "name": "Корчма «Ракита»", "tags": ["tavern"], "owner_id": "new:host"},
			{"key": "home", "name": "Двор старосты", "tags": ["home"], "public": false, "owner_id": "new:head"}],
		"npcs": [{"key": "host", "name": "Явдоха Ракитная", "role": "корчмарка", "gender": "female", "room_id": "new:inn", "trader": true, "trade_kind": "food"},
			{"key": "head", "name": "Мирон Рябой", "role": "староста", "gender": "male", "room_id": "new:house"},
			{"key": "guard", "name": "Гаврила Кол", "role": "стражник", "gender": "male", "monster": "guard", "room_id": "new:street"}]}


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
