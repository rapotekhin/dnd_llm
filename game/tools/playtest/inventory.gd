extends "res://tools/playtest/playtest_base.gd"
## The character window as in BG3 (python tools/godot_playtest.py --scenario inventory, v0.8.4.43.6; the inventory of
## v0.8.4.32): not the whole screen — the hotbar stays under it; I opens «Снаряжение»: the doll and the grid of icons.
## The group filters as icons with their counts, a sort by weight and the order turned round, a search by name; a ring
## dragged onto the doll is worn and dragged back is taken off, a potion onto the belt, ore past the window's edge is
## dropped, Shift asks how many; a double click puts a sword in the hand, the right button lists a thing's acts; the
## sheet's three tabs, the book and a companion shown without closing the window.


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
	var sm := node("SaveManager")
	sm.inventory_view = {}
	for id: String in ["healing_potion", "spell_scroll_acid_arrow", "bread", "iron_ore", "thieves_tools", "ring_of_water_walking", "shortsword"]:
		ItemRules.add(s.character, id, 2 if id == "healing_potion" else 3 if id == "iron_ore" else 1)
	ItemRules.add(s.character, "silver_ring", 1)
	var game := screen()
	(game.get("input") as Control).release_focus()  # the chat input takes letters while it has the focus
	await frames(2)
	await key(KEY_I)
	var sheet: Control = find(game, "CharacterSheet")
	if not step("I opens the window on «Снаряжение»", sheet != null and sheet.visible and sheet.call("current_tab") == 0):
		return
	await frames(3)
	var panel: Control = find(sheet, "ModalPanel")
	var bar := game.get_tree().get_first_node_in_group("hotbar") as Control
	var view := game.get_viewport_rect()
	step("not the whole screen: the world at its sides, the hotbar under it", panel.size.x < view.size.x - 200 and bar != null and bar.is_visible_in_tree()
		and panel.get_global_rect().end.y <= bar.get_global_rect().position.y + 2, "%s / bar %s" % [panel.get_global_rect(), bar.get_global_rect() if bar != null else Rect2()])
	step("the doll, two weapon sets with the AC shield, the belt", find(sheet, "Slot_head") != null and find(sheet, "Slot_main_hand") != null
		and find(sheet, "Stowed_main_hand") != null and find(sheet, "AcShield") != null and find(sheet, "Belt_0") != null)
	var hit: Label = find(sheet, "SetHit")
	step("under the set: the attack bonus and the damage", hit != null and hit.text.begins_with("+") and (find(sheet, "SetDamage") as Label).text.contains("~"),
		"%s %s" % [hit.text if hit != null else "", (find(sheet, "SetDamage") as Label).text if find(sheet, "SetDamage") != null else ""])
	var on_belt := ""
	for i in 5:
		if str(find(sheet, "Belt_%d" % i).get("item")) == "healing_potion":
			on_belt = "Belt_%d" % i
	step("the potions on the belt by themselves, back onto the grid by a drag", not on_belt.is_empty() and await drag(find(sheet, on_belt), find(sheet, "InvGrid"))
		and not ItemRules.on_belt(s.character, data, s.items, "healing_potion") and find(sheet, "Item_healing_potion") != null, on_belt)
	var all: IconSlot = find(sheet, "InvGroup_all")
	var loose := Gear.loose(s.character, data, s.items)
	step("«Все» with the number of kinds, pressed", all != null and all.button_pressed and all.badge == str(loose.size()), "%s / %d" % [all.badge if all != null else "", loose.size()])
	step("an icon for weapons and potions", find(sheet, "InvGroup_weapon") != null and find(sheet, "InvGroup_potion") != null)
	step("no icon of an empty group", find(sheet, "InvGroup_quest") == null)
	var cell: IconSlot = find(sheet, "Item_healing_potion")
	step("a cell: the stack's number, the price in its card", cell != null and cell.badge == "2" and cell.text.contains("зм"), "%s | %s" % [cell.badge, cell.text] if cell != null else "")
	step("the worn armour is on the doll, not in the grid", find(sheet, "Item_" + str(s.character["equipped"].get("armor", "-"))) == null
		and str(find(sheet, "Slot_armor").get("item")) == str(s.character["equipped"].get("armor", "")))
	await shot("window_gear")

	await press(find(sheet, "InvGroup_weapon"))
	await frames(3)
	step("«Оружие» leaves only weapons", not _shown(sheet).is_empty() and _shown(sheet).all(func(id: String) -> bool: return ItemGroups.of(data, s.items, id) == "weapon"), ", ".join(_shown(sheet)))
	step("the group kept in the settings", str(sm.inventory_view.get("group", "")) == "weapon")
	await press(find(sheet, "InvGroup_all"))
	await frames(2)
	var sort: OptionButton = find(sheet, "InvSort")
	var at := -1
	for i in sort.item_count:
		if str(sort.get_item_metadata(i)) == "weight":
			at = i
	sort.select(at)
	sort.item_selected.emit(at)
	await frames(3)
	var rows := _shown(sheet).duplicate()
	var heavy := func(id: String) -> float: return ItemGroups.weight(data, s.items, id, int(s.character["inventory"][id]))
	step("by weight: the heaviest first", rows.size() > 1 and heavy.call(rows[0]) >= heavy.call(rows[rows.size() - 1]), "%s … %s" % [rows[0], rows[rows.size() - 1]] if rows.size() > 1 else "")
	await press(find(sheet, "InvReverse"))
	await frames(3)
	var back: Array = _shown(sheet)
	step("⇅ turns the order round: the lightest first", back.size() == rows.size() and heavy.call(back[0]) <= heavy.call(back[back.size() - 1]), str(back.slice(0, 3)) + " / " + str(rows.slice(-3)))
	var find_box: LineEdit = find(sheet, "InvSearch")
	find_box.text = "зелье"
	find_box.text_changed.emit("зелье")
	await frames(3)
	step("the search by name finds the potion", _shown(sheet) == ["healing_potion"], ", ".join(_shown(sheet)))
	find_box.text = "нет такого"
	find_box.text_changed.emit("нет такого")
	await frames(3)
	step("nothing found says so", find(sheet, "InvNone") != null)
	await shot("window_search")
	find_box.text = ""
	find_box.text_changed.emit("")
	sm.inventory_view = {}
	node("EventBus").state_changed.emit()
	await frames(3)

	# Drag and drop (as in BG3).
	step("a silver ring of treasure does not go onto a finger", not await drag(find(sheet, "Item_silver_ring"), find(sheet, "Slot_ring1")))
	step("the ring dragged onto the doll is worn", await drag(find(sheet, "Item_ring_of_water_walking"), find(sheet, "Slot_ring1"))
		and str(s.character["equipped"].get("ring1", "")) == "ring_of_water_walking")
	step("the ring is gone from the grid", find(sheet, "Item_ring_of_water_walking") == null)
	await shot("window_ring")
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var off_ok := await drag(find(sheet, "Slot_ring1"), find(sheet, "InvGrid"))
	step("the ring dragged back onto the grid comes off", off_ok and str(s.character["equipped"].get("ring1", "")).is_empty() and find(sheet, "Item_ring_of_water_walking") != null,
		"%s %s %s" % [off_ok, s.character["equipped"].get("ring1", "-"), Equip.off_why(s, data, Being.HERO, "ring1", false)])
	step("a sword does not go onto the head", not await drag(find(sheet, "Item_shortsword"), find(sheet, "Slot_head")))
	step("a potion dragged onto the belt", await drag(find(sheet, "Item_healing_potion"), find(sheet, "Belt_4")) and ItemRules.on_belt(s.character, data, s.items, "healing_potion"))
	step("Shift + a drag of a stack past the window's edge asks how many", await drag(find(sheet, "Item_iron_ore"), find(sheet, "DropAway"), true) and find(sheet, "QtyBox") != null)
	var spin: SpinBox = find(sheet, "QtySpin")
	if spin != null:
		spin.value = 1
		await press(find(sheet, "QtyOk"))
		await frames(3)
	step("one ore of three dropped", int(s.character["inventory"].get("iron_ore", 0)) == 2, str(s.character["inventory"].get("iron_ore", 0)))
	step("the stack dragged without Shift is dropped whole", await drag(find(sheet, "Item_iron_ore"), find(sheet, "DropAway"))
		and int(s.character["inventory"].get("iron_ore", 0)) == 0)
	var sword: Control = find(sheet, "Item_shortsword")
	var held := str(s.character["equipped"].get("main_hand", ""))
	sword.call("double")
	await frames(3)
	step("a double click puts the sword in the hand", str(s.character["equipped"].get("main_hand", "")) == "shortsword", held + " → " + str(s.character["equipped"].get("main_hand", "")))
	(find(sheet, "Item_bread").get("on_menu") as Callable).call(find(sheet, "Item_bread"))
	await frames(3)
	var menu: PopupMenu = sheet.get("_menu")
	step("the right button lists a thing's acts", menu != null and menu.visible and menu.item_count > 1, str(menu.item_count) if menu != null else "")
	await shot("window_menu")
	if menu != null:
		menu.hide()
	sheet.call("stage", "healing_potion")
	await frames(2)
	step("the acts staged by name for the menu", find(sheet, "Drop_healing_potion") != null and find(sheet, "DropAll_healing_potion") != null)

	# The sheet's tabs.
	await press(find(sheet, "SheetTab_skills"))
	await frames(3)
	var athletics: Control = find(sheet, "Skill_athletics")
	step("«Навыки»: ★ on a proficient skill", athletics != null and (athletics.find_child("Mark", true, false) as Label).text.contains("★"))
	await shot("window_skills")
	await press(find(sheet, "SheetTab_detail"))
	await frames(3)
	step("«Подробно»: the initiative and the saves", find(sheet, "Save_str") != null and find(sheet, "Initiative") != null)
	await shot("window_detail")
	await press(find(sheet, "SheetTab_summary"))
	await key(KEY_K)
	await frames(3)
	step("K opens the book in the same window", sheet.visible and sheet.call("current_tab") == 1 and (find(sheet, "BookPage") as Control).visible)
	await shot("window_book")
	await key(KEY_K)
	step("K again closes it", not sheet.visible)

	# A companion in the same window.
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	await key(KEY_I)
	await frames(3)
	var mate: BaseButton = find(sheet, "Party_npc_mercenary")
	if step("the companion's portrait in the window", mate != null):
		await press(mate)
		await frames(3)
		step("its doll and its things, the window still open", sheet.visible and sheet.get("who") == "npc_mercenary"
			and str(find(sheet, "Slot_main_hand").get("item")) == str(Gear.of(s, data, "npc_mercenary")["equipped"].get("main_hand", "")))
		await shot("window_companion")
		await press(find(sheet, "Party_" + Being.HERO))
		await frames(3)
		var bread: Control = find(sheet, "Item_bread")
		step("bread dragged onto its portrait is handed over", await drag(bread, find(sheet, "PartyDrop_npc_mercenary"))
			and int(Gear.of(s, data, "npc_mercenary")["inventory"].get("bread", 0)) == 1)
	await press(find(sheet, "CloseSheetButton"))


## The ids in the grid's cells now, in their order.
func _shown(sheet: Control) -> Array:
	return find(sheet, "InvGrid").get("shown")
