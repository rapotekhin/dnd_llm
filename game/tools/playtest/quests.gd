extends "res://tools/playtest/playtest_base.gd"
## Quests playtest (python tools/godot_playtest.py --scenario quests), v0.7.21: a quest the master makes from Bruno —
## its «Взять задание» button, the act the designer builds on taking (v0.7.39.6; the stub — a talk with the giver),
## its steps, the way back to Bruno, the reward and the journal; an order on the tavern's board taken at the board
## (v0.7.21.2) and the hero's own deed.


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
	var game := screen()
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60  # everyone at work
	var fx: EffectEngine = gs.effects
	fx.searched_quests["t-pq"] = true
	var r := fx.validate(s, data, "t-pq", {"kind": "create_quest", "giver": "npc_innkeeper", "title": "Должок служанки",
		"difficulty": "easy", "description": "Бруно просит узнать у Миры, куда делись два бочонка.",
		"offer_text": "Спроси Миру про бочонки — она что-то темнит.",
		"acts": [{"title": "Бочонки", "goal": "Выяснить, куда делись два бочонка"}]})
	if not step("the quest is accepted by the engine", bool(r["accepted"]), str(r)):
		return
	fx.apply(s, "t-pq", [r["effect_id"]])
	var qid := str(s.generated["quests"].keys()[0])
	node("EventBus").state_changed.emit()
	await frames(3)
	var take: Button = find(game, "QuestTake_" + qid)
	if not step("Bruno offers it: the take button", take != null and not take.disabled):
		return
	await shot("offered")
	await press(take)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the quest is taken", s.quests_active.has(qid))
	step("the designer built its act on taking", await wait_until(func() -> bool:
		return int(QuestRules.quest(data["world"], qid).get("built", 0)) == 1 and not gs.is_busy(), 60.0),
		str(QuestRules.quest(data["world"], qid).get("steps", [])))
	var gold := int(s.character["gold_cp"])
	for i in 6:  # the act's steps by their buttons; a fight the real designer adds is won by the engine's fact
		await frames(3)
		if s.quests_done.has(qid):
			break
		var cur := QuestRules.current(s, data["world"], qid)
		var w: Dictionary = cur.get("when", {})
		var facts: Array = [w] + (w.get("all", []) as Array) + (w.get("any", []) as Array)
		var fought := false
		for f: Dictionary in facts:  # a fight or a search the real designer adds: the engine's fact, as the fight or the search would
			if f.has("encounter"):
				s.encounters_done.append(str(f["encounter"]))
				fought = true
			if f.has("secret"):
				var room := str(f["secret"]).get_slice(":", 0)
				var found: Array = s.revealed.get(room, [])
				found.append(str(f["secret"]).get_slice(":", 1))
				s.revealed[room] = found
				fought = true
		if fought:
			QuestRules.advance(s, data)
			node("EventBus").state_changed.emit()
			continue
		var talk: Button = find(game, "QuestStep_" + qid)
		if talk == null or talk.disabled:
			break
		await press(talk)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the quest is done and paid by the table", s.quests_done.has(qid) and int(s.character["gold_cp"]) - gold == 500,
		"%s, +%d" % [s.quests_done, int(s.character["gold_cp"]) - gold])
	await shot("done")
	await press(find(game, "JournalButton"))
	await frames(5)
	await shot("journal")

	# an order on the board: the smith is not here, the board offers it (v0.7.21.2)
	var f := fx.validate(s, data, "t-pb", {"kind": "furnish", "props": [{"name": "Доска объявлений", "text": "Заказы Брода"}]})
	if f["accepted"]:
		fx.apply(s, "t-pb", [f["effect_id"]])
	var board := ""
	for p: Dictionary in PropRules.room_props(s, s.room_id):  # the real master may have furnished the hall before
		if str(p.get("name", "")) == "Доска объявлений":
			board = str(p["id"])
	node("EventBus").state_changed.emit()
	await frames(3)
	var bbtn: Button = find(game, "Board_" + board)  # the author, after v0.7.22.33: no «заказов 0» on a board never read
	step("a board never read says so", bbtn != null and bbtn.text.contains("не осмотрена"), bbtn.text if bbtn else "")
	QuestGen.mark_board_read(s, board)
	fx.searched_quests["t-pb2"] = true
	var o := fx.validate(s, data, "t-pb2", {"kind": "create_quest", "giver": "npc_smith", "board_prop_id": board,
		"title": "Уголь для кузни", "difficulty": "easy", "acts": [{"title": "Угольщик", "goal": "Найти угольщика и привезти уголь"}]})
	if not step("the board order is accepted", bool(o["accepted"]), str(o)):
		return
	fx.apply(s, "t-pb2", [o["effect_id"]])
	var order := str(QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, board])[0])
	node("EventBus").state_changed.emit()
	await frames(3)
	var take_order: Button = find(game, "QuestTake_" + order)
	if step("the board offers the smith's order", take_order != null and not take_order.disabled):
		await press(take_order)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the order is taken", s.quests_active.has(order))
	var fresh := int(QuestGen.board_state(s, s.room_id, board).get("fresh_day", 0))
	step("taking an order rolls the board's refresh in 1d4 days", fresh - s.day >= 1 and fresh - s.day <= 4, "day %d → %d" % [s.day, fresh])
	bbtn = find(game, "Board_" + board)
	step("a read board shows its orders", bbtn != null and bbtn.text.contains("заказ"), bbtn.text if bbtn else "")
	s.day = fresh
	node("EventBus").state_changed.emit()
	await frames(3)
	bbtn = find(game, "Board_" + board)
	step("the board is unread again", bbtn != null and bbtn.text.contains("не осмотрена"), bbtn.text if bbtn else "")
	if bbtn != null:
		await press(bbtn)
		await frames(4)
		var rb: Button = find(game, "BoardRead")
		step("its «Прочитать объявления» is active again", rb != null and not rb.disabled)
		await shot("board_fresh")
		(find(game, "CloseBoardButton") as Button).pressed.emit()
		await frames(2)
	# the hero's own deed: taken at once
	fx.searched_quests["t-po"] = true
	var d := fx.validate(s, data, "t-po", {"kind": "create_quest", "own": true, "title": "Кто травит колодцы", "difficulty": "medium",
		"acts": [{"title": "Колодцы", "goal": "Осмотреть колодцы и найти, кто их травит"}]})
	if step("the own deed is accepted", bool(d["accepted"]), str(d)):
		fx.apply(s, "t-po", [d["effect_id"]])
		var deed := str(s.generated["quests"].keys()[-1])
		step("the own deed is in work at once", s.quests_active.has(deed))
		node("EventBus").state_changed.emit()
		await press(find(game, "JournalButton"))
		await frames(5)
		await shot("journal_deeds")
