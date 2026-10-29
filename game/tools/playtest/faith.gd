extends "res://tools/playtest/playtest_base.gd"
## Faith (python tools/godot_playtest.py --scenario faith), v0.7.49: Branko the cleric of Chauntea at the temple of
## Brod — «Святилище» on the panel, the window with the god and the favor; a service and two donations, the blessing
## once favor is enough; the vow «Слово правды» and its +2 on the sheet; a Deception check breaks it, the atonement
## brings it back; the sheet's Development tab shows the faith.

const GOD := "chauntea"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.settings["needs"] = false
	s.settings["weather"] = false
	s.minute = 10 * 60
	s.character["gold_cp"] = 20000
	step("Branko follows Chauntea", FaithRules.hero_god(s.character) == GOD, FaithRules.hero_god(s.character))
	if s.room_id != "brod-square":
		await _go(gs, "brod-square")
	await _go(gs, "brod-temple")

	var fb: Button = find(screen(), "FaithButton")
	if not step("«Святилище» on the panel", fb != null and fb.text.contains("Чонтия"), fb.text if fb != null else ""):
		return
	await press(fb)
	await frames(4)
	var view: Control = find(screen(), "FaithView")
	step("the shrine window", view != null and view.visible)
	var bless: Button = find(view, "FaithBless")
	step("no blessing yet: low favor", bless != null and bless.disabled and bless.tooltip_text.contains("благосклонность"), bless.tooltip_text if bless != null else "")
	await shot("faith_window")
	await press(find(view, "FaithService"))
	await frames(3)
	for i in 2:
		await press(find(view, "FaithDonate"))
		await frames(3)
	step("favor by the service and donations", FaithRules.favor(s.character, GOD) == 20, str(FaithRules.favor(s.character, GOD)))
	FaithRules.add_favor(s.character, data, GOD, 10)  # a week of donations, shortened
	view.call("_rebuild")
	await frames(3)
	bless = find(view, "FaithBless")
	step("the blessing open at «верный»", bless != null and not bless.disabled, bless.tooltip_text if bless != null else "")
	await press(bless)
	await frames(3)
	step("blessed until the long rest", ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool:
		return str(e["source"]["id"]) == FaithRules.BLESS_ID and str(e["ends"].get("rest", "")) == "long"))

	var persuasion := int(s.character["skills"]["persuasion"])
	await press(find(view, "FaithVow_truth"))
	await frames(3)
	var kept: Label = find(view, "FaithVowState_truth")
	step("the vow taken", kept != null and kept.text == "держите", kept.text if kept != null else "")
	step("+2 Persuasion by the vow", int(s.character["skills"]["persuasion"]) == persuasion + 2, str(s.character["skills"]["persuasion"]))
	await shot("faith_vow")
	view.visible = false
	await frames(2)

	gs.call("_hero_roll", {"skill": "deception", "dc_tier": "easy"}, int(s.character["skills"]["deception"]))  # a lie to the guard
	gs.call("_quiet_lines", ["Вы уверяете стражника, что просто проходили мимо"] as Array[String])
	var chat := " ".join(s.chat.map(func(e: Dictionary) -> String: return " ".join(e.get("lines", []))))
	step("a Deception check breaks the vow", chat.contains("Слово правды") and chat.contains("нарушен"), chat.right(300))
	step("the gift gone", int(s.character["skills"]["persuasion"]) == persuasion, str(s.character["skills"]["persuasion"]))
	await shot("faith_broken")

	await press(find(screen(), "FaithButton"))
	await frames(3)
	var atone: Button = find(view, "FaithAtone")
	step("the atonement offered", atone != null and not atone.disabled, atone.tooltip_text if atone != null else "")
	await press(atone)
	await frames(3)
	step("the vow back after the atonement", int(s.character["skills"]["persuasion"]) == persuasion + 2 and FaithRules.broken(s.character, data).is_empty())
	await press(find(view, "CloseFaithButton"))
	await frames(2)

	var game := screen()
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	sheet.call("open_tab", 3)
	await frames(4)
	var god_line: Label = find(sheet, "FaithSheetGod")
	step("the faith on the sheet", god_line != null and god_line.text.contains("Чонтия"), god_line.text if god_line != null else "")
	await shot("faith_sheet")
	await press(find(sheet, "CloseSheetButton"))


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("walked to %s" % to, gs.go(to))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
