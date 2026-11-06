extends "res://tools/playtest/playtest_base.gd"
## The inventory as in BG3 and Pathfinder (python tools/godot_playtest.py --scenario inventory, v0.8.4.32): the gear tab
## shows the things by groups with headings, a group button narrows the list, a sort by weight, value or the newest, the
## order turned round, a search by name; every row has the stack's weight and price; the choice stays in the settings.


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
	var sm := node("SaveManager")
	sm.inventory_view = {}
	for id: String in ["healing_potion", "spell_scroll_acid_arrow", "bread", "iron_ore", "thieves_tools", "silver_ring"]:
		ItemRules.add(s.character, id, 2 if id == "healing_potion" else 1)
	var game := screen()
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	node("EventBus").state_changed.emit()
	await frames(3)

	var all: Button = find(sheet, "InvGroup_all")
	step("«Все» with the number of kinds, pressed", all != null and all.button_pressed and all.text.contains(str((s.character["inventory"] as Dictionary).size())), all.text if all != null else "")
	step("a button for weapons, potions and scrolls", find(sheet, "InvGroup_weapon") != null and find(sheet, "InvGroup_potion") != null and find(sheet, "InvGroup_scroll") != null)
	step("no button of an empty group", find(sheet, "InvGroup_quest") == null)
	step("headings by group", find(sheet, "InvHead_weapon") != null and find(sheet, "InvHead_potion") != null)
	var info: Label = find(sheet, "Info_healing_potion")
	step("a row says the stack's price", info != null and info.text.contains("зм"), info.text if info != null else "")
	await _shot_bar(sheet, "inventory_all")

	await press(find(sheet, "InvGroup_weapon"))
	await frames(3)
	var rows := _items(sheet)
	step("«Оружие» leaves only weapons", not rows.is_empty() and rows.all(func(id: String) -> bool: return ItemGroups.of(node("Catalog").data, s.items, id) == "weapon"), ", ".join(rows))
	step("the group kept in the settings", str(sm.inventory_view.get("group", "")) == "weapon")
	await _shot_bar(sheet, "inventory_weapons")

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
	rows = _items(sheet)
	var data: Dictionary = node("Catalog").data
	var heavy := func(id: String) -> float: return ItemGroups.weight(data, s.items, id, int(s.character["inventory"][id]))
	step("by weight: the heaviest first", rows.size() > 1 and heavy.call(rows[0]) >= heavy.call(rows[rows.size() - 1]), "%s … %s" % [rows[0], rows[rows.size() - 1]] if rows.size() > 1 else "")
	step("no headings out of the sort by type", find(sheet, "InvHead_weapon") == null)
	await press(find(sheet, "InvReverse"))
	await frames(3)
	var back := _items(sheet)
	step("⇅ turns the order round", back.size() == rows.size() and back[0] == rows[rows.size() - 1], str(back.slice(0, 3)) + " / " + str(rows.slice(-3)))
	await _shot_bar(sheet, "inventory_by_weight")

	var find_box: LineEdit = find(sheet, "InvSearch")
	find_box.text = "зелье"
	find_box.text_changed.emit("зелье")
	await frames(3)
	rows = _items(sheet)
	step("the search by name finds the potion", rows == ["healing_potion"], ", ".join(rows))
	find_box.text = "нет такого"
	find_box.text_changed.emit("нет такого")
	await frames(3)
	step("nothing found says so", find(sheet, "InvNone") != null)
	await _shot_bar(sheet, "inventory_search")
	find_box.text = ""
	find_box.text_changed.emit("")
	sm.inventory_view = {}
	sm.save_settings()
	await press(find(sheet, "CloseSheetButton"))


## The gear tab scrolled down to the bar of groups, then a screenshot.
func _shot_bar(sheet: Control, name: String) -> void:
	var list: ScrollContainer = find(sheet, "GearList")
	await frames(2)
	list.scroll_vertical = int((find(sheet, "InvFilters") as Control).get_parent().position.y)
	await frames(2)
	await shot(name)


## The ids of the item rows shown, top to bottom.
func _items(sheet: Control) -> Array[String]:
	var out: Array[String] = []
	var rows: Control = find(sheet, "GearRows")
	for row in rows.get_children():
		for ch in row.get_children():
			if ch.name.begins_with("Item_") and not ch.is_queued_for_deletion():
				out.append(str(ch.name).trim_prefix("Item_"))
	return out
