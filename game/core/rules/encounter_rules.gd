class_name EncounterRules
extends RefCounted
## A meeting with foes is not a fight from the doorway (roadmap v0.7.22.12, big test #46) and a lost fight to
## thinking foes is a captivity (#11, #12).
## Meeting: an ambush strikes as before; a hero sneaking in (or unseen) rolls Stealth against the best passive
## Perception of the foes — unseen, there is no fight: the foes lurk in the room (s.lurking {room: {encounter, from}}),
## the hero may attack them by surprise, talk to them (one roll of Persuasion or Intimidation against the parley DC
## of the fight, if they think and understand the hero: a truce — they stay as creatures; a threat — they go; a
## failure — the fight, without surprise) or slip away; seen, or the sneaking dropped — the fight.
## Captivity: the foes take the hero alive (s.captive {room, foes: ids, encounter, from}): the exits are shut; the hero
## breaks free by Athletics or Sleight of Hand against rules.encounters.escape_dc (a failure — an hour), or talks
## the captors round (the parley DC). Free — the captors lurk, unaware, as at a meeting.
## v0.7.22.17 (#12, #15): «Сдаться» makes the hero a captive at once; the captors take the hero's things into a
## container of the room (`seize`) — taken back from it once free; the hero bound reaches into no container.
## v0.7.49.3: out of the room of the unaware foes by another way than in — the hero slipped past them
## (s.encounters_passed): a quest's fight step is done unless it says `defeat`; out by the way in — only turned back.
## A dead end is never passed.
## v0.7.62: an encounter stays a description with a number of heads; the first entry makes them characters of s.beings
## (`heads`) and the same ones meet the hero after that: the dead stay dead, the wounded wounded till a long rest.
## v0.8.3: foes stand on the map (MapSpots.foes) from the entry on and the meeting goes by who sees whom (`watch`): a hero
## who does not hide is noticed in their range, one who sneaks in their cone, by one Stealth roll for the room; foes who
## see a hero that does not see them have the drop on the hero; an ambush hides by a roll of each head and strikes close
## (`spring`). Until then the record of the room in s.lurking only says they do not know: `sighted` — the hero sees them.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["encounters"]


## The best passive Perception among the foes of an encounter.
static func best_passive(s: GameSession, data: Dictionary, enemies: Array) -> int:
	var best := 0
	for e: Dictionary in enemies:
		best = maxi(best, Sheet.passive(s, data, e))
	return best


## On entering a room with a live encounter: {lurk, peace?, line} with a word of the faction; else what `watch` says.
static func meet(s: GameSession, data: Dictionary, room_id: String, from: String, enc: Dictionary) -> Dictionary:
	var made := heads(s, data, room_id, enc)
	if FactionRules.peaceful(s, data, enc):  # v0.7.50: friends do not fight
		return {"lurk": false, "peace": true, "stealth": -1, "line": FactionRules.keep_peace(s, data, room_id, enc)}
	for e: Dictionary in enc["enemies"]:
		FactionRules.meet(s, data, FactionRules.of_foe(data, enc, e))
	if FactionRules.word_out(s, data, room_id, enc):  # v0.7.50.1: they heard of the hero: strike first, or talk
		s.lurking[room_id] = {"encounter": str(enc["id"]), "from": from, "word": true}
		return {"lurk": true, "stealth": -1, "line": "Они уже слышали о вас и ждут, что вы скажете: %s" % _names(enc)}
	s.lurking[room_id] = {"encounter": str(enc["id"]), "from": from, "seen": false}
	if bool(enc.get("ambush", false)):
		s.lurking[room_id]["hidden"] = _hide(s, data, made)
	return watch(s, data, WalkRules.view(s, data))


## An ambush hides: the heads whose Stealth beats the hero's passive Perception, the rest the hero sees from the start.
static func _hide(s: GameSession, data: Dictionary, foes: Array) -> Array:
	var passive := Sheet.passive(s, data, Sheet.HERO)
	var out: Array = []
	for e: Dictionary in foes:
		if int(CombatRules.stealth_roll(s, data, e)["total"]) >= passive:
			out.append(foe_id(e))
	return out


