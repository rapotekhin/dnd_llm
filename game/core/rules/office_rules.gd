class_name OfficeRules
extends RefCounted
## Offices (roadmap v0.7.34, the author: city service, the army, power over a settlement, the temple; appointed on
## conditions, promoted by merit, elected or bought; decisions instead of shifts; bribes, suspicion and removal).
## An office — world.json `offices` {name, kind, location, room, chief, ways, price_cp, requires, interview, cases,
## ranks, start_rank, town, projects, text}. c.offices {id: {since, merit, last_day, suspicion, cases_day, cases,
## absent_warned, interview_day, removed_day, election_day}}; a town — c.towns {loc: {treasury, discontent, tax,
## builds {project: done_day}}}. Each day `cases_per_day` cases of the office's kinds wait at its room; an option is
## a check or plain effects (rules.office.cases). The day tick pays a week's wage, decays suspicion and runs the
## inquiry, punishes absence, and moves a town's treasury and discontent.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["office"]


static func all(data: Dictionary) -> Dictionary:
	return data["world"].get("offices", {})


static func def(data: Dictionary, id: String) -> Dictionary:
	return all(data).get(id, {})


static func view(c: Dictionary) -> Dictionary:
	return c.get("offices", {})


static func _st(c: Dictionary, id: String) -> Dictionary:
	if not (c.get("offices") is Dictionary):
		c["offices"] = {}
	if not c["offices"].has(id):
		c["offices"][id] = {}
	return c["offices"][id]


static func holds(c: Dictionary, id: String) -> bool:
	return view(c).get(id, {}).has("since")


