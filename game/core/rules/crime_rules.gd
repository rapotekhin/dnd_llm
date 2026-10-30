class_name CrimeRules
extends RefCounted
## Crimes of the hero (roadmap v0.7.14, the author's finding: a priestess killed in the temple was forgotten at once).
## A murder is a fight the hero began (a scene NPC attacked by words, the guard resisted) that ends with a pack NPC
## dead; a fight the NPC began (a caught theft, an ambush) is self-defence. The crime is a fact of the world in
## s.crimes [{id, victim, room, location, at, witnesses, known, settled}]:
##   the living NPCs of the room are witnesses — they know at once; without witnesses the body is found after
##   rules.crime.found_minutes (or the hero confesses — the master's `crime_known`), then the whole location knows.
## Known: every NPC of the location −attitude (witnesses one more). In a location with `law` (pack: guards, a guard
## monster) the hero is wanted (s.wanted {location: abs minute}): its traders do not trade, its givers give nothing,
## a guard NPC in the room or a patrol (after search_minutes, not when sneaking or invisible) holds the hero
## (s.arrest = room): pay the wergild, sit in the stocks, or resist (a fight). Paid or served — the location forgives
## one step of the attitude. The body stays in the room as a thing to search (s.bodies {npc_id: room}).
## Big test (v0.7.22.2): the hold has more answers, as in BG3 — Persuasion, Deception, Intimidation against a
## tier by the crimes (`talk_tier`, a notable victim one step harder), each once a hold, or a bribe (bribe_share of
## the wergild). Talked out or bribed — the hero is let go (s.let_go {location: abs minute}) but still wanted; resisted
## — the same after the fight. Until let_go_minutes pass nobody holds the hero there; then a guard NPC in the room
## holds again and a patrol finds the hero only by patrol_chance a step. The guard may lead the hero (the master's
## `move` while held — to any room of the location, the hold goes along) and let go by words after a check that
## passed at the talk tier (`crime_release`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["crime"]


## v0.7.22.16: a crime has a kind (rules.crime.kinds) — `murder` (an old save's crime has none) or `assault`: a pack
## NPC the hero attacked and left alive. An assault is known at once when someone saw it or the victim stayed awake;
## a victim knocked out with nobody by tells when it wakes or is let go. It is not a body: never found by a search,
## never buried; a victim finished off after it — its assault becomes the murder.
static func kind_of(data: Dictionary, crime: Dictionary) -> Dictionary:
	var kinds: Dictionary = cfg(data).get("kinds", {})
	return kinds.get(str(crime.get("kind", "murder")), kinds.get("murder", {"severity": 1, "name": "убийство"}))


static func _assault(crime: Dictionary) -> bool:
	return str(crime.get("kind", "murder")) == "assault"


## A fight the hero began ended with a pack NPC alive (knocked out, surrendered, at peace, fled): an assault.
## `aware` — the victim saw who did it and is awake. Lines.
static func on_assault(s: GameSession, data: Dictionary, npc_id: String, aware: bool, room_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var witnesses := s.npcs_here(world.world, room_id).filter(func(id: String) -> bool: return id != npc_id)
	if ConditionRules.invisible(s.character, data):
		witnesses = []
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "assault", "victim": npc_id, "room": room_id,
		"location": world.location_id(room_id), "at": TimeRules.abs_minute(s), "witnesses": witnesses, "known": false, "settled": false}
	s.crimes.append(crime)
	var faith := FaithRules.deed(s, data, "assault", room_id)  # v0.7.49
	var who := _name(data, npc_id)
	if witnesses.is_empty() and not aware:
		return ["Нападение: %s — никто не видел, %s без сознания" % [who, who]] + faith
	for w: String in witnesses:
		s.shift_attitude(w, int(cfg(data)["witness_attitude"]), data)
	var lines: Array[String] = ["Нападение: %s%s" % [who, (" — видели: " + ", ".join(witnesses.map(func(id: String) -> String: return _name(data, id)))) if not witnesses.is_empty() else ""]]
	lines.append_array(_known(s, data, crime))
	lines.append_array(faith)
	return lines


## Walking into a private room before eyes (v0.7.22.24, SiteRules): a light crime where there is law — known at
## once, its wergild by `rules.crime.kinds.trespass`. Lines.
static func on_trespass(s: GameSession, data: Dictionary, owner: String, room_id: String, witnesses: Array) -> Array[String]:
	var world := WorldView.new(data["world"])
	var loc := world.location_id(room_id)
	if law(data, loc).is_empty():
		return []
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "trespass", "victim": owner, "room": room_id, "site": world.site_id(room_id),
		"location": loc, "at": TimeRules.abs_minute(s), "witnesses": witnesses.filter(func(id: String) -> bool: return id != owner), "known": false, "settled": false}
	s.crimes.append(crime)
	return _known(s, data, crime) + FaithRules.deed(s, data, "trespass", room_id)


