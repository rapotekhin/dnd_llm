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
## The console's blow (`hit`): its name in the lines, the to-hit bonus without `+N`, the type without one, a reach and a range
## past any map so the distance gives it nothing.
const STRIKE := {"name": "удар консоли", "to_hit": 5, "type": "bludgeoning", "reach": 999, "range": 9999}
const HIT_USAGE := "hit <кубики> [тип урона] [+атака] [adv|dis] [crit] [magic] [silver] [ranged] [@кто бьёт]"
const DMG_USAGE := "dmg <кубики> [тип урона] [crit] [magic] [silver]"
const DMG_NAME := "урон консоли"
## The words of `hit` → the flag of its spec.
const STRIKE_WORDS := {"adv": "adv", "преим": "adv", "преимущество": "adv", "dis": "dis", "помеха": "dis", "crit": "crit", "крит": "crit",
	"magic": "magical", "магия": "magical", "silver": "silvered", "серебро": "silvered", "ranged": "ranged", "выстрел": "ranged"}
static var DICE := RegEx.create_from_string("^\\d*d\\d+([+-]\\d+)?$")
static var TO_HIT := RegEx.create_from_string("^[+-]\\d+$")
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
		if not ThingRules.only_things(data, id) and not EXHAUSTION_STEP.search(id):
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
	return {"reason": "несколько: %s%s" % [", ".join(found.slice(0, 8).map(tag)), " …" if found.size() > 8 else ""]}


## How the console names an entry or a unit: «Имя [id]», a unit's id with `@` to put after it.
static func tag(e: Dictionary) -> String:
	return "%s [%s%s]" % [e["name"], "@" if e.has("fighter") else "", e["id"]]


## «HP 7/11» of `who` (an id), the hero or anybody.
static func hp_line(s: GameSession, data: Dictionary, who: String) -> String:
	var w := Sheet.own(s, who)
	return "HP %d/%d" % [Sheet.hp(s, data, w), Sheet.max_hp(s, data, w)]


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


## The units whose id or name without spaces is `query` (`exact`) or begins with it (`@` and case aside).
static func units_like(s: GameSession, data: Dictionary, query: String, exact := false) -> Array[Dictionary]:
	var q := query.trim_prefix("@").to_lower().replace(" ", "")
	return units(s, data).filter(func(u: Dictionary) -> bool:
		var keys := [str(u["id"]).to_lower(), str(u["name"]).to_lower().replace(" ", "")]
		return keys.has(q) if exact else keys.any(func(k: String) -> bool: return k.begins_with(q)))


## One unit by its id, its name without spaces or the start of either that only one has: {id, fighter} or {reason}.
static func unit(s: GameSession, data: Dictionary, query: String) -> Dictionary:
	var hit := units_like(s, data, query, true)
	if hit.is_empty():
		hit = units_like(s, data, query)
	if hit.size() == 1:
		return hit[0]
	if hit.is_empty():
		return {"reason": "здесь нет %s (units — кто здесь)" % query}
	return {"reason": "несколько: %s" % ", ".join(hit.map(tag))}


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
## lifted. `dice` — the damage each turn of a status that has it (`cond burning 2d6`, v0.8.4.43.54): its row's type and moment.
## Lines.
static func condition(s: GameSession, data: Dictionary, who: String, cond: String, on: bool, dice: String = "") -> Array[String]:
	var w := Sheet.own(s, who)
	if not on and cond == "exhaustion":  # a level of the one scale off, as a rest takes it
		return ConditionRules.add_exhaustion(s, data, -1, "", who)
	if not on:
		ConditionRules.remove(Sheet.holder(s, w), cond)
		return ["снято: %s" % ConditionRules.name_of(data, cond)]
	var e := {"condition": cond, "ends": {}, "source": SOURCE.duplicate()}
	var row_harm: Dictionary = data["rules"]["condition_effects"].get(cond, {}).get("harm", {})
	if not dice.is_empty():
		if row_harm.is_empty():
			return ["у состояния «%s» нет урона каждый ход" % ConditionRules.name_of(data, cond)]
		e["harm"] = row_harm.merged({"dice": dice}, true)
	var lines := ConditionRules.impose(s, data, e, w)
	var hm := ConditionRules.harm_text(data, ConditionRules.effects_of(Sheet.holder(s, w), cond)[0]) if ConditionRules.has(Sheet.holder(s, w), cond) else ""
	lines.push_front("состояние: %s%s" % [ConditionRules.name_of(data, cond), (" — " + hm) if not hm.is_empty() else ""])
	return lines


