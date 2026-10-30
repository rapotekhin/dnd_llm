class_name EncounterRules
extends RefCounted
## A meeting with foes is not a fight from the doorway (roadmap v0.7.22.12, big test #46) and a lost fight to
## thinking foes is a captivity (#11, #12).
## Meeting: an ambush strikes as before; a hero sneaking in (or unseen) rolls Stealth against the best passive
## Perception of the foes — unseen, there is no fight: the foes lurk in the room (s.lurking {room: {encounter, from}}),
## the hero may attack them by surprise, talk to them (one roll of Persuasion or Intimidation against the parley DC
## of the fight, if they think and understand the hero: a truce — they stay as creatures; a threat — they go; a
## failure — the fight, without surprise) or slip away; seen, or the sneaking dropped — the fight.
## Captivity: the foes take the hero alive (s.captive {room, foes, encounter, from}): the exits are shut; the hero
## breaks free by Athletics or Sleight of Hand against rules.encounters.escape_dc (a failure — an hour), or talks
## the captors round (the parley DC). Free — the captors lurk, unaware, as at a meeting.
## v0.7.22.17 (#12, #15): «Сдаться» makes the hero a captive at once; the captors take the hero's things into a
## container of the room (`seize`) — taken back from it once free; the hero bound reaches into no container.
## v0.7.49.3: out of the room of the unaware foes by another way than in — the hero slipped past them
## (s.encounters_passed): a quest's fight step is done unless it says `defeat`; out by the way in — only turned back.
## A dead end is never passed.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["encounters"]


static func _monster(data: Dictionary, e: Dictionary) -> Dictionary:
	return data["monsters"].get(str(e.get("monster", "")), {})


## The best passive Perception among the foes of an encounter.
static func best_passive(data: Dictionary, enemies: Array) -> int:
	var best := 0
	for e: Dictionary in enemies:
		var m := _monster(data, e)
		best = maxi(best, int(m.get("passive_perception", 10 + CharacterRules.mod(int(m.get("abilities", {}).get("wis", 10))))))
	return best


## On entering a room with a live encounter: {lurk: bool, line, stealth (−1 — not rolled)}.
static func meet(s: GameSession, data: Dictionary, room_id: String, from: String, enc: Dictionary) -> Dictionary:
	if bool(enc.get("ambush", false)):
		return {"lurk": false, "line": "", "stealth": -1}
	var unseen := ConditionRules.invisible(s.character, data)
	if not s.sneaking and not unseen:
		return {"lurk": false, "line": "", "stealth": -1}
	var roll := CombatRules.stealth_roll(s, data)
	var need := best_passive(data, enc["enemies"]) - WeatherRules.unseen(s, data)
	var names := ", ".join((enc["enemies"] as Array).map(func(e: Dictionary) -> String: return str(e.get("name", e["monster"]))))
	if int(roll["total"]) < need:
		return {"lurk": false, "line": "", "stealth": int(roll["total"])}
	s.lurking[room_id] = {"encounter": str(enc["id"]), "from": from}
	return {"lurk": true, "stealth": int(roll["total"]),
		"line": "%s крадётся: Скрытность %d%s — героя не замечают: %s" % [s.character.get("name", ""), int(roll["total"]), roll["note"], names]}


## The hero leaves `from` for `to`: past the unaware foes of an encounter there, if not back the way in. The line or "".
static func slip_past(s: GameSession, from: String, to: String) -> String:
	var lk := lurking(s, from)
	var id := str(lk.get("encounter", ""))
	if id.is_empty() or str(lk.get("from", "")) == to or s.encounters_passed.has(id):
		return ""
	s.encounters_passed.append(id)
	return "Вы прошли мимо незамеченными — стража позади"


static func lurking(s: GameSession, room_id: String) -> Dictionary:
	return s.lurking.get(room_id, {})


