class_name ToggleRules
extends RefCounted
## Passives as in BG3 (v0.8.4.43.7): what a character keeps on or off — not to kill, Reckless Attack on every first blow of
## Strength, a stunning strike on every hit while ki lasts. Rows of `rules.toggles`; the state is kept on the character's
## own record for life (`toggles`, `Sheet.record`), read the same for the hero, a companion or a foe (ADR-0016): the hotbar's
## «Пассивные» cell is one switch of it. What a toggle does happens on the one road of a weapon blow (`before_blow`).


static func rows(data: Dictionary) -> Dictionary:
	var out := {}
	var all: Dictionary = data["rules"].get("toggles", {})
	for id: String in all:
		if not id.begins_with("_"):
			out[id] = all[id]
	return out


## Whether `who` has the toggle at all: anybody's, or by a feature of its class.
static func has(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> bool:
	var row: Dictionary = rows(data).get(id, {})
	if row.is_empty():
		return false
	if bool(row.get("all", false)):
		return true
	var c := Sheet.holder(s, who)
	return (row.get("features", []) as Array).any(func(f: Variant) -> bool: return CharacterRules.has_feature(c, str(f)))


## Whether the toggle of `who` is on now: fixed by the moment (a bout to surrender), else its own choice, else the row's default.
static func on(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> bool:
	if not has(s, data, who, id):
		return false
	var row: Dictionary = rows(data)[id]
	if not fixed_why(s, row).is_empty():
		return true
	return bool(Sheet.record(s, who).get("toggles", {}).get(id, row.get("default", false)))


## Why the toggle cannot be switched now, "" — it can.
static func fixed_why(s: GameSession, row: Dictionary) -> String:
	return str(row["yield_bout"]) if row.has("yield_bout") and ArenaRules.yield_bout(s) else ""


## The toggles `who` has, in the order of the rules: [{id, name, tip, on, why}].
static func of(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := rows(data)
	for id: String in all:
		if has(s, data, who, id):
			var row: Dictionary = all[id]
			out.append({"id": id, "name": str(row["name"]), "tip": str(row.get("tip", "")), "on": on(s, data, who, id), "why": fixed_why(s, row)})
	return out


## "" when `who` may switch the toggle now, else why not.
static func why(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> String:
	return "TOGGLE_NOT_YOURS" if not has(s, data, who, id) else fixed_why(s, rows(data)[id])


## Switches the toggle of `who`. "" or why not.
static func put(s: GameSession, data: Dictionary, who: Dictionary, id: String, value: bool) -> String:
	var stop := why(s, data, who, id)
	if not stop.is_empty():
		return stop
	var rec := Sheet.record(s, who, true)
	if not rec.has("toggles"):
		rec["toggles"] = {}
	rec["toggles"][id] = value
	return ""


## What the toggles of `f` that are on do to its weapon blow `b`, before it is struck: the feature action of `act` run
## first when it can, the `opts` merged, `spare` kept. The blow as it goes now.
static func before_blow(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, lines: Array[String]) -> Dictionary:
	var out := b
	var all := rows(data)
	for id: String in all:
		var row: Dictionary = all[id]
		if not row.has("blow") or not _fits(row["blow"], b) or not on(s, data, f, id):
			continue
		var act := str(row.get("act", ""))
		if not act.is_empty() and FeatureRules.why(s, data, f, act, "").is_empty():
			lines.append_array(FeatureRules.run(s, data, f, act))
		var opts: Dictionary = (out.get("opts", {}) as Dictionary).merged(row.get("opts", {}), true)
		if bool(row.get("spare", false)):
			opts["spare"] = true
		out = out.merged({"opts": opts}, true)
	return out


## The blow is of the kind the row asks: each field of `want` is the blow's own ({melee, str_based}).
static func _fits(want: Dictionary, b: Dictionary) -> bool:
	for k: String in want:
		if bool(b.get(k, true)) != bool(want[k]):
			return false
	return true
