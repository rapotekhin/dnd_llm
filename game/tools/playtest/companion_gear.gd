extends "res://tools/playtest/playtest_base.gd"
## One road of gear (python tools/godot_playtest.py --scenario companion_gear), v0.8.4.40: a follower's «Снаряжение»
## window — the hero's longsword given, put in its hand, the sets swapped and back; then a fight where it strikes with
## the sword in its hand, and a goblin that holds its scimitar and keeps its bow in the other set.


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
	ItemRules.add(s.character, "longsword", 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_mercenary")
	var gear: Button = find(screen(), "Gear_npc_mercenary")
	if not step("«Снаряжение» at the follower", gear != null):
		return
	await press(gear)
	await frames(3)
	var view: Control = find(screen(), "GearView")
	step("the window is open", view != null and view.visible)
	var c := Gear.of(s, data, "npc_mercenary")
	step("its own kit in its hands", str(c["equipped"].get("main_hand", "")) == "shortsword" and str(CharacterRules.stowed(c).get("main_hand", "")) == "longbow",
		str(c["equipped"]) + " | " + str(CharacterRules.stowed(c)))
	await shot("gear_window")
	step("its doll and two grids: its things and the hero's", find(view, "Slot_main_hand") != null and find(view, "MateGrid") != null
		and find(view, "GearHero_longsword") != null)
	var had := int(s.character["inventory"].get("longsword", 0))
	if step("the longsword dragged onto its grid is handed over", await drag(find(view, "GearHero_longsword"), find(view, "MateGrid"))):
		step("the sword is its own now", int(Gear.of(s, data, "npc_mercenary")["inventory"].get("longsword", 0)) == 1 and int(s.character["inventory"].get("longsword", 0)) == had - 1)
	view.call("stage", "longsword")  # v0.8.4.43.6: a thing's menu, staged by name
	var on: Button = find(view, "Equip_main_hand_longsword")
	if step("«В основную руку»", on != null and not on.disabled):
		await press(on)
		await frames(3)
		step("in its hand", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longsword")
	await shot("sword_in_hand")
	var swap: Button = find(view, "SwapWeapons")
	if step("«Сменить набор» on its doll", swap != null and not swap.disabled):
		await press(swap)
		await frames(3)
		step("the bow in its hands", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longbow")
		await press(find(view, "SwapWeapons"))
		await frames(3)
		step("the sword back", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longsword")
	await press(find(screen(), "CloseGearButton"))
	await frames(3)

	s.character["hp"] = 200
	s.character["max_hp"] = 200
	gs.start_combat([{"monster": "goblin", "count": 1}], {"room_from": "brod-square"})
	await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and not CombatRules.actor(s).is_empty(), 120.0)
	if not step("a fight", await hero_turn(120.0)):  # the follower's turn is the player's too (v0.8.4.43.11)
		return
	var ally := CombatRules.fighter(s, "npc_mercenary")
	var acts: Array = Sheet.template(data, ally)["actions"]
	step("the follower strikes with the sword it holds", acts.any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "longsword")
		and not acts.any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "shortsword"), str(acts.map(func(a: Dictionary) -> String: return str(a.get("name", "")))))
	var gob := CombatRules.fighter(s, TestUtils.foe(s, 1)) if not CombatRules.enemies(s).is_empty() else {}
	step("the goblin: a scimitar in hand, the bow put away", str(gob.get("equipped", {}).get("main_hand", "")) == "scimitar"
		and str(CharacterRules.stowed(gob).get("main_hand", "")) == "shortbow", str(gob.get("equipped", {})))
	await shot("fight")