## The words of `hit` (after the target, without the striker's `@`): the dice, the damage type, `+N` to hit, the forced
## advantage or disadvantage, a critical hit, a magical or silvered blow, a shot. {spec} or {reason}.
static func strike_spec(s: GameSession, data: Dictionary, words: PackedStringArray, usage: String = HIT_USAGE) -> Dictionary:
	var spec := {"dice": "", "type": STRIKE["type"], "to_hit": int(STRIKE["to_hit"]), "adv": false, "dis": false, "crit": false,
		"magical": false, "silvered": false, "ranged": false}
	var rest := PackedStringArray()
	for w: String in words:
		var lw := w.to_lower()
		var flag := str(STRIKE_WORDS.get(lw, ""))
		if DICE.search(lw.replace("к", "d")):
			spec["dice"] = lw.replace("к", "d")
		elif TO_HIT.search(lw):
			spec["to_hit"] = int(lw)
		elif not flag.is_empty():
			spec[flag] = true
		else:
			rest.append(w)
	if str(spec["dice"]).is_empty():
		return {"reason": usage}
	if not rest.is_empty():
		var r := resolve(s, data, "damage", " ".join(rest))
		if r.has("reason"):
			return r
		spec["type"] = str(r["id"])
	return {"spec": spec}


## Damage of a spec to `who` (an id) without an attack roll, as a trap or the master's damage lays it: the dice (twice with
## `crit`), on the one road of damage with no roll (Harm.typed) — in a fight or out of it, the hero or anybody. Lines.
static func harm(s: GameSession, data: Dictionary, who: String, spec: Dictionary) -> Array[String]:
	var w := Sheet.own(s, who)
	var dtype := str(spec["type"])
	var rolled := CombatRules.roll_dice(s.rng, str(spec["dice"]), bool(spec["crit"]))
	var lines: Array[String] = []
	Harm.typed(s, data, w, rolled, dtype, lines, "%s: %s%s = %d → %s −{hp} HP ({words})" % [DMG_NAME, str(spec["dice"]).replace("d", "к"),
		" ×2 (крит)" if bool(spec["crit"]) else "", rolled, Sheet.holder(s, w).get("name", WorldView.new(data["world"]).npc_name(who))],
		bool(spec["crit"]), false, bool(spec["magical"]), bool(spec["silvered"]))
	return lines


## The blow of a spec for Attack.swing: a roll of its own with no weapon nor class behind it, at any distance; a critical
## one hits on any roll. The striker's statuses and the target's defenses work on it as on any blow.
static func blow(spec: Dictionary) -> Dictionary:
	var b := {"name": STRIKE["name"], "to_hit": int(spec["to_hit"]), "pieces": [{"dice": str(spec["dice"]), "type": str(spec["type"])}],
		"bonus": 0, "melee": not bool(spec["ranged"]), "reach": int(STRIKE["reach"]), "range": [] if not bool(spec["ranged"]) else [int(STRIKE["range"]), int(STRIKE["range"])],
		"magical": bool(spec["magical"]), "silvered": bool(spec["silvered"]), "str_based": false}
	if bool(spec["adv"]):
		b["adv"] = [STRIKE["name"]]
	if bool(spec["dis"]):
		b["dis"] = [STRIKE["name"]]
	if bool(spec["crit"]):
		b["crit_min"] = 1
	return b


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