static func foe_id(e: Dictionary) -> String:
	return str(e.get("id", e.get("npc_id", e.get("name", ""))))


## Who sees whom on `map` now. {fight, source?, new_sight?, lines}: `fight` — the foes noticed the hero, `source` the start
## of that fight; `new_sight` — the hero just saw them. One Stealth roll serves the whole room.
static func watch(s: GameSession, data: Dictionary, map: Dictionary) -> Dictionary:
	var out := {"fight": false, "lines": [] as Array[String]}
	var room := s.room_id
	var lk := lurking(s, room)
	if lk.is_empty() or not lk.has("encounter") or bool(lk.get("word", false)):
		return out
	var hero := WalkRules.settle(s, data, map)
	var mine := SightRules.look(s, data, map, hero)
	var foes := MapSpots.foes(s, data, map)
	var shown := foes.filter(func(t: Dictionary) -> bool: return mine.has(Vector2i(int(t["x"]), int(t["y"]))) and not (lk.get("hidden", []) as Array).has(str(t["id"])))
	if not shown.is_empty() and not bool(lk.get("seen", false)):
		lk["seen"] = true
		out["new_sight"] = true
		out["lines"].append("Вы видите: %s" % ", ".join(shown.map(func(t: Dictionary) -> String: return str(t["name"]))))
	var enc := lurking_encounter(s, data, room)
	if bool(enc.get("ambush", false)):
		var close := foes.any(func(t: Dictionary) -> bool:
			var at := Vector2i(int(t["x"]), int(t["y"]))
			return WalkRules.distance(at, hero) <= int(SightRules.cfg(data)["spring"]) and SightRules.line(map, data["layouts"], at, hero))
		if close:
			out.merge({"fight": true, "source": {"ambush": true, "hidden": shown.is_empty()}}, true)
		return out
	var quiet := WatchRules.sneaky(s, data)
	for t: Dictionary in foes:
		var at := Vector2i(int(t["x"]), int(t["y"]))
		if not WatchRules.sees(s, data, map, str(t["id"]), at, hero, WatchRules.range_of(s, data, t["record"])):
			continue
		if not quiet:
			out.merge({"fight": true, "source": {"ambush": true} if shown.is_empty() else {}}, true)
			return out
		if not lk.has("stealth"):
			var roll := CombatRules.stealth_roll(s, data)
			lk["stealth"] = int(roll["total"])
			out["lines"].append("%s крадётся: Скрытность %d%s" % [s.character.get("name", ""), int(roll["total"]), roll["note"]])
		if int(lk["stealth"]) < best_passive(s, data, [t["record"]]) - WeatherRules.unseen(s, data):
			out.merge({"fight": true, "source": {"sneak": true, "stealth_total": int(lk["stealth"])}}, true)
			return out
	return out


## What a fight of the encounter starts from, over `extra`.
static func source(enc: Dictionary, from: String, extra: Dictionary = {}) -> Dictionary:
	var out := {"encounter": str(enc.get("id", "")), "room_from": from, "waves": enc.get("waves", []), "help": enc.get("help", {}),
		"parley": str(enc.get("parley", "")), "allies": enc.get("allies", []), "faction": str(enc.get("faction", ""))}
	out.merge(extra, true)
	return out


## The hero sees the foes of the room who do not know of it (or who wait for words, or the captors just left).
static func sighted(s: GameSession, room_id: String) -> bool:
	var lk := lurking(s, room_id)
	return not lk.is_empty() and bool(lk.get("seen", true))


