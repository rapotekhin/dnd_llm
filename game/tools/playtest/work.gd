extends "res://tools/playtest/playtest_base.gd"
## Work (python tools/godot_playtest.py --scenario work), v0.7.26: «Работа» under Bruno's acts, the window of his
## jobs, the interview, a shift from the window, a shift from the panel with its event narrated by the master, a
## promotion; the smith's job asks for the tools.


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
	var c := s.character
	c["skills"]["persuasion"] = 30
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_innkeeper")
	var jobs: Button = find(screen(), "Jobs_npc_innkeeper")
	if not step("«Работа» among Bruno's acts", jobs != null and not jobs.disabled):
		await shot("no_jobs")
		return
	await press(jobs)
	await frames(4)
	var win: Control = find(screen(), "JobView")
	step("the window of Bruno's jobs", win != null and win.visible and find(win, "Job_serve_tables") != null)
	await shot("jobs_window")

	await press(find(win, "JobHire_serve_tables"))
	await frames(4)
	step("hired after the interview", JobRules.hired(c, "serve_tables"), _last_effects(s))
	await shot("hired")

	var gold := int(c["gold_cp"])
	await press(find(win, "JobShift_serve_tables"))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(4)
	step("a shift paid", int(c["gold_cp"]) > gold, _last_effects(s))
	await shot("shift_done")
	win.visible = false
	await frames(2)

	var chance: float = float(data["rules"]["jobs"]["event_chance"])
	data["rules"]["jobs"]["event_chance"] = 1.0
	JobRules.state(c)["serve_tables"]["good"] = JobRules.promote_after(s, data) - 1
	var turns := s.chat.size()
	var panel_btn: Button = find(screen(), "WorkShift_serve_tables")
	if step("«Смена» on the panel while Bruno is here", panel_btn != null and not panel_btn.disabled, panel_btn.tooltip_text if panel_btn != null else ""):
		await shot("panel_shift")
		await press(panel_btn)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		step("the shift's event narrated by the master", s.chat.size() > turns + 1 and str(s.chat[s.chat.size() - 1].get("kind", "")) != GameSession.KIND_EFFECT)
		step("a promotion after good shifts", JobRules.rank(c, "serve_tables") >= 1 or _last_effects(s).contains("плохая"), _last_effects(s))
	data["rules"]["jobs"]["event_chance"] = chance
	await shot("promoted")

	s.room_id = "brod-smithy"
	s.minute = 12 * 60  # the smith is home at night
	c["tools"] = []
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_smith")
	var sj: Button = find(screen(), "Jobs_npc_smith")
	if step("the smith's jobs", sj != null):
		await press(sj)
		await frames(4)
		var hire: Button = find(win, "JobHire_smith_apprentice")
		step("the apprentice asks for the smith's tools", hire != null and hire.disabled, hire.tooltip_text if hire != null else "")
		await shot("smith_requires")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
