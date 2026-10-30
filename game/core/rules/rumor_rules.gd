class_name RumorRules
extends RefCounted
## Rumours (roadmap v0.7.47). A rumour is a concept of the engine: a fact of the world (a quest done, the hero's
## crime known, a death, a new place, the pack's own talk, the master's words) with a weight 1–3, a place of origin
## and a day. It spreads from its location along the map's roads: a location `hops` steps away hears it on
## day + hops × rules.rumors.days_per_hop[weight]. What it carries travels with it: the hero's fame (a share of the
## reputation points) and a known crime — the law of a settlement whose `reach` has the crime's location makes the
## hero wanted there only when the rumour arrives (a law's `reach` may limit the locations it hunts for). The people of a location know its arrived rumours (the important
## ones; a `gossip` NPC all of them): «Расспросить о слухах» once a day, the innkeeper's service `rumor` for a coin,
## the board's notices, the master's `rumor` effect. A rumour may point at a room (and a secret in it) — a tip: heard,
## it puts the room on the map and in the journal; walked into, the tip is checked: true — the secret is found, false —
## the lie is out. A true rumour fades after life_days[weight]; a lie lives until it is refuted. The state lives in
## `generated.rumors` {list {id: rumour}, heard [ids], checked {id: bool}, asked {npc: day}, seq}.


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("rules", {}).get("rumors", {})


static func on(data: Dictionary) -> bool:
	return not cfg(data).is_empty()


static func _state(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("rumors"):
		gen["rumors"] = {"list": {}, "heard": [], "checked": {}, "asked": {}, "seq": 0}
	return gen["rumors"]


static func get_rumor(s: GameSession, id: String) -> Dictionary:
	return _state(s)["list"].get(id, {})


static func heard(s: GameSession, id: String) -> bool:
	return (_state(s)["heard"] as Array).has(id)


static func _loc(data: Dictionary, room_id: String) -> String:
	return WorldView.new(data["world"]).location_id(room_id)


static func _loc_name(data: Dictionary, loc: String) -> String:
	return str(data["world"]["locations"].get(loc, {}).get("name", loc))


## The locations a step of the map away from each other: a room's exit into a room of another location.
static func roads(data: Dictionary) -> Dictionary:
	var out := {}
	var rooms: Dictionary = data["world"]["rooms"]
	for rid: String in rooms:
		var a := str(rooms[rid].get("location_id", ""))
		for e: Variant in rooms[rid].get("exits", []):
			var b := str(rooms.get(str(e), {}).get("location_id", ""))
			if a.is_empty() or b.is_empty() or a == b:
				continue
			for pair: Array in [[a, b], [b, a]]:
				var list: Array = out.get(pair[0], [])
				if not list.has(pair[1]):
					list.append(pair[1])
				out[pair[0]] = list
	return out


## {location: hops} from `from` along the roads (0 — itself).
static func hops(data: Dictionary, from: String) -> Dictionary:
	var out := {from: 0}
	var queue: Array[String] = [from]
	var g := roads(data)
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for nb: Variant in g.get(at, []):
			if not out.has(str(nb)):
				out[str(nb)] = int(out[at]) + 1
				queue.append(str(nb))
	return out


## Puts a rumour into the world: fills its id, day and the days it arrives at every location. `r` — {text, weight,
## origin, truth?, notice?, fame?, crime?, target_room?, target_secret?, source?, id?, day?, until?}. The rumour.
static func add(s: GameSession, data: Dictionary, r: Dictionary) -> Dictionary:
	var st := _state(s)
	if not r.has("id"):
		st["seq"] = int(st["seq"]) + 1
		r["id"] = "r%d" % int(st["seq"])
	var w := clampi(int(r.get("weight", 1)), 1, 3)
	r["weight"] = w
	if not r.has("day"):
		r["day"] = s.day
	r["truth"] = bool(r.get("truth", true))
	if not r.has("until"):
		r["until"] = int(r["day"]) + int(cfg(data)["life_days"][str(w)]) if bool(r["truth"]) else -1  # a lie lives until refuted
	var per := int(cfg(data)["days_per_hop"][str(w)])
	var arrive := {}
	var h := hops(data, str(r["origin"]))
	for loc: String in h:
		arrive[loc] = int(r["day"]) + int(h[loc]) * per
	r["arrive"] = arrive
	if not r.has("landed"):
		r["landed"] = [str(r["origin"])]  # what it carries is already known where it began
	r["refuted"] = bool(r.get("refuted", false))
	st["list"][str(r["id"])] = r
	return r


## The pack's own rumours (world.json `rumors`) put in on the first day or into an older save; once each.
static func seed(s: GameSession, data: Dictionary) -> void:
	if not on(data):
		return
	var st := _state(s)
	var pack: Dictionary = data["world"].get("rumors", {})
	for id: String in pack:
		if st["list"].has(id):
			continue
		var p: Dictionary = pack[id]
		var r := {"id": id, "text": str(p["text"]), "weight": int(p.get("weight", 1)), "origin": str(p["origin"]),
			"day": s.day - int(p.get("ago", 0)), "truth": bool(p.get("truth", true)), "notice": bool(p.get("notice", false)),
			"target_room": str(p.get("target_room", "")), "target_secret": str(p.get("target_secret", "")), "source": "pack"}
		r["until"] = (int(r["day"]) + int(p["days"])) if p.has("days") else -1  # the pack's talk lasts until checked
		add(s, data, r)


static func alive(s: GameSession, r: Dictionary) -> bool:
	return not bool(r.get("refuted", false)) and (int(r.get("until", -1)) < 0 or s.day <= int(r["until"]))


static func arrived(s: GameSession, r: Dictionary, loc: String) -> bool:
	return alive(s, r) and r["arrive"].has(loc) and s.day >= int(r["arrive"][loc])


## The rumours of a location by now: the weighty first, then the newest.
static func known_at(s: GameSession, data: Dictionary, loc: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not on(data):
		return out
	for r: Dictionary in _state(s)["list"].values():
		if arrived(s, r, loc):
			out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["weight"]) > int(b["weight"]) if int(a["weight"]) != int(b["weight"]) else int(a["day"]) > int(b["day"]))
	return out