## The foes of an encounter as characters: made on the first entry, one record per head. A person of the pack among them
## is its own record.
static func heads(s: GameSession, data: Dictionary, room_id: String, enc: Dictionary) -> Array:
	var id := str(enc.get("id", ""))
	var out: Array = Being.records(s, "encounter").filter(func(b: Dictionary) -> bool: return str(b["encounter"]) == id and not b.has("creature"))
	var fresh := out.is_empty()
	var named := {}
	for e: Dictionary in enc.get("enemies", []):
		if not str(e.get("npc_id", "")).is_empty():
			out.append(e)
			continue
		if not fresh or not data["monsters"].has(str(e.get("monster", ""))):
			continue
		var base := str(e.get("name", data["monsters"][e["monster"]]["name"]))
		var count := int(e.get("count", 1))
		var same := int(named.get(base, 0))
		for i in count:
			var b: Dictionary = e.duplicate(true)
			b.erase("count")
			b.merge({"name": base + (" %d" % (same + i + 1) if count > 1 or same > 0 else ""), "base": base, "encounter": id, "at": room_id}, true)
			var side := FactionRules.of_foe(data, enc, e)
			if not side.is_empty():
				b["faction"] = side
			out.append(Being.spawn(s, b))
		named[base] = same + count
	return out


static func _names(enc: Dictionary) -> String:
	return ", ".join((enc["enemies"] as Array).map(func(e: Dictionary) -> String: return str(e.get("name", e["monster"]))))


## The hero leaves `from` for `to`: past the unaware foes of an encounter there, if not back the way in. The line or "".
static func slip_past(s: GameSession, from: String, to: String) -> String:
	var lk := lurking(s, from)
	var id := str(lk.get("encounter", ""))
	if id.is_empty() or str(lk.get("from", "")) == to or s.encounters_passed.has(id):
		return ""
	s.encounters_passed.append(id)
	return "Вас пропускают" if bool(lk.get("word", false)) else "Вы прошли мимо незамеченными — стража позади"


static func lurking(s: GameSession, room_id: String) -> Dictionary:
	return s.lurking.get(room_id, {})


## The hero left the room: the captors that lurked there without an encounter are gone.
static func unlurk(s: GameSession, room_id: String) -> void:
	for id: String in lurking(s, room_id).get("foes", []):
		Being.forget(s, id)
	s.lurking.erase(room_id)


## The encounter the lurking foes of the room are: the room's own, or — the captors of a fight without one (a creature
## attacked again, an NPC's guard), v0.7.22.16 (#16). {id, enemies: their records, waves?, help?, parley?}.
static func lurking_encounter(s: GameSession, data: Dictionary, room_id: String) -> Dictionary:
	var lk := lurking(s, room_id)
	if lk.has("foes"):
		return {"id": "", "enemies": _records(s, lk["foes"])}
	var enc: Dictionary = SceneRules.room(s, data["world"], room_id).get("encounter", {}).duplicate()
	if not enc.is_empty():
		enc["enemies"] = heads(s, data, room_id, enc)
	return enc


static func _records(s: GameSession, ids: Array) -> Array:
	return ids.map(func(id: String) -> Dictionary: return Being.view(s, id)).filter(func(b: Dictionary) -> bool: return not b.is_empty())


## Who holds the hero.
static func captors(s: GameSession) -> Array:
	return _records(s, s.captive.get("foes", []))


## The foes of an encounter that think, and whether one of them understands the hero. A threat needs no common tongue
## (v0.7.22.19, #9): gestures and a blade say it — with disadvantage (`mute`).
static func talkable(s: GameSession, data: Dictionary, enemies: Array, skill: String = "persuasion") -> String:
	if skill == "animal_handling":  # v0.7.50: beasts are calmed, not talked to
		return "" if all_beasts(data, enemies) else "COMBAT_NO_PARLEY"
	var thinking := enemies.filter(func(e: Dictionary) -> bool:
		return int(Sheet.template(data, e).get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]))
	if thinking.is_empty():
		return "COMBAT_NO_PARLEY"
	if skill != "intimidation" and mute(s, data, enemies):
		return "COMBAT_NO_LANGUAGE"
	return ""


## Every foe is a beast: «Успокоить» by Animal Handling.
static func all_beasts(data: Dictionary, enemies: Array) -> bool:
	return not enemies.is_empty() and enemies.all(func(e: Dictionary) -> bool: return str(Sheet.template(data, e).get("type", "")) == "beast")


