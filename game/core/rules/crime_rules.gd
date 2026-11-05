class_name CrimeRules
extends RefCounted
## Crimes of the hero (roadmap v0.7.14, the author's finding: a priestess killed in the temple was forgotten at once).
## A murder is a fight the hero began (a scene NPC attacked by words, the guard resisted) that ends with a pack NPC
## dead; a fight the NPC began (a caught theft, an ambush) is self-defence. The crime is a fact of the world in
## s.crimes [{id, victim, room, location, at, witnesses, known, settled}]:
##   the living NPCs of the room are witnesses — they know at once; without witnesses the body is found after
##   rules.crime.found_minutes (or the hero confesses — the master's `crime:known`), then the whole location knows.
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
## passed at the talk tier (`crime:release`).
## v0.8.4.21: a crime has a doer (`by`; the hero when a record has none) — anybody may steal, assault, kill, force a door
## or walk in unasked. Its witnesses are WatchRules.eyes of the doer; its wanted, sentence and guilt are the doer's; its
## rumour names the doer. What people think of the hero, its fame, factions and vows hear only the hero's deeds.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["crime"]


## Who did it: the hero, or a person's id.
static func doer_of(crime: Dictionary) -> String:
	return str(crime.get("by", Being.HERO))


## Where `doer` is wanted {location: abs minute}: the hero's `s.wanted`, a person's part of its record.
static func wanted_of(s: GameSession, doer: String = Being.HERO) -> Dictionary:
	if doer == Being.HERO:
		return s.wanted
	var b := Being.of(s, doer)
	if not (b.get("wanted") is Dictionary):
		b["wanted"] = {}
	return b["wanted"]


## A crime of `doer` written down: one record for every kind; `fields` — its kind, victim, room, location and the rest.
static func _record(s: GameSession, doer: String, fields: Dictionary) -> Dictionary:
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "by": doer, "at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false}
	crime.merge(fields, true)
	s.crimes.append(crime)
	return crime


## The deed's word with its doer: «Нападение» for the hero, «Нападение (Гуннар)» for a person.
static func _word(data: Dictionary, word: String, doer: String) -> String:
	return word if doer == Being.HERO else "%s (%s)" % [word, WorldView.name_of(data, doer)]


## v0.7.22.16: a crime has a kind (rules.crime.kinds) — `murder` or `assault`: a pack
## NPC the hero attacked and left alive. An assault is known at once when someone saw it or the victim stayed awake;
## a victim knocked out with nobody by tells when it wakes or is let go. It is not a body: never found by a search,
## never buried; a victim finished off after it — its assault becomes the murder.
static func kind_of(data: Dictionary, crime: Dictionary) -> Dictionary:
	var kinds: Dictionary = cfg(data).get("kinds", {})
	return kinds.get(str(crime.get("kind", "murder")), kinds.get("murder", {"severity": 1, "name": "убийство"}))


static func _assault(crime: Dictionary) -> bool:
	return str(crime.get("kind", "murder")) == "assault"


## Those who really saw `doer` do it (v0.8.3): people of the room by WatchRules.eyes, invisibility and Stealth there.
static func _eyes(s: GameSession, data: Dictionary, victim: String, room_id: String, doer: String = Being.HERO) -> Array:
	var here := s.npcs_here(data["world"], room_id).filter(func(id: String) -> bool: return id != victim and id != doer)
	return WatchRules.eyes(s, data, here, doer)


## The witnesses think worse of the hero; a person's deed they only know (the attitude is to the hero).
static func _seen(s: GameSession, data: Dictionary, witnesses: Array, doer: String) -> void:
	if doer != Being.HERO:
		return
	for w: String in witnesses:
		s.shift_attitude(w, int(cfg(data)["witness_attitude"]), data)