## A loan whose collateral is gone ran past its grace (v0.7.28, BankRules): the crime `debt` against the creditor in
## the bank's location, known at once; its wergild is the debt itself. Returns [crime id, lines...].
static func on_debt(s: GameSession, data: Dictionary, creditor: String, loc: String, amount_cp: int) -> Array[String]:
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": str(data["rules"].get("bank", {}).get("debt_crime", "debt")), "victim": creditor,
		"room": "", "location": loc, "at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false, "fine_cp": amount_cp}
	s.crimes.append(crime)
	var out: Array[String] = [str(crime["id"])]
	out.append_array(_known(s, data, crime))
	out.append_array(FaithRules.deed(s, data, str(crime["kind"])))
	return out


## A false denunciation (v0.7.48, LetterRules): the law of `loc` read a letter against an innocent `victim` — the
## hero's crime, known there at once. Lines.
static func on_false_report(s: GameSession, data: Dictionary, victim: String, loc: String) -> Array[String]:
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "false_report", "victim": victim, "room": "", "location": loc,
		"at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false}
	s.crimes.append(crime)
	return _known(s, data, crime) + FaithRules.deed(s, data, "false_report")


## A criminal job seen or traced (v0.7.33, HeistRules): its crime of `kind` known at once in `loc` (where the law
## looks for it), the victim — an NPC or "". Lines.
static func on_job(s: GameSession, data: Dictionary, kind: String, victim: String, room_id: String, loc: String) -> Array[String]:
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": kind, "victim": victim, "room": room_id, "location": loc,
		"at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false}
	s.crimes.append(crime)
	return _known(s, data, crime) + FaithRules.deed(s, data, kind, room_id)


## One crime closed outside the law's hold (v0.7.28: the debt paid at the bank); the location's wanted goes when no
## other open crime is left there. Lines.
static func settle_one(s: GameSession, data: Dictionary, crime_id: String) -> Array[String]:
	for crime: Dictionary in s.crimes:
		if str(crime["id"]) != crime_id or bool(crime["settled"]):
			continue
		crime["settled"] = true
		_rewarn(s, crime)
		var loc := str(crime["location"])
		if _open(s, loc).is_empty() and s.wanted.has(loc):
			s.wanted.erase(loc)
			s.let_go.erase(loc)
			if not s.arrest.is_empty() and WorldView.new(data["world"]).location_id(s.arrest) == loc:
				s.arrest = ""
			return ["Вы больше не в розыске: %s" % WorldView.new(data["world"]).location(loc).get("name", loc)]
	return []


