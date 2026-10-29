extends "res://tools/playtest/playtest_base.gd"
## Teachers by words (python tools/godot_playtest.py --scenario teachers), v0.7.39.7: nobody of the pack teaches
## Fireball, so the hero's own deed «find the teacher» — its act brings a mage at the mill with the course; the course
## waits in the study window under «Где учиться»; at the mage it is closed until the talk step, the 3rd circle and the
## mage's friendship, open after; enrolled by the button.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_wizard_yalika")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	var fx: EffectEngine = gs.effects
	c["gold_cp"] = 100000
	c["level"] = 4
	c["slots_max"] = [4, 3]
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-tavern-hall"

	step("nobody of the pack teaches Fireball", TeachRules.find(s, data, "spell", "fireball").is_empty())
	fx.searched_quests["t-q"] = true
	var r := fx.validate(s, data, "t-q", {"kind": "create_quest", "own": true, "title": "Учитель огня", "difficulty": "easy",
		"description": "Найти волшебника, что учит «Огненному шару».", "acts": [{"title": "Поиски чародея", "goal": "Найти чародея на мельнице"}]})
	if not step("the own deed to find the teacher", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		return
	fx.apply(s, "t-q", [r["effect_id"]])
	var qid := str(s.generated["quests"].keys()[-1])
	var act := {"kind": "quest_act", "quest_id": qid, "act": 1,
		"new_npcs": [{"key": "mage", "name": "Ведун Орест", "role": "волшебник", "monster": "mage", "room_id": "brod-mill"}],
		"steps": [{"text": "Найти Ореста на мельнице", "kind": "talk", "target": "new:mage"}],
		"teaches": {"npc": "new:mage", "kind": "spell", "id": "fireball", "name": "Огненный шар"}}
	var a := fx.validate(s, data, "t-a", act)
	if not step("the act brings the mage and its course", bool(a["accepted"]), str(a.get("summary", a.get("reason", "")))):
		return
	fx.apply(s, "t-a", [a["effect_id"]])
	var mage := ""
	for id: String in s.generated["npcs"]:
		if str(s.generated["npcs"][id]["name"]) == "Ведун Орест":
			mage = id
	var cid := StudyRules.of_teacher(s, data, mage)
	if not step("the mage's course exists", cid.size() == 1, str(cid)):
		return
	node("EventBus").state_changed.emit()
	await frames(3)
	var sb: Button = find(screen(), "StudyButton")
	if step("«Учёба» on the panel: a course waits elsewhere", sb != null):
		await press(sb)
		await frames(4)
		var win: Control = find(screen(), "StudyView")
		step("«Где учиться» with the mage's course", win != null and win.visible and find(win, "Course_" + cid[0]) != null)
		await shot("where_to_study")
		win.visible = false
		await frames(2)

	s.room_id = "brod-mill"
	node("EventBus").state_changed.emit()
	await frames(3)
	step("closed before the talk step, the 3rd circle and friendship", StudyRules.enroll_why(s, data, cid[0]) == "STUDY_REQUIREMENTS")
	var talk: Button = find(screen(), "QuestStep_" + qid)
	if step("the talk step at the mage", talk != null and not talk.disabled):
		await press(talk)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	step("the teacher found: the quest's flag", s.flags.has(qid + "_teach"))
	c["level"] = 5
	c["slots_max"] = [4, 3, 2]
	step("still closed without friendship", StudyRules.enroll_why(s, data, cid[0]) == "STUDY_REQUIREMENTS")
	s.attitudes[mage] = 1
	node("EventBus").state_changed.emit()
	await frames(3)
	var panel: Control = find(screen(), "StudyView")
	panel.call("open", mage)
	await frames(4)
	var enroll: Button = find(panel, "Enroll_" + cid[0])
	if step("open at the 5th level and friendship", enroll != null and not enroll.disabled, StudyRules.enroll_why(s, data, cid[0])):
		await shot("fireball_course_open")
		await press(enroll)
		await frames(3)
		step("enrolled on Fireball: 900 gp paid", StudyRules.enrolled(c, cid[0]) and int(c["gold_cp"]) == 100000 - 90000, str(c["gold_cp"]))
		await shot("fireball_enrolled")
