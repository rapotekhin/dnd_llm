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
	return WorldGen.registry(s, data, "courses")


static func course(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return courses(s, data).get(id, {})


static func school(data: Dictionary, id: String) -> Dictionary:
	return data["world"].get("schools", {}).get(id, {})


static func name_of(s: GameSession, data: Dictionary, id: String) -> String:
	return str(course(s, data, id).get("name", id))


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


## The master's courses waiting for the hero at teachers out of the scene (v0.7.39.7): not begun, not finished, not
## known some other way, the teacher alive.
static func waiting(s: GameSession, data: Dictionary, who: String = Being.HERO) -> Array[String]:
	var out: Array[String] = []
	var all := courses(s, data)
	var c := Life.of(s, who, data)
	for id: String in all:
		var teacher_id := str(all[id].get("teacher", ""))
		if bool(all[id].get("generated", false)) and not teacher_id.is_empty() and not here(s, data, teacher_id, who) and not Being.dead(s, teacher_id) 				and not enrolled(c, id) and not done(c, id) and not known_already(s, data, id, who):
			out.append(id)
	return out


## Where a course's teacher is, in words: «Ольховый Брод · Мельница» ("" — unknown).
static func where(s: GameSession, data: Dictionary, id: String) -> String:
	var teacher_id := str(course(s, data, id).get("teacher", ""))
	var room := Where.base_room(s, data, teacher_id)
	return WorldView.new(data["world"]).place_path(room) if not room.is_empty() else ""


static func is_teacher(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not of_teacher(s, data, npc_id).is_empty() or not headed_by(data, npc_id).is_empty()


## Book courses of the books the hero carries.
static func books(s: GameSession, data: Dictionary, who: String = Being.HERO) -> Array[String]:
	var out: Array[String] = []
	var inv: Dictionary = Life.of(s, who, data).get("inventory", {})
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
		"spell", "ability": return "%s: %s" % [label, str(data["spells"].get(what, {}).get("name", what))]
		"recipe": return "%s: %s" % [label, CraftRules.recipe_name(s, data, what)]
		"dev": return "%s: %s +%d" % [label, str(DevelopmentRules.direction(data, what).get("name", what)), int(t.get("xp", 0))]
	return "%s: %d" % [label, int(course(s, data, id).get("xp", 0))]


## The hero's highest spell circle by its slots, -1 for a non-caster.
static func max_circle(c: Dictionary) -> int:
	if str(c.get("spell_ability", "")).is_empty():
		return -1
	var top := 0
	var slots: Array = c.get("slots_max", [])
	for i in slots.size():
		if int(slots[i]) > 0:
			top = i + 1
	return top


## The hero knows a spell or an ability for good: a course, a book, or worked out alone (MakeRules).
static func learn_spell(c: Dictionary, id: String) -> void:
	var sp: Dictionary = c.get("spells", {})
	var always: Array = sp.get("always", [])
	if not always.has(id):
		always.append(id)
	sp["always"] = always
	c["spells"] = sp


static func _knows_spell(c: Dictionary, id: String) -> bool:
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "known", "prepared", "always"]:
		if (sp.get(list, []) as Array).has(id):
			return true
	return false


## What a course asks: [{text, ok}].
static func requirements(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[Dictionary]:
	var co := course(s, data, id)
	var c := Life.of(s, who, data)
	var teacher := str(co.get("teacher", ""))
	var out := Require.rows(s, data, co.get("requires", {}), {"who": who, "npc": teacher, "npc_word": "учителем", "npc_of": "учителя"})
	var t: Dictionary = co.get("teaches", {})
	var what := str(t.get("id", ""))
	match str(t.get("kind", "")):
		"skill":
			out.append({"text": "ещё не владеете навыком", "ok": not (c.get("skill_profs", []) as Array).has(what) and not CharacterRules.has_feature(c, "skill_prof_" + what)})
		"trait":
			out.append({"text": "этой черты ещё нет", "ok": not ConditionRules.has(c, what)})
		"tool":
			out.append({"text": "ещё не владеете инструментом", "ok": not CraftRules.proficient(c, what)})
		"language":
			out.append({"text": "ещё не знаете язык", "ok": not LanguageRules.hero(c, data).has(what)})
		"spell":
			var sp: Dictionary = data["spells"].get(what, {})
			var lv := int(sp.get("level", 9))
			out.append({"text": "заклинатель класса из списка заклинания", "ok": max_circle(c) >= 0 and (bool(sp.get("generated", false)) or (sp.get("classes", []) as Array).has(str(c.get("class", ""))))})
			out.append({"text": "круг %d доступен" % lv, "ok": lv <= maxi(0, max_circle(c))})
			out.append({"text": "заклинание ещё не известно", "ok": not _knows_spell(c, what)})
		"ability":
			out.append({"text": "этой способности ещё нет", "ok": not _knows_spell(c, what)})
		"recipe":
			var r := CraftRules.recipe(s, data, what)
			if CraftRules.needs_tool(r):
				out.append({"text": "владение: " + BackgroundRules.tool_name(data, CraftRules.tool_of(r)), "ok": CraftRules.proficient(c, CraftRules.tool_of(r))})
			out.append({"text": "рецепт ещё не известен", "ok": not CraftRules.known(s, data).has(what)})
	return out


## The hero already has what the course teaches (v0.7.39): a skill, a tool, a language, a spell or a recipe known
## some other way — a recipe without `learn` by the tool's proficiency. Such a course is shown as learned, not begun.
static func known_already(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> bool:
	var c := Life.of(s, who, data)
	var t: Dictionary = course(s, data, id).get("teaches", {})
	var what := str(t.get("id", ""))
	match str(t.get("kind", "")):
		"skill":
			return (c.get("skill_profs", []) as Array).has(what) or CharacterRules.has_feature(c, "skill_prof_" + what)
		"trait":
			return ConditionRules.has(c, what)
		"tool":
			return CraftRules.proficient(c, what)
		"language":
			return LanguageRules.hero(c, data).has(what)
		"spell", "ability":
			return _knows_spell(c, what)
		"recipe":
			return CraftRules.known(s, data).has(what)
	return false


static func _ok(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> bool:
	return requirements(s, data, id, who).all(func(r: Dictionary) -> bool: return bool(r["ok"]))


static func here(s: GameSession, data: Dictionary, npc_id: String, who: String = Being.HERO) -> bool:
	return s.npcs_here(data["world"], Life.room(s, data, who)).has(npc_id)


static func _loc_of_school(data: Dictionary, sid: String) -> String:
	var world := WorldView.new(data["world"])
	return str(world.site(str(school(data, sid).get("site", ""))).get("location_id", ""))


static func _banned(s: GameSession, sid: String, who: String = Being.HERO) -> bool:
	return not sid.is_empty() and int(view(Life.of(s, who))["banned"].get(sid, -1)) >= s.day


static func admitted(c: Dictionary, sid: String) -> bool:
	return sid.is_empty() or school_state(c).has(sid)


static func school_state(c: Dictionary) -> Dictionary:
	return view(c)["schools"]


# --- the exam -----------------------------------------------------------------------------------------------------


## "" when the hero may sit the school's entrance exam now, else a localization key.
static func exam_why(s: GameSession, data: Dictionary, sid: String, who: String = Being.HERO) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var sc := school(data, sid)
	if sc.is_empty():
		return "STUDY_UNKNOWN"
	if admitted(Life.of(s, who, data), sid):
		return "STUDY_ADMITTED"
	if _banned(s, sid, who):
		return "STUDY_BANNED"
	if not here(s, data, str(sc.get("head", "")), who):
		return "STUDY_TEACHER_AWAY"
	if (who == Being.HERO and SocialRules.refuses(s, data, str(sc["head"]))):
		return "TALK_REFUSED"
	var tried: Dictionary = view(Life.of(s, who, data))["tried"]
	if tried.has(sid) and s.day - int(tried[sid]) < int(cfg(data)["exam"]["retry_days"]):
		return "STUDY_TRIED"
	return ""


static func exam_chance(s: GameSession, data: Dictionary, sid: String, who: String = Being.HERO) -> int:
	var ex: Dictionary = school(data, sid).get("exam", {})
	if ex.is_empty():
		return 100
	return Roll.chance_of(s, data, Sheet.who(s, data, who), {"skill": str(ex["skill"]), "dc": int(ex["dc"])})


## The entrance exam (exam_why first). Lines.
static func exam(s: GameSession, data: Dictionary, sid: String, who: String = Being.HERO) -> Array[String]:
	var sc := school(data, sid)
	var ex: Dictionary = sc.get("exam", {})
	var lines: Array[String] = []
	var margin := 0
	var rec := LetterRules.recommender(s, data, [str(sc.get("head", ""))], true)  # v0.7.48: a recommendation lets one in without the exam
	if not ex.is_empty() and not rec.is_empty():
		lines.append("%s — без экзамена: рекомендация %s" % [sc["name"], rec])
	elif not ex.is_empty():
		var r := Roll.check(s, data, Sheet.who(s, data, who), {"what": "%s — экзамен" % sc["name"], "skill": str(ex["skill"]), "dc": int(ex["dc"])})
		var total := int(r["total"])
		margin = int(r["margin"])
		lines.append("%s — экзамен: %s %d против Сл %d — %s" % [sc["name"], CraftRules.tr_skill(data, str(ex["skill"])), total, int(ex["dc"]),
			"сдан" if margin >= 0 else "не сдан"])
		if margin < 0:
			state(Life.of(s, who, data))["tried"][sid] = s.day
			lines.append("Можно попробовать снова через %d дн." % int(cfg(data)["exam"]["retry_days"]))
			return lines
	var stipend := margin >= int(cfg(data)["exam"]["stipend_margin"])
	state(Life.of(s, who, data))["schools"][sid] = {"since": s.day, "stipend": stipend}
	lines.append("Приняты в %s%s" % [sc["name"], " — со стипендией: учёба здесь бесплатно" if stipend else ""])
	return lines


# --- enrolment ----------------------------------------------------------------------------------------------------


static func fee(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	var co := course(s, data, id)
	var sid := str(co.get("school", ""))
	if not sid.is_empty() and bool(school_state(Life.of(s, who, data)).get(sid, {}).get("stipend", false)):
		return 0
	var teacher_id := str(co.get("teacher", school(data, sid).get("head", "") if not sid.is_empty() else ""))
	var q := Price.start(int(co.get("fee_cp", 0)))
	Price.mod(q, "навык учёбы", float(DevelopmentRules.effect(Life.of(s, who, data), data, "study", "fee_pct", 100.0)))
	var sav := savant(s, data, id, who)
	if not sav.is_empty():
		Price.mod(q, str(sav["name"]), float(sav["fee_pct"]))
	return Price.rounded(Price.mod(q, "наставник", BondRules.mentor_fee_pct(s, data, teacher_id)))  # v0.7.31: a mentor asks less


static func lessons_needed(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	var n := int(course(s, data, id).get("lessons", 1))
	var sav := savant(s, data, id, who)
	if not sav.is_empty():
		n = ceili(n * float(sav["lessons_pct"]) / 100.0)
	return maxi(1, n - int(DevelopmentRules.effect(Life.of(s, who, data), data, "study", "lessons_minus", 0.0)))


## The row of `rules.study.savant` of a feature of `who` for a spell course of its school, with the feature's name; {} when
## none (Evocation Savant, v0.8.4.26.1).
static func savant(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	var teaches: Dictionary = course(s, data, id).get("teaches", {})
	if str(teaches.get("kind", "")) != "spell":
		return {}
	var school := str(data["spells"].get(str(teaches.get("id", "")), {}).get("school_id", ""))
	var c := Life.of(s, who, data)
	var rows: Dictionary = cfg(data).get("savant", {})
	for fid: String in rows:
		if not fid.begins_with("_") and str(rows[fid].get("school_id", "")) == school and CharacterRules.has_feature(c, fid):
			return (rows[fid] as Dictionary).merged({"name": str(data["classes"]["features"].get(fid, {}).get("name", fid))})
	return {}


## "" when the hero may enrol on the course now, else a localization key.
static func enroll_why(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var co := course(s, data, id)
	if co.is_empty():
		return "STUDY_UNKNOWN"
	if done(Life.of(s, who, data), id):
		return "STUDY_DONE"
	if enrolled(Life.of(s, who, data), id):
		return "STUDY_ENROLLED"
	if known_already(s, data, id, who):
		return "STUDY_KNOWN"
	if not str(co.get("book", "")).is_empty():
		return "STUDY_BOOK"
	var sid := str(co.get("school", ""))
	var teacher := str(co.get("teacher", ""))
	var head := str(school(data, sid).get("head", ""))
	if not here(s, data, teacher, who) and (head.is_empty() or not here(s, data, head, who)):
		return "STUDY_TEACHER_AWAY"
	if (who == Being.HERO and SocialRules.refuses(s, data, teacher if here(s, data, teacher, who) else head)):
		return "TALK_REFUSED"
	if _banned(s, sid, who):
		return "STUDY_BANNED"
	if not admitted(Life.of(s, who, data), sid):
		return "STUDY_NEED_EXAM"
	if not _ok(s, data, id, who):
		return "STUDY_REQUIREMENTS"
	return "STUDY_NO_MONEY" if Ledger.balance(s, who) < fee(s, data, id, who) else ""


static func enroll(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var f := fee(s, data, id, who)
	Ledger.add(s, -f, "study:enroll", who)
	var lines: Array[String] = ["Записаны на курс «%s» (%s) — %s, занятий %d%s" % [name_of(s, data, id), WorldView.name_of(data, str(course(s, data, id)["teacher"])),
		teaches_text(s, data, id), lessons_needed(s, data, id, who), (", плата " + Money.format(f)) if f > 0 else ""]]
	lines.append_array(_dorm_open(s, data, str(course(s, data, id).get("school", "")), who))
	state(c)["courses"][id] = _new_course(s, data, id, who)
	return lines


static func drop(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	var sid := str(course(s, data, id).get("school", ""))
	view(Life.of(s, who, data))["courses"].erase(id)
	var lines: Array[String] = ["Бросили курс «%s»" % name_of(s, data, id)]
	lines.append_array(_dorm_close(s, data, sid, who))
	return lines


# --- lessons ------------------------------------------------------------------------------------------------------


static func _book_course(s: GameSession, data: Dictionary, id: String) -> bool:
	return not str(course(s, data, id).get("book", "")).is_empty()


## "" when a lesson (or a reading) may go now, else a localization key.
static func lesson_why(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var co := course(s, data, id)
	if co.is_empty():
		return "STUDY_UNKNOWN"
	if done(Life.of(s, who, data), id):
		return "STUDY_DONE"
	if not enrolled(Life.of(s, who, data), id) and not view(Life.of(s, who, data))["courses"].has(id) and known_already(s, data, id, who):
		return "STUDY_KNOWN"
	if _book_course(s, data, id):
		if not books(s, data, who).has(id):
			return "STUDY_NO_BOOK"
		if not _ok(s, data, id, who):
			return "STUDY_REQUIREMENTS"
	else:
		if not enrolled(Life.of(s, who, data), id):
			return "STUDY_NOT_ENROLLED"
		if not here(s, data, str(co.get("teacher", "")), who):
			return "STUDY_TEACHER_AWAY"
	if int(view(Life.of(s, who, data))["courses"].get(id, {}).get("lesson_day", -1)) == s.day:
		return "STUDY_DONE_TODAY"
	return ""


static func lesson_hours(data: Dictionary) -> int:
	return int(cfg(data)["lesson"]["hours"])


## The check of a lesson: {bonus, parts, adv, label}.
static func _check(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	var co := course(s, data, id)
	var c := Life.of(s, who, data)
	var adv := bool(DevelopmentRules.effect(c, data, "study", "lesson_adv", false))
	var parts: Array[Dictionary] = []
	var label := ""
	if co.has("ability"):
		var ab := str(co["ability"])
		parts = [RollParts.part(RollParts.ability_name(ab), CharacterRules.mod(CharacterRules.ability(c, ab)))]
		if who == Being.HERO:
			RollParts.difficulty(s, data, parts)
		label = RollParts.ability_name(ab)
	else:
		var skill := str(co.get("skill", "history"))
		parts = RollParts.skill(s, data, skill, who)
		label = CraftRules.tr_skill(data, skill)
	RollParts.development(c, data, "study", "lesson_bonus", parts)
	var own := PropertyRules.here(s, data, who) if data["rules"].has("property") else ""
	if not own.is_empty() and PropertyRules.bonus(s, data, own, "lesson_bonus", who) != 0:  # v0.7.39.8: a library at the hero's place
		parts.append(RollParts.part(PropertyRules.name_of(s, data, own), PropertyRules.bonus(s, data, own, "lesson_bonus", who)))
	if _book_course(s, data, id):
		RollParts.development(c, data, "study", "book_bonus", parts)
		adv = adv or bool(DevelopmentRules.effect(c, data, "study", "book_adv", false))
	return {"bonus": RollParts.sum(parts), "parts": parts, "adv": adv, "label": label}


## The lesson's check for Activity.attempt and the window's chance.
static func lesson_spec(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	var co := course(s, data, id)
	var ch := _check(s, data, id, who)
	return {"what": name_of(s, data, id), "label": ch["label"], "skill": str(co.get("skill", "history")), "parts": ch["parts"], "bonus": ch["bonus"],
		"dc": int(co.get("dc", 10)), "adv": ch["adv"], "ladder": ladder(s, data, who)}


static func lesson_chance(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	return Roll.chance_of(s, data, Sheet.who(s, data, who), lesson_spec(s, data, id, who))


static func ladder(s: GameSession, data: Dictionary, who: String = Being.HERO) -> Array:
	return (cfg(data)["outcomes"] as Array).map(func(o: Dictionary) -> Dictionary:
		return o if str(o["id"]) != "great" else o.merged({"from": DevelopmentRules.effect(Life.of(s, who, data), data, "study", "great_from", float(o["from"]))}, true))


static func _new_course(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	return Progress.of_work(lessons_needed(s, data, id, who)).merged({"last": s.day, "misses": 0, "lesson_day": -1})


## A lesson of `minutes` (the time already passed); a lesson broken off counts nothing. Lines.
static func lesson(s: GameSession, data: Dictionary, id: String, minutes: int, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var co := course(s, data, id)
	var courses_st: Dictionary = state(c)["courses"]
	if not courses_st.has(id):
		courses_st[id] = _new_course(s, data, id, who)
	var st: Dictionary = courses_st[id]
	if minutes < lesson_hours(data) * 60:
		return ["Занятие прервано — не засчитано"]
	st["lesson_day"] = s.day
	st["last"] = s.day
	var a := Activity.attempt(s, data, lesson_spec(s, data, id, who), who)
	var o: Dictionary = a["step"]
	var need := lessons_needed(s, data, id, who)
	var finished := Progress.add(st, int(o.get("progress", 0)), need)
	var lines: Array[String] = ["%s (%d/%d)" % [a["line"], mini(int(st["done"]), need), need]]
	var dev: Dictionary = DevelopmentRules.direction(data, "study").get("sources", {})
	lines.append_array(DevelopmentRules.add_xp(c, data, "study", int(dev.get(str(o["id"]), 0))))
	if finished:
		lines.append_array(graduate(s, data, id, who))
	return lines


# --- the end of a course ------------------------------------------------------------------------------------------


## What the course teaches goes to the hero. Lines.
static func grant(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var t: Dictionary = course(s, data, id).get("teaches", {})
	var what := str(t.get("id", ""))
	match str(t.get("kind", "")):
		"trait":
			if who == Being.HERO:  # a trait is the hero sheet's
				MakeRules.grant_trait(s, data, what)
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
		"spell", "ability":
			learn_spell(c, what)
		"recipe":
			CraftRules.learn(s, data, what, who)
		"dev":  # the experience of a peaceful direction (v0.7.39.1: «Основы артефакции»)
			return DevelopmentRules.add_xp(c, data, what, int(t.get("xp", 0)))
		_:
			return []
	if who == Being.HERO:
		CharacterRules.refresh(c, data, s.items)
	return ["Выучено — %s" % teaches_text(s, data, id)]


static func graduate(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var co := course(s, data, id)
	var lines: Array[String] = ["Курс «%s» окончен" % name_of(s, data, id)]
	lines.append_array(grant(s, data, id, who))
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
	lines.append_array(_dorm_close(s, data, sid, who))
	return lines


static func has_diploma(c: Dictionary, id: String) -> bool:
	return int(c.get("inventory", {}).get("gen_diploma_" + id, 0)) > 0


## The hero is out of the school: the courses gone, the school closed for a while. Lines.
static func expel(s: GameSession, data: Dictionary, sid: String, why: String, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var gone: Array[String] = []
	for id: String in (view(c)["courses"] as Dictionary).keys():
		if str(course(s, data, id).get("school", "")) == sid:
			view(c)["courses"].erase(id)
			gone.append(name_of(s, data, id))
	school_state(c).erase(sid)
	state(c)["banned"][sid] = s.day + int(cfg(data)["readmit_days"])
	var lines: Array[String] = ["Отчислены из «%s» — %s%s; вернуться можно через %d дн." % [school(data, sid).get("name", sid), why,
		(" (курсы: %s)" % ", ".join(gone)) if not gone.is_empty() else "", int(cfg(data)["readmit_days"])]]
	lines.append_array(_dorm_close(s, data, sid, who))
	return lines


# --- the dorm -----------------------------------------------------------------------------------------------------


static func _studies_at(c: Dictionary, s: GameSession, data: Dictionary, sid: String) -> bool:
	for id: String in view(c)["courses"]:
		if str(course(s, data, id).get("school", "")) == sid:
			return true
	return false


## True when the room is the dorm of a school the hero studies at.
static func student_room(s: GameSession, data: Dictionary, room_id: String, who: String = Being.HERO) -> bool:
	var all: Dictionary = data["world"].get("schools", {})
	for sid: String in all:
		if str(all[sid].get("dorm", "")) == room_id and _studies_at(Life.of(s, who, data), s, data, sid):
			return true
	return false


static func _chest_id(sid: String) -> String:
	return "chest_study_" + sid


static func _dorm_open(s: GameSession, data: Dictionary, sid: String, who: String = Being.HERO) -> Array[String]:
	var room := str(school(data, sid).get("dorm", ""))
	if room.is_empty() or _studies_at(Life.of(s, who, data), s, data, sid):
		return []
	var list: Array = s.props.get(room, [])
	if not list.any(func(p: Dictionary) -> bool: return str(p.get("id", "")) == _chest_id(sid)):
		list.append({"id": _chest_id(sid), "name": "Сундук ученика", "description": "Сундук под топчаном в вашей каморке.", "item_id": "",
			"owner": "", "text": "", "state": "", "container": "chest", "contents": {}, "mine": true})
	s.props[room] = list
	return ["Каморка в общежитии ваша, пока учитесь: топчан и сундук (%s)" % WorldView.new(data["world"]).room_short(room)]


## The last course of the school is over: the chest's things go back to the hero.
static func _dorm_close(s: GameSession, data: Dictionary, sid: String, who: String = Being.HERO) -> Array[String]:
	var room := str(school(data, sid).get("dorm", ""))
	if room.is_empty() or _studies_at(Life.of(s, who, data), s, data, sid):
		return []
	var list: Array = s.props.get(room, [])
	var lines: Array[String] = []
	for p: Dictionary in list.duplicate():
		if str(p.get("id", "")) != _chest_id(sid):
			continue
		var back: Array[String] = []
		for item: String in (p.get("contents", {}) as Dictionary):
			ItemRules.found(Life.of(s, who, data), data, s.items, item, int(p["contents"][item]))
			back.append(ItemRules.display_name(data["items"], s.items, item))
		list.erase(p)
		lines.append("Каморку освободили" + ((" — вещи из сундука вам отдали: " + ", ".join(back)) if not back.is_empty() else ""))
	s.props[room] = list
	return lines


# --- days ---------------------------------------------------------------------------------------------------------


## Each new day: misses for long gaps, expelled after too many or for a crime in the school's town. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	return Life.each(s, data, "study", tick_of)


## One holder's day (v0.8.4.20): the hero's, or a person's who keeps a part of this life.
static func tick_of(s: GameSession, data: Dictionary, who: String) -> Array[String]:
	var c := Life.of(s, who, data)
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
		var passed := (s.day - int(st["last"])) / (gap + 1)  # each gap missed is a miss, however many went at once
		if passed > 0:
			st["misses"] = int(st["misses"]) + passed
			st["last"] = int(st["last"]) + passed * (gap + 1)
			lines.append("Пропуск занятий: «%s» (%d из %d допустимых)" % [name_of(s, data, id), int(st["misses"]), max_misses])
			if int(st["misses"]) > max_misses:
				out[id] = "за пропуски"
	for sid: String in (school_state(c) as Dictionary).keys():
		var loc := _loc_of_school(data, sid)
		var room := str(school(data, sid).get("dorm", ""))
		if not loc.is_empty() and not room.is_empty() and CrimeRules.wanted_at(s, data, room, who):
			lines.append_array(expel(s, data, sid, "за проступок: вас ищет стража", who))
	for id: String in out:
		if not enrolled(c, id):
			continue
		var sid := str(course(s, data, id).get("school", ""))
		if sid.is_empty():
			view(c)["courses"].erase(id)
			lines.append("Учитель больше не ждёт вас: «%s» — %s" % [name_of(s, data, id), out[id]])
		else:
			lines.append_array(expel(s, data, sid, str(out[id]), who))
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
			parts.append("курс «%s» — %s, %d/%d, пропусков %d" % [name_of(s, data, id), teaches_text(s, data, id), int(st["done"]),
				lessons_needed(s, data, id), int(st.get("misses", 0))])
		for id: Variant in view(c)["done"]:
			parts.append("окончен «%s»" % name_of(s, data, str(id)))
	var teach: Array[String] = []
	for npc: String in s.npcs_here(data["world"], s.room_id):
		for id: String in of_teacher(s, data, npc):
			teach.append("%s учит «%s» (%s)" % [WorldView.name_of(data, npc), name_of(s, data, id), teaches_text(s, data, id)])
	if not teach.is_empty():
		parts.append("здесь: " + "; ".join(teach))
	var away: Array[String] = []
	for id: String in waiting(s, data):
		away.append("«%s» у %s (%s)" % [name_of(s, data, id), WorldView.name_of(data, str(course(s, data, id)["teacher"])), where(s, data, id)])
	if not away.is_empty():
		parts.append("ждут героя: " + "; ".join(away))
	return ("Учёба (окно «Учёба» у учителя, занятия — кнопкой): " + "; ".join(parts)) if not parts.is_empty() else ""


# --- the master's courses -----------------------------------------------------------------------------------------


## A course the master makes: checked against rules.study.make. The teacher is an NPC of the scene or (v0.7.39.7) a
## living teacher of the world the master points to — the course waits for the hero there; a spell, and anything at a
## teacher away, only by TeachRules (its template, trade, `teaches`). A spell course's lessons, fee and the teacher's
## attitude are the engine's; `requires` {attitude, quest, flag, flag_text} — the master's conditions, kept as a `when` row. {plan, summary}
## or {reason}. `teacher_def` — the definition of a person a quest's act is about to bring (a check before it is made).
static func make(s: GameSession, data: Dictionary, spec: Dictionary, teacher_def: Dictionary = {}) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var who := str(spec.get("npc_id", ""))
	var away := teacher_def.is_empty() and not here(s, data, who)
	if away and (BondRules.npc_def(s, data, who).is_empty() or Being.dead(s, who)):
		return {"reason": "%s — нет такого живого NPC в мире: учитель — NPC сцены или найденный find_teachers" % who}
	var kind := str(spec.get("teach_kind", ""))
	if not (m["kinds"] as Array).has(kind):
		return {"reason": "teach_kind — из %s (опыта мастер не даёт)" % ", ".join(m["kinds"])}
	var what := str(spec.get("teach_id", ""))
	var named := TeachRules.resolve(s, data, kind, what)  # v0.7.39.7: «Огненный шар» is fireball
	if not named.is_empty():
		what = named
	var recipe := {}
	if kind == "recipe" and MakeRules.is_property(data, what):
		what = CraftRules.imbue_formula(what)
	if kind == "recipe" and CraftRules.recipe(s, data, what).is_empty():
		var made := _course_recipe(s, data, what, spec.get("recipe"))
		if made.has("reason"):
			return made
		what = str(made.get("id", what))
		recipe = made.get("plan", {})
	var ok := false
	match kind:
		"skill": ok = data["rules"]["skills"].has(what)
		"tool": ok = CraftRules.cfg(data)["tools"].has(what)
		"language": ok = data["misc"]["languages"].has(what)
		"spell": ok = data["spells"].has(what)
		"ability": ok = MakeRules.is_ability(data, what)
		"trait": ok = MakeRules.is_trait(data, what)
		"recipe": ok = not recipe.is_empty() or not CraftRules.recipe(s, data, what).is_empty()
	if not ok:
		return {"reason": _unknown_why(data, kind, what)}
	if kind == "spell" or away or not teacher_def.is_empty():  # v0.7.39.7: a spell or a teacher away — only by what the teacher can teach
		var r_def: Dictionary = recipe.get("def", {})
		var why := TeachRules.why_not_def(s, data, teacher_def, kind, what, r_def) if not teacher_def.is_empty() else TeachRules.why_not(s, data, who, kind, what, r_def)
		if not why.is_empty():
			return {"reason": why + ". Кто учит — find_teachers"}
	var n := int(spec.get("lessons", 4))
	if n < int(m["lessons"][0]) or n > int(m["lessons"][1]):
		return {"reason": "lessons — от %d до %d" % [m["lessons"][0], m["lessons"][1]]}
	var circle := int(data["spells"][what]["level"]) if kind == "spell" else -1
	if circle > 0:
		n = mini(TeachRules.spell_lessons(data, circle, n), int(m["lessons"][1]))
	var tier := str(spec.get("dc_tier", "medium"))
	if not (m["dc_tiers"] as Array).has(tier):
		return {"reason": "dc_tier — из %s" % ", ".join(m["dc_tiers"])}
	var f := int(spec.get("fee_cp", 0))
	if circle > 0:
		f = TeachRules.spell_fee(data, circle, n, f)
	elif f < int(m["fee_cp_lesson"][0]) * n or f > int(m["fee_cp_lesson"][1]) * n:
		return {"reason": "fee_cp — от %s до %s за %d занятий" % [Money.format(int(m["fee_cp_lesson"][0]) * n), Money.format(int(m["fee_cp_lesson"][1]) * n), n]}
	var req := _make_requires(s, data, spec.get("requires"), circle)
	if req.has("reason"):
		return req
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
		return {"reason": "%s уже учит этому — кнопка «Учёба» в его действиях" % WorldView.name_of(data, who)}
	var def := {"name": name, "teacher": who, "teaches": {"kind": kind, "id": what}, "lessons": n, "skill": skill,
		"dc": int(data["rules"]["dc_tiers"][tier]), "fee_cp": f, "generated": true}
	if not (req["requires"] as Dictionary).is_empty():
		def["requires"] = req["requires"]
	var where := (", ждёт у учителя: " + WorldView.new(data["world"]).place_path(Where.base_room(s, data, who))) if away else ""
	return {"plan": {"id": id, "def": def, "recipe": recipe}, "summary": "Курс — %s: «%s», %d занятий, %s%s" % [WorldView.name_of(data, who), name, n,
		Money.format(f) if f > 0 else "бесплатно", where]}


## The conditions of a master's course: its `requires` checked, and the teacher's attitude a spell's circle asks
## (TeachRules). {requires} or {reason}.
static func _make_requires(s: GameSession, data: Dictionary, spec: Variant, circle: int) -> Dictionary:
	var out := {}
	var r: Dictionary = spec if spec is Dictionary else {}
	if r.get("attitude") != null:
		var b := GameSession.attitude_bounds(data)
		var a := int(r["attitude"])
		if a < b.x or a > b.y:
			return {"reason": "requires.attitude — от %d до %d" % [b.x, b.y]}
		out["attitude"] = a
	var need := TeachRules.spell_attitude(data, circle)
	if need > int(out.get("attitude", -99)):
		out["attitude"] = need
	if not str(r.get("quest", "") if r.get("quest") != null else "").is_empty():
		var q := str(r["quest"])
		if not data["world"].get("quests", {}).has(q):
			return {"reason": "requires.quest — id задания мира (%s нет)" % q}
		out["quest"] = q
	if not str(r.get("flag", "") if r.get("flag") != null else "").is_empty():
		out["when"] = {"flag": str(r["flag"])}
		out["when_text"] = str(r.get("flag_text", "") if r.get("flag_text") != null else "").strip_edges().left(80)
	return {"requires": out}


## The recipe a course teaches by an item (v0.7.39.4): the game's recipe of that item, else the course's own `recipe`
## spec (as the effect `recipe`, its output the item) made by CraftRules.make without the hero's proficiency.
## {id} | {id, plan} | {reason}.
static func _course_recipe(s: GameSession, data: Dictionary, item_id: String, spec: Variant) -> Dictionary:
	var known := CraftRules.for_item(s, data, item_id)
	if not known.is_empty():
		return {"id": known}
	if ItemRules.def_of(data["items"], s.items, item_id).is_empty() and not (spec is Dictionary):
		return {"reason": "рецепта %s нет, и такой вещи нет в каталоге: teach_id — рецепт или вещь каталога (find_items)" % item_id}
	if not (spec is Dictionary):
		return {"reason": "у вещи %s нет рецепта в игре — добавь курсу recipe (инструмент, станция, материалы, часы, как в эффекте recipe), выход — эта вещь" % item_id}
	var r: Dictionary = (spec as Dictionary).duplicate()
	if str(r.get("output_id", "")).is_empty() and not (r.get("output") is Dictionary):
		r["output_id"] = item_id
	r["for_course"] = true
	var made := CraftRules.make(s, data, r)
	if made.has("reason"):
		return {"reason": "recipe курса: " + str(made["reason"])}
	return {"id": str(made["id"]), "plan": made}


static func _unknown_why(data: Dictionary, kind: String, what: String) -> String:
	match kind:
		"spell":
			return "заклинания %s нет" % what
		"skill":
			return "навыка %s нет; можно: %s" % [what, ", ".join(data["rules"]["skills"].keys())]
		"tool":
			return "инструмента %s движок не знает; можно: %s" % [what, ", ".join(CraftRules.cfg(data)["tools"].keys())]
		"language":
			return "языка %s нет" % what
	return "рецепта %s нет — teach_id рецепт или вещь каталога" % what


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var all: Dictionary = gen.get("courses", {})
	all[str(plan["id"])] = (plan["def"] as Dictionary).duplicate(true)
	gen["courses"] = all
	var r: Dictionary = plan.get("recipe", {})
	if not r.is_empty():  # the course's own recipe: known to the game, learned only by the course
		if not (gen.get("recipes") is Dictionary):
			gen["recipes"] = {}
		gen["recipes"][str(r["id"])] = r["def"]
		if not (r.get("item", {}) as Dictionary).is_empty():
			s.items[str(r["def"]["output"])] = r["item"]
	return ["%s берёт учеников: «%s» — кнопка «Учёба» в его действиях" % [WorldView.name_of(data, str(plan["def"]["teacher"])), plan["def"]["name"]]]