## The victim of an unknown assault woke up or was let go: it tells. Lines.
static func assault_known(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	for crime: Dictionary in s.crimes:
		if _assault(crime) and str(crime["victim"]) == npc_id and not bool(crime["known"]):
			return _known(s, data, crime)
	return []


static func law(data: Dictionary, location_id: String) -> Dictionary:
	return WorldView.new(data["world"]).location(location_id).get("law", {})


## The NPCs of the pack whose room is in `location_id`.
static func people_of(data: Dictionary, location_id: String) -> Array[String]:
	var out: Array[String] = []
	var rooms: Dictionary = data["world"]["rooms"]
	for rid: String in rooms:
		if str(rooms[rid].get("location_id", "")) == location_id:
			for n: Variant in rooms[rid].get("npcs", []):
				if not out.has(str(n)):
					out.append(str(n))
	return out


## The pack NPC killed in a fight: the body stays, its quests pass to the heir or fail, and a fight the hero began
## is a murder. Lines.
static func on_death(s: GameSession, data: Dictionary, npc_id: String, by_hero: bool, room_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var lines: Array[String] = TradeRules.on_death(s, data, npc_id)  # v0.7.17.2: the goods to the heir
	s.crimes = s.crimes.filter(func(c: Dictionary) -> bool: return not (_assault(c) and str(c["victim"]) == npc_id and not bool(c["known"])))  # finished off: the murder
	if not s.dead_npcs.has(npc_id):
		s.dead_npcs.append(npc_id)
	s.bodies[npc_id] = room_id
	s.body_at[npc_id] = TimeRules.abs_minute(s)  # buried some days later (v0.7.22.10)
	lines.append_array(QuestRules.on_death(s, data, npc_id))
	if not by_hero:
		RumorRules.on_death(s, data, npc_id, room_id)  # v0.7.47
		return lines
	var witnesses := s.npcs_here(world.world, room_id).filter(func(id: String) -> bool: return id != npc_id)
	if ConditionRules.invisible(s.character, data):
		witnesses = []  # an unseen killer: they saw a death, not who did it
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "murder", "victim": npc_id, "room": room_id, "location": world.location_id(room_id),
		"at": TimeRules.abs_minute(s), "witnesses": witnesses, "known": false, "settled": false}
	s.crimes.append(crime)
	var who := str(world.npc(npc_id).get("name", npc_id))
	if witnesses.is_empty():
		lines.append("Убийство: %s — свидетелей нет" % who)
		return lines + FaithRules.deed(s, data, "murder", room_id)  # v0.7.49
	lines.append("Убийство: %s — видели: %s" % [who, ", ".join(witnesses.map(func(id: String) -> String: return str(world.npc(id).get("name", id))))])
	for w: String in witnesses:
		s.shift_attitude(w, int(cfg(data)["witness_attitude"]), data)
	lines.append_array(_known(s, data, crime))
	lines.append_array(FaithRules.deed(s, data, "murder", room_id))
	return lines


## The crime becomes known in its location: attitudes, and the hero is wanted where there is law. Lines.
static func _known(s: GameSession, data: Dictionary, crime: Dictionary) -> Array[String]:
	FactionRules.on_crime(s, data, str(crime["victim"]), str(crime["kind"]))  # v0.7.50
	crime["known"] = true
	crime["known_at"] = TimeRules.abs_minute(s)
	var loc := str(crime["location"])
	var world := WorldView.new(data["world"])
	var what := str(kind_of(data, crime)["name"])
	var victim := str(crime["victim"])
	var kind := kind_of(data, crime)
	var lines: Array[String] = []
	# v0.7.22.24: a kind may set its own echo — the location's attitude, the memory, a share of the reputation
	var att := int(kind.get("known_attitude", -1 if _assault(crime) else int(cfg(data)["attitude"])))
	if att != 0:
		lines.append("%s знает: %s — отношение хуже" % [world.location(loc).get("name", loc), what])
	for id: String in people_of(data, loc):
		if not s.dead_npcs.has(id) and id != victim:
			if att != 0:
				s.shift_attitude(id, att, data)
			s.remember(id, (str(kind["memory"]).format({"victim": _name(data, victim)})) if kind.has("memory") else
				("знает: герой напал на %s" % _name(data, victim)) if _assault(crime) else
				("знает: %s убит%s героем" % [_name(data, victim), _ending(data, victim)]))
	if _assault(crime):
		lines.append_array(BondRules.on_deed(s, data, victim, "assault", "нападение"))  # v0.7.31
	var share := int(kind.get("reputation_share", 2 if _assault(crime) else 1))
	var delta := int(ReputationRules.cfg(data)["points"]["crime_known"]) / share if share > 0 else 0
	if share > 0:
		lines.append_array(ReputationRules.add(s, data, loc, delta, what, false))  # v0.7.17
	RumorRules.on_crime(s, data, crime, delta)  # v0.7.47: the news, the blame and the wanted go on to the neighbours
	if not law(data, loc).is_empty():
		if not s.wanted.has(loc):
			s.wanted[loc] = TimeRules.abs_minute(s)
		lines.append("Вы в розыске: %s" % law(data, loc).get("name", "стража"))
		lines.append_array(check_arrest(s, data))
	return lines


## Hidden crimes whose body is found by now: an unhidden body after rules.crime.found_minutes; a hidden one by a roll
## once a day, harder each day (v0.7.22.10). Then the found bodies are buried. Called as time passes. Lines.
static func spread(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var h: Dictionary = cfg(data)["hide"]
	for crime: Dictionary in s.crimes:
		if bool(crime["known"]) or _assault(crime):  # an assault is told by its victim, not found
			continue
		if not crime.has("hide_dc"):
			if now - int(crime["at"]) >= int(cfg(data)["found_minutes"]):
				lines.append("Нашли тело: %s" % _name(data, str(crime["victim"])))
				lines.append_array(_known(s, data, crime))
			continue
		var days := (now - int(crime["at"])) / 1440
		while int(crime.get("searched_days", 0)) < days and not bool(crime["known"]):
			crime["searched_days"] = int(crime.get("searched_days", 0)) + 1
			var dc := int(crime["hide_dc"]) + int(h["day_step"]) * int(crime["searched_days"])
			if s.rng.randi_range(1, 20) + int(h["search_bonus"]) >= dc:
				lines.append("Нашли спрятанное тело: %s" % _name(data, str(crime["victim"])))
				lines.append_array(_known(s, data, crime))
	lines.append_array(bury(s, data))
	return lines


## "" when the hero can hide this body now: it lies here and its murder is still a secret.
static func can_hide(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if str(s.bodies.get(npc_id, "")) != s.room_id:
		return "CRIME_NO_BODY"
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == npc_id and not bool(crime["known"]):
			return "CRIME_HIDDEN_ALREADY" if crime.has("hide_dc") else ""
	return "CRIME_NO_SECRET"


## The body hidden by a check that the engine rolled (rules.crime.hide): a success — its total is how hard it is to
## find; a failure — hidden badly, found like an unhidden one. Lines.
static func hide(s: GameSession, data: Dictionary, npc_id: String, total: int, success: bool) -> Array[String]:
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == npc_id and not bool(crime["known"]):
			if not success:
				return ["Тело спрятано наспех — его найдут"]
			crime["hide_dc"] = total
			crime["searched_days"] = 0
			return ["Тело %s спрятано: искать его будут, но найти непросто" % _name(data, npc_id)]
	return []


## Known bodies are buried after rules.crime.bury_days (a body of a hidden murder is not — nobody knows of it). Lines.
static func bury(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var world := WorldView.new(data["world"])
	for npc_id: String in s.bodies.keys():
		var since := int(s.body_at.get(npc_id, 0))
		var secret := false
		for crime: Dictionary in s.crimes:
			if str(crime["victim"]) == npc_id:
				secret = not bool(crime["known"])
				since = int(crime.get("known_at", since))
		if secret or now - since < int(cfg(data)["bury_days"]) * 1440:
			continue
		var room := str(s.bodies[npc_id])
		s.bodies.erase(npc_id)
		lines.append("Похоронили: %s — там, где лежало тело (%s), осталось тёмное пятно" % [_name(data, npc_id), world.room(room).get("name", room)])
	return lines


## The master's `crime_known`: the hero confessed or was exposed. {"reason"} or {"plan", "summary"}.
static func plan_reveal(s: GameSession, data: Dictionary, victim: String) -> Dictionary:
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == victim and not bool(crime["known"]):
			var what := str(kind_of(data, crime)["name"])
			return {"plan": {"victim": victim}, "summary": "%s раскрыто: %s" % [what.left(1).to_upper() + what.substr(1), _name(data, victim)]}
	return {"reason": "тайного преступления против %s нет" % victim}


static func reveal(s: GameSession, data: Dictionary, victim: String) -> Array[String]:
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == victim and not bool(crime["known"]):
			return _known(s, data, crime)
	return []


## «убит» / «убита» / «убит(а)» by the NPC's gender (v0.7.15).
static func _ending(data: Dictionary, npc_id: String) -> String:
	match str(data["world"]["npcs"].get(npc_id, {}).get("gender", "")):
		"male":
			return ""
		"female":
			return "а"
	return "(а)"


static func _name(data: Dictionary, npc_id: String) -> String:
	return str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))


## Wanted in the location of `room_id`.
static func wanted_at(s: GameSession, data: Dictionary, room_id: String) -> bool:
	return s.wanted.has(WorldView.new(data["world"]).location_id(room_id))


## An NPC who turns the wanted hero away (traders do not trade, givers give nothing).
static func shunned_by(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	var loc := ""
	var rooms: Dictionary = data["world"]["rooms"]
	for rid: String in rooms:
		if (rooms[rid].get("npcs", []) as Array).has(npc_id):
			loc = str(rooms[rid].get("location_id", ""))
	return s.wanted.has(loc) and not BondRules.close(s, data, npc_id)  # v0.7.31: a close friend serves the wanted


## The guard holds the hero in this room: a guard NPC of the law is here, or a patrol finds the hero after
## search_minutes (not when sneaking or invisible). Lines.
static func check_arrest(s: GameSession, data: Dictionary) -> Array[String]:
	var world := WorldView.new(data["world"])
	var loc := world.location_id(s.room_id)
	if not s.wanted.has(loc) or s.arrest == s.room_id or CombatRules.active(s):
		return []
	var now := TimeRules.abs_minute(s)
	if now < int(s.let_go.get(loc, -1)):
		return []  # just let go or fought free: the guard does not come back at once (big test #6)
	if data["rules"].has("underworld") and not OrgRules.hideout_of(s, data, s.room_id, "hide").is_empty():
		return []  # v0.7.33: the guard does not know the hideout
	var l := law(data, loc)
	var guards := s.npcs_here(world.world, s.room_id).filter(func(id: String) -> bool: return (l.get("guards", []) as Array).has(id))
	var patrol := now - int(s.wanted[loc]) >= int(cfg(data)["search_minutes"]) \
		and not s.sneaking and not ConditionRules.invisible(s.character, data)
	if patrol and s.let_go.has(loc):
		patrol = s.rng.randf() < float(cfg(data)["patrol_chance"])
	if guards.is_empty() and not patrol:
		return []
	s.arrest = s.room_id
	s.arrest_tried = []
	var who := str(world.npc(guards[0]).get("name", "")) if not guards.is_empty() else str(l.get("patrol", "Патруль стражи"))
	return ["%s: «Стой! Именем закона — ты задержан»" % who]


## The fight with the guard is lost or the hero gave up to it (v0.7.22.17): held here again, as at an arrest — the
## answers are the same, only resisting is spent. Lines.
static func held_after_fight(s: GameSession, data: Dictionary) -> Array[String]:
	s.let_go.erase(WorldView.new(data["world"]).location_id(s.room_id))
	s.arrest = s.room_id
	s.arrest_tried = ["resist", "intimidate"]  # a beaten threat rings hollow
	return ["Стража скручивает героя — задержан"]


## Time passes where the law may come (v0.7.22.18, #27): the wanted hero waits in steps of rules.crime.wait_step
## minutes and the patrol looks in after each — held, the wait stops there. Elsewhere — the whole wait at once.
## {lines, minutes} — the minutes really waited.
static func wait(s: GameSession, data: Dictionary, minutes: int) -> Dictionary:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var lines: Array[String] = []
	if law(data, loc).is_empty() or held(s):
		lines.append_array(TimeRules.advance(s, data, minutes))
		return {"lines": lines, "minutes": minutes}
	var step := maxi(1, int(cfg(data)["wait_step"]))
	var done := 0
	while done < minutes:
		var m := mini(step, minutes - done)
		lines.append_array(TimeRules.advance(s, data, m))  # a body found on the way makes the hero wanted
		done += m
		lines.append_array(check_arrest(s, data))
		if held(s):
			lines.append("Ожидание прервано: стража здесь")
			break
	return {"lines": lines, "minutes": done}


## Who comes to the help of an NPC the hero attacks (v0.7.22.18, #29): the people of the room who are the law's guards
## or carry a tag of rules.crime.defend — not the hero's friends (attitude from friend_attitude), not those who go
## with the hero, not ones already in the fight. `foes` — the specs of the fight about to start; [] when no NPC of
## them was attacked by the hero. Specs of the defenders.
static func defenders(s: GameSession, data: Dictionary, foes: Array) -> Array:
	var victims: Array = foes.filter(func(f: Dictionary) -> bool: return bool(f.get("by_hero", false)) and not str(f.get("npc_id", "")).is_empty())
	if victims.is_empty():
		return []
	var world := WorldView.new(data["world"])
	var d: Dictionary = cfg(data)["defend"]
	var guards: Array = law(data, world.location_id(s.room_id)).get("guards", [])
	var out: Array = []
	for id: String in s.npcs_here(world.world, s.room_id):
		if foes.any(func(f: Dictionary) -> bool: return str(f.get("npc_id", "")) == id) or s.followers.has(id):
			continue
		if s.attitude(id) >= int(d["friend_attitude"]):
			continue
		var n := world.npc(id)
		var tags: Array = n.get("tags", [])
		if not guards.has(id) and not tags.any(func(t: Variant) -> bool: return (d["tags"] as Array).has(t)):
			continue
		out.append({"monster": str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"])), "name": str(n.get("name", id)),
			"desc": str(n.get("description", "")), "npc_id": id, "col": 1, "by_hero": true, "law": guards.has(id)})
	return out


## The outcome of an answer to the guard in words for the master (v0.7.22.18, #28): it narrated a wergild and the
## stocks after a threat that let the hero go. One of three, by the state after the answer.
static func outcome(s: GameSession, data: Dictionary) -> String:
	if held(s):
		return "стража по-прежнему держит героя: его не отпустили и не наказали — дальше выбирает игрок"
	if wanted_at(s, data, s.room_id):
		return "героя отпустили, но розыск не снят; вергельда он не платил, в колодках и под замком не был"
	return "вина искуплена — розыск снят"


static func held(s: GameSession) -> bool:
	return not s.arrest.is_empty() and s.arrest == s.room_id


## The wergild for the unsettled known crimes of the location: fine_cp each, ×notable_mult for notable victims.
static func fine(s: GameSession, data: Dictionary, loc: String) -> int:
	var total := 0
	var debts := 0
	for crime: Dictionary in _open(s, loc):
		if crime.has("fine_cp"):  # a debt's wergild is the debt (v0.7.28)
			debts += int(crime["fine_cp"])
			continue
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		var notable := tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t))
		total += int(kind_of(data, crime).get("fine_cp", cfg(data)["fine_cp"])) * (int(cfg(data)["notable_mult"]) if notable else 1)
	if not BondRules.intercessor(s, data, loc).is_empty():  # v0.7.31: a friend of the law speaks for the hero
		total = total * int(BondRules.cfg(data)["perks"]["intercede"]["fine_pct"]) / 100
	return total + debts


## The weight of the open crimes of the location for the sentence and the talk (v0.7.22.16): the sum of their kinds.
static func _weight(s: GameSession, data: Dictionary, loc: String) -> int:
	var w := 0
	for crime: Dictionary in _open(s, loc):
		w += int(kind_of(data, crime).get("severity", 1))
	return w


static func _open(s: GameSession, loc: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crime: Dictionary in s.crimes:
		if str(crime["location"]) == loc and bool(crime["known"]) and not bool(crime["settled"]):
			out.append(crime)
	return out


static func stocks_days(s: GameSession, data: Dictionary, loc: String) -> int:
	return int(sentence(s, data, loc)["days"])


## The sentence for the open crimes of the location (v0.7.22.10): the highest of rules.crime.sentences whose severity
## fits — the crimes, +1 for a notable victim. {kind, days, name, exhaustion?}.
static func sentence(s: GameSession, data: Dictionary, loc: String) -> Dictionary:
	var severity := _weight(s, data, loc)
	for crime: Dictionary in _open(s, loc):
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		if tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t)):
			severity += 1
			break
	if not BondRules.intercessor(s, data, loc).is_empty():
		severity -= int(BondRules.cfg(data)["perks"]["intercede"]["severity"])
	var out: Dictionary = cfg(data)["sentences"][0]
	for sn: Dictionary in cfg(data)["sentences"]:
		if severity >= int(sn["severity"]):
			out = sn
	return out


