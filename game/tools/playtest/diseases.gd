extends "res://tools/playtest/playtest_base.gd"
## Diseases (python tools/godot_playtest.py --scenario diseases), v0.7.23.1: the coughing pilgrim at the herbalist's
## (a save on entering), the cackle fever shows after a day as a chip, the herbalist cures it for coins; the rot fever
## of a rat bite the herbalist cannot take, the priestess can; foul water in the flooded drift asks a save.


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
	s.character["gold_cp"] = 5000
	s.room_id = "brod-square"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	if not await _go(gs, "brod-herbalist"):
		return
	step("a save against the pilgrim's fever", _chat_has(s, "Зараза от Тодор"), _last_effects(s))
	await shot("pilgrim")

	DiseaseRules.cure_all(s.character)
	DiseaseRules.contract(s, data, "cackle_fever")
	TimeRules.advance(s, data, 25 * 60)
	s.minute = 12 * 60
	s.rested_at = TimeRules.abs_minute(s)
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the fever shows as a chip", DiseaseRules.active(s.character).has("cackle_fever"))
	await shot("fever_chip")
	if await _trade(gs, "npc_herbalist"):
		var herbs: Button = find(screen(), "Service_herbal_cure")
		step("the herbalist's cure", herbs != null and not herbs.disabled, herbs.text if herbs != null else "")
		await shot("herbalist_service")
		if herbs != null:
			await press(herbs)
			await frames(3)
		step("cured by herbs", not DiseaseRules.sick(s.character, "cackle_fever"))
		await _leave(gs)

	DiseaseRules.contract(s, data, "rot_fever")
	TimeRules.advance(s, data, 25 * 60)
	s.minute = 12 * 60
	s.rested_at = TimeRules.abs_minute(s)
	NeedRules.set_value(s, data, "food", 100.0)
	NeedRules.set_value(s, data, "water", 100.0)
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the rot fever shows", DiseaseRules.active(s.character).has("rot_fever") and ConditionRules.has(s.character, "poisoned"))
	await shot("rot_fever")
	if await _trade(gs, "npc_herbalist"):
		var herbs: Button = find(screen(), "Service_herbal_cure")
		step("herbs cannot take the rot", herbs != null and herbs.disabled, herbs.tooltip_text if herbs != null else "")
		await _leave(gs)
	s.room_id = "brod-temple"
	node("EventBus").state_changed.emit()
	await frames(3)
	if await _trade(gs, "npc_priestess"):
		var cure: Button = find(screen(), "Service_cure_disease")
		step("the priestess cures any disease", cure != null and not cure.disabled, cure.text if cure != null else "")
		await shot("priestess_service")
		if cure != null:
			await press(cure)
			await frames(3)
		step("cured by the priestess", DiseaseRules.active(s.character).is_empty() and not ConditionRules.has(s.character, "poisoned"))
		await _leave(gs)

	s.room_id = "mine-flooded"
	NeedRules.set_value(s, data, "water", 30.0)
	node("EventBus").state_changed.emit()
	await frames(3)
	var drink: Button = find(screen(), "DrinkButton")
	if step("«Попить» in the flooded drift", drink != null and not drink.disabled):
		await press(drink)
		await frames(3)
		step("foul water asks a save", _chat_has(s, "Гнилая вода"), _last_effects(s))
	await shot("foul_water")


func _chat_has(s: GameSession, text: String) -> bool:
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 6)):
		if str(e.get("kind", "")) == GameSession.KIND_EFFECT and " ".join(e.get("lines", [])).contains(text):
			return true
	return false


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


func _go(gs: Node, room: String) -> bool:
	var exit: Button = find(screen(), "Exit_" + room)
	if not step("walk to " + room, exit != null and not exit.disabled):
		await shot("no_exit_" + room)
		return false
	await press(exit)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	return true