## A fight the hero began ended with a pack NPC alive (knocked out, surrendered, at peace, fled): an assault.
## `aware` — the victim saw who did it and is awake. Lines.
static func on_assault(s: GameSession, data: Dictionary, npc_id: String, aware: bool, room_id: String, doer: String = Being.HERO) -> Array[String]:
	var world := WorldView.new(data["world"])
	var witnesses := _eyes(s, data, npc_id, room_id, doer)
	var crime := _record(s, doer, {"kind": "assault", "victim": npc_id, "room": room_id, "location": world.location_id(room_id), "witnesses": witnesses})
	var faith := WorldEvent.deed(s, data, "assault", room_id, doer)  # v0.7.49
	var who := WorldView.name_of(data, npc_id)
	var word := _word(data, "Нападение", doer)
	if witnesses.is_empty() and not aware:
		return ["%s: %s — никто не видел, %s без сознания" % [word, who, who]] + faith
	_seen(s, data, witnesses, doer)
	var lines: Array[String] = ["%s: %s%s" % [word, who, (" — видели: " + ", ".join(witnesses.map(func(id: String) -> String: return WorldView.name_of(data, id)))) if not witnesses.is_empty() else ""]]
	lines.append_array(_known(s, data, crime))
	lines.append_array(faith)
	return lines


## Walking into a private room before eyes (v0.7.22.24, SiteRules): a light crime where there is law — known at
## once, its wergild by `rules.crime.kinds.trespass`. Lines.
static func on_trespass(s: GameSession, data: Dictionary, owner: String, room_id: String, witnesses: Array, doer: String = Being.HERO) -> Array[String]:
	var world := WorldView.new(data["world"])
	var loc := world.location_id(room_id)
	if law(data, loc).is_empty():
		return []
	var crime := _record(s, doer, {"kind": "trespass", "victim": owner, "room": room_id, "site": world.site_id(room_id), "location": loc,
		"witnesses": witnesses.filter(func(id: String) -> bool: return id != owner)})
	return _known(s, data, crime) + WorldEvent.deed(s, data, "trespass", room_id, doer)


## A loan whose collateral is gone ran past its grace (v0.7.28, BankRules): the crime `debt` against the creditor in
## the bank's location, known at once; its wergild is the debt itself. Returns [crime id, lines...].
static func on_debt(s: GameSession, data: Dictionary, creditor: String, loc: String, amount_cp: int, doer: String = Being.HERO) -> Array[String]:
	var crime := _record(s, doer, {"kind": str(data["rules"].get("bank", {}).get("debt_crime", "debt")), "victim": creditor, "room": "", "location": loc,
		"fine_cp": amount_cp})
	var out: Array[String] = [str(crime["id"])]
	out.append_array(_known(s, data, crime))
	out.append_array(WorldEvent.deed(s, data, str(crime["kind"]), "", doer))
	return out


## A false denunciation (v0.7.48, LetterRules): the law of `loc` read a letter against an innocent `victim` — the
## hero's crime, known there at once. Lines.
static func on_false_report(s: GameSession, data: Dictionary, victim: String, loc: String, doer: String = Being.HERO) -> Array[String]:
	var crime := _record(s, doer, {"kind": "false_report", "victim": victim, "room": "", "location": loc})
	return _known(s, data, crime) + WorldEvent.deed(s, data, "false_report", "", doer)


## A criminal job seen or traced (v0.7.33, HeistRules): its crime of `kind` known at once in `loc` (where the law
## looks for it), the victim — an NPC or "". Lines.
static func on_job(s: GameSession, data: Dictionary, kind: String, victim: String, room_id: String, loc: String, doer: String = Being.HERO) -> Array[String]:
	var crime := _record(s, doer, {"kind": kind, "victim": victim, "room": room_id, "location": loc})
	return _known(s, data, crime) + WorldEvent.deed(s, data, kind, room_id, doer)


## One crime closed outside the law's hold (v0.7.28: the debt paid at the bank); the location's wanted goes when no
## other open crime is left there. Lines.
static func settle_one(s: GameSession, data: Dictionary, crime_id: String) -> Array[String]:
	for crime: Dictionary in s.crimes:
		if str(crime["id"]) != crime_id or bool(crime["settled"]):
			continue
		crime["settled"] = true
		_rewarn(s, crime)
		var loc := str(crime["location"])
		var doer := doer_of(crime)
		if _open(s, loc, doer).is_empty() and wanted_of(s, doer).has(loc):
			wanted_of(s, doer).erase(loc)
			if doer != Being.HERO:
				return ["%s больше не в розыске: %s" % [WorldView.name_of(data, doer), WorldView.location_name(data, loc)]]
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
	return WorldView.new(data["world"]).location_inherit(location_id, "law", {})


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


