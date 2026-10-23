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
	if not s.dead_npcs.has(npc_id):
		s.dead_npcs.append(npc_id)
	s.bodies[npc_id] = room_id
	lines.append_array(QuestRules.on_death(s, data, npc_id))
	if not by_hero:
		return lines
	var witnesses := s.npcs_here(world.world, room_id).filter(func(id: String) -> bool: return id != npc_id)
	if ConditionRules.invisible(s.character, data):
		witnesses = []  # an unseen killer: they saw a death, not who did it
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "victim": npc_id, "room": room_id, "location": world.location_id(room_id),
		"at": TimeRules.abs_minute(s), "witnesses": witnesses, "known": false, "settled": false}
	s.crimes.append(crime)
	var who := str(world.npc(npc_id).get("name", npc_id))
	if witnesses.is_empty():
		lines.append("Убийство: %s — свидетелей нет" % who)
		return lines
	lines.append("Убийство: %s — видели: %s" % [who, ", ".join(witnesses.map(func(id: String) -> String: return str(world.npc(id).get("name", id))))])
	for w: String in witnesses:
		s.shift_attitude(w, int(cfg(data)["witness_attitude"]), data)
	lines.append_array(_known(s, data, crime))
	return lines


## The crime becomes known in its location: attitudes, and the hero is wanted where there is law. Lines.
static func _known(s: GameSession, data: Dictionary, crime: Dictionary) -> Array[String]:
	crime["known"] = true
	var loc := str(crime["location"])
	var world := WorldView.new(data["world"])
	var lines: Array[String] = ["%s знает об убийстве: отношение хуже" % world.location(loc).get("name", loc)]
	for id: String in people_of(data, loc):
		if not s.dead_npcs.has(id):
			s.shift_attitude(id, int(cfg(data)["attitude"]), data)
			s.remember(id, "знает: %s убит%s героем" % [_name(data, str(crime["victim"])), _ending(data, str(crime["victim"]))])
	lines.append_array(ReputationRules.add(s, data, loc, int(ReputationRules.cfg(data)["points"]["crime_known"]), "убийство"))  # v0.7.17
	if not law(data, loc).is_empty():
		if not s.wanted.has(loc):
			s.wanted[loc] = TimeRules.abs_minute(s)
		lines.append("Вы в розыске: %s" % law(data, loc).get("name", "стража"))
		lines.append_array(check_arrest(s, data))
	return lines