## The DC of calming beasts (rules.factions.calm): base + the strongest's WIS modifier + per_cr × the highest CR.
static func calm_dc(data: Dictionary, enemies: Array) -> int:
	var c: Dictionary = FactionRules.cfg(data)["calm"]
	var wis := -5
	var cr := 0.0
	for e: Dictionary in enemies:
		var m := Sheet.template(data, e)
		wis = maxi(wis, CharacterRules.mod(int(m.get("abilities", {}).get("wis", 10))))
		cr = maxf(cr, float(m.get("cr", 0)))
	return int(c["base_dc"]) + wis + int(c["per_cr"]) * int(ceil(cr))


## Nobody of the thinking foes understands the hero.
static func mute(s: GameSession, data: Dictionary, enemies: Array) -> bool:
	return not enemies.any(func(e: Dictionary) -> bool:
		return int(Sheet.template(data, e).get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]) 			and LanguageRules.foe_understands(s.character, data, e))


## The parley DC of the fight for foes not fighting yet (CombatRules.parley_dc without the wounds).
static func parley_dc(data: Dictionary, enemies: Array, hard: bool) -> int:
	var p: Dictionary = CombatRules.cfg(data)["parley"]
	var wis := -5
	var cr := 0.0
	for e: Dictionary in enemies:
		var m := Sheet.template(data, e)
		if int(m.get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]):
			wis = maxi(wis, int(m.get("saves", {}).get("wis", CharacterRules.mod(int(m.get("abilities", {}).get("wis", 10))))))
			cr = maxf(cr, float(m.get("cr", 0)))
	var dc := int(p["base_dc"]) + wis + int(p.get("per_cr", 0)) * int(floor(cr)) + (int(p.get("hard", 0)) if hard else 0)
	return maxi(int(p["min_dc"]), dc)


## A roll of the hero's skill against `dc` (the game's difficulty counts). {total, ok, line}.
static func roll(s: GameSession, data: Dictionary, skill: String, dc: int, dis: bool = false) -> Dictionary:
	var skill_name := TranslationServer.translate("SKILL_" + skill.to_upper())
	var r := Roll.hero(s, data, {"what": skill_name, "skill": skill, "dc": dc, "dis": dis})
	var total := int(r["total"])
	var ok := bool(r["ok"])
	return {"total": total, "ok": ok, "line": "%s %d против Сл %d%s — %s" % [skill_name, total, dc, " (помеха: без общего языка — жесты и оружие)" if dis else "", "успех" if ok else "провал"]}


## The foes of the encounter as creatures of the room (a truce), one per head; `extra` — what each one carries.
static func as_creatures(s: GameSession, room_id: String, enemies: Array, state: String, extra: Dictionary = {}) -> void:
	var now := TimeRules.abs_minute(s)
	for e: Dictionary in enemies:
		if e.has("id"):  # a head of the encounter stays this character
			var known := {"name": str(e["name"]), "monster": str(e["monster"]), "state": state, "at": room_id, "bound": false, "led": false, "since": now}
			if e.has("hp"):
				known.merge({"hp": int(e["hp"]), "max_hp": int(e.get("max_hp", e["hp"]))})
			if bool(e.get("no_xp", false)):
				known["xp_given"] = true
			known.merge(extra, true)
			Being.put(s, str(e["id"]), "creature", known)
			continue
		for i in int(e.get("count", 1)):
			var c := {"name": str(e.get("name", e["monster"])) + (" %d" % (i + 1) if int(e.get("count", 1)) > 1 else ""), "monster": str(e["monster"]), "state": state,
				"bound": false, "led": false, "since": now}
			c.merge(extra)
			for k: String in ["hp", "max_hp"]:  # captors keep the wounds of the fight, and its XP stays given
				if e.has(k):
					c[k] = int(e[k])
			if bool(e.get("no_xp", false)):
				c["xp_given"] = true
			CreatureRules.add(s, room_id, c)


