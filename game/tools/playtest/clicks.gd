extends "res://tools/playtest/playtest_base.gd"
## Clicks and the map (python tools/godot_playtest.py --scenario clicks), v0.8.4.2: the seed of a new game, a private door
## shut with its menu, a knock, a trap's menu, the exit button walks, a quest at talking distance, what was offered goes
## with the place, the input grows, a wait of any minutes, the list of a worn slot.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	var seed_edit: LineEdit = find(screen(), "SeedEdit")
	step("the seed field says 42", seed_edit != null and seed_edit.text == "42", seed_edit.text if seed_edit else "")
	seed_edit.text = "Марка, 7!"
	seed_edit.text_changed.emit(seed_edit.text)
	await shot("seed")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	step("any text is a seed", s.game_seed == GameSession.seed_of("Марка, 7!") and s.game_seed != 42, str(s.game_seed))
	step("the seed is no setting of the master", not s.settings.has("seed"))
	var game := screen()

	var input: TextEdit = game.get("input")
	var low := input.size.y
	input.text = "Долго и подробно объясняю всё, что видел в дороге, ".repeat(8)
	await frames(4)
	step("the input grows upward with the text", input.size.y > low + 30.0, "%d → %d" % [low, input.size.y])
	await shot("input_grown")
	input.text = ""
	await frames(4)
	step("and comes back", is_equal_approx(input.size.y, low), str(input.size.y))

	s.room_id = "brod-tavern-hall"
	node("SaveManager").confirm_risky = false
	node("EventBus").state_changed.emit()
	await frames(3)
	var kitchen: Button = find(game, "Exit_brod-tavern-kitchen")
	step("the kitchen's door is shut to a stranger", kitchen != null and kitchen.text.contains("заперто"), kitchen.text if kitchen else "")
	await press(kitchen)
	await frames(4)
	var menu: Control = find(game, "ThingActs")  # v0.8.4.43.4: the one menu, read off these buttons
	step("the exit walks up to the door and opens its menu", s.room_id == "brod-tavern-hall" and acts_menu() != null and find(menu, "DoorWay_force") != null)
	step("a knock, for the owner is near", find(menu, "DoorWay_ask") != null)
	step("no fire or force left on the exits tab", find(find(game, "Bar"), "DoorWay_force") == null)
	await shot("door_menu")
	s.permits["brod-tavern"] = "npc_innkeeper"
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the owner's leave opens the door", WayRules.blocked(s, data, s.room_id, "brod-tavern-kitchen").is_empty())
	s.permits.clear()
	node("EventBus").state_changed.emit()
	await frames(3)
	screen().call("_close_menu")

	s.options.assign(["Спросить про эль"])
	var at := s.minute
	var out: Button = find(game, "Exit_brod-square")
	await press(out)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the exit button walks and goes through", s.room_id == "brod-square" and s.minute > at, s.room_id)
	step("what was offered stays there", s.options.is_empty() or not s.options.has("Спросить про эль"), str(s.options))

	var before := TimeRules.abs_minute(s)
	game.get("_side").wait_requested.emit()
	await frames(3)
	var dialog: Control = find(game, "WaitView")
	var spin: SpinBox = find(dialog, "WaitMinutes")
	step("a wait of any minutes", dialog.visible and spin != null)
	spin.value = 47
	await frames(2)
	step("the clock of the end", (find(dialog, "WaitUntil") as Label).text == tr("WAIT_UNTIL").format({"clock": TimeRules.clock_after(s, 47)}))
	await shot("wait")
	await press(find(dialog, "DialogConfirm"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("waited 47 minutes", TimeRules.abs_minute(s) - before == 47, str(TimeRules.abs_minute(s) - before))

	s.character["inventory"]["dagger"] = 1
	await _key_sheet(game)
	var pick: Button = find(game, "SlotPick_off_hand")
	if step("a slot opens its list", pick != null):
		await press(pick)
		await frames(3)
		var pop: PopupMenu = find(game, "SlotList_off_hand")
		step("the list has the dagger", pop.visible and pop.item_count >= 1 and pop.get_item_text(0).length() > 0, str(pop.item_count))
		await shot("slot_list")
		pop.hide()
	(find(game, "CharacterSheet") as Control).visible = false


func _key_sheet(game: Node) -> void:
	game.get("_sheet").call("open_tab", 2)
	await frames(4)
