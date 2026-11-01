class_name FightAI
extends RefCounted
## The turn of a creature in a fight (v0.8.4): a search over the squares it can walk to and the acts it has from each, by a
## value. What it weighs comes from its role in `rules.combat.ai.roles`; the role from its SRD record: a caster, a shooter,
## a pack hunter, a beast, one who strikes and runs, a brute. `budget` in rules.json limits the lines traced in a turn.
## Nothing here changes the world but walking: the blows and spells are CombatRules and MonsterRules.

const FAR := 1 << 20


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["combat"]["ai"]


static func role_name(data: Dictionary, f: Dictionary) -> String:
	var c := cfg(data)
	var m := CombatRules._monster(data, f)
	var own := str(c["monsters"].get(str(f.get("monster", "")), ""))
	if not own.is_empty():
		return own
	if m.has("spellcasting"):
		return "caster"
	var actions: Array = m.get("actions", [])
	if not actions.is_empty() and actions.all(func(a: Dictionary) -> bool: return str(a.get("kind")) != "melee" or a.has("range")):
		return "archer"
	for t: Dictionary in m.get("traits", []):
		if c["by_trait"].has(str(t.get("id", ""))):
			return str(c["by_trait"][str(t["id"])])
	return str(c["by_type"].get(str(m.get("type", "")), "brute"))


static func role(data: Dictionary, f: Dictionary) -> Dictionary:
	return cfg(data)["roles"][role_name(data, f)]


## The squares of its walk this turn.
static func steps(s: GameSession, data: Dictionary, f: Dictionary) -> int:
	if ConditionRules.does(f, data, "no_move"):
		return 0
	var m := CombatRules._monster(data, f)
	var n := FightGrid.steps_of(data, MonsterRules.move_speed(m) - int(f.get("slowed", 0)) + ConditionRules.sum(f, "speed"))
	return n / 2 if CombatRules._has(f, "slowed_spell") else n