## The pack NPC killed in a fight: the body stays, its quests pass to the heir or fail, and a fight `doer` began
## (`by_hero` — by the doer's hand) is a murder. Lines.
static func on_death(s: GameSession, data: Dictionary, npc_id: String, by_hero: bool, room_id: String, doer: String = Being.HERO) -> Array[String]:
	var world := WorldView.new(data["world"])
	var lines := WorldEvent.emit(s, data, "dying", {"npc": npc_id})
	s.crimes = s.crimes.filter(func(c: Dictionary) -> bool: return not (_assault(c) and str(c["victim"]) == npc_id and not bool(c["known"])))  # finished off: the murder
	if not Being.dead(s, npc_id):
		Being.die(s, npc_id)
	Being.unfollow(s, npc_id)
	Being.of(s, npc_id)["body"] = room_id
	Being.of(s, npc_id)["body_at"] = TimeRules.abs_minute(s)  # buried some days later (v0.7.22.10)
	lines.append_array(WorldEvent.emit(s, data, "death", {"npc": npc_id, "by_hero": by_hero, "room": room_id}))
	if not by_hero:
		return lines
	var witnesses := _eyes(s, data, npc_id, room_id, doer)  # an unseen killer: they saw a death, not who did it
	var crime := _record(s, doer, {"kind": "murder", "victim": npc_id, "room": room_id, "location": world.location_id(room_id), "witnesses": witnesses})
	var who := str(world.npc_name(npc_id))
	var word := _word(data, "Убийство", doer)
	if witnesses.is_empty():
		lines.append("%s: %s — свидетелей нет" % [word, who])
		return lines + WorldEvent.deed(s, data, "murder", room_id, doer)  # v0.7.49
	lines.append("%s: %s — видели: %s" % [word, who, ", ".join(witnesses.map(func(id: String) -> String: return str(world.npc_name(id))))])
	_seen(s, data, witnesses, doer)
	lines.append_array(_known(s, data, crime))
	lines.append_array(WorldEvent.deed(s, data, "murder", room_id, doer))
	return lines


## The crime becomes known in its location: attitudes, and the hero is wanted where there is law. Lines.
static func _known(s: GameSession, data: Dictionary, crime: Dictionary) -> Array[String]:
	crime["known"] = true
	crime["known_at"] = TimeRules.abs_minute(s)
	return WorldEvent.emit(s, data, "crime_known", {"crime": str(crime.get("kind", "murder")), "victim": str(crime["victim"]), "record": crime})


