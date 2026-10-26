extends "res://tools/playtest/playtest_base.gd"
## Study (python tools/godot_playtest.py --scenario study), v0.7.30: the magister's exam, «Грамота и летописи» enrolled,
## a lesson, the student's dorm without a trespass, a medic's manual read on the square, the course finished day by day
## with its diploma.


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
	var c := s.character
	c["gold_cp"] = 5000
	c["skills"]["history"] = 12
	(c.get("skill_profs", []) as Array).erase("history")
	s.settings["needs"] = false
	s.rested_at = TimeRules.abs_minute(s) + 30 * 1440
	s.room_id = "brod-school-hall"
	s.minute = 10 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_teacher")
	var st: Button = find(screen(), "Study_npc_teacher")
	if not step("«Учёба» among the magister's acts", st != null and not st.disabled):
		await shot("no_study")
		return
	await press(st)
	await frames(4)
	var win: Control = find(screen(), "StudyView")
	await shot("teacher")
	await press(find(win, "ExamTake_brod_school"))
	await frames(4)
	step("the exam passed", StudyRules.admitted(c, "brod_school"), _last_effects(s))
	await press(find(win, "Enroll_letters"))
	await frames(4)
	step("enrolled on «Грамота и летописи»", StudyRules.enrolled(c, "letters"), _last_effects(s))
	await press(find(win, "Lesson_letters"))
	await frames(6)
	step("a lesson", int(StudyRules.view(c)["courses"].get("letters", {}).get("lesson_day", -1)) == s.day, _last_effects(s))
	await shot("after_lesson")
	win.visible = false

	s.room_id = "brod-school-dorm"
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the dorm is the student's", SiteRules.unwelcome(s, node("Catalog").data, s.room_id).is_empty())
	await shot("dorm")

	s.room_id = "brod-square"
	ItemRules.found(c, node("Catalog").data, s.items, "field_medic_manual", 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	var mine: Button = find(screen(), "StudyButton")
	if step("«Учёба» on the panel with a book", mine != null):
		await press(mine)
		await frames(4)
		await press(find(win, "Lesson_medic_book"))
		await frames(6)
		step("the manual read", StudyRules.enrolled(c, "medic_book"), _last_effects(s))
		await shot("book")
		win.visible = false

	s.room_id = "brod-school-hall"
	for i in 12:
		if StudyRules.done(c, "letters"):
			break
		TimeRules.advance(s, node("Catalog").data, 1440)
		s.minute = 10 * 60
		gs.study_act("lesson", "letters")
		await frames(2)
	step("the course finished with a diploma", StudyRules.done(c, "letters") and StudyRules.has_diploma(c, "letters"), _last_effects(s))
	await open_row("More_npc_teacher")
	await press(find(screen(), "Study_npc_teacher"))
	await frames(4)
	await shot("finished")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
