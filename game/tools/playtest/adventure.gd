extends "res://tools/playtest/playtest_base.gd"
## Adventure systems playtest (python tools/godot_playtest.py --scenario adventure; --real for the real master),
## v0.6.3: the rogue walks to the mine (time passes on the panel), takes Drogin's quest at his button, finds the
## deadfall in the main gallery and disarms it by the button, enters the flooded drift where the cache gives the
## amulet (the quest step closes by itself), hands it over at Drogin's step button; then night falls in the town
## and the trader's button is closed. The kobolds of the gallery are marked fought — this is not a combat test.

const PATH: Array[String] = ["brod-square", "brod-gate", "mine-entrance"]


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_rogue_damir")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var start_minute := s.minute
	for room: String in PATH:
		if not await _go(gs, room):
			return
	step("time passed on the way", s.minute > start_minute, "%s → %s (%s)" % [start_minute, s.minute, TimeRules.part_name(s, node("Catalog").data)])
	var take: Button = find(screen(), "QuestTake_drogin_amulet")
	if not step("Drogin offers the quest", take != null and not take.disabled):
		await shot("no_offer")
		return
	await press(take)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("quest taken", s.quests_active.has("drogin_amulet"), str(s.quests_active))
	await shot("quest_taken")

	s.encounters_done.append("gallery_kobolds")  # not a combat test
	s.revealed["mine-gallery"] = ["deadfall"]  # as if the rogue's passive Perception noticed it
	if not await _go(gs, "mine-gallery"):
		return
	var disarm: Button = find(screen(), "Disarm_mine-deep")
	var around: Button = find(screen(), "Exit_mine-deep")
	step("the found trap: disarm and go-around buttons", disarm != null and around != null and around.text.contains("в обход"),
		around.text if around != null else "")
	await shot("trap_found")
	if disarm != null and not disarm.disabled:
		s.character["inventory"]["thieves_tools"] = 1
		await press(disarm)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("info: the trap", true, str(s.traps) + " HP %d/%d" % [s.character["hp"], s.character["max_hp"]])
		step("the trap is spent", s.traps.has("mine-gallery:deadfall"))
		await shot("trap_done")

	s.revealed["mine-flooded"] = ["amulet"]  # as if a search found it; the cache gives the item on entering
	if not await _go(gs, "mine-flooded"):
		return
	step("the cache gave the amulet", int(s.character["inventory"].get("amulet", 0)) == 1)
	step("the quest step closed by the fact", int(s.quests_active.get("drogin_amulet", -1)) == 1, str(s.quests_active))
	for room: String in ["mine-gallery", "mine-entrance"]:
		if not await _go(gs, room):
			return
	var give: Button = find(screen(), "QuestStep_drogin_amulet")
	if step("Drogin's step button", give != null and not give.disabled):
		var gold: int = s.character["gold_cp"]
		await press(give)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("quest done with the reward", s.quests_done.has("drogin_amulet") and int(s.character["gold_cp"]) > gold,
			"gold %d → %d, attitude %d" % [gold, s.character["gold_cp"], s.attitude("npc_prospector")])
		await shot("quest_done")

	for room: String in ["brod-gate", "brod-square"]:
		if not await _go(gs, room):
			return
	s.minute = 23 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var trade: Button = find(screen(), "Trade_npc_merchant")
	step("at night the trader is closed", trade != null and trade.disabled, trade.tooltip_text if trade != null else "")
	await shot("night")
	_report.append("----- chat -----")
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 24)):
		match str(e["kind"]):
			GameSession.KIND_DM:
				_report.append("МАСТЕР: " + str(e["text"]))
			GameSession.KIND_EFFECT:
				_report.append("ЭФФЕКТЫ: " + " · ".join(e["lines"]))


func _go(gs: Node, room: String) -> bool:
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
