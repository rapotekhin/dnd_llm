extends "res://tools/playtest/playtest_base.gd"
## Objects (python tools/godot_playtest.py --scenario objects), v0.7.39.5: the tavern as an object in the place window —
## its owner, its people and the hero at a job among them; the river house bought, a servant hired by his place; the
## counter built as an object of its own beside the house, its seller hired at the shop window.


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
	var data: Dictionary = node("Catalog").data  # the started game's world (merged with what was made)
	var c := s.character
	var game := screen()
	c["gold_cp"] = 100000
	s.minute = 12 * 60

	s.room_id = ReputationRules.home_room(data, "npc_innkeeper")
	JobRules.state(c)["serve_tables"] = {"rank": 0, "good": 0, "shifts": 0}
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(game, "PlaceButton"))
	await frames(4)
	var card: Control = find(game, "ObjectCard")
	var text := ""
	if card != null:
		for l: Node in card.find_children("*", "Label", true, false):
			text += (l as Label).text + " | "
	step("the tavern's card: its kind, owner and the hero at a job", card != null and text.contains("таверна") and text.contains(str(c["name"])), text)
	await shot("tavern_object")
	await key(KEY_ESCAPE)
	await frames(2)

	PropertyRules.buy(s, data, "river_house")
	s.room_id = PropertyRules.main_room(s, data, "river_house")
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(game, "PropertyButton"))
	await frames(4)
	var hire: Button = find(game, "PropertyHire_слуга")
	if step("«Нанять: слуга … (0/2)» in the house", hire != null and hire.text.contains("0/2"), hire.text if hire else ""):
		await press(hire)
		await frames(4)
	step("a servant in the house's staff", PropertyRules.staff(s, "river_house").size() == 1, _last_effects(s))
	await shot("house_servant")
	await key(KEY_ESCAPE)
	await frames(2)

	PropertyRules.upgrade(s, data, "river_house", "counter")
	TimeRules.advance(s, data, 2 * 1440)
	var cid := ""
	for id: String in PropertyRules.state(c):
		if PropertyRules.kind_id(s, data, id) == "counter":
			cid = id
	if not step("the counter is an object of its own", not cid.is_empty(), str(PropertyRules.state(c).keys())):
		return
	s.room_id = PropertyRules.main_room(s, data, cid)
	node("EventBus").state_changed.emit()
	await frames(3)
	var shop_b: Button = find(game, "ShopButton")
	if not step("«Лавка» on the panel at the counter", shop_b != null, "room %s, here %s, venues %s" % [s.room_id, ShopRules.here(s, data), ShopRules.venues(s, data)]):
		await shot("no_shop")
		return
	await press(shop_b)
	await frames(4)
	var seller: Button = find(game, "ShopHire_продавец")
	if step("«Нанять: продавец» at the counter's shop window", seller != null, ""):
		await press(seller)
		await frames(4)
	step("the counter has its seller", ShopRules.staffed(s, cid), _last_effects(s))
	await shot("counter_seller")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