static func held(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in view(c):
		if holds(c, id):
			out.append(id)
	return out


static func name_of(data: Dictionary, id: String) -> String:
	return str(def(data, id).get("name", id))


static func merit(c: Dictionary, id: String) -> int:
	return int(view(c).get(id, {}).get("merit", 0))


static func rank(c: Dictionary, data: Dictionary, id: String) -> int:
	var r := 0
	var list: Array = def(data, id).get("ranks", [])
	for i in list.size():
		if merit(c, id) >= int(list[i]["at"]):
			r = maxi(r, i)
	return maxi(r, int(view(c).get(id, {}).get("start_rank", 0)))


static func rank_name(c: Dictionary, data: Dictionary, id: String) -> String:
	var list: Array = def(data, id).get("ranks", [])
	return str(list[rank(c, data, id)]["name"]) if not list.is_empty() else name_of(data, id)


static func next_at(c: Dictionary, data: Dictionary, id: String) -> int:
	var list: Array = def(data, id).get("ranks", [])
	var r := rank(c, data, id)
	return int(list[r + 1]["at"]) if r + 1 < list.size() else 0


static func pay(c: Dictionary, data: Dictionary, id: String) -> int:
	var list: Array = def(data, id).get("ranks", [])
	return int(list[rank(c, data, id)].get("pay_cp", 0)) if not list.is_empty() else 0


static func _word(list: Array, v: int) -> String:
	var out := ""
	for w: Dictionary in list:
		if v >= int(w["at"]):
			out = str(w["name"])
	return out


static func suspicion_word(c: Dictionary, data: Dictionary, id: String) -> String:
	return _word(cfg(data)["suspicion_words"], int(view(c).get(id, {}).get("suspicion", 0)))


## The offices whose chief is this NPC.
static func of_chief(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in all(data):
		if str(all(data)[id].get("chief", "")) == npc_id:
			out.append(id)
	return out


## The offices taken by election or bought without a chief in this room.
static func of_room(data: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in all(data):
		if str(all(data)[id].get("room", "")) == room_id and str(all(data)[id].get("chief", "")).is_empty():
			out.append(id)
	return out


# --- getting one --------------------------------------------------------------------------------------------------


## The merit of all the hero's service in a location (held or not).
static func served(c: Dictionary, data: Dictionary, loc: String) -> int:
	var n := 0
	for id: String in view(c):
		if str(def(data, id).get("location", "")) == loc:
			n += merit(c, id)
	return n


## What the office asks: [{text, ok}].
static func requirements(s: GameSession, data: Dictionary, id: String) -> Array[Dictionary]:
	var d := def(data, id)
	var c := s.character
	var req: Dictionary = d.get("requires", {})
	var loc := str(d.get("location", ""))
	var out: Array[Dictionary] = []
	# v0.7.48: a recommendation of the chief or a person of standing stands for the standing (rules.letters.recommend.waives)
	var rec := LetterRules.recommender(s, data, [str(d.get("chief", ""))], true)
	var waives: Array = LetterRules.cfg(data).get("recommend", {}).get("waives", [])
	if req.has("reputation"):
		var ok := ReputationRules.step(s, data, loc) >= int(req["reputation"])
		var by_letter := not ok and not rec.is_empty() and waives.has("reputation")
		out.append({"text": "слава в поселении не ниже «%s»%s" % [ReputationRules.word(data, int(req["reputation"])), (" — рекомендация: " + rec) if by_letter else ""],
			"ok": ok or by_letter})
	if req.has("diploma"):
		out.append({"text": "грамота выпускника: " + StudyRules.name_of(s, data, str(req["diploma"])), "ok": StudyRules.has_diploma(c, str(req["diploma"]))})
	if req.has("skill"):
		out.append({"text": "владение навыком: " + CraftRules.tr_skill(data, str(req["skill"])), "ok": JobRules._skilled(c, str(req["skill"]))})
	if req.has("served"):
		out.append({"text": "заслуги на службе здесь: %d из %d" % [served(c, data, loc), int(req["served"])], "ok": served(c, data, loc) >= int(req["served"])})
	if req.has("bond"):
		var b: Dictionary = req["bond"]
		var ok := BondRules.points(c, str(b["npc"])) >= int(b["at"])
		var by_letter := not ok and not rec.is_empty() and waives.has("bond")
		out.append({"text": "близость с %s от %d%s" % [BondRules.npc_name(s, data, str(b["npc"])), int(b["at"]), (" — рекомендация: " + rec) if by_letter else ""],
			"ok": ok or by_letter})
	return out


static func _away(s: GameSession, data: Dictionary, id: String) -> bool:
	var d := def(data, id)
	if str(d.get("chief", "")).is_empty():
		return s.room_id != str(d.get("room", ""))
	return not BondRules.here(s, data, str(d["chief"]))


static func _base_why(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(data, id)
	if d.is_empty():
		return "OFFICE_UNKNOWN"
	if holds(s.character, id):
		return "OFFICE_HELD"
	if _away(s, data, id):
		return "OFFICE_AWAY"
	var st: Dictionary = view(s.character).get(id, {})
	if st.has("removed_day") and s.day - int(st["removed_day"]) < int(cfg(data)["reapply_days"]):
		return "OFFICE_REMOVED"
	if not str(d.get("chief", "")).is_empty() and SocialRules.refuses(s, data, str(d["chief"])):
		return "TALK_REFUSED"
	return ""


static func appoint_why(s: GameSession, data: Dictionary, id: String) -> String:
	var why := _base_why(s, data, id)
	if not why.is_empty():
		return why
	if not (def(data, id).get("ways", []) as Array).has("appoint"):
		return "OFFICE_NOT_THIS_WAY"
	if requirements(s, data, id).any(func(r: Dictionary) -> bool: return not bool(r["ok"])):
		return "OFFICE_REQUIREMENTS"
	if int(view(s.character).get(id, {}).get("interview_day", -99)) + int(cfg(data)["interview"]["retry_days"]) > s.day:
		return "OFFICE_TRIED"
	return ""


## The interview's skill and DC ({} — none).
static func interview(data: Dictionary, id: String) -> Dictionary:
	var iv: Variant = def(data, id).get("interview", false)
	if iv is Dictionary:
		return {"skill": str(iv["skill"]), "dc": int(data["rules"]["dc_tiers"][str(iv.get("tier", "medium"))])}
	if iv == true:
		return {"skill": str(cfg(data)["interview"]["skill"]), "dc": int(data["rules"]["dc_tiers"][str(cfg(data)["interview"]["tier"])])}
	return {}


static func appoint_chance(s: GameSession, data: Dictionary, id: String) -> int:
	var iv := interview(data, id)
	if iv.is_empty():
		return 100
	return JobRules._chance(CheckEngine.bonus_for(s.character, {"skill": iv["skill"]}) + DifficultyRules.bonus(s, data), int(iv["dc"]), false)


## Asked for the office at its chief (appoint_why first). Lines.
static func appoint(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var lines: Array[String] = []
	var iv := interview(data, id)
	if not iv.is_empty():
		var r := EncounterRules.roll(s, data, str(iv["skill"]), int(iv["dc"]))
		lines.append("%s: %s" % [name_of(data, id), r["line"]])
		if not bool(r["ok"]):
			_st(s.character, id)["interview_day"] = s.day
			lines.append("Не взяли — можно попросить снова завтра")
			return lines
	lines.append_array(_take(s, data, id, "назначен"))
	return lines


static func _take(s: GameSession, data: Dictionary, id: String, how: String) -> Array[String]:
	var d := def(data, id)
	var st := _st(s.character, id)
	st["since"] = s.day
	st["last_day"] = s.day
	st.erase("removed_day")
	st.erase("cases")
	st.erase("absent_warned")
	st["suspicion"] = int(st.get("suspicion", 0))
	var start: Dictionary = d.get("start_rank", {})
	st["start_rank"] = int(start.get(str(s.character.get("background", "")), 0))
	if bool(d.get("town", false)):
		town(s, data, str(d["location"]))
	if not str(d.get("chief", "")).is_empty():
		s.remember(str(d["chief"]), "герой служит: %s" % name_of(data, id))
	return ["%s — %s: %s, жалованье %s в неделю" % [name_of(data, id), how, rank_name(s.character, data, id), Money.format(pay(s.character, data, id))]]


static func election_dc(s: GameSession, data: Dictionary, id: String) -> int:
	var e: Dictionary = cfg(data)["election"]
	return int(e["dc"]) - int(e["per_rep"]) * ReputationRules.step(s, data, str(def(data, id).get("location", "")))


static func elect_why(s: GameSession, data: Dictionary, id: String) -> String:
	var why := _base_why(s, data, id)
	if not why.is_empty():
		return why
	if not (def(data, id).get("ways", []) as Array).has("election"):
		return "OFFICE_NOT_THIS_WAY"
	if requirements(s, data, id).any(func(r: Dictionary) -> bool: return not bool(r["ok"])):
		return "OFFICE_REQUIREMENTS"
	var st: Dictionary = view(s.character).get(id, {})
	if st.has("election_day") and s.day - int(st["election_day"]) < int(cfg(data)["election"]["retry_days"]):
		return "OFFICE_ELECTION_SOON"
	if int(s.character.get("gold_cp", 0)) < int(cfg(data)["election"]["fee_cp"]):
		return "TRADE_ERR_NO_COINS"
	return ""


static func elect_chance(s: GameSession, data: Dictionary, id: String) -> int:
	var b := CheckEngine.bonus_for(s.character, {"skill": str(cfg(data)["election"]["skill"])}) + DifficultyRules.bonus(s, data)
	return JobRules._chance(b, election_dc(s, data, id), false)


## The election: the fee for the feast and the speech, a check against the reputation. Lines.
static func elect(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var e: Dictionary = cfg(data)["election"]
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(e["fee_cp"])
	_st(s.character, id)["election_day"] = s.day
	var r := EncounterRules.roll(s, data, str(e["skill"]), election_dc(s, data, id))
	var lines: Array[String] = ["Сход выбирает: %s — угощение %s, речь: %s" % [name_of(data, id), Money.format(int(e["fee_cp"])), r["line"]]]
	if not bool(r["ok"]):
		lines.append("Сход выбрал другого — следующий сход через %d дн." % int(e["retry_days"]))
		return lines
	lines.append_array(_take(s, data, id, "выбран сходом"))
	return lines


static func buy_why(s: GameSession, data: Dictionary, id: String) -> String:
	var why := _base_why(s, data, id)
	if not why.is_empty():
		return why
	if not (def(data, id).get("ways", []) as Array).has("buy"):
		return "OFFICE_NOT_THIS_WAY"
	if int(s.character.get("gold_cp", 0)) < int(def(data, id).get("price_cp", 0)):
		return "TRADE_ERR_NO_COINS"
	return ""


## The office bought with a bribe: no conditions, but whispers from the first day. Lines.
static func buy(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var price := int(def(data, id).get("price_cp", 0))
	s.character["gold_cp"] = int(s.character["gold_cp"]) - price
	var lines := _take(s, data, id, "куплено за %s" % Money.format(price))
	_st(s.character, id)["suspicion"] = int(_st(s.character, id).get("suspicion", 0)) + int(cfg(data)["buy"]["suspicion"])
	lines.append("О купленном месте шепчутся")
	return lines


static func leave(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	_remove(s, id)
	return ["Вы оставили службу: %s" % name_of(data, id)]


static func _remove(s: GameSession, id: String) -> void:
	var st := _st(s.character, id)
	st.erase("since")
	st.erase("cases")
	st["removed_day"] = s.day


# --- the day's cases ----------------------------------------------------------------------------------------------


## The people of the location a case may be about.
static func _people(s: GameSession, data: Dictionary, loc: String) -> Array[String]:
	var out: Array[String] = []
	for n: String in data["world"]["npcs"]:
		if ReputationRules.home_of(data, n) == loc and not s.dead_npcs.has(n):
			out.append(n)
	return out


## Today's cases of the office (made on the first look of the day): [{kind, title, who, done}].
static func today(s: GameSession, data: Dictionary, id: String) -> Array:
	var st := _st(s.character, id)
	if int(st.get("cases_day", -1)) == s.day and st.has("cases"):
		return st["cases"]
	var d := def(data, id)
	var kinds: Array = d.get("cases", [])
	var people := _people(s, data, str(d.get("location", "")))
	var list: Array = []
	for i in int(cfg(data)["cases_per_day"]):
		if kinds.is_empty():
			break
		var k := str(kinds[s.rng.randi_range(0, kinds.size() - 1)])
		var kd: Dictionary = cfg(data)["cases"][k]
		var who := people[s.rng.randi_range(0, people.size() - 1)] if not people.is_empty() else ""
		people.erase(who)  # one petitioner a day
		var titles: Array = kd["titles"]
		var title := str(titles[s.rng.randi_range(0, titles.size() - 1)]).format({"who": BondRules.npc_name(s, data, who) if not who.is_empty() else "проситель"})
		list.append({"kind": k, "title": title, "who": who, "done": false})
	st["cases"] = list
	st["cases_day"] = s.day
	return list


static func option(data: Dictionary, kind: String, opt: String) -> Dictionary:
	for o: Dictionary in cfg(data)["cases"].get(kind, {}).get("options", []):
		if str(o["id"]) == opt:
			return o
	return {}


static func decide_why(s: GameSession, data: Dictionary, id: String, idx: int, opt: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	if not holds(s.character, id):
		return "OFFICE_NOT_HELD"
	if s.room_id != str(def(data, id).get("room", "")):
		return "OFFICE_NOT_THERE"
	var list := today(s, data, id)
	if idx < 0 or idx >= list.size() or bool(list[idx]["done"]):
		return "OFFICE_CASE_DONE"
	var o := option(data, str(list[idx]["kind"]), opt)
	if o.is_empty():
		return "OFFICE_UNKNOWN"
	var cost := -int(o.get("effects", {}).get("treasury_cp", 0))
	if cost > 0 and int(town(s, data, str(def(data, id)["location"]))["treasury"]) < cost:
		return "OFFICE_NO_TREASURY"
	return ""


static func option_chance(s: GameSession, data: Dictionary, o: Dictionary) -> int:
	if not o.has("check"):
		return 100
	var ch: Dictionary = o["check"]
	var b := CheckEngine.bonus_for(s.character, {"skill": str(ch["skill"])}) + DifficultyRules.bonus(s, data)
	return JobRules._chance(b, int(data["rules"]["dc_tiers"][str(ch.get("tier", "medium"))]), false)


## One decision (decide_why first; its time already passed). Lines.
static func decide(s: GameSession, data: Dictionary, id: String, idx: int, opt: String) -> Array[String]:
	var case: Dictionary = today(s, data, id)[idx]
	var o := option(data, str(case["kind"]), opt)
	var lines: Array[String] = ["%s: %s — %s" % [name_of(data, id), case["title"], o["name"]]]
	var fx: Dictionary = o.get("effects", {})
	if o.has("check"):
		var ch: Dictionary = o["check"]
		var r := EncounterRules.roll(s, data, str(ch["skill"]), int(data["rules"]["dc_tiers"][str(ch.get("tier", "medium"))]))
		lines.append(str(r["line"]))
		fx = o["ok"] if bool(r["ok"]) else o.get("fail", {})
	case["done"] = true
	var st := _st(s.character, id)
	st["last_day"] = s.day
	st.erase("absent_warned")
	lines.append_array(_apply(s, data, id, str(case.get("who", "")), fx))
	return lines


static func _apply(s: GameSession, data: Dictionary, id: String, who: String, fx: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	var st := _st(c, id)
	var loc := str(def(data, id).get("location", ""))
	if fx.has("merit"):
		var before := rank(c, data, id)
		st["merit"] = maxi(0, merit(c, id) + int(fx["merit"]))
		if rank(c, data, id) > before:
			lines.append("%s: вы теперь — %s, жалованье %s в неделю" % [name_of(data, id), rank_name(c, data, id), Money.format(pay(c, data, id))])
	if int(fx.get("pocket_cp", 0)) > 0:
		c["gold_cp"] = int(c.get("gold_cp", 0)) + int(fx["pocket_cp"])
		lines.append("В карман: %s" % Money.format(int(fx["pocket_cp"])))
	if fx.has("suspicion"):
		st["suspicion"] = int(st.get("suspicion", 0)) + int(fx["suspicion"])
	if fx.has("treasury_cp") or fx.has("discontent"):
		var t := town(s, data, loc)
		t["treasury"] = int(t["treasury"]) + int(fx.get("treasury_cp", 0))
		t["discontent"] = clampi(int(t["discontent"]) + int(fx.get("discontent", 0)), 0, 100)
		if int(fx.get("treasury_cp", 0)) != 0:
			lines.append("Казна: %s%s" % ["+" if int(fx["treasury_cp"]) > 0 else "−", Money.format(absi(int(fx["treasury_cp"])))])
	if int(fx.get("attitude", 0)) != 0 and not who.is_empty():
		s.shift_attitude(who, int(fx["attitude"]), data)
		s.remember(who, "герой решал его дело на службе: %s" % ("в его пользу" if int(fx["attitude"]) > 0 else "против него"))
	if int(fx.get("rep", 0)) != 0:
		lines.append_array(ReputationRules.add(s, data, loc, int(fx["rep"]), name_of(data, id).to_lower()))
	if fx.has("flag") and not s.flags.has(str(fx["flag"])):
		s.flags.append(str(fx["flag"]))
	return lines


# --- a town -------------------------------------------------------------------------------------------------------


## The town of a location as the hero's office sees it (made on first need).
static func town(s: GameSession, data: Dictionary, loc: String) -> Dictionary:
	var c := s.character
	if not (c.get("towns") is Dictionary):
		c["towns"] = {}
	if not c["towns"].has(loc):
		c["towns"][loc] = {"treasury": int(cfg(data)["town"]["treasury_cp"]), "discontent": 0, "tax": "normal", "builds": {}, "last_day": s.day}
	return c["towns"][loc]


static func headman_of(c: Dictionary, data: Dictionary, loc: String) -> String:
	for id: String in held(c):
		if bool(def(data, id).get("town", false)) and str(def(data, id)["location"]) == loc:
			return id
	return ""


static func tax_why(s: GameSession, data: Dictionary, id: String, level: String) -> String:
	if not holds(s.character, id) or not bool(def(data, id).get("town", false)):
		return "OFFICE_NOT_HELD"
	if not (cfg(data)["town"]["taxes"] as Dictionary).has(level):
		return "OFFICE_UNKNOWN"
	if str(town(s, data, str(def(data, id)["location"]))["tax"]) == level:
		return "OFFICE_TAX_SAME"
	return ""


static func set_tax(s: GameSession, data: Dictionary, id: String, level: String) -> Array[String]:
	town(s, data, str(def(data, id)["location"]))["tax"] = level
	return ["%s: подать теперь %s" % [str(data["world"]["locations"][str(def(data, id)["location"])].get("name", "")), cfg(data)["town"]["taxes"][level]["name"]]]


static func project(data: Dictionary, id: String, pid: String) -> Dictionary:
	for p: Dictionary in def(data, id).get("projects", []):
		if str(p["id"]) == pid:
			return p
	return {}


static func build_why(s: GameSession, data: Dictionary, id: String, pid: String) -> String:
	if not holds(s.character, id) or not bool(def(data, id).get("town", false)):
		return "OFFICE_NOT_HELD"
	var p := project(data, id, pid)
	if p.is_empty():
		return "OFFICE_UNKNOWN"
	if s.room_id != str(def(data, id)["room"]):
		return "OFFICE_NOT_THERE"
	var t := town(s, data, str(def(data, id)["location"]))
	if (t["builds"] as Dictionary).has(pid):
		return "OFFICE_BUILT"
	if int(t["treasury"]) < int(p["cost_cp"]):
		return "OFFICE_NO_TREASURY"
	return ""


static func build(s: GameSession, data: Dictionary, id: String, pid: String) -> Array[String]:
	var p := project(data, id, pid)
	var t := town(s, data, str(def(data, id)["location"]))
	t["treasury"] = int(t["treasury"]) - int(p["cost_cp"])
	t["builds"][pid] = s.day + int(p["days"])
	return ["Стройка: %s — из казны %s, готово через %d дн." % [p["name"], Money.format(int(p["cost_cp"])), int(p["days"])]]


# --- days ---------------------------------------------------------------------------------------------------------


## Wages, suspicion and the inquiry, absence, towns. Day by day from each office's last tick. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	if not data["rules"].has("office"):
		return []
	var lines: Array[String] = []
	var c := s.character
	for id: String in held(c):
		var st := _st(c, id)
		var last := int(st.get("tick_day", st["since"]))
		st["tick_day"] = s.day
		for day in range(last + 1, s.day + 1):
			if not holds(c, id):
				break
			lines.append_array(_day(s, data, id, st, day))
	if c.get("towns") is Dictionary:
		for loc: String in c["towns"]:
			var t: Dictionary = c["towns"][loc]
			var last := int(t.get("last_day", s.day))
			t["last_day"] = s.day
			for day in range(last + 1, s.day + 1):
				lines.append_array(_town_day(s, data, loc, t, day))
	return lines


static func _day(s: GameSession, data: Dictionary, id: String, st: Dictionary, day: int) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	if (day - int(st["since"])) % 7 == 0:
		c["gold_cp"] = int(c.get("gold_cp", 0)) + pay(c, data, id)
		lines.append("%s: жалованье за неделю — %s" % [name_of(data, id), Money.format(pay(c, data, id))])
	st["suspicion"] = maxi(0, int(st.get("suspicion", 0)) - int(cfg(data)["suspicion_decay"]))
	if int(st["suspicion"]) >= int(cfg(data)["inquiry_at"]):
		lines.append_array(_inquiry(s, data, id, st))
		if not holds(c, id):
			return lines
	var away := day - int(st.get("last_day", st["since"]))
	if away > int(cfg(data)["remove_absent_days"]):
		_remove(s, id)
		lines.append("%s: вас сняли — %d дн. без службы" % [name_of(data, id), away])
	elif away > int(cfg(data)["absent_days"]) and not bool(st.get("absent_warned", false)):
		st["absent_warned"] = true
		st["merit"] = maxi(0, merit(c, id) + int(cfg(data)["absent_merit"]))
		lines.append("%s: вас не видно на службе — заслуги падают; ещё неделя — и снимут" % name_of(data, id))
	return lines


static func _inquiry(s: GameSession, data: Dictionary, id: String, st: Dictionary) -> Array[String]:
	var iq: Dictionary = cfg(data)["inquiry"]
	var r := EncounterRules.roll(s, data, str(iq["skill"]), int(data["rules"]["dc_tiers"][str(iq["tier"])]))
	var lines: Array[String] = ["%s: разбирательство о мзде — %s" % [name_of(data, id), r["line"]]]
	if bool(r["ok"]):
		st["suspicion"] = int(cfg(data)["inquiry_at"]) / 2
		lines.append("Отговорились — но за вами следят")
		return lines
	var d := def(data, id)
	_remove(s, id)
	lines.append("Вас сняли с должности")
	lines.append_array(CrimeRules.on_job(s, data, str(cfg(data)["crime"]), str(d.get("chief", "")), str(d["room"]), str(d["location"])))
	return lines


static func _town_day(s: GameSession, data: Dictionary, loc: String, t: Dictionary, day: int) -> Array[String]:
	var lines: Array[String] = []
	var tc: Dictionary = cfg(data)["town"]
	var tax: Dictionary = tc["taxes"][str(t.get("tax", "normal"))]
	t["treasury"] = int(t["treasury"]) + int(tax["income_cp"])
	var drift := int(tax["discontent"]) - int(tc["decay"]) if int(t["discontent"]) > 0 else int(tax["discontent"])
	t["discontent"] = clampi(int(t["discontent"]) + drift, 0, 100)
	var head := headman_of(s.character, data, loc)
	for pid: String in (t["builds"] as Dictionary).keys():
		var done := int(t["builds"][pid])
		if done == day and not head.is_empty():
			var p := project(data, head, pid)
			if not p.is_empty():
				if not s.flags.has(str(p["flag"])):
					s.flags.append(str(p["flag"]))
				t["discontent"] = clampi(int(t["discontent"]) + int(p.get("discontent", 0)), 0, 100)
				lines.append("Достроено: %s" % p["name"])
	if not head.is_empty() and int(t["discontent"]) >= int(tc["remove_at"]):
		_remove(s, head)
		t["discontent"] = 50
		lines.append("%s: сход снял вас — народ на грани бунта" % name_of(data, head))
	return lines


# --- for the master -----------------------------------------------------------------------------------------------


static func text(s: GameSession, data: Dictionary) -> String:
	if not data["rules"].has("office"):
		return ""
	var c := s.character
	var parts: Array[String] = []
	for id: String in held(c):
		var p := "%s — %s (заслуги %d, о мзде: %s)" % [name_of(data, id), rank_name(c, data, id), merit(c, id), suspicion_word(c, data, id)]
		if bool(def(data, id).get("town", false)):
			var t := town(s, data, str(def(data, id)["location"]))
			p += ", казна %s, народ %s, подать %s" % [Money.format(int(t["treasury"])), _word(cfg(data)["discontent_words"], int(t["discontent"])),
				cfg(data)["town"]["taxes"][str(t["tax"])]["name"]]
		parts.append(p)
	for npc: String in SceneRules.npcs(s, data["world"], s.room_id):
		for id: String in of_chief(data, npc):
			if not holds(c, id):
				parts.append("%s даёт место: %s" % [BondRules.npc_name(s, data, npc), name_of(data, id)])
	for id: String in of_room(data, s.room_id):
		if not holds(c, id):
			parts.append("здесь выбирают: %s" % name_of(data, id))
	if parts.is_empty():
		return ""
	return "Служба (окно «Служба»: решения, назначение, выборы — кнопки): " + "; ".join(parts)
