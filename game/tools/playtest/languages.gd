extends "res://tools/playtest/playtest_base.gd"
## «Языки, предыстории, инструменты» playtest (python tools/godot_playtest.py --scenario languages), v0.7.11: the bard
## Yas (an entertainer) performs in the tavern hall for coins and a free room; the sheet shows languages and tools;
## Persuasion of an innkeeper who speaks only Giant fails by itself; a gnoll does not understand words — the parley
## by Persuasion is closed. With --real: the master answers in a strange speech.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_bard_yas")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	var game := screen()

	# The show.
	var perform: Button = find(game, "PerformButton")
	step("the perform button on the tavern stage", perform != null and not perform.disabled, perform.tooltip_text if perform != null else "")
	await shot("perform_button")
	var gold := int(c["gold_cp"])
	if perform != null and not perform.disabled:
		await press(perform)
		await wait_until(func() -> bool: return gs.is_busy(), 5.0)
		await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	step("the show was rolled", int(c.get("performed_day", 0)) == s.day, "gold %d → %d" % [gold, int(c["gold_cp"])])
	await frames(3)
	game = screen()
	perform = find(game, "PerformButton")
	step("once a day", perform != null and perform.disabled, perform.tooltip_text if perform != null else "")
	if int(c["gold_cp"]) > gold:
		step("an entertainer sleeps free tonight", int(ExplorationRules.rest_place(data["world"], "brod-tavern-upstairs", s, data)["cost_cp"]) == 0)
	await shot("after_show")

	# The sheet: languages and tools.
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	await frames(3)
	var text := _text_of(sheet)
	step("the sheet shows the languages", text.contains("Языки:") and text.contains("Общий"), "")
	step("the sheet shows the tools", text.contains("Инструменты:"), "")
	await shot("sheet_languages")
	await press(find(sheet, "CloseSheetButton"))

	# An innkeeper who speaks only Giant: Persuasion fails by itself.
	var keeper := ""
	for id: String in s.npcs_here(gs.world().world, s.room_id):
		keeper = id
		break
	if step("someone to talk to in the hall", not keeper.is_empty()):
		var npc: Dictionary = data["world"]["npcs"][keeper]
		var old_langs: Variant = npc.get("languages")
		npc["languages"] = ["giant"]
		var r: Dictionary = gs._engine_check({"skill": "persuasion", "dc_tier": "easy", "target_id": keeper})
		step("no common tongue — Persuasion fails", not bool(r.get("success", true)), str(r))
		await frames(3)
		await shot("no_language_check")
		if OS.get_environment("BTR_PLAYTEST_REAL") == "1":
			var before := s.chat.size()
			game = screen()
			game.get("input").text = "Подхожу к %s и вежливо прошу комнату подешевле" % str(npc.get("name", keeper))
			game.get("send_button").pressed.emit()
			await wait_until(func() -> bool: return gs.is_busy(), 5.0)
			await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
			var dm := ""
			for i in range(before, s.chat.size()):
				if str(s.chat[i]["kind"]) == GameSession.KIND_DM:
					dm += str(s.chat[i].get("text", ""))
			step("info: the master on a stranger's tongue", true, dm.left(400))
			await shot("real_strange_speech")
		if old_langs == null:
			npc.erase("languages")
		else:
			npc["languages"] = old_langs

	# A gnoll understands no words: the parley by Persuasion is closed, Intimidation stays.
	gs.start_combat([{"monster": "gnoll", "col": 2}])
	if not step("a fight with a gnoll", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await wait_until(func() -> bool: return CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty(), 60.0)
	await frames(3)
	var cs := screen()
	var persuade: Button = find(cs, "Parley_persuasion")
	var scare: Button = find(cs, "Parley_intimidation")
	step("Persuasion closed: no common tongue", persuade != null and persuade.disabled and persuade.tooltip_text.contains("не понимает"),
		persuade.tooltip_text if persuade != null else "")
	step("Intimidation stays", scare != null, scare.tooltip_text.left(120) if scare != null else "")
	await shot("parley_gnoll")


func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out