## Talking to the lurking foes before a fight. {lines, fight: bool}: a success — they stay as a truce (Persuasion) or
## cowed (Intimidation), the faction respects the hero (v0.7.50.1), the encounter is over; a failure — the fight, they
## know where the hero is.
static func parley(s: GameSession, data: Dictionary, room_id: String, enc: Dictionary, skill: String) -> Dictionary:
	var calm := skill == "animal_handling"
	var dc := calm_dc(data, enc["enemies"]) if calm else parley_dc(data, enc["enemies"], str(enc.get("parley", "")) == "hard")
	var r := roll(s, data, skill, dc, skill == "intimidation" and mute(s, data, enc["enemies"]))
	var lines: Array[String] = [str(r["line"])]
	s.lurking.erase(room_id)
	if not bool(r["ok"]):
		lines.append("Звери скалятся — не вышло" if calm else "Слова не помогли — они хватаются за оружие")
		return {"lines": lines, "fight": true}
	if not str(enc.get("id", "")).is_empty():
		s.encounters_done.append(str(enc["id"]))
	var id := FactionRules.of_foe(data, enc, enc["enemies"][0])
	var stay := {"kept": true, "faction": id}
	if skill == "intimidation":
		as_creatures(s, room_id, enc["enemies"], "surrendered", stay)
		lines.append("Угроза подействовала — они складывают оружие и не тронут вас")
		lines.append_array(FactionRules.won_by_word(s, data, id, room_id, FactionRules.word_why(skill)))
	elif calm:  # v0.7.50: the friendship of beasts grows from here
		as_creatures(s, room_id, enc["enemies"], "truce")
		lines.append("Звери успокоились и не трогают вас")
		lines.append_array(WorldEvent.standing(s, data, FactionRules.of_foe(data, enc, enc["enemies"][0]), "calm", "звери успокоены"))
	else:
		as_creatures(s, room_id, enc["enemies"], "truce", stay)
		lines.append("Удалось договориться — перемирие")
		lines.append_array(FactionRules.won_by_word(s, data, id, room_id, FactionRules.word_why(skill)))
	return {"lines": lines, "fight": false}


# --- captivity -------------------------------------------------------------------------------------------------


## The fight is lost to thinking foes: the hero is their captive here.
static func capture(s: GameSession, foes: Array, encounter: String, from: String) -> Array[String]:
	s.captive = {"room": s.room_id, "foes": foes, "encounter": encounter, "from": from}
	var names := ", ".join(captors(s).map(func(e: Dictionary) -> String: return str(e["name"])))
	var bound: String = {"female": "связана", "male": "связан"}.get(str(s.character.get("gender", "")), "связан(а)")
	return ["%s %s — в плену у: %s" % [s.character.get("name", ""), bound, names]]


