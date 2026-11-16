extends "res://tools/playtest/playtest_base.gd"
## The party window on Tab (python tools/godot_playtest.py --scenario party_window), v0.8.4.44.10, as in BG3: the hero and
## two followers side by side, a sword dragged to one, a stack of rope to the other with the slider, the rope passed on
## from one companion to the other; Tab closes it, Esc too, and in a fight Tab is the next target, not the window.


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
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	Being.follow(s, "npc_veteran")
	s.character["inventory"].erase("rope")
	ItemRules.add(s.character, "rope", 3)
	ItemRules.add(s.character, "longsword", 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	var has := func(who: String, item: String) -> int: return int(Gear.of(s, data, who).get("inventory", {}).get(item, 0))

	await key(KEY_TAB)  # over the chat's input: Tab never types
	await frames(3)
	var view: Control = find(screen(), "PartyView")
	if not step("Tab opens the party window", view != null and view.visible):
		return
	step("a column for the hero and each follower", find(view, "PartyCol_p") != null and find(view, "PartyCol_npc_mercenary") != null
		and find(view, "PartyCol_npc_veteran") != null)
	var w: Label = find(view, "PartyWeight_npc_mercenary")
	step("its load and its most", w != null and w.text.contains("из"), w.text if w != null else "")
	await shot("party_window")

	var sword_had := has.call("npc_mercenary", "longsword") as int
	var hero_swords := has.call(Being.HERO, "longsword") as int
	if step("the longsword dragged onto the mercenary's column", await drag(find(view, "PartyItem_p_longsword"), view.call("grid_of", "npc_mercenary"))):
		step("one thing goes with no question", find(view, "QtyBox") == null and has.call("npc_mercenary", "longsword") == sword_had + 1
			and has.call(Being.HERO, "longsword") == hero_swords - 1)
	var rope_had := has.call("npc_veteran", "rope") as int
	if step("three ropes dragged onto the veteran's column ask how many", await drag(find(view, "PartyItem_p_rope"), view.call("grid_of", "npc_veteran"))
			and find(view, "QtyBox") != null):
		await shot("party_slider")
		(find(view, "QtySpin") as SpinBox).value = 2
		await press(find(view, "QtyOk"))
		await frames(3)
		step("two went, one stayed", has.call("npc_veteran", "rope") == rope_had + 2 and has.call(Being.HERO, "rope") == 1,
			"%d / %d" % [has.call("npc_veteran", "rope"), has.call(Being.HERO, "rope")])
	var merc_rope := has.call("npc_mercenary", "rope") as int
	if step("the veteran's rope dragged onto the mercenary's column", await drag(find(view, "PartyItem_npc_veteran_rope"), view.call("grid_of", "npc_mercenary"))):
		if find(view, "QtyBox") != null:
			(find(view, "QtySpin") as SpinBox).value = 1
			await press(find(view, "QtyOk"))
			await frames(3)
		step("one companion handed it to another", has.call("npc_mercenary", "rope") == merc_rope + 1)
	await shot("party_moved")

	await key(KEY_TAB)
	step("Tab closes it", not view.visible)
	await key(KEY_TAB)
	step("Tab again opens it", view.visible)
	await key(KEY_ESCAPE)
	step("Esc closes it", not view.visible)

	s.character["hp"] = 200
	s.character["max_hp"] = 200
	gs.start_combat([{"monster": "goblin", "count": 1}], {"room_from": "brod-square"})
	await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and not CombatRules.actor(s).is_empty(), 120.0)
	await key(KEY_TAB)
	step("in a fight Tab is no party window", not view.visible)
	await shot("fight_tab")
