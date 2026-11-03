class_name Cheats
extends RefCounted
## The dev console's cheats (docs/tech/godot-client.md «Отладка»): a search over the catalogs for the commands and their
## completion, the toggles kept on the hero's sheet (`cheats`), and a rebuild of the hero at level 1. Every change of the
## world goes through the engine's own road (Gear, Ledger, CombatRules, LevelUp, StudyRules); here is only what the
## console needs beside them. Pure: no nodes.

## The toggles: `god` — the hero's hit points never fall under 1 (Harm.take); `slots` — spell slots are never spent and
## every circle has one (Stock.spend, SpellRules.slots_left).
const TOGGLES: Array[String] = ["god", "slots"]
## Where a resistance or a status of the console comes from: it lasts until taken off.
const SOURCE := {"kind": "dev", "name": "консоль"}
## The defenses against a damage type a cheat lays: the effect's list → its word.
const DEFENSES := {"resist": "сопротивление", "immune": "иммунитет", "vulnerable": "уязвимость"}
## The rows of exhaustion's own steps (exhaustion_3): read by the level, never laid by hand.
static var EXHAUSTION_STEP := RegEx.create_from_string("^exhaustion_\\d+$")
## What a search is over: a command's argument kind → where its entries live.
const KINDS: Array[String] = ["item", "monster", "spell", "feature", "trait", "room", "class", "damage", "condition"]
## Fields of the hero a rebuild keeps: who it is, what it carries, what lies on it and what it chose at creation beside
## its class.
const KEPT: Array[String] = ["name", "gender", "race", "subrace", "background", "body", "story", "inventory", "equipped",
	"copies", "gold_cp", "languages", "traits", "conditions", "effects", "next_effect", "exhaustion", "faith", "cheats"]


static func on(c: Dictionary, key: String) -> bool:
	return bool((c.get("cheats", {}) as Dictionary).get(key, false))


## Flips a toggle; its new state.
static func toggle(c: Dictionary, key: String) -> bool:
	var ch: Dictionary = c.get("cheats", {})
	ch[key] = not bool(ch.get(key, false))
	c["cheats"] = ch
	return bool(ch[key])


## The save remembers which cheats were used: a trace with a cheat is not a bug report.
static func note(c: Dictionary, cmd: String) -> void:
	var ch: Dictionary = c.get("cheats", {})
	var used: Array = ch.get("used", [])
	if not used.has(cmd):
		used.append(cmd)
	ch["used"] = used
	c["cheats"] = ch


## The entries of a kind: {id: {name, …}}.
static func pool(s: GameSession, data: Dictionary, kind: String) -> Dictionary:
	match kind:
		"item":
			var all: Dictionary = (data["items"]["catalog"] as Dictionary).duplicate()
			all.merge(s.items)
			return all
		"monster":
			return data["monsters"]
		"spell":
			return data["spells"]
		"feature":
			return data["classes"]["features"]
		"trait":
			return data["races"]["traits"]
		"room":
			return data["world"]["rooms"]
		"class":
			return data["classes"]["classes"]
		"damage":
			var types := {}
			for id: String in data["misc"]["damage_types"]:
				types[id] = {"name": str(data["misc"]["damage_types"][id])}
			return types
		"condition":
			return conditions(data)
	return {}


## The statuses a creature can have: the conditions of the rules and the statuses of spells with a row of their own
## (Faerie Fire's light, Ray of Enfeeblement), not a thing's (burning, oiled) nor a step of exhaustion. {id: {name}}.
static func conditions(data: Dictionary) -> Dictionary:
	var out := {}
	var ids: Array = (data["rules"]["conditions"] as Dictionary).keys()
	for id: String in data["rules"].get("condition_effects", {}):
		if not id.begins_with("_") and not ids.has(id):
			ids.append(id)
	for id: String in ids:
		if not ThingRules.lies_on_things(data, id) and not EXHAUSTION_STEP.search(id):
			out[id] = {"name": ConditionRules.name_of(data, id)}
	return out


## Entries whose id or name (Russian or English) holds `query`, the ones that begin with it first: [{id, name}].
static func find(s: GameSession, data: Dictionary, kind: String, query: String, limit: int = 0) -> Array[Dictionary]:
	var q := query.strip_edges().to_lower()
	var first: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	var all := pool(s, data, kind)
	for id: String in all:
		var d: Variant = all[id]
		var name := str(d.get("name", id)) if d is Dictionary else id
		var en := str(d.get("name_en", "")) if d is Dictionary else ""
		var keys := [id.to_lower(), name.to_lower(), en.to_lower()]
		if keys.any(func(k: String) -> bool: return k.begins_with(q)):
			first.append({"id": id, "name": name})
		elif keys.any(func(k: String) -> bool: return k.contains(q)):
			rest.append({"id": id, "name": name})
	var by_name := func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"])
	first.sort_custom(by_name)
	rest.sort_custom(by_name)
	var out := first + rest
	return out.slice(0, limit) if limit > 0 else out


