class_name StudyRules
extends RefCounted
## Study (roadmap v0.7.30, rules.study): a course is data — what it teaches (a skill, a tool, a language, a spell, a
## recipe or only experience), lessons, the check of a lesson, the fee. Taught by a teacher while it is here (once a
## day) or read from a carried book. A school's course needs its entrance exam (a stipend for a brilliant one), ends
## with a diploma and gives a bed and a chest in the dorm while the hero studies. Long gaps are misses; too many, or a
## crime in the town, and the hero is expelled. The pack's courses (world.json `courses`, `schools`) and the master's
## (effect `course`). The hero keeps c["study"] {schools: {id: {stipend}}, tried, banned, courses: {id: {progress,
## last, misses, lesson_day}}, done}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["study"]


## Read-only: the hero's study or an empty one (reading must not change a session — a save would differ).
static func view(c: Dictionary) -> Dictionary:
	if c.get("study") is Dictionary:
		return state(c)
	return {"schools": {}, "tried": {}, "banned": {}, "courses": {}, "done": []}


static func state(c: Dictionary) -> Dictionary:
	if not (c.get("study") is Dictionary):
		c["study"] = {}
	var st: Dictionary = c["study"]
	for k: String in ["schools", "tried", "banned", "courses"]:
		if not (st.get(k) is Dictionary):
			st[k] = {}
	if not (st.get("done") is Array):
		st["done"] = []
	return st