## The talk answers to the guard and their skills (v0.7.22.2).
const TALK := {"persuade": "persuasion", "deceive": "deception", "intimidate": "intimidation"}


## The tier of talking the guard out of it: talk_tier, one step harder for each crime past the first and a notable victim.
static func talk_tier(s: GameSession, data: Dictionary, loc: String) -> String:
	var tiers: Array = (data["rules"]["dc_tiers"] as Dictionary).keys()
	var w := _weight(s, data, loc)  # v0.7.22.16: only assaults — a step easier
	var i := tiers.find(str(cfg(data)["talk_tier"])) + (maxi(0, w - 1) if w > 0 else -1 if not _open(s, loc).is_empty() else 0)
	for crime: Dictionary in _open(s, loc):
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		if tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t)):
			i += 1
			break
	return str(tiers[clampi(i, 0, tiers.size() - 1)])


static func bribe(s: GameSession, data: Dictionary, loc: String) -> int:
	return int(fine(s, data, loc) * float(cfg(data)["bribe_share"]))


## "" when the arrest can be answered this way: pay / stocks / resist / persuade / deceive / intimidate / bribe.
static func can_answer(s: GameSession, data: Dictionary, how: String) -> String:
	if not held(s):
		return "CRIME_NOT_HELD"
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	if how == "pay" and int(s.character["gold_cp"]) < fine(s, data, loc):
		return "CRIME_NO_MONEY"
	if (TALK.has(how) or how in ["bribe", "resist"]) and s.arrest_tried.has(how):
		return "CRIME_TRIED"
	if how == "bribe" and int(s.character["gold_cp"]) < bribe(s, data, loc):
		return "CRIME_NO_MONEY"
	return ""


