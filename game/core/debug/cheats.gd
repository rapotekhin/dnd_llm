class_name Cheats
extends RefCounted
## The dev console's cheats (docs/tech/godot-client.md «Отладка»): a search over the catalogs for the commands and their
## completion, the toggles kept on the hero's sheet (`cheats`), and a rebuild of the hero at level 1. Every change of the
## world goes through the engine's own road (Gear, Ledger, CombatRules, LevelUp, StudyRules); here is only what the
## console needs beside them. Pure: no nodes.

## The toggles: `god` — the hero's hit points never fall under 1 (Harm.take); `slots` — spell slots are never spent and
## every circle has one (Stock.spend, SpellRules.slots_left).
const TOGGLES: Array[String] = ["god", "slots"]
## What a search is over: a command's argument kind → where its entries live.
const KINDS: Array[String] = ["item", "monster", "spell", "feature", "trait", "room", "class"]
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
	return {}


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