## The encounter the lurking foes of the room are: the room's own, or — the captors of a fight without one (a creature
## attacked again, an NPC's guard), v0.7.22.16 (#16) — their list as it was. {id, enemies, waves?, help?, parley?}.
static func lurking_encounter(s: GameSession, data: Dictionary, room_id: String) -> Dictionary:
	var lk := lurking(s, room_id)
	if lk.has("foes"):
		return {"id": "", "enemies": lk["foes"]}
	return SceneRules.room(s, data["world"], room_id).get("encounter", {})


## The foes of an encounter that think, and whether one of them understands the hero. A threat needs no common tongue
## (v0.7.22.19, #9): gestures and a blade say it — with disadvantage (`mute`).
static func talkable(s: GameSession, data: Dictionary, enemies: Array, skill: String = "persuasion") -> String:
	var thinking := enemies.filter(func(e: Dictionary) -> bool:
		return int(_monster(data, e).get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]))
	if thinking.is_empty():
		return "COMBAT_NO_PARLEY"
	if skill != "intimidation" and mute(s, data, enemies):
		return "COMBAT_NO_LANGUAGE"
	return ""


## Nobody of the thinking foes understands the hero.
static func mute(s: GameSession, data: Dictionary, enemies: Array) -> bool:
	return not enemies.any(func(e: Dictionary) -> bool:
		return int(_monster(data, e).get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]) 			and LanguageRules.foe_understands(s.character, data, e))


## The parley DC of the fight for foes not fighting yet (CombatRules.parley_dc without the wounds).
static func parley_dc(data: Dictionary, enemies: Array, hard: bool) -> int:
	var p: Dictionary = CombatRules.cfg(data)["parley"]
	var wis := -5
	var cr := 0.0
	for e: Dictionary in enemies:
		var m := _monster(data, e)
		if int(m.get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]):
			wis = maxi(wis, int(m.get("saves", {}).get("wis", CharacterRules.mod(int(m.get("abilities", {}).get("wis", 10))))))
			cr = maxf(cr, float(m.get("cr", 0)))
	var dc := int(p["base_dc"]) + wis + int(p.get("per_cr", 0)) * int(floor(cr)) + (int(p.get("hard", 0)) if hard else 0)
	return maxi(int(p["min_dc"]), dc)


## A roll of the hero's skill against `dc` (the game's difficulty counts). {total, ok, line}.
static func roll(s: GameSession, data: Dictionary, skill: String, dc: int, dis: bool = false) -> Dictionary:
	var rolls: Array[int] = [s.rng.randi_range(1, 20)]
	if dis:
		rolls.append(s.rng.randi_range(1, 20))
	var nat: int = rolls.min()
	var parts := RollParts.skill(s, data, skill)
	var total := nat + RollParts.sum(parts)
	var ok := nat == 20 or (nat != 1 and total >= dc)
	if not ok and nat != 1:  # Bardic Inspiration on a failed roll here too (v0.7.49.4)
		var die := FeatureRules.inspiration_die(s.character)
		var insp := FeatureRules.use_inspiration(s)
		if insp > 0:
			parts.append({"label": "Вдохновение барда (к%d)" % die, "value": insp})
			total += insp
			ok = total >= dc
	RollParts.note(s, TranslationServer.translate("SKILL_" + skill.to_upper()), rolls, nat, parts, total - nat, dc)
	s.faith_lines.append_array(FaithRules.deed(s, data, "check:" + skill))  # v0.7.49
	var skill_name := TranslationServer.translate("SKILL_" + skill.to_upper())
	return {"total": total, "ok": ok, "line": "%s %d против Сл %d%s — %s" % [skill_name, total, dc, " (помеха: без общего языка — жесты и оружие)" if dis else "", "успех" if ok else "провал"]}