## The outcome of a talk answer whose check the engine rolled (GameState). Lines; a failed threat leaves
## s.pending_fight with the guard.
static func talked(s: GameSession, data: Dictionary, how: String, success: bool) -> Array[String]:
	s.arrest_tried.append(how)
	if success:
		return let_go(s, data, "Стража отпускает героя — но розыск не снят")
	if how == "intimidate":
		var lines: Array[String] = ["Угроза не подействовала — стража берётся за оружие"]
		lines.append_array(answer(s, data, "resist"))
		return lines
	return ["Стража не верит ни слову"]


## The hero is free for now but still wanted: nobody holds them here for let_go_minutes. Lines.
static func let_go(s: GameSession, data: Dictionary, line: String) -> Array[String]:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	s.arrest = ""
	s.arrest_tried = []
	s.let_go[loc] = TimeRules.abs_minute(s) + int(cfg(data)["let_go_minutes"])
	return [line]


## The master's `crime_release`: the guard lets the hero go by words — only after a check this turn that passed at
## the talk tier (`won` — the tiers of the passed checks). {"reason"} or {"plan", "summary"}.
static func plan_release(s: GameSession, data: Dictionary, won: Array) -> Dictionary:
	if not held(s):
		return {"reason": "стража не держит героя"}
	var need := talk_tier(s, data, WorldView.new(data["world"]).location_id(s.room_id))
	var dcs: Dictionary = data["rules"]["dc_tiers"]
	if not won.any(func(t: Variant) -> bool: return int(dcs.get(str(t), 0)) >= int(dcs[need])):
		return {"reason": "отпустить словами — только после пройденной в этом ходе проверки Убеждения, Обмана или Запугивания сложности %s (%d); сначала engine.check" % [need, int(dcs[need])]}
	return {"plan": {"crime_release": true}, "summary": "Стража отпускает героя (розыск не снят)"}


