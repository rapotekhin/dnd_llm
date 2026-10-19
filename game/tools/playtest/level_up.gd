extends "res://tools/playtest/playtest_base.gd"
## Level-up of a caster by hand (python tools/godot_playtest.py --scenario level_up): the ready-made wizard,
## experience set by the scenario (in the game it comes only from quests and combat), the level-up screen to
## level 2 (subclass, two spellbook spells, one more prepared) and level 3 (2nd-circle spells), each pick by a
## click on its checkbox. Needs llm_server (stub turn is enough) for the enter turn.


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
	for target: int in [2, 3]:
		gs.session.character["xp"] = LevelUp.xp_for(node("Catalog").data, target)
		node("EventBus").state_changed.emit()
		await frames(2)
		var lv: Button = find(game, "LevelUpButton")
		if not step("level-up button for %d" % target, lv != null and not lv.disabled):
			return
		await press(lv)
		var view: Control = find(game, "LevelUpView")
		await shot("level_%d_open" % target)
		var p := LevelUp.plan(gs.session.character, node("Catalog").data, {})
		if bool(p["subclass"]):
			await _click(view, "Pick_subclass_" + str(p["subclasses"][0]))
		for i in int(p["spells"]):
			await _click(view, "Pick_spell_" + str(p["spell_list"][i]))
		p = LevelUp.plan(gs.session.character, node("Catalog").data, view.get("picks"))
		for i in mini(int(p["prepared"]), (p["prepared_list"] as Array).size()):
			await _click(view, "Pick_prep_" + str(p["prepared_list"][i]))
		await shot("level_%d_picked" % target)
		var confirm: Button = find(view, "LevelUpConfirm")
		step("picks complete for %d" % target, not confirm.disabled, (find(view, "LevelUpConfirm").get_parent().get_parent().get_child(1) as Label).text)
		await press(confirm)
		var c: Dictionary = gs.session.character
		step("level %d" % target, int(c["level"]) == target and not view.visible,
			"HP %d, known %d, prepared %d, subclass %s" % [c["max_hp"], c["spells"]["known"].size(), c["spells"]["prepared"].size(), c["subclass"]])
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	await shot("sheet_after")
	var scroll: ScrollContainer = tabs.get_child(1)
	scroll.scroll_vertical = 100000
	await frames(3)
	await shot("sheet_spells")
	step("cast buttons on the sheet", find(sheet, "Cast_" + str(gs.session.character["spells"]["prepared"][0])) != null)


func _click(view: Control, node_name: String) -> void:
	var cb: CheckBox = find(view, node_name)
	if not step("pick " + node_name, cb != null):
		return
	cb.button_pressed = true
	await frames(3)
