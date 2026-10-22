extends "res://tools/playtest/playtest_base.gd"
## Quests playtest (python tools/godot_playtest.py --scenario quests), v0.7.21: a quest the master makes from Bruno —
## its «Взять задание» button, the step at Mira, the way back to Bruno, the reward and the journal.


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
		"scale": "trifle", "description": "Бруно просит узнать у Миры, куда делись два бочонка.",
		"offer_text": "Спроси Миру про бочонки — она что-то темнит.",
		"steps": [{"text": "Расспросить Миру о бочонках", "kind": "talk", "target": "npc_serving"}]})
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
	var talk: Button = find(game, "QuestStep_" + qid)
	if step("the step at Mira", talk != null and not talk.disabled):
		await press(talk)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	var back: Button = find(game, "QuestStep_" + qid)
	var gold := int(s.character["gold_cp"])
	if step("the way back to Bruno", back != null and not back.disabled):
		await press(back)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the quest is done and paid by the table", s.quests_done.has(qid) and int(s.character["gold_cp"]) - gold == 500,
		"%s, +%d" % [s.quests_done, int(s.character["gold_cp"]) - gold])
	await shot("done")
	await press(find(game, "JournalButton"))
	await frames(5)
	await shot("journal")