static func gossip(data: Dictionary, npc_id: String) -> bool:
	return bool(data["world"]["npcs"].get(npc_id, {}).get("gossip", false))


## What an NPC here knows: the place's rumours — the important ones, all of them for a gossip.
static func known_by(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var least := 1 if gossip(data, npc_id) else int(cfg(data)["plain_min_weight"])
	return known_at(s, data, _loc(data, s.room_id)).filter(func(r: Dictionary) -> bool:
		return int(r["weight"]) >= least and str(r.get("about", "")) != npc_id)


static func _fresh(s: GameSession, list: Array[Dictionary]) -> Array[Dictionary]:
	var out := list.filter(func(r: Dictionary) -> bool: return not heard(s, str(r["id"])))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:  # a tip first: it is worth the coin
		return not str(a.get("target_room", "")).is_empty() and str(b.get("target_room", "")).is_empty())
	return out


## The hero hears rumours: they go to the journal, a tip's room onto the map. Lines.
static func hear(s: GameSession, data: Dictionary, ids: Array, who: String = "") -> Array[String]:
	var lines: Array[String] = []
	var st := _state(s)
	for id: Variant in ids:
		var r := get_rumor(s, str(id))
		if r.is_empty() or heard(s, str(id)):
			continue
		st["heard"].append(str(id))
		var room := str(r.get("target_room", ""))
		var marked: bool = not room.is_empty() and data["world"]["rooms"].has(room) and not st["checked"].has(str(id))
		if marked and not s.visited.has(room):
			var scouted: Array = s.character.get("scouted", [])
			if not scouted.has(room):
				scouted.append(room)
			s.character["scouted"] = scouted
		lines.append("%s%s: %s%s" % ["Объявление" if bool(r.get("notice", false)) else "Слух", (" (%s)" % who) if not who.is_empty() else "",
			r["text"], " — отмечено на карте" if marked else ""])
	return lines


## "" when the hero may ask this NPC about rumours now, or a localization key.
static func ask_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not on(data):
		return "RUMOR_ASK_NONE"
	if s.attitude(npc_id) <= int(cfg(data)["ask"]["hostile_at"]):
		return "RUMOR_ASK_HOSTILE"
	if int(_state(s)["asked"].get(npc_id, 0)) == s.day:
		return "RUMOR_ASK_TODAY"
	if _fresh(s, known_by(s, data, npc_id)).is_empty():
		return "RUMOR_ASK_NONE"
	return ""


