extends "res://tools/playtest/playtest_base.gd"
## «Последствия и время» (python tools/godot_playtest.py --scenario consequences), v0.7.14: the fighter attacks the
## mercenary Keira in the tavern before Bruno and Mira (the master's next_mode combat — here set by hand) and kills
## her: a murder with witnesses, the Brod knows, Bruno's trade is shut; the body is searched; an hour later a patrol
## holds the hero on the square — the exits are shut, the stocks settle it; the journal's «Хроника» keeps it all.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	s.character["temp_hp"] = 200

	# The attack the master would start (next_mode combat on a scene NPC): by the hero.
	s.pending_fight = [{"monster": "scout", "name": "Кейра", "npc_id": "npc_mercenary", "col": 0, "by_hero": true}]
	gs._start_pending_fight()
	if not step("a fight with Keira", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy() and not gs.combat_playing, 90.0)):
		return
	for id: String in CombatRules.enemies(s):
		var f := CombatRules.fighter(s, id)
		f["hp"] = 0
		f["status"] = "dead"
	if CombatRules.player_can_act(s):
		await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return not str(s.combat.get("outcome", "")).is_empty() and not gs.combat_playing and not gs.is_busy(), 60.0)
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	await frames(3)
	step("a murder before witnesses", _chat(s).contains("Убийство: Кейра — видели"), _chat(s))
	step("the Brod knows, the hero is wanted", s.wanted.has("brod") and s.attitude("npc_innkeeper") <= -3, "Бруно %d" % s.attitude("npc_innkeeper"))
	var trade: Button = find(screen(), "Trade_npc_innkeeper")
	step("Bruno does not trade", trade != null and trade.disabled and trade.tooltip_text == tr("SHOP_CLOSED_WANTED"), trade.tooltip_text if trade else "")
	var body: Button = find(screen(), "Body_npc_mercenary")
	step("the body is here", body != null, "")
	if body != null:
		await press(body)
		await frames(3)
	step("the body searched", _chat(s).contains("Обыскано тело Кейра"), _chat(s))
	await shot("murder")

	# An hour later a patrol finds the hero on the square.
	TimeRules.advance(s, data, 61)
	gs.go("brod-square")
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the patrol holds the hero", CrimeRules.held(s), _chat(s))
	var exit: Button = find(screen(), "Exit_brod-gate")
	step("the exits are shut", exit != null and exit.disabled, "")
	var stocks: Button = find(screen(), "Crime_stocks")
	step("the arrest buttons", stocks != null and find(screen(), "Crime_pay") != null and find(screen(), "Crime_resist") != null, "")
	step("the talk buttons (v0.7.22.2)", find(screen(), "Crime_persuade") != null and find(screen(), "Crime_deceive") != null
		and find(screen(), "Crime_intimidate") != null and find(screen(), "Crime_bribe") != null, "")
	await shot("arrest")
	# A bribe lets the hero go but keeps them wanted; no patrol at once. Then the hold again for the stocks.
	s.character["gold_cp"] = int(s.character["gold_cp"]) + CrimeRules.bribe(s, data, "brod")
	node("EventBus").state_changed.emit()
	await frames(3)
	var bribe: Button = find(screen(), "Crime_bribe")
	if bribe != null:
		await press(bribe)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	step("bribed — free but still wanted", not CrimeRules.held(s) and s.wanted.has("brod") and CrimeRules.check_arrest(s, data).is_empty(), _chat(s))
	s.let_go.erase("brod")
	CrimeRules.check_arrest(s, data)
	node("EventBus").state_changed.emit()
	await frames(3)
	stocks = find(screen(), "Crime_stocks")
	var day := s.day
	var days := CrimeRules.stocks_days(s, data, "brod")  # the sentence by severity (v0.7.22.10)
	if stocks != null:
		await press(stocks)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	step("the sentence — days later, free, in the lockup", s.day == day + days and s.room_id == "brod-lockup" and not s.wanted.has("brod")
		and not CrimeRules.held(s), _chat(s))
	await shot("stocks")

	# v0.7.14.4: the journal's «Хроника» keeps the murder with its day and place.
	var game := screen()
	await press(find(game, "JournalButton"))
	var tab: Button = find(game, "JournalTab_chronicle")
	if step("the chronicle tab", tab != null):
		await press(tab)
		await frames(3)
		var box: Node = find(game, "JournalTab_chronicle").get_parent().get_parent()  # the journal's column (rebuilt on a click)
		for b: Node in box.find_children("*", "Button", true, false):  # older days are folded: open the first
			if (b as Button).text.begins_with("▸ " + tr("JOURNAL_DAY").format({"day": 1})):
				await press(b as Button)
				await frames(3)
				break
		box = find(game, "JournalTab_chronicle").get_parent().get_parent()  # rebuilt after the click
		var text := " ".join(box.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text))
		step("the murder in the chronicle", text.contains("Убийство: Кейра"), "")
		await shot("chronicle")
	# v0.7.17: the places tab shows the name of Brod after the murder.
	var places: Button = find(game, "JournalTab_places")
	if step("the places tab", places != null):
		await press(places)
		await frames(3)
		var pbox: Node = find(game, "JournalTab_places").get_parent().get_parent()
		var ptext := " ".join(pbox.find_children("*", "Button", true, false).map(func(l: Node) -> String: return (l as Button).text))
		step("Brod's name is bad", ptext.contains("Ольховый Брод — дурная слава") or ptext.contains("Ольховый Брод — чужак с душком"), ptext.left(200))
	# v0.7.15: the people of Brod remember the murder — the journal's «Разговоры» shows it under each of them.
	var people: Button = find(game, "JournalTab_people")
	if step("the people tab", people != null):
		await press(people)
		await frames(3)
		var box: Node = find(game, "JournalTab_people").get_parent().get_parent()
		var text := " ".join(box.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text))
		step("the people remember the murder", text.contains("помнит: день 1 — знает: Кейра убита героем"), text.left(200))
		await shot("people")
	await key(KEY_ESCAPE)


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 6)):
		out.append(" · ".join(e.get("lines", [])) if e.has("lines") else str(e.get("text", "")))
	return " | ".join(out)
