class_name ConditionRules
extends RefCounted
## Conditions (roadmap v0.6.0): the master lays or lifts them with the effect `condition`, the engine keeps them
## on the character (`conditions` + `condition_ends` {id: short_rest | long_rest}) and applies what they do to
## checks (rules.json `condition_effects`: disadvantage or auto-fail on checks, skills or saves). Combat effects
## (attacks, speed) come with combat.

const UNTIL: Array[String] = ["short_rest", "long_rest"]


static func known(data: Dictionary, id: String) -> bool:
	return (data["rules"]["conditions"] as Dictionary).has(id)


static func has(c: Dictionary, id: String) -> bool:
	return (c.get("conditions", []) as Array).has(id)


static func add(c: Dictionary, id: String, until: String) -> void:
	var list: Array = c.get("conditions", [])
	if not list.has(id):
		list.append(id)
	c["conditions"] = list
	var ends: Dictionary = c.get("condition_ends", {})
	ends[id] = until if UNTIL.has(until) else "long_rest"
	c["condition_ends"] = ends


static func remove(c: Dictionary, id: String) -> void:
	(c.get("conditions", []) as Array).erase(id)
	(c.get("condition_ends", {}) as Dictionary).erase(id)


## Clears what a rest ends: a short rest — short_rest conditions, a long rest — all. Returns the removed ids.
static func clear_on_rest(c: Dictionary, rest: String) -> Array[String]:
	var out: Array[String] = []
	var ends: Dictionary = c.get("condition_ends", {})
	for id: Variant in (c.get("conditions", []) as Array).duplicate():
		if rest == "long" or str(ends.get(id, "long_rest")) == "short_rest":
			remove(c, str(id))
			out.append(str(id))
	return out


## What the conditions do to a check: {"disadvantage": [condition ids], "auto_fail": [condition ids]}.
static func check_mods(c: Dictionary, data: Dictionary, params: Dictionary) -> Dictionary:
	var out := {"disadvantage": [], "auto_fail": []}
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	var save := str(params.get("save", "")) if params.get("save") != null else ""
	var table: Dictionary = data["rules"].get("condition_effects", {})
	for id: Variant in c.get("conditions", []):
		var fx: Dictionary = table.get(str(id), {})
		var mode := ""
		if not skill.is_empty():
			mode = str(fx.get("skills", {}).get(skill, fx.get("checks", "")))
		elif not save.is_empty():
			mode = str(fx.get("saves", {}).get(save, ""))
		if mode == "disadvantage" or mode == "auto_fail":
			(out[mode] as Array).append(str(id))
	return out


## The hero is invisible (v0.7.5): the condition, or concentration on an invisibility spell (rules.invisibility).
static func invisible(c: Dictionary, data: Dictionary) -> bool:
	if has(c, "invisible"):
		return true
	return (data["rules"].get("invisibility", {}).get("spells", {}) as Dictionary).has(str(c.get("concentration", "")))


## −passive Perception for those who would see the hero (5e disadvantage on a passive check), 0 when visible.
static func unseen_penalty(c: Dictionary, data: Dictionary) -> int:
	return int(data["rules"].get("invisibility", {}).get("passive_penalty", 5)) if invisible(c, data) else 0


## An attack or a spell ends 5e Invisibility (not Greater): its concentration and the condition go. Lines.
static func end_invisibility_on_attack(c: Dictionary, data: Dictionary) -> Array[String]:
	var spells: Dictionary = data["rules"].get("invisibility", {}).get("spells", {})
	var conc := str(c.get("concentration", ""))
	var lines: Array[String] = []
	if spells.has(conc) and bool(spells[conc].get("ends_on_attack", true)):
		c["concentration"] = ""
		lines.append("Невидимость спадает")
	if has(c, "invisible") and lines.is_empty() and not (spells.has(conc) and not bool(spells[conc].get("ends_on_attack", true))):
		remove(c, "invisible")
		lines.append("Невидимость спадает")
	elif has(c, "invisible") and not lines.is_empty():
		remove(c, "invisible")
	return lines
