extends "res://tools/playtest/playtest_base.gd"
## The master's quests by acts (python tools/godot_playtest.py --scenario quests_complex), v0.7.39.6: a hard quest from
## Bruno in two acts — the first with a talk and a guarded tower, the second with a gnoll's lair, its boss and the
## finale's choice that changes the place; the reward by the difficulty; a deadly order on the board asks «Точно?».
## The acts are applied as the designer's `quest_act` would be (the stub designer only builds a talk).


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
	fx.searched_quests["t-qc"] = true
	var r := fx.validate(s, data, "t-qc", {"kind": "create_quest", "giver": "npc_innkeeper", "title": "Пепельная стая",
		"difficulty": "hard", "description": "Гноллы с пепельными метками режут скот у Пущи.",
		"offer_text": "Кто-то ведёт этих тварей — найди вожака, я в долгу не останусь.",
		"acts": [{"title": "Следы", "goal": "Расспросить Миру и проверить башню у дороги"},
			{"title": "Логово Хорта", "goal": "Найти логово вожака и решить его судьбу"}],
		"villain": "Хорт, вожак гноллов", "finale": "Пощадить выводок или сжечь логово"})
	if not step("the skeleton is accepted", bool(r["accepted"]), str(r)):
		return
	fx.apply(s, "t-qc", [r["effect_id"]])
	var qid := str(s.generated["quests"].keys()[-1])
	node("EventBus").state_changed.emit()
	await frames(3)
	var take: Button = find(game, "QuestTake_" + qid)
	step("Bruno offers it with its difficulty", take != null and take.tooltip_text.contains("сложное"), take.tooltip_text if take else "")
	await shot("offered")
	QuestRules.accept(s, data, qid)  # taken without the stub designer: the acts below are the designer's
	var a1 := fx.validate(s, data, "t-a1", {"kind": "quest_act", "quest_id": qid, "act": 1,
		"encounters": [{"key": "watch", "room": "outpost-tower", "kind": "guard", "enemies": [{"monster": "wolf"}, {"monster": "bandit"}],
			"text": "волк и разбойник с пепельной меткой"}],
		"steps": [{"text": "Расспросить Миру о метках", "kind": "talk", "target": "npc_serving"},
			{"text": "Осмотреть штрек и башню", "kind": "all", "parts": [{"text": "штрек", "kind": "visit", "target": "mine-flooded"},
				{"text": "башня", "kind": "fight", "target": "watch"}]}]})
	if not step("act 1 is accepted", bool(a1["accepted"]), str(a1)):
		return
	fx.apply(s, "t-a1", [a1["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var mira: Button = find(game, "QuestStep_" + qid)
	if step("act 1: the step at Mira", mira != null and not mira.disabled):
		await press(mira)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("Mira told", QuestRules.step_text(s, data["world"], qid).contains("штрек"), QuestRules.step_text(s, data["world"], qid))
	s.room_id = "mine-flooded"
	s.visited.append("mine-flooded")
	QuestRules.advance(s, data)
	s.room_id = "outpost-tower"
	var enc: Dictionary = SceneRules.room(s, data["world"], "outpost-tower").get("encounter", {})
	step("the tower holds the quest's guard", str(enc.get("id", "")) == qid + "_watch", str(enc))
	s.encounters_done.append(qid + "_watch")
	QuestRules.advance(s, data)
	step("act 1 done: the quest waits for its act 2", QuestRules.awaiting(s, data["world"]).has(qid), QuestRules.step_text(s, data["world"], qid))
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	await shot("waits_for_act")
	var lair := {"room_id": "pushcha-edge", "edge": 0, "rooms": [{"key": "den", "name": "Логово Хорта", "description": "Нора под корнями, пахнет пеплом.",
		"encounter": {"enemies": [{"monster": "gnoll", "name": "Хорт"}], "boss": true}}]}
	var a2 := fx.validate(s, data, "t-a2", {"kind": "quest_act", "quest_id": qid, "act": 2, "new_places": [lair],
		"steps": [{"text": "Одолеть Хорта", "kind": "fight", "target": "new:den"},
			{"text": "Решить судьбу логова", "kind": "choice", "target": "new:den"}],
		"choices": [{"id": "spare", "action": "Пощадить щенков", "done_text": "Щенки уползли в чащу, логово опустело.",
				"attitude": {"npc_innkeeper": 1}, "changes": [{"room_id": "new:den", "description": "Пустая нора, кости и тишина."}]},
			{"id": "burn", "action": "Сжечь логово", "done_text": "Нора горит до утра.", "reward_item_id": "healers_kit"}]})
	if not step("act 2 is accepted", bool(a2["accepted"]), str(a2)):
		return
	fx.apply(s, "t-a2", [a2["effect_id"]])
	var den := str(s.generated["rooms"].keys()[-1])
	var boss: Dictionary = data["world"]["rooms"][den].get("encounter", {})
	step("the lair holds its boss", bool(boss.get("boss", false)), str(boss))
	s.room_id = den
	s.visited.append(den)
	s.encounters_done.append(str(boss.get("id", "")))
	QuestRules.advance(s, data)
	node("EventBus").state_changed.emit()
	await frames(3)
	var spare: Button = find(game, "QuestChoice_%s_spare" % qid)
	step("the finale's choice in the lair", spare != null and find(game, "QuestChoice_%s_burn" % qid) != null)
	await shot("choice")
	if spare != null:
		await press(spare)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the choice sets its flag", s.flags.has(qid + "_spare"), str(s.flags))
	step("the lair has changed", str(SceneRules.room(s, data["world"], den)["description"]) == "Пустая нора, кости и тишина.")
	await shot("lair_changed")
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var gold := int(s.character["gold_cp"])
	var back: Button = find(game, "QuestStep_" + qid)
	if step("the way back to Bruno", back != null and not back.disabled):
		await press(back)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var paid := int(s.character["gold_cp"]) - gold
	step("done and paid by the difficulty", s.quests_done.has(qid) and paid == 7500 - int(data["items"]["catalog"]["healers_kit"]["value_cp"]),
		"%s, +%d" % [s.quests_done, paid])
	await press(find(game, "JournalButton"))
	await frames(5)
	await shot("journal")
	key(KEY_ESCAPE)
	await frames(3)

	# a deadly order on the board asks first
	var f := fx.validate(s, data, "t-qb", {"kind": "furnish", "props": [{"name": "Доска объявлений", "text": "Заказы Брода"}]})
	if f["accepted"]:
		fx.apply(s, "t-qb", [f["effect_id"]])
	var board := str(PropRules.room_props(s, s.room_id)[0]["id"])
	QuestGen.mark_board_read(s, board)
	fx.searched_quests["t-qd"] = true
	var o := fx.validate(s, data, "t-qd", {"kind": "create_quest", "giver": "npc_smith", "board_prop_id": board,
		"title": "Пепельный курган", "difficulty": "deadly", "description": "В кургане за Пущей проснулось что-то древнее.",
		"acts": [{"title": "Слухи", "goal": "Узнать, что проснулось в кургане"}, {"title": "Дорога", "goal": "Пройти к кургану через топь"},
			{"title": "Курган", "goal": "Спуститься в курган и покончить с ним"}], "finale": "Запечатать курган или забрать его силу"})
	if not step("the deadly order is accepted", bool(o["accepted"]), str(o)):
		return
	fx.apply(s, "t-qd", [o["effect_id"]])
	var order := str(QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, board])[0])
	node("EventBus").state_changed.emit()
	await frames(3)
	var bbtn: Button = find(game, "Board_" + board)
	if not step("the board", bbtn != null):
		return
	await press(bbtn)
	await frames(4)
	await shot("board_deadly")
	var bt: Button = find(game, "BoardTake_" + order)
	if step("the board offers the deadly order", bt != null and not bt.disabled):
		node("SaveManager").confirm_risky = true  # the base turns «Точно?» off
		await press(bt)
		await frames(4)
		step("taking it asks «Точно?»", find(game, "ConfirmBox") != null or find(game.get_tree().root, "ConfirmBox") != null)
		await shot("deadly_confirm")
		var no: Button = find(game.get_tree().root, "ConfirmNo")
		if no != null:
			await press(no)
			await frames(3)
		step("not taken without the yes", not s.quests_active.has(order))
		var all: Button = find(game, "BoardTakeAll")
		if all != null:
			await press(all)
			await frames(4)
			step("«Взять все» asks too", find(game.get_tree().root, "ConfirmNo") != null)
			var no2: Button = find(game.get_tree().root, "ConfirmNo")
			if no2 != null:
				await press(no2)
				await frames(3)
			step("still not taken", not s.quests_active.has(order))
		node("SaveManager").confirm_risky = false
