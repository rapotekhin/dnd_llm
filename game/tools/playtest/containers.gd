extends "res://tools/playtest/playtest_base.gd"
## Containers playtest (python tools/godot_playtest.py --scenario containers), v0.7.18.1: a locked chest in the hall —
## the side panel opens its window, the key opens it, a thing is taken out and another put in; the backpack from the
## sheet (v0.7.18.2) — a torch put in, the backpack left in the hall with it.


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
	var game := screen()
	# A chest the master would have furnished: locked, with a key the hero carries.
	var list: Array = s.props.get(s.room_id, [])
	list.append({"id": "pchest", "name": "Сундук под лестницей", "description": "Окованный сундук.", "item_id": "", "owner": "",
		"text": "", "state": "", "container": "chest", "contents": {"dagger": 2, "candle": 1}, "locked": true, "lock_dc": 10, "key": "lock"})
	s.props[s.room_id] = list
	s.character["inventory"]["lock"] = 1
	node("EventBus").state_changed.emit()
	await frames(3)
	var open: Button = find(game, "Container_pchest")
	if not step("the side panel offers the chest", open != null and not open.disabled):
		return
	await press(open)
	await frames(3)
	var view: Control = find(game, "ContainerView")
	step("the contents window opens locked", view != null and view.visible and find(view, "Unlock_key") != null)
	await shot("locked")
	await press(find(view, "Unlock_key"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the key opened it", not bool(PropRules.find(s, s.room_id, "pchest")["locked"]))
	var take: Button = find(view, "TakeOut_dagger")
	if step("a dagger to take", take != null):
		var before := int(s.character["inventory"].get("dagger", 0))
		await press(take)
		await frames(3)
		step("taken", int(s.character["inventory"].get("dagger", 0)) == before + 1, "%d → %d" % [before, int(s.character["inventory"].get("dagger", 0))])
	var put: Button = find(view, "PutIn_lock")
	if step("the key can be put in", put != null):
		await press(put)
		await frames(3)
		step("put in", int((PropRules.find(s, s.room_id, "pchest")["contents"] as Dictionary).get("lock", 0)) == 1)
	await shot("open")
	await press(find(view, "CloseContainerButton"))
	await frames(3)

	# v0.7.18.2: the backpack from the sheet.
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	await frames(3)
	var bags: Array = ContainerRules.bags_of(s.character, "backpack")
	if not step("the hero has a backpack bag", not bags.is_empty(), str(s.character.get("bags", {}))):
		return
	var bag := str(bags[0])
	var ob: Button = find(sheet, "OpenBag_" + bag)
	if step("the sheet offers to open it", ob != null):
		await press(ob)
		await frames(3)
		var put_torch: Button = find(view, "PutIn_torch")
		if step("a torch to put in", put_torch != null):
			await press(put_torch)
			await frames(3)
			step("the torch is in the backpack", int(ContainerRules.bags(s.character)[bag]["contents"].get("torch", 0)) == 1)
		await shot("backpack")
		var drop: Button = find(view, "DropBag")
		if step("the backpack can be left here", drop != null):
			await press(drop)
			await frames(3)
			var left := PropRules.room_props(s, s.room_id).filter(func(p: Dictionary) -> bool: return str(p.get("item_id", "")) == "backpack")
			step("the backpack lies in the hall with the torch", not left.is_empty() and int((left[0]["contents"] as Dictionary).get("torch", 0)) == 1)