## The people of the location learn of it. Lines.
static func people_know(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var crime: Dictionary = f["record"]
	var loc := str(crime["location"])
	var victim := str(crime["victim"])
	var kind := kind_of(data, crime)
	var lines: Array[String] = []
	# v0.7.22.24: a kind may set its own echo — the location's attitude, the memory, a share of the reputation
	var att := int(kind.get("known_attitude", -1 if _assault(crime) else int(cfg(data)["attitude"])))
	var doer := doer_of(crime)
	if doer != Being.HERO:  # a person's crime: the people know it of the doer; what they think of the hero stays
		for id: String in people_of(data, loc):
			if not Being.dead(s, id) and id != victim and id != doer:
				s.remember(id, "знает: %s — %s, сделал%s %s" % [WorldView.name_of(data, victim), str(kind["name"]), _ending(data, doer), WorldView.name_of(data, doer)])
		return lines
	if att != 0:
		lines.append("%s знает: %s — отношение хуже" % [WorldView.new(data["world"]).location(loc).get("name", loc), kind["name"]])
	for id: String in people_of(data, loc):
		if not Being.dead(s, id) and id != victim:
			if att != 0:
				s.shift_attitude(id, att, data)
			s.remember(id, (str(kind["memory"]).format({"victim": WorldView.name_of(data, victim)})) if kind.has("memory") else
				("знает: герой напал на %s" % WorldView.name_of(data, victim)) if _assault(crime) else
				("знает: %s убит%s героем" % [WorldView.name_of(data, victim), _ending(data, victim)]))
	return lines


## The settlement's opinion and the news to the neighbours. Lines.
static func fame_known(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var crime: Dictionary = f["record"]
	var kind := kind_of(data, crime)
	var share := int(kind.get("reputation_share", 2 if _assault(crime) else 1))
	var delta := int(ReputationRules.cfg(data)["points"]["crime_known"]) / share if share > 0 else 0
	var lines: Array[String] = []
	if doer_of(crime) != Being.HERO:  # the fame is the hero's: a person's crime is only the news
		delta = 0
	elif share > 0:
		lines.append_array(ReputationRules.add(s, data, str(crime["location"]), delta, str(kind["name"]), false))  # v0.7.17
	RumorRules.on_crime(s, data, crime, delta)  # v0.7.47: the news, the blame and the wanted go on to the neighbours
	return lines


## Where there is law the doer is wanted. Lines.
static func wanted_known(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var loc := str(f["record"]["location"])
	if law(data, loc).is_empty():
		return []
	var doer := doer_of(f["record"])
	var wanted := wanted_of(s, doer)
	if not wanted.has(loc):
		wanted[loc] = TimeRules.abs_minute(s)
	if doer != Being.HERO:  # the hold is the hero's: a person is only wanted
		return ["%s в розыске: %s" % [WorldView.name_of(data, doer), law(data, loc).get("name", "стража")]]
	var lines: Array[String] = ["Вы в розыске: %s" % law(data, loc).get("name", "стража")]
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
				lines.append("Нашли тело: %s" % WorldView.name_of(data, str(crime["victim"])))
				lines.append_array(_known(s, data, crime))
			continue
		var days := (now - int(crime["at"])) / 1440
		while int(crime.get("searched_days", 0)) < days and not bool(crime["known"]):
			crime["searched_days"] = int(crime.get("searched_days", 0)) + 1
			var dc := int(crime["hide_dc"]) + int(h["day_step"]) * int(crime["searched_days"])
			if Roll.check(s, data, {"monster": str(h.get("searcher", "guard"))}, {"skill": "investigation", "bonus": int(h["search_bonus"]), "dc": dc})["ok"]:
				lines.append("Нашли спрятанное тело: %s" % WorldView.name_of(data, str(crime["victim"])))
				lines.append_array(_known(s, data, crime))
	lines.append_array(bury(s, data))
	return lines


## "" when the hero can hide this body now: it lies here and its murder is still a secret.
static func can_hide(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if str(Being.view(s, npc_id).get("body", "")) != s.room_id:
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
			return ["Тело %s спрятано: искать его будут, но найти непросто" % WorldView.name_of(data, npc_id)]
	return []


## Gentle Repose (v0.8.4.26.3): the bodies lying in `room` keep for `days` — nobody buries them before. Lines.
static func repose(s: GameSession, data: Dictionary, room: String, days: int) -> Array[String]:
	var out: Array[String] = []
	for npc_id: String in Being.with(s, "body"):
		if str(Being.view(s, npc_id)["body"]) == room:
			Being.of(s, npc_id)["repose_until"] = TimeRules.abs_minute(s) + days * 1440
			out.append("тело %s не тронет тление %d дней" % [WorldView.name_of(data, npc_id), days])
	return out if not out.is_empty() else ["здесь нет тела, которое нужно сберечь"] as Array[String]


## Known bodies are buried after rules.crime.bury_days (a body of a hidden murder is not — nobody knows of it). Lines.
static func bury(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var world := WorldView.new(data["world"])
	for npc_id: String in Being.with(s, "body"):
		var since := int(Being.view(s, npc_id).get("body_at", 0))
		var secret := false
		for crime: Dictionary in s.crimes:
			if str(crime["victim"]) == npc_id:
				secret = not bool(crime["known"])
				since = int(crime.get("known_at", since))
		if secret or now - since < int(cfg(data)["bury_days"]) * 1440 or now < int(Being.view(s, npc_id).get("repose_until", 0)):
			continue
		var room := str(Being.of(s, npc_id)["body"])
		Being.drop(s, npc_id, "body")
		lines.append("Похоронили: %s — там, где лежало тело (%s), осталось тёмное пятно" % [WorldView.name_of(data, npc_id), world.room(room).get("name", room)])
	return lines


## The master's `crime:known`: the hero confessed or was exposed. {"reason"} or {"plan", "summary"}.
static func plan_reveal(s: GameSession, data: Dictionary, victim: String) -> Dictionary:
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == victim and not bool(crime["known"]):
			var what := str(kind_of(data, crime)["name"])
			return {"plan": {"victim": victim}, "summary": "%s раскрыто: %s" % [what.left(1).to_upper() + what.substr(1), WorldView.name_of(data, victim)]}
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


## `doer` is wanted in the location of `room_id`.
static func wanted_at(s: GameSession, data: Dictionary, room_id: String, doer: String = Being.HERO) -> bool:
	return wanted_of(s, doer).has(WorldView.new(data["world"]).location_id(room_id))


## An NPC who turns the wanted away (traders do not trade, givers give nothing); `who` — anybody, the hero by default.
## Every service asks it through `SocialRules.service_why`.
static func shunned_by(s: GameSession, data: Dictionary, npc_id: String, who: String = Being.HERO) -> bool:
	var loc := ReputationRules.home_of(data, npc_id)
	return wanted_of(s, who).has(loc) and not (who == Being.HERO and BondRules.close(s, data, npc_id))  # v0.7.31: a close friend serves the wanted


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
		and not WatchRules.sneaky(s, data)
	if patrol and s.let_go.has(loc):
		patrol = s.rng.randf() < float(cfg(data)["patrol_chance"])
	if guards.is_empty() and not patrol:
		return []
	if Guise.fools(s, data, s.character, str(guards[0]) if not guards.is_empty() else "patrol:" + loc):
		return []  # v0.7.63: the wanted one is somebody else to this guard
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
		if foes.any(func(f: Dictionary) -> bool: return str(f.get("npc_id", "")) == id) or Being.follows(s, id):
			continue
		if s.attitude(id) >= int(d["friend_attitude"]):
			continue
		var n := world.npc(id)
		var tags: Array = n.get("tags", [])
		if not guards.has(id) and not tags.any(func(t: Variant) -> bool: return (d["tags"] as Array).has(t)):
			continue
		out.append({"monster": str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"])), "name": str(n.get("name", id)),
			"desc": str(n.get("description", "")), "npc_id": id, "by_hero": true, "law": guards.has(id)})
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


## The wergild for the unsettled known crimes of `doer` in the location: fine_cp each, ×notable_mult for notable victims.
static func fine(s: GameSession, data: Dictionary, loc: String, doer: String = Being.HERO) -> int:
	var total := 0
	var debts := 0
	for crime: Dictionary in _open(s, loc, doer):
		if crime.has("fine_cp"):  # a debt's wergild is the debt (v0.7.28)
			debts += int(crime["fine_cp"])
			continue
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		var notable := tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t))
		total += int(kind_of(data, crime).get("fine_cp", cfg(data)["fine_cp"])) * (int(cfg(data)["notable_mult"]) if notable else 1)
	if doer == Being.HERO and not BondRules.intercessor(s, data, loc).is_empty():  # v0.7.31: a friend of the law speaks for the hero
		total = Price.share(total, float(BondRules.cfg(data)["perks"]["intercede"]["fine_pct"]))
	return total + debts


## The weight of the open crimes of the location for the sentence and the talk (v0.7.22.16): the sum of their kinds.
static func _weight(s: GameSession, data: Dictionary, loc: String, doer: String = Being.HERO) -> int:
	var w := 0
	for crime: Dictionary in _open(s, loc, doer):
		w += int(kind_of(data, crime).get("severity", 1))
	return w


## The guilt of `doer` in the location: its known crimes there not yet settled.
static func _open(s: GameSession, loc: String, doer: String = Being.HERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crime: Dictionary in s.crimes:
		if str(crime["location"]) == loc and bool(crime["known"]) and not bool(crime["settled"]) and doer_of(crime) == doer:
			out.append(crime)
	return out


static func stocks_days(s: GameSession, data: Dictionary, loc: String, doer: String = Being.HERO) -> int:
	return int(sentence(s, data, loc, doer)["days"])


## The sentence for the open crimes of the location (v0.7.22.10): the highest of rules.crime.sentences whose severity
## fits — the crimes, +1 for a notable victim. {kind, days, name, exhaustion?}.
static func sentence(s: GameSession, data: Dictionary, loc: String, doer: String = Being.HERO) -> Dictionary:
	var severity := _weight(s, data, loc, doer)
	for crime: Dictionary in _open(s, loc, doer):
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		if tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t)):
			severity += 1
			break
	if doer == Being.HERO and not BondRules.intercessor(s, data, loc).is_empty():
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
	return Price.share(fine(s, data, loc), float(cfg(data)["bribe_share"]) * 100.0)


## "" when the arrest can be answered this way: pay / stocks / resist / persuade / deceive / intimidate / bribe.
static func can_answer(s: GameSession, data: Dictionary, how: String) -> String:
	if not held(s):
		return "CRIME_NOT_HELD"
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	if how == "pay" and Ledger.balance(s) < fine(s, data, loc):
		return "CRIME_NO_MONEY"
	if (TALK.has(how) or how in ["bribe", "resist"]) and s.arrest_tried.has(how):
		return "CRIME_TRIED"
	if how == "bribe" and Ledger.balance(s) < bribe(s, data, loc):
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


## The master's `crime:release`: the guard lets the hero go by words — only after a check this turn that passed at
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
			Ledger.add(s, -bcp, "crime:answer")
			s.arrest_tried.append("bribe")
			lines.append("Взятка: −%s" % Money.format(bcp))
			lines.append_array(let_go(s, data, "Стража смотрит в сторону — но розыск не снят"))
		"pay":
			var cp := fine(s, data, loc)
			Ledger.add(s, -cp, "crime:answer")
			lines.append("Вергельд уплачен: −%s" % Money.format(cp))
			lines.append_array(_settle(s, data, loc))
		"stocks":  # the sentence by severity (v0.7.22.10): prison or hard labour, the hero wakes in the law's prison
			var sn := sentence(s, data, loc)
			var days := int(sn["days"])
			var prison := str(l.get("prison", "")) if str(sn.get("kind", "")) != "stocks" else ""  # the stocks — where the hero stands
			if not prison.is_empty() and data["world"]["rooms"].has(prison):
				s.room_id = prison
				if not s.visited.has(prison):
					s.visited.append(prison)
			var passed := TimeRules.jump(s, data, days)  # the world's days pass too (v0.8.4.17)
			s.character["hp"] = int(s.character["max_hp"])  # the wounds healed in the days
			lines.append("%d дн. — %s; день %d, утро, %s; вещи вернули" % [days, sn["name"], s.day,
				world.room(s.room_id).get("name", s.room_id)])
			lines.append_array(passed)
			if int(sn.get("exhaustion", 0)) > 0:
				lines.append_array(ConditionRules.add_exhaustion(s, data, int(sn["exhaustion"]), str(sn["name"])))
			lines.append_array(_settle(s, data, loc))
		"resist":
			var foes: Array = [{"monster": str(l.get("guard_monster", "guard")), "count": int(cfg(data)["patrol_size"]),
				"name": str(l.get("guard_name", "Стражник")), "by_hero": true, "law": true}]
			for id: String in s.npcs_here(world.world, s.room_id):
				if (l.get("guards", []) as Array).has(id):
					var n := world.npc(id)
					foes.append({"monster": str(n.get("monster", "guard")), "name": str(n.get("name", id)), "desc": str(n.get("description", "")),
						"npc_id": id, "by_hero": true, "law": true})
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
		if not Being.dead(s, id):
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
	for id: String in Being.with(s, "body"):
		if str(Being.of(s, id)["body"]) == s.room_id:
			out.append({"npc_id": id, "name": "Тело: " + str(WorldView.new(data["world"]).npc_name(id)), "searched": Being.searched(s, id)})
	return out


## Searching a body: all it had and a few things of its wares; living NPCs here see a theft. Lines.
static func search_body(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var c := s.character
	var got: Array[String] = []
	var things := Gear.strip(s, data, npc_id, false)
	if int(things["cp"]) > 0:
		Ledger.add(s, int(things["cp"]), "crime:search_body")
		got.append(Money.format(int(things["cp"])))
	for item: String in things["items"]:
		ItemRules.found(c, data, s.items, item, int(things["items"][item]))
		got.append(ItemRules.display_name(data["items"], s.items, item))
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
	Being.search(s, npc_id)
	var lines: Array[String] = ["Обыскано тело %s: %s" % [world.npc_name(npc_id), ", ".join(got) if not got.is_empty() else "ничего"]]
	var seen := _eyes(s, data, npc_id, s.room_id)
	if not seen.is_empty():
		s.shift_attitude(seen[0], int(data["rules"]["theft"]["caught_attitude"]), data)
		lines.append("%s видит, как вы обираете мёртвого: отношение хуже" % world.npc_name(seen[0]))
	lines.append_array(WorldEvent.deed(s, data, "rob_dead"))  # v0.7.49
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
			var r := Where.npc_room(s, data, str(g))
			if not r.is_empty() and r != s.room_id:
				escort.append("%s — %s [%s]" % [world.npc(str(g)).get("name", g), world.room(r).get("name", r), r])
		out["escort_to"] = escort
	return out
