class_name BackgroundRules
extends RefCounted
## Background features and tool proficiencies by 5e (roadmap v0.7.11).
## Backgrounds (rules.json `backgrounds`): the people of the pack the hero's past ties them to (NPC `tags`: clergy,
## underworld, commoner, military) like the hero from the start (+1 attitude); an acolyte rests free in a temple (room
## tag `temple`); an outlander finds food for a camp once a day outside settlements and walks a quarter faster there; an
## entertainer performs on a stage (room tag `stage`) for coins and a free room that night; the rest — a rule for the
## master (`master`).
## Tools (rules.json `tools`): a check the master asks with `tool` gets the proficiency bonus when the hero is proficient
## and carries the tool, advantage when also proficient in the skill (XGtE), and fails without a tool that is a must.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["backgrounds"]


static func spec(c: Dictionary, data: Dictionary) -> Dictionary:
	return cfg(data).get(str(c.get("background", "")), {})


## A new game: the people of the pack the hero's past ties them to start one step warmer. Lines.
static func apply_ties(s: GameSession, data: Dictionary) -> Array[String]:
	var tag := str(spec(s.character, data).get("ties", ""))
	var names: Array[String] = []
	if tag.is_empty():
		return names
	var npcs: Dictionary = data["world"].get("npcs", {})
	for id: String in npcs:
		if (npcs[id].get("tags", []) as Array).has(tag):
			s.shift_attitude(id, 1, data)
			names.append(str(npcs[id].get("name", id)))
	return names


## The tie of an NPC with the hero's past, for the master: «свой для героя-солдата» or "".
static func tie_text(c: Dictionary, data: Dictionary, n: Dictionary) -> String:
	var sp := spec(c, data)
	var tag := str(sp.get("ties", ""))
	if tag.is_empty() or not (n.get("tags", []) as Array).has(tag):
		return ""
	return str(sp.get("tie_text", ""))


## The feature of the background for the master: «Воинское звание: …».
static func master_text(c: Dictionary, data: Dictionary) -> String:
	var bg: Dictionary = data["backgrounds"].get(str(c.get("background", "")), {})
	var feature := str(bg.get("feature", {}).get("name", ""))
	var rule := str(spec(c, data).get("master", ""))
	return ("%s: %s" % [feature, rule]) if not feature.is_empty() and not rule.is_empty() else ""


## An acolyte's free rest in a temple, an entertainer's free room the night after a show.
static func free_rest(s: GameSession, data: Dictionary, room_id: String) -> bool:
	var c := s.character
	if bool(spec(c, data).get("temple_rest", false)) and SceneRules.tags(s, data["world"], room_id).has("temple"):
		return true
	return int(c.get("free_rest_day", 0)) == s.day


## An outlander's forage for a camp: once a day, outside settlements (locations without `lit`).
static func can_forage(s: GameSession, data: Dictionary) -> bool:
	if not bool(spec(s.character, data).get("forage", false)) or int(s.character.get("foraged_day", 0)) == s.day:
		return false
	var w := WorldView.new(data["world"])
	return not w.flag(s.room_id, "lit")


## The minutes of a way outside settlements: a quarter less for an outlander, or for one carrying a tool of the way it
## knows (a navigator's, a cartographer's: `wayfinder` of rules.tools, v0.8.4.26.4); as they are for the rest.
static func travel_minutes(s: GameSession, data: Dictionary, minutes: int, to: String) -> int:
	var w := WorldView.new(data["world"])
	var finder := bool(spec(s.character, data).get("wayfinder", false)) or not tool_with(s.character, data, "wayfinder", true).is_empty()
	if finder and not w.flag(to, "lit"):
		return int(ceil(minutes * 0.75))
	return minutes


## The check of a show: Performance with the instrument the hero plays (its proficiency adds, v0.8.4.26.4).
static func perform_check(s: GameSession, data: Dictionary) -> Dictionary:
	var spec := {"skill": "performance", "dc_tier": str(cfg(data)["_perform"]["dc_tier"])}
	var tool := tool_with(s.character, data, "perform")
	if not tool.is_empty():
		spec["tool"] = tool
	return spec


## "" when the hero can perform here now (an entertainer's stage, once a day), otherwise a localization key.
static func can_perform(s: GameSession, data: Dictionary) -> String:
	if not SceneRules.tags(s, data["world"], s.room_id).has("stage"):
		return "PERFORM_NO_STAGE"
	if s.in_conversation() or CombatRules.active(s):
		return "PERFORM_NOT_NOW"
	if int(s.character.get("performed_day", 0)) == s.day:
		return "PERFORM_DONE_TODAY"
	return ""


## The show's result: coins by the Performance total, a free room tonight for an entertainer. Lines.
static func performed(s: GameSession, data: Dictionary, total: int, success: bool) -> Array[String]:
	var c := s.character
	c["performed_day"] = s.day
	if not success:
		return ["публика осталась равнодушной"]
	var pay: Dictionary = data["rules"]["backgrounds"]["_perform"]
	var cp := int(pay["great_cp"]) if total >= int(pay["great_total"]) else int(pay["good_cp"])
	Ledger.add(s, cp, "background:performed")
	var lines: Array[String] = ["+" + Money.format(cp)]
	if bool(spec(c, data).get("stage_lodging", false)):
		c["free_rest_day"] = s.day
		lines.append("ночлег сегодня — бесплатно")
	return lines


# --- tools ----------------------------------------------------------------------------------------------


static func tool_name(data: Dictionary, id: String) -> String:
	return str(data["items"]["catalog"].get(id, {}).get("name", id))


## The tool the character carries whose row of rules.tools has `key` (an instrument to play — `perform`, one to find the
## way — `wayfinder`): a proficient one first; with `owned` only a proficient one counts. "" — none (v0.8.4.26.4).
## `c` carries the tool (v0.8.4.29.1: the one «has it» of a check, a recipe, a liquid, a lock; a bag's contents are not at hand).
static func has_tool(c: Dictionary, tool: String) -> bool:
	return not tool.is_empty() and int(c.get("inventory", {}).get(tool, 0)) > 0


## `c` is proficient with the tool (its background, class, race or a course).
static func proficient(c: Dictionary, tool: String) -> bool:
	return (c.get("tools", []) as Array).has(tool)


static func tool_with(c: Dictionary, data: Dictionary, key: String, owned := false) -> String:
	var any := ""
	for id: String in c.get("inventory", {}):
		if not bool(data["rules"]["tools"].get(id, {}).get(key, false)):
			continue
		if proficient(c, id):
			return id
		if any.is_empty() and not owned:
			any = id
	return any


## What a tool brings to a check: {"bonus": int, "advantage": reason, "auto_fail": reason, "note": text}.
static func tool_check(c: Dictionary, data: Dictionary, tool: String, skill: String) -> Dictionary:
	var out := {"bonus": 0, "advantage": "", "auto_fail": "", "note": ""}
	if tool.is_empty():
		return out
	var t: Dictionary = data["rules"]["tools"].get(tool, {})
	if not has_tool(c, tool):
		if bool(t.get("required", false)):
			out["auto_fail"] = "нет: " + tool_name(data, tool)
		return out
	if proficient(c, tool):
		out["note"] = "владение: " + tool_name(data, tool)
		var skilled := (c.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(c, "skill_prof_" + skill)
		if skilled and (t.get("skills", []) as Array).has(skill):
			out["advantage"] = "навык и %s" % tool_name(data, tool)  # both proficiencies: advantage, not twice the bonus (XGtE)
		elif not skilled:
			out["bonus"] = CharacterRules.prof_bonus(c, data)
	return out
