extends "res://tools/playtest/playtest_base.gd"
## Property (python tools/godot_playtest.py --scenario property), v0.7.27: the clerk's places on sale, buying the house
## and its deed, «Имущество» on the panel, a bed and a forge ordered and ready days later, a horse from the dealer at
## the gate, the house on the map as the hero's.


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
	c["gold_cp"] = 20000
	s.settings["needs"] = false
	s.room_id = "brod-townhall"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_clerk")
	var sale: Button = find(screen(), "PropertySale_npc_clerk")
	if not step("«Имущество» among the clerk's acts", sale != null and not sale.disabled):
		await shot("no_sale")
		return
	await press(sale)
	await frames(4)
	var win: Control = find(screen(), "PropertyView")
	step("the places on sale", win != null and win.visible and find(win, "Property_river_house") != null and find(win, "Property_plot") != null)
	await shot("on_sale")

	await press(find(win, "PropertyBuy_river_house"))
	await frames(4)
	step("the house bought", PropertyRules.owned(c, "river_house"), _last_effects(s))
	var deed: Button = find(win, "PropertyDeed_river_house")
	step("the deed offered at the town hall", deed != null and not deed.disabled)
	await shot("bought")
	if deed != null:
		await press(deed)
		await frames(4)
	step("the deed written", bool(PropertyRules.state(c)["river_house"].get("deed", false)), _last_effects(s))
	win.visible = false

	s.room_id = "brod-river-house"
	for r: String in ["brod-square", "brod-townhall", "brod-river-yard", "brod-river-house", "brod-gate"]:
		if not s.visited.has(r):
			s.visited.append(r)
	node("EventBus").state_changed.emit()
	await frames(3)
	var own: Button = find(screen(), "PropertyButton")
	step("«Имущество» on the panel at home", own != null and own.text.contains("Дом у реки"), own.text if own != null else "")
	await press(own)
	await frames(4)
	await press(find(win, "PropertyUpgrade_bed"))
	await frames(3)
	await press(find(win, "PropertyUpgrade_forge"))
	await frames(4)
	step("a bed and a forge ordered", not PropertyRules.pending(c, "river_house", "bed").is_empty() and not PropertyRules.pending(c, "river_house", "forge").is_empty())
	await shot("home_window")
	win.visible = false
	node("EventBus").state_changed.emit()
	await frames(2)
	s.chat.append(GameSession.effect_entry(TimeRules.advance(s, data, 4 * 1440)))
	node("EventBus").state_changed.emit()
	await frames(3)
	step("ready after days", PropertyRules.has_upgrade(c, "river_house", "bed") and PropertyRules.has_upgrade(c, "river_house", "forge"))
	step("a free rest at home", ExplorationRules.can_rest(s, data["world"], data).is_empty())
	await press(own if is_instance_valid(own) else find(screen(), "PropertyButton"))
	await frames(4)
	await shot("home_ready")
	win.visible = false

	s.room_id = "brod-gate"
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_drover")
	var animals: Button = find(screen(), "Animals_npc_drover")
	if step("«Животные» at the dealer", animals != null):
		await press(animals)
		await frames(4)
		await shot("animals")
		await press(find(win, "AnimalBuy_riding_horse"))
		await frames(4)
		step("a horse bought", PropertyRules.animals(s).size() == 1, _last_effects(s))
		win.visible = false
		node("EventBus").state_changed.emit()
		await frames(3)
		var horse := str(PropertyRules.animals(s)[0]["id"]) if not PropertyRules.animals(s).is_empty() else ""
		step("the horse's row on the panel", find(screen(), "CreatureLine_" + horse) != null)
		await open_row("CreatureMore_" + horse)
		step("its buttons: stay, let go", find(screen(), "Creature_lead_" + horse) != null and find(screen(), "Creature_release_" + horse) != null)
		var line: Control = find(screen(), "CreatureLine_" + horse)
		if line != null:
			var sc := line.get_parent()
			while sc != null and not (sc is ScrollContainer):
				sc = sc.get_parent()
			if sc != null:
				(sc as ScrollContainer).ensure_control_visible(line)
		await frames(3)
		await shot("horse")

	var map: Button = find(screen(), "MapButton")
	if map != null:
		await press(map)
		await frames(6)
		await shot("map")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
