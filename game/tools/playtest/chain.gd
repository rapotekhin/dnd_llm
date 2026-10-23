extends "res://tools/playtest/playtest_base.gd"
## The captain's chain playtest (python tools/godot_playtest.py --scenario chain; --real for the real master), v0.6.4:
## the fighter takes «Пепел над Маркой» at the gate, the outpost and the mine count in any order (their fights are
## marked fought — not a combat test), the report opens the burrow under the hollow, the finale is marked fought, the
## choice at the menhir is made by its button, the captain pays at the end. Fights: --scenario combat.

const QID := "ash_over_the_march"


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
	s.encounters_done.append_array(["trail_wolves", "hollow_spiders", "road_watch"])  # the way to the hollow is not the test
	if not await _walk(gs, ["brod-square", "brod-gate"]):
		return
	# playtest-2: the quest buttons vanished while talking to the giver — take it inside the conversation
	if not await _press(gs, "Talk_npc_captain", "talk to the captain"):
		return
	step("in conversation with the captain", s.in_conversation() and s.npc_id == "npc_captain")
	if not await _press(gs, "QuestTake_" + QID, "the captain offers the chain in the conversation"):
		return
	step("quest taken", s.quests_active.has(QID), QuestRules.step_text(s, node("Catalog").data["world"], QID))
	await shot("quest_taken_in_conversation")
	if not await _press(gs, "LeaveButton", "end the conversation"):
		return

	s.encounters_done.append("deep_ghoul")  # the mine first
	if not await _walk(gs, ["mine-entrance", "brod-gate"]):
		return
	step("one part counted, the step waits", int(s.quests_active.get(QID, -1)) == 0 and (s.quest_parts.get(QID, []) as Array).size() == 1,
		QuestRules.step_text(s, node("Catalog").data["world"], QID))
	s.encounters_done.append("crypt_commandant")
	if not await _walk(gs, ["outpost-road", "brod-gate"]):
		return
	step("both parts: report to the captain", int(s.quests_active.get(QID, -1)) == 1)
	await shot("report")
	if not await _press(gs, "QuestStep_" + QID, "report button"):
		return
	step("the burrow is known", s.flags.has("burrow_known"), "gold %d" % s.character["gold_cp"])

	if not await _walk(gs, ["pushcha-edge", "pushcha-trail", "pushcha-hollow"]):
		return
	step("the burrow exit is open", find(screen(), "Exit_pushcha-burrow") != null)
	await shot("hollow")
	s.encounters_done.append("burrow_priest")
	if not await _walk(gs, ["pushcha-burrow"]):
		return
	step("the finale step closed", int(s.quests_active.get(QID, -1)) == 3, QuestRules.step_text(s, node("Catalog").data["world"], QID))
	await shot("burrow")
	if not await _walk(gs, ["pushcha-hollow", "pushcha-trail", "pushcha-glade"]):
		return
	await shot("menhir")
	gs.session.revealed["pushcha-glade"] = ["runes"]  # the runes read (v0.7.22.13: the ending needs knowing)
	node("EventBus").state_changed.emit()
	await frames(3)
	if not await _press(gs, "QuestChoice_%s_restore" % QID, "the menhir choice"):
		return
	step("the menhir restored", s.flags.has("menhir_restored") and int(s.character["inventory"].get("potion_of_greater_healing", 0)) >= 2,
		"hermit %d" % s.attitude("npc_hermit"))
	await frames(3)  # v0.7.14.1: the glade by the flag — lit, and a free rest by the hermit's fire
	var rest: Button = find(screen(), "RestButton")
	step("the restored glade: lit and safe", str(SceneRules.room(s, node("Catalog").data["world"], s.room_id)["description"]).contains("залитая светом")
		and rest != null and not rest.disabled and ExplorationRules.can_rest(s, node("Catalog").data["world"], node("Catalog").data).is_empty(), "")
	await shot("glade_restored")
	if not await _walk(gs, ["pushcha-trail", "pushcha-edge", "brod-gate"]):
		return
	var gold: int = s.character["gold_cp"]
	if await _press(gs, "QuestStep_" + QID, "the final report"):
		step("the chain is done and paid", s.quests_done.has(QID) and int(s.character["gold_cp"]) > gold,
			"xp %d, level %d, gold %d → %d, day %d %s" % [s.character["xp"], s.character["level"], gold, s.character["gold_cp"], s.day, TimeRules.clock(s)])
		await shot("done")
	_report.append("----- chat -----")
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 30)):
		match str(e["kind"]):
			GameSession.KIND_DM:
				_report.append("МАСТЕР: " + str(e["text"]))
			GameSession.KIND_EFFECT:
				_report.append("ЭФФЕКТЫ: " + " · ".join(e["lines"]))


func _walk(gs: Node, rooms: Array) -> bool:
	for room: String in rooms:
		if gs.session.in_conversation():  # the master may open a talk on entering (next_mode social)
			var leave: Button = find(screen(), "LeaveButton")
			if leave != null:
				await press(leave)
				await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var exit: Button = find(screen(), "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			await shot("no_exit_" + room)
			return false
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	return true


func _press(gs: Node, button: String, what: String) -> bool:
	var b: Button = find(screen(), button)
	if not step(what, b != null and not b.disabled):
		await shot("no_" + button)
		return false
	await press(b)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	return true
