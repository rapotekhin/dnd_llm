class_name DevelopmentRules
extends RefCounted
## Peaceful development (roadmap v0.7.19.1, the author: keep the 5e levelling and carry it over to the peaceful sides
## of life — not a tree, a choice from a list on every level). The class levelling of 5e stays as it is (XpRules,
## LevelUp): the hero's fighting road. A peaceful direction (rules.development.directions — «Торговля» first, crafts
## and the rest with their systems) has its own experience from its own deeds, levels 0–5 by rules.development.xp, and on
## every level the player picks one skill from the list open to that level. A skill works only in the deeds of its
## direction (`effect` — the engine's knobs there). Experience never crosses between directions or into the class.
## The hero keeps it in c["development"] {direction: {xp, skills: [ids]}}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["development"]


static func direction(data: Dictionary, dir: String) -> Dictionary:
	return cfg(data)["directions"].get(dir, {})


static func state(c: Dictionary, dir: String) -> Dictionary:
	if not c.has("development"):
		c["development"] = {}
	if not c["development"].has(dir):
		c["development"][dir] = {"xp": 0, "skills": []}
	return c["development"][dir]


static func xp(c: Dictionary, dir: String) -> int:
	return int(c.get("development", {}).get(dir, {}).get("xp", 0))


## The level by the experience: 0 … the last threshold of rules.development.xp.
static func level(c: Dictionary, data: Dictionary, dir: String) -> int:
	return Scale.index(cfg(data)["xp"], xp(c, dir))


## The experience the next level needs (-1 — the top).
static func next_xp(c: Dictionary, data: Dictionary, dir: String) -> int:
	var table: Array = cfg(data)["xp"]
	var lvl := level(c, data, dir)
	return int(table[lvl + 1]) if lvl + 1 < table.size() else -1


static func skills(c: Dictionary, dir: String) -> Array:
	return c.get("development", {}).get(dir, {}).get("skills", [])


## Levels not yet paid with a skill.
static func picks_left(c: Dictionary, data: Dictionary, dir: String) -> int:
	return maxi(0, level(c, data, dir) - skills(c, dir).size())


## The skills the hero may pick now: of a level ≤ the direction's level, not taken, their `needs` taken.
static func choices(c: Dictionary, data: Dictionary, dir: String) -> Array[String]:
	var out: Array[String] = []
	if picks_left(c, data, dir) <= 0:
		return out
	var all: Dictionary = direction(data, dir).get("skills", {})
	for id: String in all:
		var sk: Dictionary = all[id]
		if int(sk.get("level", 1)) <= level(c, data, dir) and not skills(c, dir).has(id) \
				and (sk.get("needs", []) as Array).all(func(n: Variant) -> bool: return skills(c, dir).has(str(n))):
			out.append(id)
	return out


## Takes a skill (one of choices). "" or a localization key.
static func pick(c: Dictionary, data: Dictionary, dir: String, skill: String) -> String:
	if not choices(c, data, dir).has(skill):
		return "DEV_CANNOT_PICK"
	(state(c, dir)["skills"] as Array).append(skill)
	return ""


## Experience in a direction from its deed. Lines: «Торговля: +12 опыта», a new level — «выберите навык».
static func add_xp(c: Dictionary, data: Dictionary, dir: String, amount: int) -> Array[String]:
	var lines: Array[String] = []
	if amount <= 0 or direction(data, dir).is_empty():
		return lines
	var before := level(c, data, dir)
	var st := state(c, dir)
	st["xp"] = int(st["xp"]) + amount
	var name := str(direction(data, dir)["name"])
	lines.append("%s: +%d опыта" % [name, amount])
	if level(c, data, dir) > before:
		lines.append("%s — уровень %d: выберите навык в листе персонажа, «Развитие»" % [name, level(c, data, dir)])
	return lines


## A knob of the hero's skills in a direction: the product of numbers (`*_pct`, `*_mult`), any true flag, the
## largest other number; `default` when no skill sets it.
static func effect(c: Dictionary, data: Dictionary, dir: String, key: String, default: Variant) -> Variant:
	var all: Dictionary = direction(data, dir).get("skills", {})
	var out: Variant = default
	for id: Variant in skills(c, dir):
		var fx: Dictionary = all.get(str(id), {}).get("effect", {})
		if not fx.has(key):
			continue
		var v: Variant = fx[key]
		if v is bool:
			out = out or v
		elif key.ends_with("_pct"):  # percents multiply: 100 × 105 / 100
			out = float(out) * float(v) / 100.0
		elif key.ends_with("_mult"):
			out = float(out) * float(v)
		else:
			out = maxf(float(out), float(v))
	return out


## Any direction with a level not yet paid with a skill (the side panel's reminder).
static func any_pick(c: Dictionary, data: Dictionary) -> String:
	for dir: String in cfg(data)["directions"]:
		if picks_left(c, data, dir) > 0:
			return dir
	return ""


## For the master: «Торговля 2: Глаз оценщика, Язык без костей».
static func text(c: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for dir: String in c.get("development", {}):
		var d := direction(data, dir)
		if d.is_empty():
			continue
		var names: Array = skills(c, dir).map(func(id: Variant) -> String: return str(d["skills"].get(str(id), {}).get("name", id)))
		out.append("%s %d%s" % [d["name"], level(c, data, dir), (": " + ", ".join(names)) if not names.is_empty() else ""])
	return out