## The captors take what the hero carries (v0.7.22.17, #15): the pack and the bags with what is in them go into a
## container of the room — one standing there nobody owns (not a trader's wares), or a new one (rules.encounters.seized_*). A
## cursed thing does not leave the hero; the coins stay hidden on the hero. Lines.
static func seize(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var taken := {}
	for bag: Dictionary in ContainerRules.bags(c).values():
		for id: String in bag.get("contents", {}):
			taken[id] = int(taken.get(id, 0)) + int(bag["contents"][id])
	c["bags"] = {}
	var inv: Dictionary = c["inventory"]
	var had := {}
	for id: String in inv.keys():
		var keep := 1 if ItemRules.held_by_curse(c, data, s.items, id) else 0
		var n := int(inv[id]) - keep
		if n <= 0:
			continue
		taken[id] = int(taken.get(id, 0)) + n
		had[id] = Thing.take(c, id, n)
	for slot: String in CharacterRules.SLOTS:
		if not inv.has(str(c.get("equipped", {}).get(slot, ""))):
			c["equipped"][slot] = ""
	c["attuned"] = (c.get("attuned", []) as Array).filter(func(id: Variant) -> bool: return inv.has(str(id)))
	CharacterRules.refresh(c, data, s.items)
	if taken.is_empty():
		return []
	var chest := {}
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if ContainerRules.is_container(p) and not p.has("wares") and not bool(p.get("dropped", false)) and str(p.get("owner", "")).is_empty():
			chest = p
			break
	if chest.is_empty():
		var list: Array = s.props.get(s.room_id, [])
		var n := 1
		while list.any(func(p: Dictionary) -> bool: return str(p["id"]) == "seized%d" % n):
			n += 1
		chest = {"id": "seized%d" % n, "name": str(cfg(data)["seized_name"]), "description": "", "item_id": "", "owner": "",
			"text": "", "state": "", "container": str(cfg(data)["seized_container"]), "contents": {}, "seized": true}
		list.append(chest)
		s.props[s.room_id] = list
	if not chest.has("contents"):
		chest["contents"] = {}
	for id: String in taken:
		Thing.add(chest, id, int(taken[id]), had[id])
	var count := 0
	for id: String in taken:
		count += int(taken[id])
	return ["Пленители отбирают у героя вещи (%d) и складывают в %s" % [count, chest["name"]]]


static func captive(s: GameSession) -> bool:
	return not s.captive.is_empty() and str(s.captive.get("room", "")) == s.room_id


## "" when the hero is free to work, cook, study or take a shift (v0.7.39), else why not: bound, a captive, held by
## the guard — even unbound.
static func unfree_why(s: GameSession) -> String:
	if ConditionRules.has(s.character, "restrained"):
		return "UNFREE_RESTRAINED"
	if captive(s):
		return "UNFREE_CAPTIVE"
	if CrimeRules.held(s):
		return "UNFREE_HELD"
	return ""


## "" when the hero can try this way out now (escape_athletics, escape_sleight, talk), else a localization key.
static func can_escape(s: GameSession, data: Dictionary, how: String) -> String:
	if not captive(s):
		return "CAPTIVE_NOT"
	if how == "talk":
		return talkable(s, data, captors(s))
	return ""


## A try to get free (can_escape first). Lines; free — the captors lurk unaware, the hero sneaks.
static func escape(s: GameSession, data: Dictionary, how: String) -> Array[String]:
	var foes := captors(s)
	var r: Dictionary
	if how == "talk":
		r = roll(s, data, "persuasion", parley_dc(data, foes, false))
	else:
		r = roll(s, data, "athletics" if how == "escape_athletics" else "sleight_of_hand", int(cfg(data)["escape_dc"]))
	var lines: Array[String] = [str(r["line"])]
	if not bool(r["ok"]):
		lines.append("Не вышло — путы держат, за вами следят")
		lines.append_array(TimeRules.advance(s, data, int(cfg(data)["escape_fail_minutes"])))
		return lines
	var room := str(s.captive["room"])
	if how == "talk":
		as_creatures(s, room, foes, "truce")
		if not str(s.captive.get("encounter", "")).is_empty():
			s.encounters_done.append(str(s.captive["encounter"]))
		lines.append("Вас отпускают — перемирие")
	else:
		s.sneaking = true
		if not str(s.captive.get("encounter", "")).is_empty():
			s.lurking[room] = {"encounter": str(s.captive["encounter"]), "from": str(s.captive.get("from", "")), "stealth": 99}
		elif not foes.is_empty():  # a fight without an encounter: the captors stay, unaware (v0.7.22.16, #16)
			s.lurking[room] = {"foes": (s.captive["foes"] as Array).duplicate(), "from": str(s.captive.get("from", ""))}
		lines.append("Путы сброшены — враги ещё не заметили; можно ускользнуть или ударить первым")
	s.captive = {}
	return lines


## For the master: the lurking foes and the captors as creatures of the scene.
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var lk := lurking(s, room_id)
	if sighted(s, room_id):
		var enc := lurking_encounter(s, data, room_id)
		for e: Dictionary in enc.get("enemies", []):
			out.append("%s — враждебен, героя не заметил" % e["name"])
	if captive(s):
		for e: Dictionary in captors(s):
			out.append("%s — держит героя в плену, герой связан" % e["name"])
	return out