## The answer to the guard (can_answer first). Lines; resisting leaves s.pending_fight with the guard.
static func answer(s: GameSession, data: Dictionary, how: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var loc := world.location_id(s.room_id)
	var l := law(data, loc)
	var lines: Array[String] = []
	match how:
		"bribe":
			var bcp := bribe(s, data, loc)
			s.character["gold_cp"] = int(s.character["gold_cp"]) - bcp
			s.arrest_tried.append("bribe")
			lines.append("Взятка: −%s" % Money.format(bcp))
			lines.append_array(let_go(s, data, "Стража смотрит в сторону — но розыск не снят"))
		"pay":
			var cp := fine(s, data, loc)
			s.character["gold_cp"] = int(s.character["gold_cp"]) - cp
			lines.append("Вергельд уплачен: −%s" % Money.format(cp))
			lines.append_array(_settle(s, data, loc))
		"stocks":  # the sentence by severity (v0.7.22.10): prison or hard labour, the hero wakes in the law's prison
			var sn := sentence(s, data, loc)
			var days := int(sn["days"])
			s.day += days
			s.minute = int(TimeRules.cfg(data)["wake_minute"])
			s.rested_at = TimeRules.abs_minute(s)
			s.awake_saves = 0
			s.character["hp"] = int(s.character["max_hp"])  # the wounds healed in the days
			var prison := str(l.get("prison", "")) if str(sn.get("kind", "")) != "stocks" else ""  # the stocks — where the hero stands
			if not prison.is_empty() and data["world"]["rooms"].has(prison):
				s.room_id = prison
				if not s.visited.has(prison):
					s.visited.append(prison)
			lines.append("%d дн. — %s; день %d, утро, %s; вещи вернули" % [days, sn["name"], s.day,
				world.room(s.room_id).get("name", s.room_id)])
			lines.append_array(ConditionRules.expire(s, data))
			if int(sn.get("exhaustion", 0)) > 0:
				lines.append_array(ConditionRules.add_exhaustion(s, data, int(sn["exhaustion"]), str(sn["name"])))
			lines.append_array(_settle(s, data, loc))
		"resist":
			var foes: Array = [{"monster": str(l.get("guard_monster", "guard")), "count": int(cfg(data)["patrol_size"]),
				"name": str(l.get("guard_name", "Стражник")), "col": 1, "by_hero": true, "law": true}]
			for id: String in s.npcs_here(world.world, s.room_id):
				if (l.get("guards", []) as Array).has(id):
					var n := world.npc(id)
					foes.append({"monster": str(n.get("monster", "guard")), "name": str(n.get("name", id)), "desc": str(n.get("description", "")),
						"npc_id": id, "col": 1, "by_hero": true, "law": true})
			s.pending_fight = foes
			lines.append_array(let_go(s, data, "Вы сопротивляетесь страже"))  # fought free — no new patrol at once (big test #6)
	return lines


## Paid or served: the crimes of the location are settled, the hero is free, the location forgives a step.
static func _settle(s: GameSession, data: Dictionary, loc: String) -> Array[String]:
	for crime: Dictionary in _open(s, loc):
		crime["settled"] = true
		_rewarn(s, crime)
	s.wanted.erase(loc)
	s.let_go.erase(loc)
	s.arrest = ""
	for id: String in people_of(data, loc):
		if not s.dead_npcs.has(id):
			if int(cfg(data)["forgiven"]) != 0:
				s.shift_attitude(id, int(cfg(data)["forgiven"]), data)
			s.remember(id, "герой отбыл наказание за преступление — но доверия ему нет")
	var lines: Array[String] = ["Вы больше не в розыске — но люди помнят"]  # the guilt stays (v0.7.22.10, big test #7)
	var back := int(ReputationRules.cfg(data)["points"]["crime_settled"])
	if back != 0:
		lines.append_array(ReputationRules.add(s, data, loc, back, "вина искуплена"))  # v0.7.17
	return lines


## A punished trespass starts the count anew (v0.7.39.2, the author: arrested at every entry after the second): the
## next walk in unasked is a warning again.
static func _rewarn(s: GameSession, crime: Dictionary) -> void:
	if str(crime.get("kind", "")) == "trespass":
		s.trespass_warned.erase(str(crime.get("site", "")))


# --- the body -----------------------------------------------------------------------------------------------


## The bodies in this room: [{npc_id, name}].
static func bodies_here(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in s.bodies:
		if str(s.bodies[id]) == s.room_id:
			out.append({"npc_id": id, "name": "Тело: " + str(WorldView.new(data["world"]).npc(id).get("name", id)), "searched": s.searched.has(id)})
	return out


## Searching a body: its pockets and a few things of its wares; living NPCs here see a theft. Lines.
static func search_body(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var c := s.character
	var got: Array[String] = []
	for e: Dictionary in TheftRules.pockets(s, data, npc_id):
		if int(e.get("cp", 0)) > 0:
			c["gold_cp"] = int(c["gold_cp"]) + int(e["cp"])
			got.append(Money.format(int(e["cp"])))
		elif not str(e.get("item_id", "")).is_empty():
			ItemRules.found(c, data, s.items, str(e["item_id"]), int(e.get("qty", 1)))
			got.append(str(e["name"]))
	s.pockets[npc_id] = []
	# What a trader carried of its wares — out of its stock, the rest stays in its shop (v0.7.22.8).
	var wares: Dictionary = TradeRules.merchant(s, data, npc_id)["stock"] if bool(world.npc(npc_id).get("trader", false)) else {}
	var stock := wares.keys().filter(func(id: Variant) -> bool: return int(wares[id]) > 0)
	for i in mini(stock.size(), int(cfg(data)["body_wares"])):
		var id := str(stock[i])
		ItemRules.found(c, data, s.items, id, 1)
		wares[id] = int(wares[id]) - 1
		if int(wares[id]) <= 0:
			wares.erase(id)
		got.append(ItemRules.display_name(data["items"], s.items, id))
	s.searched.append(npc_id)
	var lines: Array[String] = ["Обыскано тело %s: %s" % [world.npc(npc_id).get("name", npc_id), ", ".join(got) if not got.is_empty() else "ничего"]]
	var seen := s.npcs_here(world.world, s.room_id)
	if not seen.is_empty() and not ConditionRules.invisible(c, data):
		s.shift_attitude(seen[0], int(data["rules"]["theft"]["caught_attitude"]), data)
		lines.append("%s видит, как вы обираете мёртвого: отношение хуже" % world.npc(seen[0]).get("name", seen[0]))
	lines.append_array(FaithRules.deed(s, data, "rob_dead"))  # v0.7.49
	return lines


# --- for the master -----------------------------------------------------------------------------------------


## The snapshot part (protocol 0.19.0): {deeds, wanted, arrest} or {} when the hero has no crimes.
static func snapshot(s: GameSession, data: Dictionary) -> Dictionary:
	if s.crimes.is_empty():
		return {}
	var world := WorldView.new(data["world"])
	var deeds: Array[String] = []
	for crime: Dictionary in s.crimes:
		var w: Array = crime["witnesses"]
		deeds.append("%s %s [%s] — %s, день %d; %s%s" % ["нападение на" if _assault(crime) else "убит(а)", world.npc(str(crime["victim"])).get("name", crime["victim"]), crime["victim"],
			world.room(str(crime["room"])).get("name", crime["room"]), int(crime["at"]) / 1440 + 1,
			("видели: " + ", ".join(w.map(func(id: Variant) -> String: return str(world.npc(str(id)).get("name", id)))) + "; ") if not w.is_empty() else "",
			"искуплено" if bool(crime["settled"]) else ("знает вся округа" if bool(crime["known"]) else "никто не знает — тайна героя")])
	var out := {"deeds": deeds, "wanted": wanted_at(s, data, s.room_id), "arrest": held(s)}
	if held(s):  # v0.7.22.2: where the guard may lead the hero — the rooms of the law's people
		var escort: Array[String] = []
		for g: Variant in law(data, world.location_id(s.room_id)).get("guards", []):
			var r := WorldMap.npc_room(world.world, str(g))
			if not r.is_empty() and r != s.room_id:
				escort.append("%s — %s [%s]" % [world.npc(str(g)).get("name", g), world.room(r).get("name", r), r])
		out["escort_to"] = escort
	return out