static func _opts(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var m := CombatRules._monster(data, f)
	var out := {"flying": MonsterRules.flies(data, f), "latch": CombatRules._intelligent(data, f), "swims": int(m.get("swim", 0)) > 0}
	if CombatRules._has(f, "frightened"):
		out["fear"] = FightGrid.cell(CombatRules.player(s))
	return out


## Who it fights: the foes of its side still in the fight. The hero lying at 0 HP is nobody's target (v0.7.9).
static func _targets(s: GameSession, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if str(f.get("side")) == "enemy":
		if int(s.character.get("hp", 0)) > 0:
			out.append(CombatRules.player(s))
		for id: String in CombatRules.allies(s):
			out.append(CombatRules.fighter(s, id))
		return out
	for id: String in CombatRules.enemies(s):
		var e := CombatRules.fighter(s, id)
		if not bool(e.get("hidden", false)) and not CombatRules._has(e, "invisible"):
			out.append(e)
	return out


static func _avg(a: Dictionary) -> float:
	var total := 0.0
	for d: Dictionary in a.get("damage", []):
		var r := CombatRules.dice_range(str(d["dice"]))
		total += (r[0] + r[1]) / 2.0
	return total


## How many blows of this kind its Multiattack gives.
static func _blows(data: Dictionary, f: Dictionary, a: Dictionary) -> int:
	var m := CombatRules._monster(data, f)
	var n := 0
	for x: Dictionary in m.get("multiattack", []):
		for b: Dictionary in m["actions"]:
			if str(b["name_en"]) == str(x["action"]) and str(b.get("kind")) == str(a.get("kind")):
				n += int(x["count"])
	return maxi(1, n)


## What it can do at each target: [{t, kind, act, near, far, power}]. `near` and `far` are squares of its body to the target.
static func _options(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in targets:
		var hero := str(t.get("id")) == CombatRules.PLAYER
		var melee := MonsterRules.pick(s, data, f, "melee") if hero else CombatRules._pick_plain(data, f, "melee")
		var ranged := MonsterRules.pick(s, data, f, "ranged") if hero else CombatRules._pick_plain(data, f, "ranged")
		if not melee.is_empty():
			out.append({"t": t, "kind": "melee", "act": melee, "far": CombatRules.reach_of(data, f), "power": _avg(melee) * _blows(data, f, melee)})
		if not ranged.is_empty():
			var far := FightGrid.squares_of(data, int(ranged["range"][1]))
			out.append({"t": t, "kind": "ranged", "act": ranged, "far": far, "short": FightGrid.squares_of(data, int(ranged["range"][0])), "power": _avg(ranged) * _blows(data, f, ranged)})
		if hero:
			var special := MonsterRules.save_action(s, data, f, 0)
			if not special.is_empty():
				out.append({"t": t, "kind": "save", "act": special, "far": FightGrid.squares_of(data, int(special.get("effect", {}).get("area", {}).get("ft", 5))),
					"power": _avg(special) + float(role(data, f)["control"])})
			var reach := MonsterRules.cast_reach(s, data, f)
			if reach > 0:
				out.append({"t": t, "kind": "cast", "act": {}, "far": reach, "power": float(role(data, f)["cast"])})
	return out


## The turn it would take: {path, option} or {} when there is nobody to fight. An empty `option` — it only walks closer.
static func plan(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var targets := _targets(s, f)
	if targets.is_empty():
		return {}
	var w := role(data, f)
	var n := steps(s, data, f)
	var opts := _opts(s, data, f)
	var walk := n * 2 if MonsterRules.has_trait(data, f, "aggressive") else n  # Aggressive: a bonus move towards the foe
	var routes := FightGrid.reach(s, data, f, walk, opts)
	var cells := FightGrid.stops(s, f, routes)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return int(routes[a][0]) < int(routes[b][0]))
	var options := _options(s, data, f, targets)
	var budget := int(cfg(data)["budget"])
	var ghost := f.duplicate()
	var best := {}
	var top := -INF
	var at_best := FightGrid.cell(f)
	var stay_near := CombatRules.reach_of(data, f)
	for cell: Vector2i in cells:
		FightGrid.put(ghost, cell)
		var place := _place(s, data, f, ghost, cell, routes, targets, w, stay_near)
		for o: Dictionary in options:
			var t: Dictionary = o["t"]
			var d := FightGrid.dist(ghost, t)
			if d > int(o["far"]):
				continue
			var cover := 0
			match str(o["kind"]):
				"melee":
					if not CombatRules.blade_reaches(s, data, ghost, t, int(o["far"])):
						continue
				_:
					if budget <= 0:
						continue
					budget -= 1
					cover = FightGrid.cover(s, data, ghost, t)
					if cover >= FightGrid.FULL_COVER or (str(o["kind"]) == "cast" and not FightGrid.veiled(s, data, ghost, t).is_empty()):
						continue
			var v := place + _worth(s, data, f, o, t, d, cover, w)
			if v > top:
				top = v
				best = o
				at_best = cell
	if not best.is_empty():
		return {"path": FightGrid.route(routes, at_best), "option": best}
	return {"path": _closer(s, data, f, targets, n * 2, opts), "option": {}}


## What an act is worth from there: the chance times the damage, more on the wounded, the kill counted.
static func _worth(s: GameSession, data: Dictionary, f: Dictionary, o: Dictionary, t: Dictionary, d: int, cover: int, w: Dictionary) -> float:
	var hero := str(t.get("id")) == CombatRules.PLAYER
	var hp := float(s.character.get("hp", 1)) if hero else float(t.get("hp", 1))
	var most := maxf(1.0, float(s.character.get("max_hp", 1)) if hero else float(t.get("max_hp", 1)))
	var ac := int(s.character.get("ac", 10)) if hero else CombatRules.ac_of(t)
	var power := float(o["power"])
	var v := power
	if str(o["kind"]) in ["melee", "ranged"]:
		var chance := clampf((21.0 + int(o["act"].get("to_hit", 0)) - ac - cover) / 20.0, 0.05, 0.95)
		v = power * chance
		if str(o["kind"]) == "ranged" and (d <= 1 or d > int(o.get("short", 999))):
			v *= 0.6
	v *= 1.0 + float(w["focus"]) * (1.0 - hp / most)
	if power >= hp:
		v += float(w["finish"])
	if hero and (bool(t.get("hidden", false)) or ConditionRules.has(s.character, "invisible")):
		v *= 0.5
	if float(w["pack"]) > 0.0 and _friend_beside(s, f, t):
		v += float(w["pack"])
	return v


static func _friend_beside(s: GameSession, f: Dictionary, t: Dictionary) -> bool:
	for id: String in CombatRules.enemies(s) if str(f.get("side")) == "enemy" else CombatRules.allies(s):
		if id != str(f.get("id")) and FightGrid.touching(CombatRules.fighter(s, id), t):
			return true
	return false


## What a square is worth by itself: the danger on it, who stands beside it, the way there, the blow in the back.
static func _place(s: GameSession, data: Dictionary, f: Dictionary, ghost: Dictionary, cell: Vector2i, routes: Dictionary, targets: Array[Dictionary], w: Dictionary, near: int) -> float:
	var v := -float(w["step"]) * int(routes[cell][0])
	if FightField.hurts(s, data, ghost):
		v -= float(w["hazard"])
	var nearest := 1 << 30
	for t: Dictionary in targets:
		nearest = mini(nearest, FightGrid.dist(ghost, t))
		if FightGrid.touching(ghost, t):
			v -= float(w["adjacent"])
	v += float(w["keep"]) * mini(nearest, int(cfg(data)["keep_most"]))
	var p := CombatRules.player(s)
	if not bool(p.get("reacted", false)) and FightGrid.touching(f, p) and not FightGrid.touching(ghost, p) and not MonsterRules.has_trait(data, f, "flyby"):
		v -= float(w["leave"])
	return v


## The way nearest to someone to fight, when nothing can be done this turn: it dashes.
static func _closer(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary], budget: int, opts: Dictionary) -> Array[Vector2i]:
	if budget <= 0:
		return []
	var routes := FightGrid.reach(s, data, f, budget, opts)
	var field := {}
	var least := 1 << 30
	for t: Dictionary in targets:
		var flow := FightGrid.flow(s, data, FightGrid.cell(t), bool(opts.get("flying", false)))
		var here := int(flow.get(FightGrid.cell(f), FAR))
		if here < least:
			least = here
			field = flow
	var best := FightGrid.cell(f)
	var score := int(field.get(best, FAR)) * 4
	for at: Vector2i in FightGrid.stops(s, f, routes):
		var v := int(field.get(at, FAR)) * 4 + int(routes[at][0])
		if v < score:
			score = v
			best = at
	return FightGrid.route(routes, best)


# --- the turn played ------------------------------------------------------------------------------------------


## Walks it along the path: a blow when it leaves the hero's reach, a door opened, what is under its feet. Squares walked.
static func walk(s: GameSession, data: Dictionary, f: Dictionary, path: Array[Vector2i], lines: Array[String]) -> int:
	var moved := 0
	var trail: Array = []
	for at: Vector2i in path:
		CombatRules.foe_leaving(s, data, f, at, lines)
		if str(f.get("status")) != "active":
			break
		FightField.opens_on_way(s, data, f, at, lines)
		FightGrid.put(f, at)
		trail.append(FightGrid.tag(at))
		moved += 1
		if FightField.stepped(s, data, f, lines):
			break
	FightField.note_walk(s, str(f["id"]), trail)
	return moved


## The whole turn of a foe or of an ally of the hero.
static func act(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var foe := str(f.get("side")) == "enemy"
	var p := plan(s, data, f)
	if p.is_empty():
		if foe:
			lines.append(("%s не добивает упавшего" if CombatRules._intelligent(data, f) else "%s теряет интерес к упавшему") % f["name"])
		else:
			lines.append("%s не видит врага" % f["name"])
		return
	var moved := walk(s, data, f, p["path"], lines)
	f["moved"] = moved
	if str(f.get("status")) != "active":
		return
	if foe:
		CombatRules._find_hidden(s, f, lines)
	var o: Dictionary = p["option"]
	if o.is_empty():
		if foe and CombatRules.aloft(s) and not MonsterRules.flies(data, f):
			lines.append("%s не достаёт летящего героя" % f["name"])
		elif moved > 0:
			lines.append("%s бежит ближе" % f["name"])
		elif foe:
			FightField.force_way(s, data, f, lines)
		return
	var t: Dictionary = o["t"]
	var hero := str(t.get("id")) == CombatRules.PLAYER
	if foe and int(s.character.get("hp", 0)) > 0 and MonsterRules.cast_turn(s, data, f, lines):
		return
	match str(o["kind"]):
		"save":
			CombatRules._enemy_attack(s, data, f, o["act"], lines)
		"cast":
			pass  # nothing worth casting after all: the action is lost to the walk
		"melee":
			if moved > 0:
				lines.append("%s сближается вплотную" % f["name"] if hero else "%s сближается с %s" % [f["name"], t["name"]])
				if hero:
					CombatRules._reach_strike(s, data, f, lines)
					if str(f.get("status")) != "active":
						return
			_strike(s, data, f, o["act"], t, hero, lines)
		_:
			_strike(s, data, f, o["act"], t, hero, lines)


static func _strike(s: GameSession, data: Dictionary, f: Dictionary, a: Dictionary, t: Dictionary, hero: bool, lines: Array[String]) -> void:
	if hero:
		CombatRules._enemy_attack_full(s, data, f, a, lines)
	else:
		CombatRules._creature_full(s, data, f, a, t, lines)
	if str(a.get("kind")) == "melee" and FightGrid.dist(f, t) <= CombatRules.reach_of(data, f) and MonsterRules.flies(data, f):
		f["swooped"] = true  # came down to strike: in reach until its own next turn


## One who runs: to the nearest way out, away from the hero when there is none. Off the map or out of sight — gone.
static func flee(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var opts := _opts(s, data, f)
	opts.erase("fear")
	var routes := FightGrid.reach(s, data, f, steps(s, data, f) * 2, opts)
	var cells := FightGrid.stops(s, f, routes)
	var ways := FightField.ways_out(s, data)
	var hero := FightGrid.cell(CombatRules.player(s))
	var best := FightGrid.cell(f)
	var score := -INF
	for at: Vector2i in cells:
		var v := float(WalkRules.distance(at, hero))
		for way: Vector2i in ways:
			v = maxf(v, 100.0 - WalkRules.distance(at, way))
		if v > score:
			score = v
			best = at
	walk(s, data, f, FightGrid.route(routes, best), lines)
	if str(f.get("status")) != "active":
		return
	var lost := FightGrid.dist_to(f, hero) >= int(cfg(data)["flee_lost"]) and not FightGrid.clear(FightGrid.grid(s, data), FightGrid.cell(f), hero)
	if lost or FightField.at_way_out(s, data, FightGrid.cell(f)):
		f["status"] = "fled"
		lines.append("%s сбежал" % f["name"])


## Walks up to `t` and no more: a helper's turn. True when it stands beside.
static func go_to(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, lines: Array[String]) -> bool:
	if not FightGrid.touching(f, t):
		var routes := FightGrid.reach(s, data, f, steps(s, data, f), _opts(s, data, f))
		var best := FightGrid.cell(f)
		var least := FightGrid.dist(f, t)
		var ghost := f.duplicate()
		for at: Vector2i in FightGrid.stops(s, f, routes):
			FightGrid.put(ghost, at)
			var d := FightGrid.dist(ghost, t)
			if d < least:
				least = d
				best = at
		walk(s, data, f, FightGrid.route(routes, best), lines)
	return str(f.get("status")) == "active" and FightGrid.touching(f, t)
