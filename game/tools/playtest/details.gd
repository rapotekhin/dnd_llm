extends "res://tools/playtest/playtest_base.gd"
## One description panel (python tools/godot_playtest.py --scenario details), v0.7.22.21: the sheet's spells by circle
## with their school's frame and the panel on the right over the chat; the right button pins a spell — hovering
## another does not change it — and the lock unpins it; the journal's people: names, then a person's card; the
## level-up spells by circle.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 20.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_wizard_yalika")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and gs.has_session() and not gs.is_busy(), 30.0)):
		return
	var game := screen()
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	await frames(3)
	var spells: Array = sheet.find_children("Spell_*", "Button", true, false)
	if not step("spells as rows of the sheet", spells.size() >= 2, str(spells.size())):
		return
	var panel: DetailsPanel = sheet.find_children("ItemDetails", "PanelContainer", true, false)[0]
	var a: Button = spells[0]
	var b: Button = spells[1]
	a.mouse_entered.emit()
	await frames(2)
	var title_a := panel.title()
	step("hover shows the spell in the panel", not title_a.is_empty() and panel.body().contains("·"), title_a)
	await shot("sheet_spells")
	_right_click(a)
	await frames(2)
	b.mouse_entered.emit()
	await frames(2)
	step("pinned: another hover does not change it", panel.title() == title_a and panel.pinned() == title_a, panel.title())
	step("the pinned row is lit, the lock shows", a.modulate != Color.WHITE and find(panel, "DetailsUnpin").visible)
	await shot("sheet_pinned")
	await press(find(panel, "DetailsUnpin"))
	b.mouse_entered.emit()
	await frames(2)
	step("unpinned by the lock: hover works again", panel.pinned().is_empty() and panel.title() != title_a, panel.title())
	tabs.current_tab = 2
	await frames(3)
	await shot("sheet_gear")
	await key(KEY_ESCAPE)

	await press(find(game, "JournalButton"))
	var journal: Control = find(game, "JournalView")
	await press(find(journal, "JournalTab_people"))
	await frames(3)
	var people: Array = journal.find_children("Person_*", "Button", true, false)
	if step("people as names", not people.is_empty()):
		var who: Button = people[0]
		await press(who)
		await frames(2)
		var card: DetailsPanel = journal.find_children("PersonCard", "PanelContainer", true, false)[0]
		step("a click opens the person's card", card.title() == who.text.strip_edges().trim_suffix("✝").strip_edges() or card.body().length() > 10, card.title())
		await shot("journal_people")
	await key(KEY_ESCAPE)

	gs.session.character["xp"] = LevelUp.xp_for(node("Catalog").data, 3)
	gs.session.character["level"] = 2
	CharacterRules.refresh(gs.session.character, node("Catalog").data, gs.session.items)
	node("EventBus").state_changed.emit()
	await frames(2)
	var lv: Button = find(game, "LevelUpButton")
	if step("level-up to 3", lv != null and not lv.disabled):
		await press(lv)
		await frames(3)
		await shot("level_up_circles")


func _right_click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c.gui_input.emit(ev)