## «Расспросить о слухах»: the NPC tells what it knows and the hero has not heard — a gossip more. Lines.
static func ask(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var n := int(cfg(data)["ask"]["gossip_tells" if gossip(data, npc_id) else "tells"])
	var picked := _fresh(s, known_by(s, data, npc_id)).slice(0, n).map(func(r: Dictionary) -> String: return str(r["id"]))
	_state(s)["asked"][npc_id] = s.day
	return hear(s, data, picked, str(data["world"]["npcs"].get(npc_id, {}).get("name", npc_id)))


## The service `rumor` (v0.7.16 by data): a rumour of the place the hero has not heard, a tip first; [] — none.
static func for_sale(s: GameSession, data: Dictionary) -> Array[String]:
	if not on(data):
		return []
	var out: Array[String] = []
	for r: Dictionary in _fresh(s, known_at(s, data, _loc(data, s.room_id))):
		out.append(str(r["id"]))
	return out


static func sell(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var ids := for_sale(s, data)
	return hear(s, data, ids.slice(0, 1), str(data["world"]["npcs"].get(npc_id, {}).get("name", npc_id)))


## A new day: the rumours that arrived somewhere bring what they carry — the fame, the wanted. Lines for the hero's
## location only: elsewhere nobody tells the hero.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	var here := _loc(data, s.room_id)
	for r: Dictionary in _state(s)["list"].values():
		if int(r.get("fame", 0)) == 0 and str(r.get("crime", "")).is_empty():
			continue
		for loc: String in r["arrive"]:
			if (r["landed"] as Array).has(loc) or not arrived(s, r, loc):
				continue
			r["landed"].append(loc)
			var got := _land(s, data, r, loc)
			if loc == here and not got.is_empty():
				lines.append("%s: дошёл слух — %s" % [_loc_name(data, loc), r["text"]])
				lines.append_array(got)
	return lines


static func _land(s: GameSession, data: Dictionary, r: Dictionary, loc: String) -> Array[String]:
	var lines: Array[String] = []
	var fame := int(r.get("fame", 0)) * int(cfg(data)["fame"]["share_pct"]) / 100
	var crime: Dictionary = {}
	for c: Dictionary in s.crimes:
		if str(c["id"]) == str(r.get("crime", "")):
			crime = c
	if not crime.is_empty() and bool(crime.get("settled", false)):
		return lines  # atoned before the news came
	if fame != 0:
		lines.append_array(ReputationRules.add(s, data, loc, fame, "дошёл слух", false))
	if not crime.is_empty():
		var law := CrimeRules.law(data, loc)
		var reach: Array = law.get("reach", [str(r["origin"])])  # a law's `reach` limits whose crimes it hunts; none — all
		if not law.is_empty() and reach.has(str(r["origin"])) and not s.wanted.has(loc):
			s.wanted[loc] = TimeRules.abs_minute(s)
			lines.append("Вы в розыске: %s" % law.get("name", "стража"))
	return lines


## The hero's fame grew or fell in `loc` (ReputationRules.add): the talk goes to the neighbours.
static func on_fame(s: GameSession, data: Dictionary, loc: String, delta: int, why: String, crime_id: String = "") -> void:
	if not on(data) or loc.is_empty() or (absi(delta) < int(cfg(data)["fame"]["min"]) and crime_id.is_empty()):
		return
	var steps: Array = cfg(data)["fame"]["weight_at"]
	var w := 1
	for t: Variant in steps:
		if absi(delta) >= int(t):
			w += 1
	var hero := str(s.character.get("name", "чужак"))
	add(s, data, {"text": "о чужаке по имени %s говорят %s: %s" % [hero, "хорошее" if delta > 0 else "дурное", why], "weight": w,
		"origin": loc, "fame": delta, "crime": crime_id, "source": "fame"})


## A crime became known in its location: the news with the crime and its blame goes out.
static func on_crime(s: GameSession, data: Dictionary, crime: Dictionary, delta: int) -> void:
	if not on(data):
		return
	var kind := CrimeRules.kind_of(data, crime)
	var weights: Dictionary = cfg(data)["crime_weight"]
	var w := int(weights.get(str(crime["kind"]), weights["_default"]))
	var victim := str(data["world"]["npcs"].get(str(crime["victim"]), {}).get("name", ""))
	add(s, data, {"text": "%s%s — винят чужака по имени %s" % [kind.get("name", crime["kind"]), (": " + victim) if not victim.is_empty() else "",
		s.character.get("name", "")], "weight": w, "origin": str(crime["location"]), "fame": delta, "crime": str(crime["id"]),
		"source": "crime", "about": str(crime["victim"])})


## A person of the pack died not by the hero's hand.
static func on_death(s: GameSession, data: Dictionary, npc_id: String, room_id: String) -> void:
	if not on(data):
		return
	var n: Dictionary = data["world"]["npcs"].get(npc_id, {})
	add(s, data, {"text": "погиб%s %s%s" % ["ла" if str(n.get("gender", "")) == "female" else "", n.get("name", npc_id),
		(" (%s)" % n["role"]) if n.has("role") else ""], "weight": int(cfg(data)["death_weight"]), "origin": _loc(data, room_id),
		"source": "death", "about": npc_id})


## A place the master made: the neighbours talk of it, the way to it marked.
static func on_place(s: GameSession, data: Dictionary, room_id: String) -> void:
	if not on(data) or not data["world"]["rooms"].has(room_id):
		return
	var room: Dictionary = data["world"]["rooms"][room_id]
	add(s, data, {"text": "говорят, есть место — %s" % room.get("name", room_id), "weight": int(cfg(data)["place_weight"]),
		"origin": str(room.get("location_id", "")), "target_room": room_id, "source": "place"})


## The hero walked into a tip's room: true — the secret is found, false — the lie is out. Lines.
static func on_enter(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	var st := _state(s)
	for id: Variant in st["heard"]:
		var r := get_rumor(s, str(id))
		if r.is_empty() or str(r.get("target_room", "")) != room_id or st["checked"].has(str(id)):
			continue
		st["checked"][str(id)] = bool(r["truth"])
		if not bool(r["truth"]):
			r["refuted"] = true
			lines.append("Слух соврал: %s" % r["text"])
			continue
		var found := ""
		var sid := str(r.get("target_secret", "")).get_slice(":", 1) if str(r.get("target_secret", "")).contains(":") else str(r.get("target_secret", ""))
		for sec: Dictionary in ExplorationRules.secrets(data["world"], room_id):
			if str(sec["id"]) == sid and ExplorationRules._reveal(s, room_id, sec):
				found = str(sec["text"])
		lines.append("Слух подтвердился: %s%s" % [r["text"], (" — " + found) if not found.is_empty() else ""])
	return lines


## The heard tips not checked yet: {room: [texts]} for the map.
static func marks(s: GameSession, data: Dictionary) -> Dictionary:
	var out := {}
	if not on(data):
		return out
	var st := _state(s)
	for id: Variant in st["heard"]:
		var r := get_rumor(s, str(id))
		var room := str(r.get("target_room", ""))
		if r.is_empty() or room.is_empty() or st["checked"].has(str(id)) or not alive(s, r):
			continue
		var list: Array = out.get(room, [])
		list.append(str(r["text"]))
		out[room] = list
	return out


## The notices of the hero's location (the board): the alive ones that arrived here.
static func notices(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	return known_at(s, data, _loc(data, s.room_id)).filter(func(r: Dictionary) -> bool: return bool(r.get("notice", false)))


## The journal tab «Слухи»: tips to check, the heard ones, the checked ones (folded).
static func groups(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var tips: Array[String] = []
	var plain: Array[String] = []
	var done: Array[String] = []
	var st := _state(s)
	for id: Variant in st["heard"]:
		var r := get_rumor(s, str(id))
		if r.is_empty():
			continue
		var at := " (день %d, %s)" % [int(r["day"]), _loc_name(data, str(r["origin"]))] if int(r["day"]) > 0 else ""
		if st["checked"].has(str(id)):
			done.append("%s %s" % ["✓" if bool(st["checked"][str(id)]) else "✗", r["text"]])
		elif not alive(s, r):
			continue
		elif not str(r.get("target_room", "")).is_empty():
			tips.append("%s → %s%s" % [r["text"], data["world"]["rooms"].get(str(r["target_room"]), {}).get("name", r["target_room"]), at])
		else:
			plain.append(str(r["text"]) + at)
	var out: Array[Dictionary] = []
	if not tips.is_empty():
		out.append({"title": "Наводки", "lines": tips})
	if not plain.is_empty():
		out.append({"title": "Слышал", "lines": plain})
	if not done.is_empty():
		out.append({"title": "Проверено", "lines": done, "folded": true})
	return out


static func count(s: GameSession, data: Dictionary) -> int:
	var n := 0
	for g: Dictionary in groups(s, data):
		if not bool(g.get("folded", false)):
			n += (g["lines"] as Array).size()
	return n


## For the master (`scene.rumors`): what the NPC in the conversation knows, or what the place talks about —
## «[id] текст (важный; уже слышал)»; the truth is the engine's.
static func snapshot(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not on(data):
		return out
	var list := known_by(s, data, s.npc_id) if s.in_conversation() and not s.npc_id.is_empty() else \
		known_at(s, data, _loc(data, s.room_id)).filter(func(r: Dictionary) -> bool: return int(r["weight"]) >= int(cfg(data)["plain_min_weight"]))
	var names: Dictionary = cfg(data)["weight_names"]
	for r: Dictionary in list.slice(0, int(cfg(data)["snapshot_max"])):
		var tags: Array[String] = [str(names[str(int(r["weight"]))])]
		if bool(r.get("notice", false)):
			tags.append("объявление")
		if heard(s, str(r["id"])):
			tags.append("герой уже слышал")
		out.append("[%s] %s (%s)" % [r["id"], r["text"], "; ".join(tags)])
	return out


## The plan of the master's effect `rumor`: op spread (the hero's or an NPC's words go round), tell (an NPC tells
## a rumour of the scene), refute (a lie shown up). {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary, pending: Array) -> Dictionary:
	if not on(data):
		return {"reason": "слухов в этих правилах нет"}
	var op := str(e.get("op", "")) if e.get("op") != null else ""
	var id := str(e.get("rumor_id", "")) if e.get("rumor_id") != null else ""
	match op:
		"spread":
			var words := str(e.get("text", "")).strip_edges() if e.get("text") != null else ""
			if words.length() < 10 or words.length() > 200:
				return {"reason": "text слуха — от 10 до 200 знаков"}
			if pending.any(func(p: Dictionary) -> bool: return str(p.get("plan", {}).get("rumor", "")) == "spread"):
				return {"reason": "один новый слух за ход"}
			var w := int(e.get("importance", 1)) if e.get("importance") != null else 1
			if w < 1 or w > 3:
				return {"reason": "importance — от 1 до 3"}
			var most := int(cfg(data)["master_fame_max"])
			var fame := int(e.get("fame", 0)) if e.get("fame") != null else 0
			if absi(fame) > most:
				return {"reason": "fame — от −%d до +%d" % [most, most]}
			var room := str(e.get("target_room", "")) if e.get("target_room") != null else ""
			if not room.is_empty() and not data["world"]["rooms"].has(room):
				return {"reason": "target_room — комната мира (её id из снимка)"}
			var p := {"rumor": "spread", "words": words, "weight": w, "truth": bool(e.get("truth", true)) if e.get("truth") != null else true,
				"notice": bool(e.get("notice", false)) if e.get("notice") != null else false, "fame": fame * int(cfg(data)["fame"]["master_step"]),
				"target_room": room, "origin": _loc(data, s.room_id)}
			return {"plan": p, "summary": "Пошёл слух: %s" % words.left(60)}
		"tell":
			var ids: Array = (e.get("rumor_ids", []) as Array).duplicate() if e.get("rumor_ids") is Array else []
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
			if ids.is_empty():
				return {"reason": "rumor_ids — слухи из строки «Слухи здесь», что услышал герой"}
			for x: Variant in ids:
				var r := get_rumor(s, str(x))
				if r.is_empty() or not arrived(s, r, _loc(data, s.room_id)):
					return {"reason": "rumor_ids — только слухи из строки «Слухи здесь» (нет %s)" % x}
			return {"plan": {"rumor": "tell", "ids": ids.map(func(x: Variant) -> String: return str(x))}, "summary": "Услышано слухов: %d" % ids.size()}
		"refute":
			var r := get_rumor(s, id)
			if r.is_empty() or not alive(s, r):
				return {"reason": "rumor_id — живой слух из строки «Слухи здесь»"}
			if bool(r["truth"]):
				return {"reason": "за этим слухом правда — словами его не опровергнуть"}
			return {"plan": {"rumor": "refute", "id": id}, "summary": "Слух опровергнут"}
	return {"reason": "op — spread, tell или refute"}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	match str(p["rumor"]):
		"spread":
			var r := add(s, data, {"text": str(p["words"]), "weight": int(p["weight"]), "origin": str(p["origin"]), "truth": bool(p["truth"]),
				"notice": bool(p["notice"]), "fame": int(p["fame"]), "target_room": str(p["target_room"]), "source": "master"})
			_state(s)["heard"].append(str(r["id"]))  # the hero was there when it began
			var lines: Array[String] = ["Пошёл слух: %s" % r["text"]]
			if int(p["fame"]) != 0:
				lines.append_array(ReputationRules.add(s, data, str(p["origin"]), int(p["fame"]), "слух", false))
			return lines
		"tell":
			return hear(s, data, p["ids"])
		"refute":
			var r := get_rumor(s, str(p["id"]))
			r["refuted"] = true
			return ["Слух опровергнут: %s" % r["text"]]
	return []