## Hidden crimes whose body is found by now (rules.crime.found_minutes). Called as time passes. Lines.
static func spread(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	for crime: Dictionary in s.crimes:
		if not bool(crime["known"]) and now - int(crime["at"]) >= int(cfg(data)["found_minutes"]):
			lines.append("Нашли тело: %s" % _name(data, str(crime["victim"])))
			lines.append_array(_known(s, data, crime))
	return lines


## The master's `crime_known`: the hero confessed or was exposed. {"reason"} or {"plan", "summary"}.
static func plan_reveal(s: GameSession, data: Dictionary, victim: String) -> Dictionary:
	for crime: Dictionary in s.crimes:
		if str(crime["victim"]) == victim and not bool(crime["known"]):
			return {"plan": {"victim": victim}, "summary": "Убийство раскрыто: %s" % _name(data, victim)}
	return {"reason": "тайного убийства %s нет" % victim}


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
	return s.wanted.has(loc)


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


static func held(s: GameSession) -> bool:
	return not s.arrest.is_empty() and s.arrest == s.room_id


## The wergild for the unsettled known crimes of the location: fine_cp each, ×notable_mult for notable victims.
static func fine(s: GameSession, data: Dictionary, loc: String) -> int:
	var total := 0
	for crime: Dictionary in _open(s, loc):
		var tags: Array = WorldView.new(data["world"]).npc(str(crime["victim"])).get("tags", [])
		var notable := tags.any(func(t: Variant) -> bool: return (cfg(data)["notable_tags"] as Array).has(t))
		total += int(cfg(data)["fine_cp"]) * (int(cfg(data)["notable_mult"]) if notable else 1)
	return total


static func _open(s: GameSession, loc: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crime: Dictionary in s.crimes:
		if str(crime["location"]) == loc and bool(crime["known"]) and not bool(crime["settled"]):
			out.append(crime)
	return out


static func stocks_days(s: GameSession, data: Dictionary, loc: String) -> int:
	return int(cfg(data)["stocks_days"]) * maxi(1, _open(s, loc).size())


## The talk answers to the guard and their skills (v0.7.22.2).
const TALK := {"persuade": "persuasion", "deceive": "deception", "intimidate": "intimidation"}


## The tier of talking the guard out of it: talk_tier, one step harder for each crime past the first and a notable victim.
static func talk_tier(s: GameSession, data: Dictionary, loc: String) -> String:
	var tiers: Array = (data["rules"]["dc_tiers"] as Dictionary).keys()
	var i := tiers.find(str(cfg(data)["talk_tier"])) + maxi(0, _open(s, loc).size() - 1)
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
	if (TALK.has(how) or how == "bribe") and s.arrest_tried.has(how):
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
		"stocks":
			var days := stocks_days(s, data, loc)
			s.day += days
			s.minute = int(TimeRules.cfg(data)["wake_minute"])
			s.rested_at = TimeRules.abs_minute(s)
			s.awake_saves = 0
			lines.append("%d дн. в колодках — день %d, утро; вещи вернули" % [days, s.day])
			lines.append_array(ConditionRules.expire(s, data))
			lines.append_array(_settle(s, data, loc))
		"resist":
			var foes: Array = [{"monster": str(l.get("guard_monster", "guard")), "count": int(cfg(data)["patrol_size"]),
				"name": str(l.get("guard_name", "Стражник")), "col": 1, "by_hero": true}]
			for id: String in s.npcs_here(world.world, s.room_id):
				if (l.get("guards", []) as Array).has(id):
					var n := world.npc(id)
					foes.append({"monster": str(n.get("monster", "guard")), "name": str(n.get("name", id)), "desc": str(n.get("description", "")),
						"npc_id": id, "col": 1, "by_hero": true})
			s.pending_fight = foes
			lines.append_array(let_go(s, data, "Вы сопротивляетесь страже"))  # fought free — no new patrol at once (big test #6)
	return lines


## Paid or served: the crimes of the location are settled, the hero is free, the location forgives a step.
static func _settle(s: GameSession, data: Dictionary, loc: String) -> Array[String]:
	for crime: Dictionary in _open(s, loc):
		crime["settled"] = true
	s.wanted.erase(loc)
	s.let_go.erase(loc)
	s.arrest = ""
	for id: String in people_of(data, loc):
		if not s.dead_npcs.has(id):
			s.shift_attitude(id, int(cfg(data)["forgiven"]), data)
	var lines: Array[String] = ["Вы больше не в розыске"]
	lines.append_array(ReputationRules.add(s, data, loc, int(ReputationRules.cfg(data)["points"]["crime_settled"]), "вина искуплена"))  # v0.7.17
	return lines


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
	var stock := TradeRules.pack_stock(world.npc(npc_id), data["rules"]).keys()
	for i in mini(stock.size(), int(cfg(data)["body_wares"])):
		var id := str(stock[i])
		ItemRules.found(c, data, s.items, id, 1)
		got.append(ItemRules.display_name(data["items"], s.items, id))
	s.searched.append(npc_id)
	var lines: Array[String] = ["Обыскано тело %s: %s" % [world.npc(npc_id).get("name", npc_id), ", ".join(got) if not got.is_empty() else "ничего"]]
	var seen := s.npcs_here(world.world, s.room_id)
	if not seen.is_empty() and not ConditionRules.invisible(c, data):
		s.shift_attitude(seen[0], int(data["rules"]["theft"]["caught_attitude"]), data)
		lines.append("%s видит, как вы обираете мёртвого: отношение хуже" % world.npc(seen[0]).get("name", seen[0]))
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
		deeds.append("убит(а) %s [%s] — %s, день %d; %s%s" % [world.npc(str(crime["victim"])).get("name", crime["victim"]), crime["victim"],
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
