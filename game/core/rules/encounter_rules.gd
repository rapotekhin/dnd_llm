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
	var need := best_passive(data, enc["enemies"]) - ConditionRules.unseen_penalty(s.character, data)
	var names := ", ".join((enc["enemies"] as Array).map(func(e: Dictionary) -> String: return str(e.get("name", e["monster"]))))
	if int(roll["total"]) < need:
		return {"lurk": false, "line": "", "stealth": int(roll["total"])}
	s.lurking[room_id] = {"encounter": str(enc["id"]), "from": from}
	return {"lurk": true, "stealth": int(roll["total"]),
		"line": "%s крадётся: Скрытность %d%s — героя не замечают: %s" % [s.character.get("name", ""), int(roll["total"]), roll["note"], names]}


static func lurking(s: GameSession, room_id: String) -> Dictionary:
	return s.lurking.get(room_id, {})


## The foes of an encounter that think, and whether one of them understands the hero.
static func talkable(s: GameSession, data: Dictionary, enemies: Array) -> String:
	var thinking := enemies.filter(func(e: Dictionary) -> bool:
		return int(_monster(data, e).get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"]))
	if thinking.is_empty():
		return "COMBAT_NO_PARLEY"
	if not thinking.any(func(e: Dictionary) -> bool: return LanguageRules.foe_understands(s.character, data, e)):
		return "COMBAT_NO_LANGUAGE"
	return ""


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
static func roll(s: GameSession, data: Dictionary, skill: String, dc: int) -> Dictionary:
	var nat := s.rng.randi_range(1, 20)
	var total := nat + CheckEngine.bonus_for(s.character, {"skill": skill}) + DifficultyRules.bonus(s, data)
	var ok := nat == 20 or (nat != 1 and total >= dc)
	var skill_name := TranslationServer.translate("SKILL_" + skill.to_upper())
	return {"total": total, "ok": ok, "line": "%s %d против Сл %d — %s" % [skill_name, total, dc, "успех" if ok else "провал"]}


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
	var r := roll(s, data, skill, dc)
	var lines: Array[String] = [str(r["line"])]
	s.lurking.erase(room_id)
	if not bool(r["ok"]):
		lines.append("Слова не помогли — они хватаются за оружие")
		return {"lines": lines, "fight": true}
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
	return ["%s связан — в плену у: %s" % [s.character.get("name", ""), names]]


static func captive(s: GameSession) -> bool:
	return not s.captive.is_empty() and str(s.captive.get("room", "")) == s.room_id


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
		lines.append("Путы сброшены — враги ещё не заметили; можно ускользнуть или ударить первым")
	s.captive = {}
	return lines


## For the master: the lurking foes and the captors as creatures of the scene.
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var lk := lurking(s, room_id)
	if not lk.is_empty():
		var enc: Dictionary = SceneRules.room(s, data["world"], room_id).get("encounter", {})
		for e: Dictionary in enc.get("enemies", []):
			out.append("%s ×%d — враждебны, героя не заметили (он крадётся рядом)" % [e.get("name", e["monster"]), int(e.get("count", 1))])
	if captive(s):
		for e: Dictionary in s.captive["foes"]:
			out.append("%s — держит героя в плену, герой связан" % e.get("name", e["monster"]))
	return out