## One id by an id, a whole name or a part that only one entry has: {id} or {reason}.
static func resolve(s: GameSession, data: Dictionary, kind: String, query: String) -> Dictionary:
	var all := pool(s, data, kind)
	var id := Lookup._resolve(all, query)
	if not id.is_empty():
		return {"id": id}
	var found := find(s, data, kind, query)
	if found.size() == 1:
		return {"id": str(found[0]["id"])}
	if found.is_empty():
		return {"reason": "не найдено: %s (find %s <часть имени>)" % [query, kind]}
	return {"reason": "несколько: %s%s" % [", ".join(found.slice(0, 8).map(func(e: Dictionary) -> String: return "%s [%s]" % [e["name"], e["id"]])),
		" …" if found.size() > 8 else ""]}


## The ones in this room a cheat may aim at (`@цель`): the fighters of the fight but the hero, else the people here.
## [{id, name, fighter}].
static func units(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if CombatRules.active(s):
		for id: String in s.combat["fighters"]:
			var f := CombatRules.fighter(s, id)
			if id != CombatRules.PLAYER and not f.is_empty():
				out.append({"id": id, "name": str(f.get("name", id)), "fighter": true, "side": str(f.get("side", "")),
					"status": str(f.get("status", ""))})
		return out
	for id: String in s.npcs_here(data["world"], s.room_id):
		out.append({"id": id, "name": WorldView.new(data["world"]).npc_name(id), "fighter": false})
	return out


## One unit by its id, its name without spaces or the start of it that only one has: {id, fighter} or {reason}.
static func unit(s: GameSession, data: Dictionary, query: String) -> Dictionary:
	var q := query.trim_prefix("@").to_lower().replace(" ", "")
	var all := units(s, data)
	var hit := all.filter(func(u: Dictionary) -> bool: return str(u["id"]).to_lower() == q or str(u["name"]).to_lower().replace(" ", "") == q)
	if hit.is_empty():
		hit = all.filter(func(u: Dictionary) -> bool: return str(u["name"]).to_lower().replace(" ", "").begins_with(q))
	if hit.size() == 1:
		return hit[0]
	if hit.is_empty():
		return {"reason": "здесь нет %s (units — кто здесь)" % query}
	return {"reason": "несколько: %s" % ", ".join(hit.map(func(u: Dictionary) -> String: return "%s [@%s]" % [u["name"], u["id"]]))}


## A defense of `who` (an id) against `dtype` until it is taken off: `kind` of DEFENSES — an effect on it with that list,
## read by Sheet.defenses for anybody; `on` false takes the console's off. Its line.
static func defense(s: GameSession, data: Dictionary, who: String, kind: String, dtype: String, on: bool) -> String:
	var h := Sheet.holder(s, Sheet.own(s, who))
	var name := "%s: %s" % [DEFENSES[kind], data["misc"]["damage_types"][dtype]]
	if not on:
		for e: Dictionary in ConditionRules.effects(h).duplicate():
			if str(e.get("source", {}).get("kind", "")) == SOURCE["kind"] and (e.get(kind, []) as Array).has(dtype):
				ConditionRules.remove_effect(h, int(e["uid"]))
		return "снято — " + name
	ConditionRules.add_effect(h, {"condition": "", kind: [dtype], "source": SOURCE.duplicate(), "ends": {}})
	return name


## A status of the engine on `who` (an id) until it is taken off, laid as anything lays it (ConditionRules.impose), or
## lifted. Lines.
static func condition(s: GameSession, data: Dictionary, who: String, cond: String, on: bool) -> Array[String]:
	var w := Sheet.own(s, who)
	if not on and cond == "exhaustion":  # a level of the one scale off, as a rest takes it
		return ConditionRules.add_exhaustion(s, data, -1, "", who)
	if not on:
		ConditionRules.remove(Sheet.holder(s, w), cond)
		return ["снято: %s" % ConditionRules.name_of(data, cond)]
	var lines := ConditionRules.impose(s, data, {"condition": cond, "ends": {}, "source": SOURCE.duplicate()}, w)
	lines.push_front("состояние: %s" % ConditionRules.name_of(data, cond))
	return lines


## The hero again at level 1 of `class_id` (its own class when ""): its race, background, name, things and statuses
## stay, the class's picks are the engine's first ones (CharacterBuilder.random_choices with what stays fixed). Lines.
static func rebuild(s: GameSession, data: Dictionary, class_id: String) -> Array[String]:
	var c := s.character
	var klass := class_id if not class_id.is_empty() else str(c.get("class", ""))
	var fixed := {"race": str(c.get("race", "")), "subrace": str(c.get("subrace", "")), "class": klass,
		"background": str(c.get("background", "")), "name": str(c.get("name", "")), "gender": str(c.get("gender", "male")),
		"god": FaithRules.hero_god(c)}
	if klass == str(c.get("class", "")):
		fixed["subclass"] = str(c.get("subclass", ""))
	var fresh := CharacterBuilder.build(CharacterBuilder.random_choices(data, s.rng, fixed), data)
	for k: String in fresh:
		if not KEPT.has(k):
			c[k] = fresh[k]
	c.erase("hp")
	CharacterRules.refresh(c, data, s.items)
	return ["%s — %s 1 уровня" % [c["name"], data["classes"]["classes"][klass]["name"]]]
