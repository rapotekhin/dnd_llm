extends "res://tools/playtest/playtest_base.gd"
## The character window by the author's findings on 0.8.4.43.8 (python tools/godot_playtest.py --scenario character_window,
## v0.8.4.43.13, as in BG3): the sections in the middle of the head with the experience under them, the coins only on top,
## the window in the middle of the screen; a shield in the off hand — two hands in a set, a dagger put there takes its
## place; the notable features as a list; the book: the class's tab with the cantrips, the class actions, the strip of
## prepared spells and every spell by circle with its slots, a click lists «Колдовать» by circle and casts Cure Wounds, a
## spell taken off the hotbar comes back by a drag from the book; «Общие» with the fight's acts under their keys,
## «Реакции» with icons.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_druid_olha")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	var game := screen()
	(game.get("input") as Control).release_focus()  # the chat input takes letters while it has the focus
	await frames(2)
	if str(c["equipped"].get("off_hand", "")) != "shield":
		ItemRules.add(c, "shield", 1)
		gs.item_act({"act": "equip", "item": "shield", "slot": "off_hand"}, Being.HERO)
	await key(KEY_I)
	var sheet: Control = find(game, "CharacterSheet")
	if not step("I opens the window", sheet != null and sheet.visible):
		return
	await frames(4)

	# The head and the place of the window.
	var panel: Control = find(sheet, "ModalPanel")
	var pr := panel.get_global_rect()
	var sr := (find(sheet, "Sections") as Control).get_global_rect()
	var lr := (find(sheet, "LevelBox") as Control).get_global_rect()
	step("the sections in the middle of the head", absf(sr.get_center().x - pr.get_center().x) < 8.0, "%s in %s" % [sr, pr])
	step("the experience under them, in the middle too", lr.position.y >= sr.end.y - 1.0 and absf(lr.get_center().x - pr.get_center().x) < 8.0, str(lr))
	step("the coins only on top", find(sheet, "HeadCoins") != null and find(sheet, "GearCoins") == null and find(sheet, "CoinRow") == null)
	var bar := game.get_tree().get_first_node_in_group("hotbar") as Control
	var view := game.get_viewport_rect().size
	var above := bar.get_global_rect().position.y if bar != null and bar.is_visible_in_tree() else view.y
	step("the window in the middle of the screen", absf(pr.get_center().x - view.x / 2.0) < 6.0 and absf(pr.get_center().y - above / 2.0) < 30.0,
		"%s, the room %s × %d" % [pr, view.x, above])

	# A shield in the off hand: two hands in a set.
	var eq: Dictionary = c["equipped"]
	step("a shield in the off hand, no slot of its own", str(eq.get("off_hand", "")) == "shield" and not eq.has("shield") and find(sheet, "Slot_shield") == null
		and str(find(sheet, "Slot_off_hand").get("item")) == "shield", str(eq))
	step("two hands in a set", (find(sheet, "SetHeld") as Node).find_children("Slot_*", "", true, false).size() == 2)
	var ac := int(c["ac"])
	ItemRules.add(c, "dagger", 1)
	var err: String = gs.item_act({"act": "equip", "item": "dagger", "slot": "off_hand"}, Being.HERO)
	await frames(3)
	step("a dagger in the off hand takes the shield's place", err.is_empty() and str(c["equipped"]["off_hand"]) == "dagger" and int(c["ac"]) == ac - 2,
		"%s, AC %d → %d" % [err, ac, int(c["ac"])])
	gs.item_act({"act": "equip", "item": "shield", "slot": "off_hand"}, Being.HERO)
	await frames(3)
	step("the shield back, the AC back", str(c["equipped"]["off_hand"]) == "shield" and int(c["ac"]) == ac)
	step("the notable features as a list", find(sheet, "FeatureList") != null and (find(sheet, "FeatureList") as Node).get_child_count() >= 2)
	await shot("window_head")

	# The book: the class's tab.
	await key(KEY_K)
	await frames(4)
	sheet = find(game, "CharacterSheet")
	step("K opens the book on the class's tab", sheet.visible and str(sheet.get("section")) == "book" and (find(sheet, "BookTab_class") as Button).button_pressed)
	var cantrips: Node = find(sheet, "BookCantrips")
	step("the cantrips as icons", cantrips != null and cantrips.find_children("Spell_*", "", true, false).size() >= 2)
	var strip: Node = find(sheet, "PreparedStrip")
	var cure: IconSlot = find(strip, "Spell_cure_wounds") if strip != null else null
	step("the strip of prepared spells, dragged by «spell:<id>»", cure != null and cure.drag_key == "spell:cure_wounds")
	var pips: Label = find(sheet, "Slots_1")
	step("every spell of the 1st circle in its row, its slots as pips", find(sheet, "Circle_1") != null and pips != null and pips.text.contains("●"),
		pips.text if pips != null else "")
	await shot("book_class")

	# A click lists the circles and casts.
	c["hp"] = int(c["max_hp"]) - 5
	var hurt := int(c["hp"])
	var slots := SpellRules.slots_left(c, 1)
	await press(cure)
	await frames(3)
	var menu: PopupMenu = find(sheet, "CastList_cure_wounds")
	if step("a click lists «Колдовать» by circle", menu != null and menu.item_count >= 1 and menu.get_item_text(0).contains("1 круг"),
			menu.get_item_text(0) if menu != null and menu.item_count > 0 else ""):
		await shot("book_cast_menu")
		menu.id_pressed.emit(menu.get_item_id(0))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("cast from the book: a slot spent, the hero healed, the window closed", SpellRules.slots_left(c, 1) == slots - 1 and int(c["hp"]) > hurt and not sheet.visible,
			"slots %d → %d, HP %d → %d" % [slots, SpellRules.slots_left(c, 1), hurt, int(c["hp"])])

	# A spell taken off the hotbar comes back from the book.
	var pinned: IconSlot = find(bar, "Pin_spell_cure_wounds")
	if step("Cure Wounds on the hotbar", pinned != null and pinned.is_visible_in_tree()):
		pinned.dropped_off.emit(pinned.drag_key)
		await frames(4)
		step("dragged off the bar, it is gone", not _on_bar(bar, "Pin_spell_cure_wounds"))
		sheet.call("open_tab", 1)  # the chat input has the focus after the cast: K would be a letter
		await frames(4)
		var from_book: IconSlot = find(find(sheet, "PreparedStrip"), "Spell_cure_wounds")
		var free: HotSlot = null
		for n: Node in bar.find_children("*", "HotSlot", true, false):
			if free == null and n.get_child_count() == 0 and (n as Control).is_visible_in_tree():
				free = n
		if step("an empty place on the bar", free != null and from_book != null):
			free._drop_data(Vector2.ZERO, {"hotbar": from_book.drag_key})
			await frames(6)
			step("dragged from the book, it is on the bar again", _on_bar(bar, "Pin_spell_cure_wounds"))
	if not sheet.visible:
		sheet.call("open_tab", 1)
		await frames(3)

	# «Общие» and «Реакции».
	await press(find(sheet, "BookTab_common"))
	await frames(3)
	var dash: IconSlot = find(sheet, "BookAct_dash")
	step("«Общие»: the fight's acts under their buttons' keys", dash != null and dash.drag_key == "Do_dash" and find(sheet, "BookAct_dodge") != null)
	step("not what comes by the moment: «Встать», a door", find(sheet, "BookAct_stand") == null and find(sheet, "BookAct_field") == null)
	await shot("book_common")
	await press(find(sheet, "BookTab_react"))
	await frames(3)
	step("«Реакции»: an icon and its own choice", find(sheet, "Reaction_opportunity") is IconSlot and find(sheet, "React_opportunity_ask") != null)
	await shot("book_react")


## The cell is drawn on the hotbar now.
func _on_bar(bar: Control, cell_name: String) -> bool:
	var n: Control = find(bar, cell_name)
	return n != null and n.is_visible_in_tree()