static func courses(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (data["world"].get("courses", {}) as Dictionary).duplicate()
	if s != null:
		out.merge(WorldGen.generated(s).get("courses", {}), true)
	return out


static func course(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return courses(s, data).get(id, {})


static func school(data: Dictionary, id: String) -> Dictionary:
	return data["world"].get("schools", {}).get(id, {})


static func name_of(s: GameSession, data: Dictionary, id: String) -> String:
	return str(course(s, data, id).get("name", id))


static func npc_name(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return JobRules.npc_name(s, data, npc_id)


## The courses an NPC teaches.
static func of_teacher(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var all := courses(s, data)
	for id: String in all:
		if str(all[id].get("teacher", "")) == npc_id:
			out.append(id)
	return out


## The schools an NPC heads.
static func headed_by(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = data["world"].get("schools", {})
	for id: String in all:
		if str(all[id].get("head", "")) == npc_id:
			out.append(id)
	return out


## The courses an NPC enrols on: its own and, for a school's head, every course of the school.
static func offered_by(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out := of_teacher(s, data, npc_id)
	var heads := headed_by(data, npc_id)
	var all := courses(s, data)
	for id: String in all:
		if heads.has(str(all[id].get("school", ""))) and not out.has(id):
			out.append(id)
	return out


static func is_teacher(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not of_teacher(s, data, npc_id).is_empty() or not headed_by(data, npc_id).is_empty()


## Book courses of the books the hero carries.
static func books(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var inv: Dictionary = s.character.get("inventory", {})
	var all := courses(s, data)
	for id: String in all:
		if not str(all[id].get("book", "")).is_empty() and int(inv.get(str(all[id]["book"]), 0)) > 0:
			out.append(id)
	return out


static func enrolled(c: Dictionary, id: String) -> bool:
	return view(c)["courses"].has(id)


static func done(c: Dictionary, id: String) -> bool:
	return (view(c)["done"] as Array).has(id)


## What a course teaches, in words: «навык: История».
static func teaches_text(s: GameSession, data: Dictionary, id: String) -> String:
	var t: Dictionary = course(s, data, id).get("teaches", {})
	var kind := str(t.get("kind", "xp"))
	var what := str(t.get("id", ""))
	var label := str(cfg(data)["kinds"].get(kind, kind))
	match kind:
		"skill": return "%s: %s" % [label, CraftRules.tr_skill(data, what)]
		"tool": return "%s: %s" % [label, BackgroundRules.tool_name(data, what)]
		"language": return "%s: %s" % [label, LanguageRules.name_of(data, what)]
		"spell": return "%s: %s" % [label, str(data["spells"].get(what, {}).get("name", what))]
		"recipe": return "%s: %s" % [label, CraftRules.recipe_name(s, data, what)]
	return "%s: %d" % [label, int(course(s, data, id).get("xp", 0))]


## The hero's highest spell circle by its slots, -1 for a non-caster.
static func _max_circle(c: Dictionary) -> int:
	if str(c.get("spell_ability", "")).is_empty():
		return -1
	var top := 0
	var slots: Array = c.get("slots_max", [])
	for i in slots.size():
		if int(slots[i]) > 0:
			top = i + 1
	return top


static func _knows_spell(c: Dictionary, id: String) -> bool:
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "known", "prepared", "always"]:
		if (sp.get(list, []) as Array).has(id):
			return true
	return false


## What a course asks: [{text, ok}].
static func requirements(s: GameSession, data: Dictionary, id: String) -> Array[Dictionary]:
	var co := course(s, data, id)
	var c := s.character
	var out: Array[Dictionary] = []
	var req: Dictionary = co.get("requires", {})
	if req.has("level"):
		out.append({"text": "уровень %d" % int(req["level"]), "ok": int(c.get("level", 1)) >= int(req["level"])})
	if req.has("classes"):
		out.append({"text": "класс: " + ", ".join(req["classes"]), "ok": (req["classes"] as Array).has(str(c.get("class", "")))})
	var teacher := str(co.get("teacher", ""))
	var n := WorldView.new(data["world"]).npc(teacher)
	if not n.is_empty() and not LanguageRules.npc_understands(c, data, n):
		out.append({"text": "общий язык с учителем", "ok": false})
	var t: Dictionary = co.get("teaches", {})
	var what := str(t.get("id", ""))
	match str(t.get("kind", "")):
		"skill":
			out.append({"text": "ещё не владеете навыком", "ok": not (c.get("skill_profs", []) as Array).has(what) and not CharacterRules.has_feature(c, "skill_prof_" + what)})
		"tool":
			out.append({"text": "ещё не владеете инструментом", "ok": not CraftRules.proficient(c, what)})
		"language":
			out.append({"text": "ещё не знаете язык", "ok": not LanguageRules.hero(c).has(what)})
		"spell":
			var sp: Dictionary = data["spells"].get(what, {})
			var lv := int(sp.get("level", 9))
			out.append({"text": "заклинатель класса из списка заклинания", "ok": _max_circle(c) >= 0 and (sp.get("classes", []) as Array).has(str(c.get("class", "")))})
			out.append({"text": "круг %d доступен" % lv, "ok": lv <= maxi(0, _max_circle(c))})
			out.append({"text": "заклинание ещё не известно", "ok": not _knows_spell(c, what)})
		"recipe":
			var r := CraftRules.recipe(s, data, what)
			out.append({"text": "владение: " + BackgroundRules.tool_name(data, CraftRules.tool_of(r)), "ok": CraftRules.simple(r) or CraftRules.proficient(c, CraftRules.tool_of(r))})
			out.append({"text": "рецепт ещё не выучен", "ok": not CraftRules.learned(c).has(what)})
	return out


static func _ok(s: GameSession, data: Dictionary, id: String) -> bool:
	return requirements(s, data, id).all(func(r: Dictionary) -> bool: return bool(r["ok"]))


static func here(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return SceneRules.npcs(s, data["world"], s.room_id).has(npc_id)


static func _loc_of_school(data: Dictionary, sid: String) -> String:
	var world := WorldView.new(data["world"])
	return str(world.site(str(school(data, sid).get("site", ""))).get("location_id", ""))


static func _banned(s: GameSession, sid: String) -> bool:
	return not sid.is_empty() and int(view(s.character)["banned"].get(sid, -1)) >= s.day


static func admitted(c: Dictionary, sid: String) -> bool:
	return sid.is_empty() or school_state(c).has(sid)


static func school_state(c: Dictionary) -> Dictionary:
	return view(c)["schools"]


# --- the exam -----------------------------------------------------------------------------------------------------


## "" when the hero may sit the school's entrance exam now, else a localization key.
static func exam_why(s: GameSession, data: Dictionary, sid: String) -> String:
	var sc := school(data, sid)
	if sc.is_empty():
		return "STUDY_UNKNOWN"
	if admitted(s.character, sid):
		return "STUDY_ADMITTED"
	if _banned(s, sid):
		return "STUDY_BANNED"
	if not here(s, data, str(sc.get("head", ""))):
		return "STUDY_TEACHER_AWAY"
	if SocialRules.refuses(s, data, str(sc["head"])):
		return "TALK_REFUSED"
	var tried: Dictionary = view(s.character)["tried"]
	if tried.has(sid) and s.day - int(tried[sid]) < int(cfg(data)["exam"]["retry_days"]):
		return "STUDY_TRIED"
	return ""


static func exam_chance(s: GameSession, data: Dictionary, sid: String) -> int:
	var ex: Dictionary = school(data, sid).get("exam", {})
	if ex.is_empty():
		return 100
	var b := CheckEngine.bonus_for(s.character, {"skill": str(ex["skill"])}) + DifficultyRules.bonus(s, data)
	return JobRules._chance(b, int(ex["dc"]), false)


## The entrance exam (exam_why first). Lines.
static func exam(s: GameSession, data: Dictionary, sid: String) -> Array[String]:
	var sc := school(data, sid)
	var ex: Dictionary = sc.get("exam", {})
	var lines: Array[String] = []
	var margin := 0
	if not ex.is_empty():
		var nat := s.rng.randi_range(1, 20)
		var total := nat + CheckEngine.bonus_for(s.character, {"skill": str(ex["skill"])}) + DifficultyRules.bonus(s, data)
		margin = 5 if nat == 20 else -5 if nat == 1 else total - int(ex["dc"])
		lines.append("%s — экзамен: %s %d против Сл %d — %s" % [sc["name"], CraftRules.tr_skill(data, str(ex["skill"])), total, int(ex["dc"]),
			"сдан" if margin >= 0 else "не сдан"])
		if margin < 0:
			state(s.character)["tried"][sid] = s.day
			lines.append("Можно попробовать снова через %d дн." % int(cfg(data)["exam"]["retry_days"]))
			return lines
	var stipend := margin >= int(cfg(data)["exam"]["stipend_margin"])
	state(s.character)["schools"][sid] = {"since": s.day, "stipend": stipend}
	lines.append("Приняты в %s%s" % [sc["name"], " — со стипендией: учёба здесь бесплатно" if stipend else ""])
	return lines


# --- enrolment ----------------------------------------------------------------------------------------------------


static func fee(s: GameSession, data: Dictionary, id: String) -> int:
	var co := course(s, data, id)
	var sid := str(co.get("school", ""))
	if not sid.is_empty() and bool(school_state(s.character).get(sid, {}).get("stipend", false)):
		return 0
	var who := str(co.get("teacher", school(data, sid).get("head", "") if not sid.is_empty() else ""))
	return roundi(int(co.get("fee_cp", 0)) * float(DevelopmentRules.effect(s.character, data, "study", "fee_pct", 100.0)) / 100.0
		* BondRules.mentor_fee_pct(s, data, who) / 100.0)  # v0.7.31: a mentor asks less


static func lessons_needed(s: GameSession, data: Dictionary, id: String) -> int:
	return maxi(1, int(course(s, data, id).get("lessons", 1)) - int(DevelopmentRules.effect(s.character, data, "study", "lessons_minus", 0.0)))


## "" when the hero may enrol on the course now, else a localization key.
static func enroll_why(s: GameSession, data: Dictionary, id: String) -> String:
	var co := course(s, data, id)
	if co.is_empty():
		return "STUDY_UNKNOWN"
	if done(s.character, id):
		return "STUDY_DONE"
	if enrolled(s.character, id):
		return "STUDY_ENROLLED"
	if not str(co.get("book", "")).is_empty():
		return "STUDY_BOOK"
	var sid := str(co.get("school", ""))
	var teacher := str(co.get("teacher", ""))
	var head := str(school(data, sid).get("head", ""))
	if not here(s, data, teacher) and (head.is_empty() or not here(s, data, head)):
		return "STUDY_TEACHER_AWAY"
	if SocialRules.refuses(s, data, teacher if here(s, data, teacher) else head):
		return "TALK_REFUSED"
	if _banned(s, sid):
		return "STUDY_BANNED"
	if not admitted(s.character, sid):
		return "STUDY_NEED_EXAM"
	if not _ok(s, data, id):
		return "STUDY_REQUIREMENTS"
	return "STUDY_NO_MONEY" if int(s.character.get("gold_cp", 0)) < fee(s, data, id) else ""


static func enroll(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var f := fee(s, data, id)
	c["gold_cp"] = int(c.get("gold_cp", 0)) - f
	var lines: Array[String] = ["Записаны на курс «%s» (%s) — %s, занятий %d%s" % [name_of(s, data, id), npc_name(s, data, str(course(s, data, id)["teacher"])),
		teaches_text(s, data, id), lessons_needed(s, data, id), (", плата " + Money.format(f)) if f > 0 else ""]]
	lines.append_array(_dorm_open(s, data, str(course(s, data, id).get("school", ""))))
	state(c)["courses"][id] = {"progress": 0, "last": s.day, "misses": 0, "lesson_day": -1}
	return lines


static func drop(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var sid := str(course(s, data, id).get("school", ""))
	view(s.character)["courses"].erase(id)
	var lines: Array[String] = ["Бросили курс «%s»" % name_of(s, data, id)]
	lines.append_array(_dorm_close(s, data, sid))
	return lines


# --- lessons ------------------------------------------------------------------------------------------------------


static func _book_course(s: GameSession, data: Dictionary, id: String) -> bool:
	return not str(course(s, data, id).get("book", "")).is_empty()


## "" when a lesson (or a reading) may go now, else a localization key.
static func lesson_why(s: GameSession, data: Dictionary, id: String) -> String:
	var co := course(s, data, id)
	if co.is_empty():
		return "STUDY_UNKNOWN"
	if done(s.character, id):
		return "STUDY_DONE"
	if _book_course(s, data, id):
		if not books(s, data).has(id):
			return "STUDY_NO_BOOK"
		if not _ok(s, data, id):
			return "STUDY_REQUIREMENTS"
	else:
		if not enrolled(s.character, id):
			return "STUDY_NOT_ENROLLED"
		if not here(s, data, str(co.get("teacher", ""))):
			return "STUDY_TEACHER_AWAY"
	if int(view(s.character)["courses"].get(id, {}).get("lesson_day", -1)) == s.day:
		return "STUDY_DONE_TODAY"
	return ""


static func lesson_hours(data: Dictionary) -> int:
	return int(cfg(data)["lesson"]["hours"])


## The check of a lesson: {bonus, adv, label}.
static func _check(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var co := course(s, data, id)
	var c := s.character
	var bonus := int(DevelopmentRules.effect(c, data, "study", "lesson_bonus", 0.0)) + DifficultyRules.bonus(s, data)
	var adv := bool(DevelopmentRules.effect(c, data, "study", "lesson_adv", false))
	if _book_course(s, data, id):
		bonus += int(DevelopmentRules.effect(c, data, "study", "book_bonus", 0.0))
		adv = adv or bool(DevelopmentRules.effect(c, data, "study", "book_adv", false))
	if co.has("ability"):
		var ab := str(co["ability"])
		return {"bonus": bonus + CharacterRules.mod(int(c.get("abilities", {}).get(ab, 10))), "adv": adv,
			"label": TranslationServer.translate("ABILITY_" + ab.to_upper())}
	var skill := str(co.get("skill", "history"))
	return {"bonus": bonus + CheckEngine.bonus_for(c, {"skill": skill}), "adv": adv, "label": CraftRules.tr_skill(data, skill)}


static func lesson_chance(s: GameSession, data: Dictionary, id: String) -> int:
	var ch := _check(s, data, id)
	return JobRules._chance(int(ch["bonus"]), int(course(s, data, id).get("dc", 10)), bool(ch["adv"]))


static func outcome_for(s: GameSession, data: Dictionary, margin: int) -> Dictionary:
	var out: Dictionary = cfg(data)["outcomes"][0]
	for o: Dictionary in cfg(data)["outcomes"]:
		var from := int(o["from"])
		if str(o["id"]) == "great":
			from = int(DevelopmentRules.effect(s.character, data, "study", "great_from", float(from)))
		if margin >= from:
			out = o
	return out


## A lesson of `minutes` (the time already passed); a lesson broken off counts nothing. Lines.
static func lesson(s: GameSession, data: Dictionary, id: String, minutes: int) -> Array[String]:
	var c := s.character
	var co := course(s, data, id)
	var courses_st: Dictionary = state(c)["courses"]
	if not courses_st.has(id):
		courses_st[id] = {"progress": 0, "last": s.day, "misses": 0, "lesson_day": -1}
	var st: Dictionary = courses_st[id]
	if minutes < lesson_hours(data) * 60:
		return ["Занятие прервано — не засчитано"]
	st["lesson_day"] = s.day
	st["last"] = s.day
	var ch := _check(s, data, id)
	var mods := ConditionRules.check_mods(c, data, {"skill": str(co.get("skill", "history"))})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, bool(ch["adv"]), dis)
	var nat: int = rolls.max() if bool(ch["adv"]) and not dis else rolls.min() if dis and not bool(ch["adv"]) else rolls[0]
	var dc := int(co.get("dc", 10))
	var total := nat + int(ch["bonus"])
	var margin := 5 if nat == 20 else -5 if nat == 1 else total - dc
	var o := outcome_for(s, data, margin)
	st["progress"] = int(st["progress"]) + int(o.get("progress", 0))
	var need := lessons_needed(s, data, id)
	var lines: Array[String] = ["%s: %s %d %s %d = %d против Сл %d — %s (%d/%d)" % [name_of(s, data, id), ch["label"], nat, "−" if total < nat else "+", absi(total - nat), total, dc,
		o["name"], mini(int(st["progress"]), need), need]]
	var dev: Dictionary = DevelopmentRules.direction(data, "study").get("sources", {})
	lines.append_array(DevelopmentRules.add_xp(c, data, "study", int(dev.get(str(o["id"]), 0))))
	if int(st["progress"]) >= need:
		lines.append_array(graduate(s, data, id))
	return lines


# --- the end of a course ------------------------------------------------------------------------------------------


## What the course teaches goes to the hero. Lines.
static func grant(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var t: Dictionary = course(s, data, id).get("teaches", {})
	var what := str(t.get("id", ""))
	match str(t.get("kind", "")):
		"skill":
			var profs: Array = c.get("skill_profs", [])
			if not profs.has(what):
				profs.append(what)
			c["skill_profs"] = profs
		"tool":
			var tools: Array = c.get("tools", [])
			if not tools.has(what):
				tools.append(what)
			c["tools"] = tools
		"language":
			var langs: Array = c.get("languages", [])
			if not langs.has(what):
				langs.append(what)
			c["languages"] = langs
		"spell":
			var sp: Dictionary = c.get("spells", {})
			var always: Array = sp.get("always", [])
			if not always.has(what):
				always.append(what)
			sp["always"] = always
			c["spells"] = sp
		"recipe":
			CraftRules.learn(s, data, what)
		_:
			return []
	CharacterRules.refresh(c, data, s.items)
	return ["Выучено — %s" % teaches_text(s, data, id)]


static func graduate(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var co := course(s, data, id)
	var lines: Array[String] = ["Курс «%s» окончен" % name_of(s, data, id)]
	lines.append_array(grant(s, data, id))
	if not bool(co.get("generated", false)):  # the master's courses give no class experience
		lines.append_array(XpRules.award(c, data, int(co.get("xp", 0)), "учёба"))
	var dev: Dictionary = DevelopmentRules.direction(data, "study").get("sources", {})
	lines.append_array(DevelopmentRules.add_xp(c, data, "study", int(dev.get("graduate", 0))))
	var sid := str(co.get("school", ""))
	if not sid.is_empty():
		var doc := {"id": "gen_diploma_" + id, "name": "Грамота училища: %s" % name_of(s, data, id), "item_type": "gear", "value_cp": 0, "weight": 0,
			"description": "%s: предъявитель окончил курс «%s» — %s." % [school(data, sid)["name"], name_of(s, data, id), teaches_text(s, data, id)]}
		s.items[doc["id"]] = doc
		ItemRules.found(c, data, s.items, doc["id"], 1)
		lines.append("Грамота выпускника — в вещах")
	if co.has("teacher"):
		lines.append_array(BondRules.mentor(s, data, str(co["teacher"])))  # v0.7.31
	view(c)["courses"].erase(id)
	(view(c)["done"] as Array).append(id)
	lines.append_array(_dorm_close(s, data, sid))
	return lines


static func has_diploma(c: Dictionary, id: String) -> bool:
	return int(c.get("inventory", {}).get("gen_diploma_" + id, 0)) > 0


## The hero is out of the school: the courses gone, the school closed for a while. Lines.
static func expel(s: GameSession, data: Dictionary, sid: String, why: String) -> Array[String]:
	var c := s.character
	var gone: Array[String] = []
	for id: String in (view(c)["courses"] as Dictionary).keys():
		if str(course(s, data, id).get("school", "")) == sid:
			view(c)["courses"].erase(id)
			gone.append(name_of(s, data, id))
	school_state(c).erase(sid)
	state(c)["banned"][sid] = s.day + int(cfg(data)["readmit_days"])
	var lines: Array[String] = ["Отчислены из «%s» — %s%s; вернуться можно через %d дн." % [school(data, sid).get("name", sid), why,
		(" (курсы: %s)" % ", ".join(gone)) if not gone.is_empty() else "", int(cfg(data)["readmit_days"])]]
	lines.append_array(_dorm_close(s, data, sid))
	return lines


# --- the dorm -----------------------------------------------------------------------------------------------------


static func _studies_at(c: Dictionary, s: GameSession, data: Dictionary, sid: String) -> bool:
	for id: String in view(c)["courses"]:
		if str(course(s, data, id).get("school", "")) == sid:
			return true
	return false


## True when the room is the dorm of a school the hero studies at.
static func student_room(s: GameSession, data: Dictionary, room_id: String) -> bool:
	var all: Dictionary = data["world"].get("schools", {})
	for sid: String in all:
		if str(all[sid].get("dorm", "")) == room_id and _studies_at(s.character, s, data, sid):
			return true
	return false


static func _chest_id(sid: String) -> String:
	return "chest_study_" + sid


static func _dorm_open(s: GameSession, data: Dictionary, sid: String) -> Array[String]:
	var room := str(school(data, sid).get("dorm", ""))
	if room.is_empty() or _studies_at(s.character, s, data, sid):
		return []
	var list: Array = s.props.get(room, [])
	if not list.any(func(p: Dictionary) -> bool: return str(p.get("id", "")) == _chest_id(sid)):
		list.append({"id": _chest_id(sid), "name": "Сундук ученика", "description": "Сундук под топчаном в вашей каморке.", "item_id": "",
			"owner": "", "text": "", "state": "", "container": "chest", "contents": {}, "mine": true})
	s.props[room] = list
	return ["Каморка в общежитии ваша, пока учитесь: топчан и сундук (%s)" % WorldView.new(data["world"]).room_short(room)]


## The last course of the school is over: the chest's things go back to the hero.
static func _dorm_close(s: GameSession, data: Dictionary, sid: String) -> Array[String]:
	var room := str(school(data, sid).get("dorm", ""))
	if room.is_empty() or _studies_at(s.character, s, data, sid):
		return []
	var list: Array = s.props.get(room, [])
	var lines: Array[String] = []
	for p: Dictionary in list.duplicate():
		if str(p.get("id", "")) != _chest_id(sid):
			continue
		var back: Array[String] = []
		for item: String in (p.get("contents", {}) as Dictionary):
			ItemRules.found(s.character, data, s.items, item, int(p["contents"][item]))
			back.append(ItemRules.display_name(data["items"], s.items, item))
		list.erase(p)
		lines.append("Каморку освободили" + ((" — вещи из сундука вам отдали: " + ", ".join(back)) if not back.is_empty() else ""))
	s.props[room] = list
	return lines


# --- days ---------------------------------------------------------------------------------------------------------


## Each new day: misses for long gaps, expelled after too many or for a crime in the school's town. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	if not (c.get("study") is Dictionary):
		return []
	var lines: Array[String] = []
	var gap := int(cfg(data)["gap_days"])
	var max_misses := int(cfg(data)["misses_max"]) + int(DevelopmentRules.effect(c, data, "study", "misses_add", 0.0))
	var out: Dictionary = {}
	for id: String in (view(c)["courses"] as Dictionary).keys():
		var co := course(s, data, id)
		if co.is_empty() or _book_course(s, data, id):
			continue
		var st: Dictionary = view(c)["courses"][id]
		if s.day - int(st["last"]) > gap:
			st["misses"] = int(st["misses"]) + 1
			st["last"] = s.day
			lines.append("Пропуск занятий: «%s» (%d из %d допустимых)" % [name_of(s, data, id), int(st["misses"]), max_misses])
			if int(st["misses"]) > max_misses:
				out[id] = "за пропуски"
	for sid: String in (school_state(c) as Dictionary).keys():
		var loc := _loc_of_school(data, sid)
		var room := str(school(data, sid).get("dorm", ""))
		if not loc.is_empty() and not room.is_empty() and CrimeRules.wanted_at(s, data, room):
			lines.append_array(expel(s, data, sid, "за проступок: вас ищет стража"))
	for id: String in out:
		if not enrolled(c, id):
			continue
		var sid := str(course(s, data, id).get("school", ""))
		if sid.is_empty():
			view(c)["courses"].erase(id)
			lines.append("Учитель больше не ждёт вас: «%s» — %s" % [name_of(s, data, id), out[id]])
		else:
			lines.append_array(expel(s, data, sid, str(out[id])))
	return lines


## For the master: «Учёба (…): …».
static func text(s: GameSession, data: Dictionary) -> String:
	var c := s.character
	var parts: Array[String] = []
	if c.get("study") is Dictionary:
		for sid: String in school_state(c):
			parts.append("принят в %s%s" % [school(data, sid).get("name", sid), " (стипендия)" if bool(school_state(c)[sid].get("stipend", false)) else ""])
		for id: String in view(c)["courses"]:
			var st: Dictionary = view(c)["courses"][id]
			parts.append("курс «%s» — %s, %d/%d, пропусков %d" % [name_of(s, data, id), teaches_text(s, data, id), int(st["progress"]),
				lessons_needed(s, data, id), int(st.get("misses", 0))])
		for id: Variant in view(c)["done"]:
			parts.append("окончен «%s»" % name_of(s, data, str(id)))
	var teach: Array[String] = []
	for npc: String in SceneRules.npcs(s, data["world"], s.room_id):
		for id: String in of_teacher(s, data, npc):
			teach.append("%s учит «%s» (%s)" % [npc_name(s, data, npc), name_of(s, data, id), teaches_text(s, data, id)])
	if not teach.is_empty():
		parts.append("здесь: " + "; ".join(teach))
	return ("Учёба (окно «Учёба» у учителя, занятия — кнопкой): " + "; ".join(parts)) if not parts.is_empty() else ""


# --- the master's courses -----------------------------------------------------------------------------------------


## A course the master makes at a teacher of the scene: checked against rules.study.make. {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var who := str(spec.get("npc_id", ""))
	if not here(s, data, who):
		return {"reason": "%s не в сцене — учит только тот, кто здесь" % who}
	var kind := str(spec.get("teach_kind", ""))
	if not (m["kinds"] as Array).has(kind):
		return {"reason": "teach_kind — из %s (опыта мастер не даёт)" % ", ".join(m["kinds"])}
	var what := str(spec.get("teach_id", ""))
	var ok := false
	match kind:
		"skill": ok = data["rules"]["skills"].has(what)
		"tool": ok = CraftRules.cfg(data)["tools"].has(what)
		"language": ok = data["misc"]["languages"].has(what)
		"spell": ok = data["spells"].has(what) and int(data["spells"][what]["level"]) <= int(m["max_spell_level"])
		"recipe": ok = not CraftRules.recipe(s, data, what).is_empty()
	if not ok:
		return {"reason": "teach_id %s для %s неизвестен движку (заклинание — до %d круга)" % [what, kind, int(m["max_spell_level"])]}
	var n := int(spec.get("lessons", 4))
	if n < int(m["lessons"][0]) or n > int(m["lessons"][1]):
		return {"reason": "lessons — от %d до %d" % [m["lessons"][0], m["lessons"][1]]}
	var tier := str(spec.get("dc_tier", "medium"))
	if not (m["dc_tiers"] as Array).has(tier):
		return {"reason": "dc_tier — из %s" % ", ".join(m["dc_tiers"])}
	var f := int(spec.get("fee_cp", 0))
	if f < int(m["fee_cp_lesson"][0]) * n or f > int(m["fee_cp_lesson"][1]) * n:
		return {"reason": "fee_cp — от %s до %s за %d занятий" % [Money.format(int(m["fee_cp_lesson"][0]) * n), Money.format(int(m["fee_cp_lesson"][1]) * n), n]}
	var skill := str(spec.get("skill", "")) if spec.get("skill") != null else ""
	if skill.is_empty():
		skill = what if kind == "skill" else "history"
	if not data["rules"]["skills"].has(skill):
		return {"reason": "skill — навык проверки занятия: %s" % ", ".join(data["rules"]["skills"].keys())}
	var name := str(spec.get("name", "")).strip_edges().left(60)
	if name.is_empty():
		return {"reason": "нужно name — как называется курс"}
	var id := "gen_c_" + ("%s|%s|%s" % [who, kind, what]).md5_text().left(8)
	if courses(s, data).has(id):
		return {"reason": "%s уже учит этому — кнопка «Учёба» в его действиях" % npc_name(s, data, who)}
	var def := {"name": name, "teacher": who, "teaches": {"kind": kind, "id": what}, "lessons": n, "skill": skill,
		"dc": int(data["rules"]["dc_tiers"][tier]), "fee_cp": f, "generated": true}
	return {"plan": {"id": id, "def": def}, "summary": "Курс — %s: «%s», %d занятий" % [npc_name(s, data, who), name, n]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var all: Dictionary = gen.get("courses", {})
	all[str(plan["id"])] = (plan["def"] as Dictionary).duplicate(true)
	gen["courses"] = all
	return ["%s берёт учеников: «%s» — кнопка «Учёба» в его действиях" % [npc_name(s, data, str(plan["def"]["teacher"])), plan["def"]["name"]]]
