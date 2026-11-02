class_name Move
extends RefCounted
## How anyone moves (v0.8.4.7, ADR-0016). A way of moving is a row of `rules.combat.moves`: a new row is a new way for the hero, a
## person and a foe at once. The rows a character has come from its SRD template and from its statuses (Fly on anybody). One walk
## for everybody: `go`.


static func table(data: Dictionary) -> Dictionary:
	var out := {}
	var rows: Dictionary = CombatRules.cfg(data)["moves"]
	for id: String in rows:
		if not id.begins_with("_"):
			out[id] = rows[id]
	return out


static func _speeds(data: Dictionary, m: Dictionary, me: Dictionary) -> Dictionary:
	var out := {}
	var rows := table(data)
	for id: String in rows:
		var row: Dictionary = rows[id]
		var ft := int(m.get(str(row["speed"]), row.get("default", 0)))
		for e: Dictionary in SpellEffects.hero_effects(me, str(row.get("status", ""))):
			ft = maxi(ft, int(e[str(row["status"])]))
		if ft > 0:
			out[id] = ft
	return out


## Its ways of moving now: {row id: feet}.
static func speeds(s: GameSession, data: Dictionary, who: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, who)
	var body := Guise.body(me) if Sheet.is_hero(who) else {}
	var m: Dictionary = data["monsters"].get(str(body.get("monster", "")), Sheet.template(data, who))
	return _speeds(data, m, me)


## The way covered in a turn: the fastest that goes anywhere; one that works only on some squares only for one who has no other.
static func _most(data: Dictionary, by: Dictionary) -> int:
	var rows := table(data)
	var any := 0
	var only := 0
	for id: String in by:
		if rows[id].has("on"):
			only = maxi(only, int(by[id]))
		else:
			any = maxi(any, int(by[id]))
	return any if any > 0 else only


## The feet of a template by its SRD record alone: a Flying Sword — 0 ft, fly 50 ft — covers 50.
static func feet_of(data: Dictionary, m: Dictionary) -> int:
	return _most(data, _speeds(data, m, {}))


static func feet(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	return _most(data, speeds(s, data, who))


## The feet its statuses give on a way that goes anywhere: the hero's sheet reads this (Fly: 60 ft).
static func status_feet(data: Dictionary, c: Dictionary) -> int:
	var rows := table(data)
	var out := 0
	for id: String in rows:
		var key := str(rows[id].get("status", ""))
		if not rows[id].has("on"):
			for e: Dictionary in SpellEffects.hero_effects(c, key):
				out = maxi(out, int(e[key]))
	return out


## «30 фт, плавание 40 фт» for a card.
static func text(data: Dictionary, m: Dictionary) -> String:
	var rows := table(data)
	var by := _speeds(data, m, {})
	var out: Array[String] = ["%d фт" % int(by.get("walk", 0))]
	for id: String in by:
		if rows[id].has("word"):
			out.append("%s %d фт" % [rows[id]["word"], int(by[id])])
	return ", ".join(out)


## It moves through the air now: out of a blade's reach unless it comes down.
static func air(s: GameSession, data: Dictionary, who: Dictionary) -> bool:
	var rows := table(data)
	for id: String in speeds(s, data, who):
		if bool(rows[id].get("air", false)):
			return true
	return false


## The squares of a turn's walk; nothing when it may not move at all.
static func steps(s: GameSession, data: Dictionary, f: Dictionary) -> int:
	if ConditionRules.does(Sheet.holder(s, f), data, "no_move"):
		return 0
	return FightGrid.steps_of(data, Sheet.speed(s, data, f))


## What the way asks of the map, for FightGrid.reach: its rows put together, the fear and a door it cannot open.
static func opts(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var rows := table(data)
	var out := {"passes": 0, "flat": false, "on": 0, "only": 0, "latch": Sheet.is_hero(f) or CombatRules._intelligent(data, f)}
	var land := false
	for id: String in speeds(s, data, f):
		var row: Dictionary = rows[id]
		out["passes"] = int(out["passes"]) | FightGrid.mask(row.get("passes", []))
		out["flat"] = bool(out["flat"]) or bool(row.get("flat", false))
		if row.has("on"):
			out["on"] = int(out["on"]) | FightGrid.mask(row["on"])
		else:
			land = true
	if not land:
		out["only"] = out["on"]
	var src := CombatRules.fear_source(s, f)
	if not src.is_empty() and not bool(f.get("fleeing", false)):
		out["fear"] = FightGrid.cell(src)
	return out


## "" when it can step at all now: a speed, on its feet, squares left.
static func stuck(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	if Sheet.speed(s, data, f) <= 0:
		return "COMBAT_NO_SPEED"
	if ConditionRules.has(Sheet.holder(s, f), "prone"):
		return "COMBAT_PRONE"
	if int(CombatRules.points(s, data, f).get("move", 0)) <= 0:
		return "COMBAT_NO_MOVE"
	return ""


## `stuck` on its own turn: "" or a key.
static func why(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	return "COMBAT_NOT_YOUR_TURN" if CombatRules.current(s) != str(f.get("id")) else stuck(s, data, f)


## Where it can walk with the squares it has left: FightGrid.reach, {} when it cannot.
static func routes(s: GameSession, data: Dictionary, f: Dictionary, budget: int = -1) -> Dictionary:
	if not stuck(s, data, f).is_empty():
		return {}
	return FightGrid.reach(s, data, f, int(CombatRules.points(s, data, f)["move"]) if budget < 0 else budget, opts(s, data, f))


## The walk of anybody, step by step: a foe whose reach it leaves strikes, a door opens on the way, a step ends on what happens
## under the feet, what is left of the way stays unwalked when it falls or a window waits. Squares walked.
static func go(s: GameSession, data: Dictionary, f: Dictionary, to: Vector2i, lines: Array[String]) -> int:
	var e := CombatRules.points(s, data, f)
	var ways := routes(s, data, f)
	var paid := 0
	var walked: Array = []
	for at: Vector2i in FightGrid.route(ways, to):
		CombatRules.leaving(s, data, f, at, lines)
		if CombatRules.stopped(s, f):
			break
		var cost := int(ways[at][0])
		e["move"] = int(e["move"]) - (cost - paid)
		paid = cost
		FightField.opens_on_way(s, data, f, at, lines)
		FightGrid.put(f, at)
		walked.append(FightGrid.tag(at))
		if FightField.stepped(s, data, f, lines) or CombatRules.stopped(s, f):
			break
	if not walked.is_empty():
		e["walked"] = int(e.get("walked", 0)) + walked.size()
		FightField.note_walk(s, str(f.get("id")), walked)
		if Sheet.is_hero(f):
			CombatRules._release_grapples(s, lines)
			FightField.hero_stands(s, data)
	return walked.size()
