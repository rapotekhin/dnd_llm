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
