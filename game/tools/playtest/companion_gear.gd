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
	var give: Button = find(screen(), "GearGive_longsword")
	var had := int(s.character["inventory"].get("longsword", 0))
	if step("«Отдать» the longsword", give != null and not give.disabled):
		await press(give)
		await frames(3)
		step("the sword is its own now", int(Gear.of(s, data, "npc_mercenary")["inventory"].get("longsword", 0)) == 1 and int(s.character["inventory"].get("longsword", 0)) == had - 1)
	var on: Button = find(screen(), "GearOn_main_hand_longsword")
	if step("«В основную руку»", on != null and not on.disabled):
		await press(on)
		await frames(3)
		step("in its hand", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longsword")
	await shot("sword_in_hand")
	var swap: Button = find(screen(), "GearSwap")
	if step("«Сменить набор»", swap != null and not swap.disabled):
		await press(swap)
		await frames(3)
		step("the bow in its hands", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longbow")
		await press(find(screen(), "GearSwap"))
		await frames(3)
		step("the sword back", str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")) == "longsword")
	await press(find(screen(), "CloseGearButton"))
	await frames(3)

	s.character["hp"] = 200
	s.character["max_hp"] = 200
	gs.start_combat([{"monster": "goblin", "count": 1}], {"room_from": "brod-square"})
	if not step("a fight", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 120.0)):
		return
	var ally := CombatRules.fighter(s, "npc_mercenary")
	var acts: Array = Sheet.template(data, ally)["actions"]
	step("the follower strikes with the sword it holds", acts.any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "longsword")
		and not acts.any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "shortsword"), str(acts.map(func(a: Dictionary) -> String: return str(a.get("name", "")))))
	var gob := CombatRules.fighter(s, TestUtils.foe(s, 1)) if not CombatRules.enemies(s).is_empty() else {}
	step("the goblin: a scimitar in hand, the bow put away", str(gob.get("equipped", {}).get("main_hand", "")) == "scimitar"
		and str(CharacterRules.stowed(gob).get("main_hand", "")) == "shortbow", str(gob.get("equipped", {})))
	await shot("fight")
