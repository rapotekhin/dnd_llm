class_name BodyRules
extends RefCounted
## Age, build and height of the hero and of NPCs (the author's request after the big test, v0.7.22.5): words, not
## numbers — the engine picks each from the lists of rules.json `body` (their own for men and women: «худой» /
## «худая», «молодой» / «молодая»), by weights, deterministically by a seed (the name, the NPC id), so the same person
## keeps the same body without a save. What a pack or the master set stays. A child and a teenager come only when
## set — the engine's own picks are grown-ups (the hero — not old either).

const KEYS: Array[String] = ["age", "build", "height"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["body"]


## The list of a key for a gender: {id: {"male": word, "female": word, "weight", "hero_weight"?}}.
static func options(data: Dictionary, key: String) -> Dictionary:
	return cfg(data)[key]


## The word of an id for a gender ("other" — the male form).
static func word(data: Dictionary, key: String, id: String, gender: String) -> String:
	var o: Dictionary = options(data, key).get(id, {})
	return str(o.get(gender if gender == "female" else "male", o.get("male", id)))


## Ids a gender has (the lists differ: «пышная» has no male form).
static func ids_for(data: Dictionary, key: String, gender: String) -> Array[String]:
	var out: Array[String] = []
	var g := "female" if gender == "female" else "male"
	for id: String in options(data, key):
		if (options(data, key)[id] as Dictionary).has(g):
			out.append(id)
	return out


## Ids the player may choose for the hero (v0.7.22.15): the gender's list but those with `hero: false`.
static func hero_ids(data: Dictionary, key: String, gender: String) -> Array[String]:
	return ids_for(data, key, gender).filter(func(id: String) -> bool: return bool((options(data, key)[id] as Dictionary).get("hero", true)))


## The player's picks that still fit the hero's gender (a gender changed — «стройная» is dropped for a man).
static func fit(data: Dictionary, given: Dictionary, gender: String) -> Dictionary:
	var out := {}
	for key: String in KEYS:
		if hero_ids(data, key, gender).has(str(given.get(key, ""))):
			out[key] = str(given[key])
	return out


## {age, build, height} ids: `given` stays (when it is an id of the list), the rest picked by weights.
static func make(data: Dictionary, gender: String, given: Dictionary, seed_text: String, hero: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var out := {}
	for key: String in KEYS:
		var g := str(given.get(key, "")) if given.get(key) != null else ""
		if options(data, key).has(g):
			out[key] = g
			continue
		var pool: Array[String] = []
		var weights: Array[float] = []
		for id: String in ids_for(data, key, gender):
			var o: Dictionary = options(data, key)[id]
			var w := float(o.get("hero_weight", o.get("weight", 1))) if hero else float(o.get("weight", 1))
			if w > 0:
				pool.append(id)
				weights.append(w)
		out[key] = pool[rng.rand_weighted(PackedFloat32Array(weights))] if not pool.is_empty() else ""
	return out


## «молодой, спортивный, высокий» — for the sheet, the talk and the master.
static func text(data: Dictionary, b: Dictionary, gender: String) -> String:
	var parts: Array[String] = []
	for key: String in KEYS:
		if not str(b.get(key, "")).is_empty():
			parts.append(word(data, key, str(b[key]), gender))
	return ", ".join(parts)


## An NPC's body: its pack (or made) fields `age`, `build`, `height` over what the engine picks by its id.
static func npc(data: Dictionary, npc_id: String, n: Dictionary) -> Dictionary:
	return make(data, str(n.get("gender", "other")), n, "npc:" + npc_id)


static func npc_text(data: Dictionary, npc_id: String, n: Dictionary) -> String:
	return text(data, npc(data, npc_id, n), str(n.get("gender", "other")))


## Checks the body the master gave a new NPC: the ids of the lists, or {reason}.
static func check(data: Dictionary, spec: Dictionary) -> Dictionary:
	var out := {}
	for key: String in KEYS:
		var v := str(spec.get(key, "")) if spec.get(key) != null else ""
		if v.is_empty():
			continue
		if not options(data, key).has(v):
			return {"reason": "%s — из %s" % [key, ", ".join(options(data, key).keys())]}
		out[key] = v
	return out
