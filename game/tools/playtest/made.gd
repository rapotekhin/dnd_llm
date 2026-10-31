extends "res://tools/playtest/playtest_base.gd"
## What the master builds of parts (python tools/godot_playtest.py --scenario made), v0.7.63: a status laid in one turn and
## shown on the panel, a skill taught by Bruno's course and standing on the sheet, a trait read from a book, and what the
## parts do not cover refused.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	var fx: EffectEngine = gs.effects
	c["gold_cp"] = 50000
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)

	var bad := fx.validate(s, data, "m-0", {"kind": "make", "what": "status", "key": "wings", "name": "Крылья", "text": "Герой летает.",
		"parts": [{"part": "fly"}]})
	step("what the parts do not cover is refused", not bool(bad["accepted"]) and str(bad.get("reason", "")).contains("части fly нет"), str(bad.get("reason", "")))

	var boon := fx.validate(s, data, "m-1", {"kind": "make", "what": "status", "key": "spring", "name": "Милость родника", "text": "Вода придаёт сил рукам.",
		"parts": [{"part": "skill_bonus", "value": "athletics", "amount": 2}]})
	var laid := fx.validate(s, data, "m-1", {"kind": "condition", "condition": "new:spring", "reason": "напился из родника"})
	if not step("a status built and laid in one turn", bool(boon["accepted"]) and bool(laid["accepted"]), str(laid.get("summary", laid.get("reason", "")))):
		return
	fx.apply(s, "m-1", [boon["effect_id"], laid["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var chips := ConditionRules.shown(s, data).map(func(e: Dictionary) -> String: return str(e["name"]))
	step("the status on the panel with its name", chips.has("Милость родника"), str(chips))
	step("its number in the skill's roll", RollParts.skill(s, data, "athletics").any(func(p: Dictionary) -> bool: return int(p["value"]) == 2))
	await shot("status")

	var skill := fx.validate(s, data, "m-2", {"kind": "make", "what": "skill", "key": "foam", "name": "Чтение пены", "text": "Угадывать погоду по пиву.", "ability": "wis"})
	var course := fx.validate(s, data, "m-2", {"kind": "course", "npc_id": "npc_innkeeper", "name": "Чтение пены", "teach_kind": "skill",
		"teach_id": "new:foam", "lessons": 4, "fee_cp": 400})
	if not step("a skill and its course in one turn", bool(skill["accepted"]) and bool(course["accepted"]), str(course.get("summary", course.get("reason", "")))):
		return
	fx.apply(s, "m-2", [skill["effect_id"], course["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var id := str(s.generated["made"].keys().filter(func(k: String) -> bool: return str(s.generated["made"][k]["what"]) == "skill")[0])
	step("nobody gets it for free", not (c.get("skill_profs", []) as Array).has(id))
	await open_row("More_npc_innkeeper")
	await press(find(screen(), "Study_npc_innkeeper"))
	await frames(4)
	var win: Control = find(screen(), "StudyView")
	var course_id := str(StudyRules.of_teacher(s, data, "npc_innkeeper")[0])
	await press(find(win, "Enroll_" + course_id))
	await frames(4)
	step("enrolled at Bruno", StudyRules.enrolled(c, course_id))
	await shot("course")
	win.visible = false
	for i in 40:
		if StudyRules.done(c, course_id):
			break
		s.rested_at = TimeRules.abs_minute(s) + 1440
		TimeRules.advance(s, data, 1440)
		s.minute = 12 * 60
		s.room_id = "brod-tavern-hall"
		gs.study_act("lesson", course_id)
		await frames(2)
	step("the course finished: the skill learned", (c.get("skill_profs", []) as Array).has(id), _last_effects(s))

	var made_trait := fx.validate(s, data, "m-3", {"kind": "make", "what": "trait", "key": "stride", "name": "Волчий шаг", "text": "Ноги несут быстрее.",
		"parts": [{"part": "speed", "amount": 10}], "book": "Записки ходока"})
	var book := fx.validate(s, data, "m-3", {"kind": "give_item", "item_id": "new:book:stride", "qty": 1, "reason": "наследство ходока"})
	if not step("a trait and its book in one turn", bool(made_trait["accepted"]) and bool(book["accepted"]), str(book.get("summary", book.get("reason", "")))):
		return
	var speed := CharacterRules.speed(c, data)
	fx.apply(s, "m-3", [made_trait["effect_id"], book["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var books := StudyRules.books(s, data)
	if not step("the book opens a course of its own", books.size() == 1):
		return
	for i in 40:
		if StudyRules.done(c, books[0]):
			break
		s.rested_at = TimeRules.abs_minute(s) + 1440
		TimeRules.advance(s, data, 1440)
		s.minute = 12 * 60
		gs.study_act("lesson", books[0])
		await frames(2)
	step("the trait read: a status with no end", CharacterRules.speed(c, data) == speed + 10, _last_effects(s))
	await press(find(screen(), "SheetButton"))
	await frames(4)
	await shot("sheet")
	step("the skill stands on the sheet", (c["skills"] as Dictionary).has(id))


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