## The foes of the encounter as creatures of the room (a truce), one per head.
static func as_creatures(s: GameSession, room_id: String, enemies: Array, state: String) -> void:
	var list: Array = s.creatures.get(room_id, [])
	for e: Dictionary in enemies:
		for i in int(e.get("count", 1)):
			s.creature_counter += 1
			var name := str(e.get("name", e["monster"])) + (" %d" % (i + 1) if int(e.get("count", 1)) > 1 else "")
			list.append({"id": "c%d" % s.creature_counter, "name": name, "monster": str(e["monster"]), "state": state,
				"bound": false, "led": false, "since": TimeRules.abs_minute(s)})
	s.creatures[room_id] = list


## Talking to the lurking foes before a fight. {lines, fight: bool}: a success — a truce (Persuasion) or they go
## (Intimidation), the encounter is over; a failure — the fight, they know where the hero is.
static func parley(s: GameSession, data: Dictionary, room_id: String, enc: Dictionary, skill: String) -> Dictionary:
	var dc := parley_dc(data, enc["enemies"], str(enc.get("parley", "")) == "hard")
	var r := roll(s, data, skill, dc, skill == "intimidation" and mute(s, data, enc["enemies"]))
	var lines: Array[String] = [str(r["line"])]
	s.lurking.erase(room_id)
	if not bool(r["ok"]):
		lines.append("Слова не помогли — они хватаются за оружие")
		return {"lines": lines, "fight": true}
	if not str(enc.get("id", "")).is_empty():
		s.encounters_done.append(str(enc["id"]))
	if skill == "intimidation":
		lines.append("Угроза подействовала — они уходят прочь")
	else:
		as_creatures(s, room_id, enc["enemies"], "truce")
		lines.append("Удалось договориться — перемирие")
	return {"lines": lines, "fight": false}


# --- captivity -------------------------------------------------------------------------------------------------


## The fight is lost to thinking foes: the hero is their captive here.
static func capture(s: GameSession, foes: Array, encounter: String, from: String) -> Array[String]:
	s.captive = {"room": s.room_id, "foes": foes, "encounter": encounter, "from": from}
	var names := ", ".join(foes.map(func(e: Dictionary) -> String: return str(e.get("name", e["monster"]))))
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
	for id: String in inv.keys():
		var keep := 1 if ItemRules.held_by_curse(c, data, s.items, id) else 0
		var n := int(inv[id]) - keep
		if n <= 0:
			continue
		taken[id] = int(taken.get(id, 0)) + n
		if keep > 0:
			inv[id] = keep
		else:
			inv.erase(id)
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
		chest["contents"][id] = int(chest["contents"].get(id, 0)) + int(taken[id])
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
		return talkable(s, data, s.captive["foes"])
	return ""


## A try to get free (can_escape first). Lines; free — the captors lurk unaware, the hero sneaks.
static func escape(s: GameSession, data: Dictionary, how: String) -> Array[String]:
	var foes: Array = s.captive["foes"]
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
			s.lurking[room] = {"encounter": str(s.captive["encounter"]), "from": str(s.captive.get("from", ""))}
		elif not foes.is_empty():  # a fight without an encounter: the captors stay, unaware (v0.7.22.16, #16)
			s.lurking[room] = {"foes": foes.duplicate(true), "from": str(s.captive.get("from", ""))}
		lines.append("Путы сброшены — враги ещё не заметили; можно ускользнуть или ударить первым")
	s.captive = {}
	return lines


## For the master: the lurking foes and the captors as creatures of the scene.
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var lk := lurking(s, room_id)
	if not lk.is_empty():
		var enc := lurking_encounter(s, data, room_id)
		for e: Dictionary in enc.get("enemies", []):
			out.append("%s ×%d — враждебны, героя не заметили (он крадётся рядом)" % [e.get("name", e["monster"]), int(e.get("count", 1))])
	if captive(s):
		for e: Dictionary in s.captive["foes"]:
			out.append("%s — держит героя в плену, герой связан" % e.get("name", e["monster"]))
	return out
