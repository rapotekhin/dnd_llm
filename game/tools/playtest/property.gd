extends "res://tools/playtest/playtest_base.gd"
## Property (python tools/godot_playtest.py --scenario property), v0.7.27: the clerk's places on sale, buying the house
## and its deed, «Имущество» on the panel — no orders by days, no hiring, «Обустроить» opens the build screen
## (v0.8.4.42.9), a horse from the dealer at the gate, the house on the map as the hero's.


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
	await shot("home_window")
	var orders := _named(win, ["PropertyUpgrade_", "PropertyBuild_", "PropertyHire_", "PropertyShift_", "PropertySerf_"])
	step("no orders by days, no hiring, no shift in the window", orders.is_empty(), ", ".join(orders))
	var furnish: Button = find(win, "PropertyFurnish_river_house")
	step("«Обустроить» there", furnish != null and not furnish.disabled)
	if furnish != null:
		await press(furnish)
		await frames(6)
		var view: Control = find(screen(), "BuildView")
		step("the build screen: a bed, a forge, a stall and a lock among its things", view != null and view.visible and find(view, "BuildItem_bed") != null
			and find(view, "BuildItem_forge") != null and find(view, "BuildItem_stall") != null and find(view, "BuildItem_lock") != null)
		await shot("build_screen")
		if view != null:
			view.visible = false
	win.visible = false
	node("EventBus").state_changed.emit()
	await frames(2)

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
		step("the horse's portrait in the party", find(screen(), "Portrait_" + horse) != null)  # v0.8.4.43.4
		await open_row("CreatureMore_" + horse)
		step("its buttons: stay, let go", find(screen(), "Creature_lead_" + horse) != null and find(screen(), "Creature_release_" + horse) != null)
		var line: Control = find(screen(), "Portrait_" + horse)
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


func _named(root: Node, starts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for n: Node in root.find_children("*", "", true, false):
		if starts.any(func(p: String) -> bool: return str(n.name).begins_with(p)):
			out.append(str(n.name))
	return out


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
