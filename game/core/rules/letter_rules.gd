class_name LetterRules
extends RefCounted
## Letters and messengers (roadmap v0.7.48). A letter is a concept of the engine: the hero writes to an NPC with a
## purpose; the purposes are data (rules.letters.purposes): who can answer it (a bond, the family, the law, a person
## of standing) and what the engine does with it (`does`: closeness, an ally, an arrest, a recommendation). It goes
## from a person with a post (an NPC's `post`: the ways it sends by — the scribe's post, a hired courier) along the
## map's roads: days and a price by the hops, a risk per wild location on the way (no law there) — a lost letter lies
## in the mud of that place with its text, to be found. Delivered, the engine decides what it can at a distance (the
## verdict); on the reply day the master writes the answer in a turn of its own (`letter`) from the NPC's memory and
## the verdict, and where the purpose leaves a choice it answers `letter_reply` yes or no. The state lives in
## `generated.letters` {list {id: letter}, seq, word {npc: day of the last letter}, home_day}.


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("rules", {}).get("letters", {})


static func on(data: Dictionary) -> bool:
	return not cfg(data).is_empty()


static func _state(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("letters"):
		gen["letters"] = {"list": {}, "seq": 0, "word": {}, "home_day": s.day}
	return gen["letters"]


static func get_letter(s: GameSession, id: String) -> Dictionary:
	return _state(s)["list"].get(id, {})


static func letters(s: GameSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in _state(s)["list"].values():
		out.append(l)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(str(a["id"]).substr(1)) > int(str(b["id"]).substr(1)))
	return out


static func purpose(data: Dictionary, id: String) -> Dictionary:
	return cfg(data).get("purposes", {}).get(id, {})


static func _name(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return BondRules.npc_name(s, data, npc_id)


static func _loc(data: Dictionary, room_id: String) -> String:
	return WorldView.new(data["world"]).location_id(room_id)


static func _loc_name(data: Dictionary, loc: String) -> String:
	return str(data["world"]["locations"].get(loc, {}).get("name", loc))


static func _room_name(data: Dictionary, room: String) -> String:
	return str(data["world"]["rooms"].get(room, {}).get("name", room))


# --- the post -----------------------------------------------------------------------------------------------------


## The ways an NPC sends letters by (its `post`).
static func ways_of(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	if not on(data):
		return out
	for w: Variant in data["world"]["npcs"].get(npc_id, {}).get("post", []):
		if cfg(data)["ways"].has(str(w)):
			out.append(str(w))
	return out


## Where an NPC is now: a follower — with the hero; one placed or travelling — there (the road — its home); else home.
static func npc_loc(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if s.followers.has(npc_id):
		return _loc(data, s.room_id)
	var at := str(s.npc_at.get(npc_id, ""))
	if not at.is_empty() and data["world"]["rooms"].has(at):
		return _loc(data, at)
	var home := ReputationRules.home_room(data, npc_id)
	if home.is_empty():
		home = str(FamilyRules.view(s.character).get("home_room", "")) if FamilyRules.household(s, data).any(
			func(h: Dictionary) -> bool: return str(h.get("npc", "")) == npc_id) else ""
	return _loc(data, home) if not home.is_empty() else ""


## The locations a letter passes from `from` to `to` along the map's roads, both ends included; [] — no road.
static func route(data: Dictionary, from: String, to: String) -> Array[String]:
	var out: Array[String] = []
	if from.is_empty() or to.is_empty():
		return out
	var parent := {from: ""}
	var queue: Array[String] = [from]
	var g := RumorRules.roads(data)
	while not queue.is_empty() and not parent.has(to):
		var at: String = queue.pop_front()
		for nb: Variant in g.get(at, []):
			if not parent.has(str(nb)):
				parent[str(nb)] = at
				queue.append(str(nb))
	if not parent.has(to):
		return out
	var at := to
	while not at.is_empty():
		out.push_front(at)
		at = str(parent[at])
	return out


## A wild location: no law keeps its roads.
static func wild(data: Dictionary, loc: String) -> bool:
	return CrimeRules.law(data, loc).is_empty()


## The price, the days and the risk of a letter by `way` from the hero's location to `to`: {cost, days, risk, hops}
## or {} when no road leads there.
static func quote(s: GameSession, data: Dictionary, way: String, to: String) -> Dictionary:
	var w: Dictionary = cfg(data)["ways"].get(way, {})
	var path := route(data, _loc(data, s.room_id), npc_loc(s, data, to))
	if w.is_empty() or path.is_empty():
		return {}
	var hops := path.size() - 1
	var risk := 0
	for loc: String in path.slice(1):
		if wild(data, loc):
			risk += int(w["lose_pct"])
	return {"cost": int(w["base_cp"]) + int(w["per_hop_cp"]) * hops, "days": maxi(int(w["min_days"]), hops * int(w["days_per_hop"])),
		"risk": mini(risk, int(cfg(data)["risk_max_pct"])), "hops": hops}


## The people the hero may write to: met (talked to, remembered, seen in a visited room), alive, not here.
static func recipients(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var w := WorldView.new(data["world"])
	var here := s.npcs_here(data["world"], s.room_id)
	var met: Array[String] = []
	for key: String in s.summaries:
		if key.begins_with("dialogue:"):
			met.append(key.get_slice(":", 1))
	for npc: String in s.npc_memory.keys():
		met.append(npc)
	for room_id: String in s.visited:
		met.append_array(w.npcs_in(room_id))
	met.append_array(FamilyRules.household(s, data).map(func(h: Dictionary) -> String: return str(h.get("npc", ""))))
	for npc: String in met:
		if out.has(npc) or w.npc(npc).is_empty() or s.dead_npcs.has(npc) or here.has(npc) or s.followers.has(npc) or npc_loc(s, data, npc).is_empty():
			continue
		out.append(npc)
	return out


## The law's people the hero may denounce to: the guards of a location's law.
static func law_people(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for loc: String in data["world"]["locations"]:
		for g: Variant in CrimeRules.law(data, loc).get("guards", []):
			if not out.has(str(g)):
				out.append(str(g))
	return out


## The location of the law an NPC serves ("" — none).
static func law_of(data: Dictionary, npc_id: String) -> String:
	for loc: String in data["world"]["locations"]:
		if (CrimeRules.law(data, loc).get("guards", []) as Array).has(npc_id):
			return loc
	return ""


## "" when the hero may send this letter at `poster` now, or why not (a line for the player).
static func send_why(s: GameSession, data: Dictionary, poster: String, to: String, pid: String, text: String, way: String, extra: Dictionary = {}) -> String:
	if not on(data):
		return "писем в этих правилах нет"
	if not ways_of(data, poster).has(way):
		return "здесь так письма не отправляют"
	if not s.npcs_here(data["world"], s.room_id).has(poster):
		return "отправить письмо можно только у %s" % _name(s, data, poster)
	var p := purpose(data, pid)
	if p.is_empty():
		return "нет такой цели письма"
	if not recipients(s, data).has(to):
		return "этому человеку не написать: герой его не знает, или он здесь — скажите сами"
	var words := text.strip_edges()
	if words.length() < int(cfg(data)["text_min"]) or words.length() > int(cfg(data)["text_max"]):
		return "письмо — от %d до %d знаков" % [int(cfg(data)["text_min"]), int(cfg(data)["text_max"])]
	if bool(p.get("law", false)) and not law_people(data).has(to):
		return "донос пишут страже: %s" % ", ".join(law_people(data).map(func(n: String) -> String: return _name(s, data, n)))
	if str(p.get("does", "")) == "arrest":
		var about := str(extra.get("about", ""))
		if about.is_empty() or about == to or data["world"]["npcs"].get(about, {}).is_empty() or s.dead_npcs.has(about):
			return "на кого донос — выберите человека"
	if str(p.get("does", "")) == "ally":
		var room := str(extra.get("room", ""))
		if room.is_empty() or not s.visited.has(room):
			return "куда прийти — выберите место, где герой бывал"
	var q := quote(s, data, way, to)
	if q.is_empty():
		return "до %s не дойти: нет дороги" % _name(s, data, to)
	if int(s.character.get("gold_cp", 0)) < int(q["cost"]):
		return "не хватает денег: %s" % Money.format(int(q["cost"]))
	return ""


## The hero sends a letter: the coins, the time to write, a letter on its way. Lines.
static func send(s: GameSession, data: Dictionary, poster: String, to: String, pid: String, text: String, way: String, extra: Dictionary = {}) -> Array[String]:
	var q := quote(s, data, way, to)
	var st := _state(s)
	st["seq"] = int(st["seq"]) + 1
	var l := {"id": "l%d" % int(st["seq"]), "to": to, "purpose": pid, "text": text.strip_edges(), "way": way, "cost": int(q["cost"]),
		"risk": int(q["risk"]), "sent_day": s.day, "sent_loc": _loc(data, s.room_id), "deliver_day": s.day + int(q["days"]),
		"reply_day": s.day + int(q["days"]) * 2 + (0 if int(q["days"]) > 0 else 1), "status": "en_route", "room": str(extra.get("room", "")),
		"about": str(extra.get("about", "")), "evidence": "", "verdict": "", "can": false, "decision": "", "reply": "", "outcome": []}
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(q["cost"])
	var lines: Array[String] = []
	if str(purpose(data, pid).get("does", "")) == "arrest":  # the evidence the hero carries goes with the letter
		var item := _evidence_item(s, data, str(l["about"]))
		if not item.is_empty():
			l["evidence"] = item
			var left := int(s.character["inventory"].get(item, 0)) - 1
			if left > 0:
				s.character["inventory"][item] = left
			else:
				s.character["inventory"].erase(item)
			lines.append("К письму приложено: %s" % ItemRules.display_name(data["items"], s.items, item))
	st["list"][str(l["id"])] = l
	lines.push_front("Письмо → %s (%s) отправлено %s за %s — дойдёт к %d-му дню, ответ — не раньше %d-го" % [_name(s, data, to),
		purpose(data, pid)["name"], cfg(data)["ways"][way]["name"], Money.format(int(q["cost"])), int(l["deliver_day"]), int(l["reply_day"])])
	lines.append_array(TimeRules.advance(s, data, int(cfg(data)["write_minutes"])))
	return lines


# --- the delivery -------------------------------------------------------------------------------------------------


## The days pass: letters reach their people or get lost on a wild road, a denounced one is taken, a helper comes to
## the place and waits, a silent family worries. Lines for the hero.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	var here := _loc(data, s.room_id)
	for l: Dictionary in letters(s):
		if str(l["status"]) == "en_route" and s.day >= int(l["deliver_day"]):
			if s.rng.randi_range(1, 100) <= int(l["risk"]):
				_lose(s, data, l)
			else:
				_deliver(s, data, l)
		if l.has("arrest") and not bool(l["arrest"].get("done", false)) and s.day >= int(l["arrest"]["day"]):
			lines.append_array(_arrest(s, data, l, here))
		if l.has("ally"):
			lines.append_array(_ally_day(s, data, l))
	lines.append_array(_jail_days(s, data))
	lines.append_array(_family(s, data))
	return lines


static func _lose(s: GameSession, data: Dictionary, l: Dictionary) -> void:
	l["status"] = "lost"
	var path := route(data, str(l["sent_loc"]), npc_loc(s, data, str(l["to"])))
	var where := ""
	for loc: String in path.slice(1):
		if wild(data, loc):
			where = loc
			break
	var rooms: Array[String] = []
	for rid: String in data["world"]["rooms"]:
		if str(data["world"]["rooms"][rid].get("location_id", "")) == where:
			rooms.append(rid)
	if rooms.is_empty():
		return
	rooms.sort()
	var room := rooms[s.rng.randi_range(0, rooms.size() - 1)]
	var lost: Dictionary = cfg(data)["lost_item"]
	var def := {"name": str(lost["name"]).format({"to": _name(s, data, str(l["to"]))}), "item_type": "quest", "weight": 0, "value_cp": 0,
		"description": str(lost["description"]), "text": str(l["text"]), "generated": true, "letter": str(l["id"])}
	var id := ItemRules.generated_id(def)
	s.items[id] = def
	var list: Array = s.props.get(room, [])
	list.append({"id": "lost_" + str(l["id"]), "name": def["name"], "description": def["description"], "item_id": id, "owner": "",
		"text": "", "state": "", "dropped": true, "dropped_at": TimeRules.abs_minute(s), "lost": true})
	s.props[room] = list
	l["lost_room"] = room


## The letter reached its person: the engine's verdict on what it can do at a distance, and what needs no answer.
static func _deliver(s: GameSession, data: Dictionary, l: Dictionary) -> void:
	l["status"] = "delivered"
	var to := str(l["to"])
	var p := purpose(data, str(l["purpose"]))
	var v := verdict(s, data, l)
	l["can"] = bool(v["can"])
	l["verdict"] = str(v["text"])
	var last := int(_state(s)["word"].get(to, -9999))
	_state(s)["word"][to] = s.day
	if FamilyRules.spouse(s) == to or FamilyRules.children(s).has(to):
		_state(s)["home_day"] = s.day  # the family heard from the hero
	match str(p.get("does", "")):
		"closeness":
			if bool(v["can"]) and s.day - last >= int(p.get("cooldown_days", 0)):
				l["outcome"].append_array(BondRules.add(s, data, to, int(p["bond"]), "письмо"))
		"arrest":
			var about := str(l["about"])
			if bool(v["can"]):
				l["arrest"] = {"npc": about, "day": int(l["deliver_day"]) + int(p["arrest_days"]), "loc": law_of(data, to), "done": false}
			elif str(v.get("false", "")) == "yes":
				l["outcome"].append_array(CrimeRules.on_false_report(s, data, about, law_of(data, to)))
	l["outcome"] = (l["outcome"] as Array).map(func(x: Variant) -> String: return str(x))


## What the person can do at a distance for this letter: {can, text, false?} — the engine's, the master answers by it.
static func verdict(s: GameSession, data: Dictionary, l: Dictionary) -> Dictionary:
	var to := str(l["to"])
	var p := purpose(data, str(l["purpose"]))
	var c := s.character
	var who := _name(s, data, to)
	if SocialRules.refuses(s, data, to):
		return {"can": false, "text": "%s враждебен герою — ничего не сделает" % who}
	var family := FamilyRules.spouse(s) == to or FamilyRules.children(s).has(to)
	var bond := BondRules.points(c, to)
	match str(p.get("does", "")):
		"closeness":
			return {"can": true, "text": "письмо дошло; близость растёт, если писали не только что"}
		"ally":
			if s.dead_npcs.has(to) or jailed(s, to):
				return {"can": false, "text": "%s не может прийти: под стражей" % who}
			if (family and bool(p.get("family", false))) or bond >= int(p["min_bond"]):
				var road := maxi(1, (route(data, npc_loc(s, data, to), _loc(data, str(l["room"]))).size() - 1) * int(p["days_per_hop"]))
				return {"can": true, "text": "%s может прийти: «%s» (%s), дорога — %d дн. от ответа — решай: `letter_reply` yes или no" % [who,
					_room_name(data, str(l["room"])), "семья" if family else BondRules.word(c, data, to), road]}
			return {"can": false, "text": "%s не пойдёт на помощь: близость %d (нужно %d) — только вежливый отказ" % [who, bond, int(p["min_bond"])]}
		"arrest":
			var about := str(l["about"])
			var proof := evidence(s, data, about, str(l.get("evidence", "")))
			if not proof.is_empty():
				return {"can": true, "text": "дело заведено: улика — %s; под стражу возьмут: %s" % [proof, _name(s, data, about)]}
			if guilty(s, data, about):
				return {"can": false, "text": "улик нет — дела не будет; на слово стража не верит"}
			return {"can": false, "false": "yes", "text": "донос ложный: %s ни в чём таком не замечен — это преступление героя (ложный донос)" % _name(s, data, about)}
		"recommendation":
			if not notable(s, data, to):
				return {"can": false, "text": "%s — не того положения, чтобы её рекомендация что-то значила" % who}
			if bond >= int(p["min_bond"]) or (bool(p.get("mentor", false)) and BondRules.kind(c, to) == "mentor"):
				return {"can": true, "text": "%s может дать рекомендацию — решай: `letter_reply` yes или no" % who}
			return {"can": false, "text": "%s не поручится за героя: близость %d (нужно %d) — только отказ" % [who, bond, int(p["min_bond"])]}
	return {"can": false, "text": ""}


# --- the reply turn -----------------------------------------------------------------------------------------------


## The first letter whose reply is due — its id, or "".
static func due(s: GameSession, data: Dictionary) -> String:
	if not on(data):
		return ""
	var list := letters(s)
	list.reverse()  # the oldest first
	for l: Dictionary in list:
		if str(l["status"]) == "delivered" and s.day >= int(l["reply_day"]):
			return str(l["id"])
	return ""


## The input of the master's `letter` turn: the letter, the person, the engine's verdict.
static func frame(s: GameSession, data: Dictionary, id: String) -> String:
	var l := get_letter(s, id)
	var to := str(l["to"])
	var p := purpose(data, str(l["purpose"]))
	var n: Dictionary = data["world"]["npcs"].get(to, {})
	var c := s.character
	var mem: Array = (s.npc_memory.get(to, []) as Array).slice(-int(cfg(data)["memory_max"])).map(func(m: Variant) -> String:
		return str(m.get("text", m)) if m is Dictionary else str(m))
	var parts: Array[String] = [
		"[letter:%s] Ответ на письмо героя. Адресат: %s (%s, %s). Цель: %s. Отправлено в %d-й день, дошло в %d-й, сегодня %d-й." % [id, n.get("name", to),
			n.get("role", ""), _loc_name(data, npc_loc(s, data, to)), p["name"], int(l["sent_day"]), int(l["deliver_day"]), s.day],
		"Письмо героя: «%s»" % l["text"],
		"Отношение к герою: %+d; связь: %s (%d)." % [s.attitude(to), BondRules.word(c, data, to) if not BondRules.word(c, data, to).is_empty() else "нет", BondRules.points(c, to)],
	]
	if not str(l["about"]).is_empty():
		parts.append("Донос на: %s." % _name(s, data, str(l["about"])))
	if not str(l["room"]).is_empty():
		parts.append("Куда герой зовёт: «%s»." % _room_name(data, str(l["room"])))
	if not mem.is_empty():
		parts.append("%s помнит о герое: %s." % [n.get("name", to), "; ".join(mem)])
	parts.append("Движок: %s." % l["verdict"])
	if not (l["outcome"] as Array).is_empty():
		parts.append("Уже случилось: %s." % "; ".join(l["outcome"]))
	return "\n".join(parts)


## Whether the master may answer this letter `letter_reply` yes.
static func choice(data: Dictionary, l: Dictionary) -> bool:
	return bool(purpose(data, str(l["purpose"])).get("choice", false))


## The plan of the master's `letter_reply` {letter_id, answer}: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary, pending: Array) -> Dictionary:
	var id := str(e.get("letter_id", "")) if e.get("letter_id") != null else ""
	var l := get_letter(s, id)
	if l.is_empty() or str(l["status"]) != "delivered":
		return {"reason": "letter_id — письмо из строки [letter:…] этого хода"}
	if not choice(data, l):
		return {"reason": "у этого письма ответ решил движок — letter_reply не нужен, просто напиши ответ"}
	if pending.any(func(p: Dictionary) -> bool: return str(p.get("plan", {}).get("letter", "")) == id):
		return {"reason": "ответ на это письмо уже дан"}
	var answer := str(e.get("answer", "")) if e.get("answer") != null else ""
	if not answer in ["yes", "no"]:
		return {"reason": "answer — yes или no"}
	if answer == "yes" and not bool(l["can"]):
		return {"reason": "движок: %s — только отказ (no)" % l["verdict"]}
	return {"plan": {"letter": id, "answer": answer}, "summary": "%s: %s" % [_name(s, data, str(l["to"])), "согласие" if answer == "yes" else "отказ"]}


static func apply(s: GameSession, _data: Dictionary, p: Dictionary) -> Array[String]:
	get_letter(s, str(p["letter"]))["decision"] = str(p["answer"])
	return []


## The master's turn wrote the answer: the letter is answered, a yes does what its purpose does. Lines.
static func answered(s: GameSession, data: Dictionary, id: String, text: String) -> Array[String]:
	var l := get_letter(s, id)
	if l.is_empty() or str(l["status"]) != "delivered":
		return []
	l["status"] = "answered"
	l["reply"] = text.strip_edges()
	l["answer_day"] = s.day
	var who := _name(s, data, str(l["to"]))
	var lines: Array[String] = ["Пришёл ответ: %s (%s)" % [who, purpose(data, str(l["purpose"]))["name"]]]
	lines.append_array(l["outcome"])
	if not choice(data, l):
		return lines
	if str(l["decision"]) != "yes":
		lines.append("%s отказывает" % who)
		return lines
	var p := purpose(data, str(l["purpose"]))
	match str(p["does"]):
		"ally":
			var room := str(l["room"])
			var path := route(data, npc_loc(s, data, str(l["to"])), _loc(data, room))
			var arrive := s.day + maxi(1, (path.size() - 1) * int(p["days_per_hop"]))
			l["ally"] = {"npc": str(l["to"]), "room": room, "arrive": arrive, "until": arrive + int(p["wait_days"]), "state": "road"}
			s.npc_at[str(l["to"])] = ""  # on the road: nowhere in the world
			lines.append("%s придёт: «%s», к %d-му дню, и будет ждать до %d-го" % [who, _room_name(data, room), arrive, arrive + int(p["wait_days"])])
		"recommendation":
			var def := {"name": "Рекомендация: %s" % who, "item_type": "quest", "weight": 0, "value_cp": 0, "generated": true,
				"description": "Письмо за подписью и печатью %s: рекомендует героя." % who, "text": str(l["reply"]).left(1000),
				"recommends": str(l["to"])}
			var item := ItemRules.generated_id(def)
			s.items[item] = def
			ItemRules.found(s.character, data, s.items, item, 1)
			lines.append("Получено: %s" % def["name"])
	return lines


# --- the ally, the arrest, the family ------------------------------------------------------------------------------


static func _ally_day(s: GameSession, data: Dictionary, l: Dictionary) -> Array[String]:
	var a: Dictionary = l["ally"]
	var npc := str(a["npc"])
	var lines: Array[String] = []
	if str(a["state"]) == "road" and s.day >= int(a["arrive"]):
		a["state"] = "waits"
		s.npc_at[npc] = str(a["room"])
		if s.room_id == str(a["room"]):
			lines.append_array(_join(s, data, l))
	elif str(a["state"]) == "waits" and s.day > int(a["until"]):
		a["state"] = "gone"
		s.npc_at.erase(npc)
		if s.room_id == str(a["room"]):
			lines.append("%s не дождался(лась) и ушёл(ушла) домой" % _name(s, data, npc))
	return lines


static func _join(s: GameSession, data: Dictionary, l: Dictionary) -> Array[String]:
	var a: Dictionary = l["ally"]
	var npc := str(a["npc"])
	a["state"] = "joined"
	if s.followers.size() >= int(FollowRules.cfg(data)["max"]):
		s.npc_at.erase(npc)
		return ["%s пришёл(пришла) на зов, но с героем уже идут %d — и уходит домой" % [_name(s, data, npc), s.followers.size()]]
	FollowRules.apply(s, {"follow_npc": npc, "on": true, "room": ""})
	return ["%s пришёл(пришла) на зов письма и идёт с героем" % _name(s, data, npc)]


## The hero walked into a room: a helper waiting there joins. Lines.
static func on_enter(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	for l: Dictionary in letters(s):
		if l.has("ally") and str(l["ally"]["state"]) == "waits" and str(l["ally"]["room"]) == room_id:
			lines.append_array(_join(s, data, l))
	return lines


static func _arrest(s: GameSession, data: Dictionary, l: Dictionary, here: String) -> Array[String]:
	var a: Dictionary = l["arrest"]
	a["done"] = true
	var npc := str(a["npc"])
	var prison := str(CrimeRules.law(data, str(a["loc"])).get("prison", ""))
	if s.dead_npcs.has(npc) or prison.is_empty():
		return []
	FollowRules.apply(s, {"follow_npc": npc, "on": false, "room": prison})
	a["until"] = s.day + int(purpose(data, str(l["purpose"]))["jail_days"])
	s.remember(npc, "знает: герой донёс на него страже")
	s.attitudes[npc] = mini(s.attitude(npc), int(SocialRules.cfg(data)["thresholds"]["refuse_at"]))
	var what := "%s взят(а) под стражу по доносу" % _name(s, data, npc)
	RumorRules.add(s, data, {"text": what, "weight": int(cfg(data)["arrest_rumor_weight"]), "origin": str(a["loc"]), "source": "letter", "about": npc})
	return [what] if _loc(data, s.room_id) == str(a["loc"]) or here == str(a["loc"]) else []


static func jailed(s: GameSession, npc_id: String) -> bool:
	for l: Dictionary in _state(s)["list"].values():
		var a: Dictionary = l.get("arrest", {})
		if str(a.get("npc", "")) == npc_id and bool(a.get("done", false)) and a.has("until") and s.day <= int(a["until"]):
			return true
	return false


static func _jail_days(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for l: Dictionary in _state(s)["list"].values():
		var a: Dictionary = l.get("arrest", {})
		if a.has("until") and not bool(a.get("freed", false)) and s.day > int(a["until"]):
			a["freed"] = true
			s.npc_at.erase(str(a["npc"]))
			if _loc(data, s.room_id) == str(a["loc"]):
				lines.append("%s отпущен(а) из-под стражи" % _name(s, data, str(a["npc"])))
	return lines


## A family left without word: the hero away from home and no letter for silence_days — the spouse worries.
static func _family(s: GameSession, data: Dictionary) -> Array[String]:
	var sp := FamilyRules.spouse(s)
	var home := str(FamilyRules.view(s.character).get("home_room", ""))
	var st := _state(s)
	var f: Dictionary = cfg(data)["family"]
	if sp.is_empty() or home.is_empty() or _loc(data, s.room_id) == _loc(data, home):
		st["home_day"] = s.day
		return []
	var silent := s.day - int(st["home_day"]) - int(f["silence_days"])
	if silent < 0 or int(st.get("worried_day", -1)) == s.day or silent % int(f["every_days"]) != 0:
		return []
	st["worried_day"] = s.day
	var lines: Array[String] = ["%s тревожится: от вас %d дн. ни вести" % [_name(s, data, sp), s.day - int(st["home_day"])]]
	lines.append_array(BondRules.add(s, data, sp, int(f["bond"]), "долгое молчание"))
	return lines


# --- evidence, standing, recommendations ---------------------------------------------------------------------------


## An item the hero carries that shows this NPC's crime ("" — none): a pack or a made item with `evidence`.
static func _evidence_item(s: GameSession, data: Dictionary, npc_id: String) -> String:
	for id: String in s.character.get("inventory", {}):
		if str(ItemRules.def_of(data["items"], s.items, id).get("evidence", "")) == npc_id:
			return id
	return ""


## What proves the crime of `npc_id`: an evidence item sent with the letter, or a secret about it the hero was told.
static func evidence(s: GameSession, data: Dictionary, npc_id: String, item: String = "") -> String:
	if not item.is_empty() and str(ItemRules.def_of(data["items"], s.items, item).get("evidence", "")) == npc_id:
		return ItemRules.display_name(data["items"], s.items, item)
	for who: String in data["world"]["npcs"]:
		for sec: Dictionary in SocialRules.secrets(data, who):
			if str(sec.get("crime_of", "")) == npc_id and SocialRules.told(s, who, str(sec["id"])):
				return "свидетель — %s: %s" % [_name(s, data, who), sec["text"]]
	return ""


## Whether the NPC has a crime in the world: a secret or an evidence item names it.
static func guilty(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	for who: String in data["world"]["npcs"]:
		if SocialRules.secrets(data, who).any(func(sec: Dictionary) -> bool: return str(sec.get("crime_of", "")) == npc_id):
			return true
	for defs: Dictionary in [data["items"]["catalog"], s.items]:
		for id: String in defs:
			if str(defs[id].get("evidence", "")) == npc_id:
				return true
	return false


## A person of standing: a notable tag (rules.letters.notable_tags), an office's chief, a school's head, a site's owner.
static func notable(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	var w: Dictionary = data["world"]
	var tags: Array = w["npcs"].get(npc_id, {}).get("tags", [])
	if tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(str(t))):
		return true
	for o: Dictionary in w.get("offices", {}).values():
		if str(o.get("chief", "")) == npc_id:
			return true
	for sc: Dictionary in w.get("schools", {}).values():
		if str(sc.get("head", "")) == npc_id:
			return true
	for si: Dictionary in w.get("sites", {}).values():
		if str(si.get("owner", "")) == npc_id:
			return true
	return false


## The name of a person whose recommendation the hero carries — one of `from`, or any person of standing when
## `any_notable`; "" — none.
static func recommender(s: GameSession, data: Dictionary, from: Array, any_notable: bool = false) -> String:
	if not on(data):
		return ""
	for id: String in s.character.get("inventory", {}):
		var by := str(ItemRules.def_of(data["items"], s.items, id).get("recommends", ""))
		if not by.is_empty() and (from.has(by) or (any_notable and notable(s, data, by))):
			return _name(s, data, by)
	return ""


# --- the journal ---------------------------------------------------------------------------------------------------


## The journal tab «Письма»: what we wait for, the answers, the sent ones gone silent.
static func groups(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var waiting: Array[String] = []
	var answers: Array[String] = []
	var silent: Array[String] = []
	var allies: Array[String] = []
	for l: Dictionary in letters(s):
		var head := "%s — %s (%d-й день)" % [_name(s, data, str(l["to"])), purpose(data, str(l["purpose"]))["name"], int(l["sent_day"])]
		var st := str(l["status"])
		if st == "answered":
			answers.append("%s: «%s»" % [head, str(l["reply"]).left(300)])
		elif st == "lost" and s.day >= int(l["reply_day"]) + int(cfg(data)["silent_after_days"]):
			silent.append("%s — ответа нет: гонец, видно, пропал в пути" % head)
		else:
			var road := s.day < int(l["deliver_day"])
			waiting.append("%s — %s, ответ к %d-му дню" % [head, "в пути" if road else "доставлено", int(l["reply_day"])])
		if l.has("ally") and str(l["ally"]["state"]) in ["road", "waits"]:
			var a: Dictionary = l["ally"]
			allies.append("%s %s «%s» %s" % [_name(s, data, str(a["npc"])), "ждёт у" if str(a["state"]) == "waits" else "идёт к",
				_room_name(data, str(a["room"])), "до %d-го дня" % int(a["until"]) if str(a["state"]) == "waits" else "к %d-му дню" % int(a["arrive"])])
	var out: Array[Dictionary] = []
	if not allies.is_empty():
		out.append({"title": "Идут на помощь", "lines": allies})
	if not waiting.is_empty():
		out.append({"title": "Ждём ответа", "lines": waiting})
	if not answers.is_empty():
		out.append({"title": "Ответы", "lines": answers})
	if not silent.is_empty():
		out.append({"title": "Без ответа", "lines": silent, "folded": true})
	return out


static func count(s: GameSession, data: Dictionary) -> int:
	var n := 0
	for g: Dictionary in groups(s, data):
		if str(g["title"]) != "Ответы" and not bool(g.get("folded", false)):
			n += (g["lines"] as Array).size()
	return n
