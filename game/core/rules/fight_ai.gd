class_name FightAI
extends RefCounted
## The turn of a creature in a fight (v0.8.4): a search over the squares it can walk to and the acts it has from each, by a
## value. What it weighs comes from its role in `rules.combat.ai.roles`; the role from its SRD record: a caster, a shooter,
## a pack hunter, a beast, one who strikes and runs, a brute. `budget` in rules.json limits the lines traced in a turn.
## Nothing here changes the world but walking: what it does is an `Act`, the same the player has.

const FAR := 1 << 20


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["combat"]["ai"]


static func role_name(data: Dictionary, f: Dictionary) -> String:
	var c := cfg(data)
	var m := Sheet.template(data, f)
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


## Who it fights: the foes of its side still in the fight. The hero lying at 0 HP is nobody's target (v0.7.9).
static func _targets(s: GameSession, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if str(f.get("side")) == "enemy":
		if int(s.character.get("hp", 0)) > 0 and not ArenaRules.watching(s):
			out.append(CombatRules.player(s))
		for id: String in CombatRules.allies(s):
			if not bool(CombatRules.fighter(s, id).get("hidden", false)):
				out.append(CombatRules.fighter(s, id))
		return out
	for id: String in CombatRules.enemies(s):
		var e := CombatRules.fighter(s, id)
		if not bool(e.get("hidden", false)) and not CombatRules._has(e, "invisible"):
			out.append(e)
	return out


static func avg(a: Dictionary) -> float:
	var total := 0.0
	for d: Dictionary in a.get("damage", []):
		var r := CombatRules.dice_range(str(d["dice"]))
		total += (r[0] + r[1]) / 2.0
	return total


## How many blows of this kind its Multiattack gives.
static func blows(data: Dictionary, f: Dictionary, a: Dictionary) -> int:
	var m := Sheet.template(data, f)
	var n := 0
	for x: Dictionary in m.get("multiattack", []):
		for b: Dictionary in m["actions"]:
			if str(b["name_en"]) == str(x["action"]) and str(b.get("kind")) == str(a.get("kind")):
				n += int(x["count"])
	return maxi(1, n)


## What it can do at each target: what every act offers (`Act.offers`).
static func _options(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Act in Acts.all():
		out.append_array(a.offers(s, data, f, targets))
	return out


## The turn it would take: {path, option} or {} when there is nobody to fight. An empty `option` — nothing to do from any square
## of its walk this turn.
static func plan(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var targets := _targets(s, f)
	if targets.is_empty():
		return {}
	var w := role(data, f)
	var routes := Move.routes(s, data, f)
	if routes.is_empty():
		routes = {FightGrid.cell(f): [0, FightGrid.cell(f)]}
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
			if bool(o.get("self", false)):  # on itself: no aim to reach, from any square
				if place + float(o["power"]) > top:
					top = place + float(o["power"])
					best = o
					at_best = cell
				continue
			var t: Dictionary = o["t"]
			var d := FightGrid.dist(ghost, t)
			if d > int(o["far"]):
				continue
			var cover := 0
			if bool(o.get("touch", false)):
				if not CombatRules.blade_reaches(s, data, ghost, t, int(o["far"])):
					continue
			else:
				if budget <= 0:
					continue
				budget -= 1
				cover = FightGrid.cover(s, data, ghost, t)
				if cover >= FightGrid.FULL_COVER or (bool(o.get("sight", false)) and not FightGrid.veiled(s, data, ghost, t).is_empty()):
					continue
			var v := place + _worth(s, data, f, o, t, d, cover, w)
			if v > top:
				top = v
				best = o
				at_best = cell
	return {"path": FightGrid.route(routes, at_best), "option": best}


## What an act is worth from there: the chance times the damage, more on the wounded, the kill counted.
static func _worth(s: GameSession, data: Dictionary, f: Dictionary, o: Dictionary, t: Dictionary, d: int, cover: int, w: Dictionary) -> float:
	if bool(o.get("kindly", false)):
		return float(o["power"])
	var hero := str(t.get("id")) == CombatRules.PLAYER
	var hp := float(s.character.get("hp", 1)) if hero else float(t.get("hp", 1))
	var most := maxf(1.0, float(s.character.get("max_hp", 1)) if hero else float(t.get("max_hp", 1)))
	var ac := Sheet.ac(s, t)
	var power := float(o["power"])
	var v := power
	if str(o["kind"]) in ["melee", "ranged"]:
		var chance := clampf((21.0 + int(o["blow"].get("to_hit", 0)) - ac - cover) / 20.0, 0.05, 0.95)
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
	for id: String in CombatRules.friends_of(s, f):
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
	if not bool(p.get("reacted", false)) and not bool(f.get("disengaged", false)) and FightGrid.touching(f, p) and not FightGrid.touching(ghost, p) \
			and not Sheet.has_trait(s, data, f, "flyby"):
		v -= float(w["leave"])
	return v


## The way nearest to someone to fight within `budget` squares.
static func _closer(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary], budget: int) -> Array[Vector2i]:
	var routes := Move.routes(s, data, f, budget)
	if budget <= 0 or routes.is_empty():
		return []
	var field := _way_to(s, data, f, targets)
	var best := FightGrid.cell(f)
	var score := int(field.get(best, FAR)) * 4
	for at: Vector2i in FightGrid.stops(s, f, routes):
		var v := int(field.get(at, FAR)) * 4 + int(routes[at][0])
		if v < score:
			score = v
			best = at
	return FightGrid.route(routes, best)


## The walking distances to the nearest of the targets.
static func _way_to(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Dictionary:
	var passes := int(Move.opts(s, data, f)["passes"])
	var field := {}
	var least := 1 << 30
	for t: Dictionary in targets:
		var flow := FightGrid.flow(s, data, FightGrid.cell(t), passes)
		var here := int(flow.get(FightGrid.cell(f), FAR))
		if here < least:
			least = here
			field = flow
	return field


## Nobody to fight within its walk and reach, and more squares would bring it closer: what a Dash is for.
static func far_off(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	var targets := _targets(s, f)
	if targets.is_empty():
		return false
	var left := int(CombatRules.points(s, data, f).get("move", 0))
	var near := int(_way_to(s, data, f, targets).get(FightGrid.cell(f), FAR))
	if near >= FAR or near <= left + CombatRules.reach_of(data, f):
		return false
	return not _closer(s, data, f, targets, left + Move.steps(s, data, f)).is_empty()


# --- the turn played ------------------------------------------------------------------------------------------


static func _walk(s: GameSession, data: Dictionary, f: Dictionary, path: Array[Vector2i], lines: Array[String]) -> int:
	return 0 if path.is_empty() else Move.go(s, data, f, path[-1], lines)


## What it does for nothing but points before it walks and strikes.
static func first(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	_free(s, data, f, "first", lines)


## What it does for nothing but points when all is done.
static func last(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	_free(s, data, f, "last", lines)


static func _free(s: GameSession, data: Dictionary, f: Dictionary, when: String, lines: Array[String]) -> void:
	for a: Act in Acts.wanted(s, data, f, false, when):
		if a.can(s, data, f).is_empty():
			lines.append_array(a.go(s, data, f))
	for a: Act in Acts.all():
		for o: Dictionary in a.spare(s, data, f, when):
			if a.can(s, data, f, str(o["to"]), o["how"]).is_empty():
				lines.append_array(a.go(s, data, f, str(o["to"]), o["how"]))


## The whole turn, and Haste's action after it (v0.7.50.1).
static func turn(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	act(s, data, f, lines)
	if int(CombatRules.points(s, data, f).get("haste", 0)) > 0 and str(f.get("status")) == "active":
		act(s, data, f, lines)


## The whole turn of a foe or of an ally of the hero.
static func act(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var foe := str(f.get("side")) == "enemy"
	first(s, data, f, lines)
	var p := plan(s, data, f)
	if p.is_empty():
		if foe:
			lines.append(("%s не добивает упавшего" if CombatRules._intelligent(data, f) else "%s теряет интерес к упавшему") % f["name"])
		else:
			lines.append("%s не видит врага" % f["name"])
		return
	var o: Dictionary = p["option"]
	var path: Array[Vector2i] = p["path"]
	if o.is_empty():  # nothing within its walk: what its action is best for, and closer
		var acts := Acts.wanted(s, data, f, true)
		if not acts.is_empty():
			lines.append_array(acts[0].go(s, data, f))
		path = _closer(s, data, f, _targets(s, f), int(CombatRules.points(s, data, f)["move"]))
	var moved := _walk(s, data, f, path, lines)
	if str(f.get("status")) != "active":
		return
	if foe:
		CombatRules._find_hidden(s, f, lines)
	if o.is_empty():
		if foe and CombatRules.airborne(s, data, CombatRules.player(s)) and not Move.air(s, data, f):
			lines.append("%s не достаёт летящего героя" % f["name"])
		elif moved > 0:
			lines.append("%s бежит ближе" % f["name"])
		elif foe:
			FightField.force_way(s, data, f, lines)
		return
	var t: Dictionary = o["t"]
	var hero := str(t.get("id")) == CombatRules.PLAYER
	if str(o["kind"]) == "cast" and not Acts.one(str(o["act"])).can(s, data, f, str(o["to"]), o["how"]).is_empty():  # the spell does not go after all: its weapon, if it gets there
		var blow := {} if not CombatRules.foes_of(s, f).has(str(t["id"])) else MonsterRules.pick(s, data, f, t, "melee" if CombatRules.blade_reaches(s, data, f, t, CombatRules.reach_of(data, f)) else "ranged")
		o = {} if blow.is_empty() else {"act": "attack", "to": str(t["id"]), "how": {"action": str(blow["name_en"])}, "kind": "melee"}
	elif str(o["kind"]) == "melee" and moved > 0:
		lines.append("%s сближается вплотную" % f["name"] if hero else "%s сближается с %s" % [f["name"], t["name"]])
		if hero:
			CombatRules._reach_strike(s, data, f, lines)
			if str(f.get("status")) != "active":
				return
	if o.is_empty() or not Acts.one(str(o["act"])).can(s, data, f, str(o["to"]), o["how"]).is_empty():
		lines.append("%s выжидает" % f["name"])
		return
	var act_now := Acts.one(str(o["act"]))
	var by_bonus := act_now.cost(s, data, f, o["how"]) == "bonus"
	var had := int(CombatRules.points(s, data, f).get("action", 0))
	lines.append_array(act_now.go(s, data, f, str(o["to"]), o["how"]))
	var left := int(CombatRules.points(s, data, f).get("action", 0))
	if (by_bonus or left < had) and left > 0 and str(f.get("status")) == "active" and not CombatRules.stopped(s, f):
		act(s, data, f, lines)  # its action is still there, or Action Surge gave one more


## One who runs: to the nearest way out, away from the hero when there is none. Off the map or out of sight — gone.
static func flee(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	first(s, data, f, lines)
	if Acts.one("dash").can(s, data, f).is_empty():
		lines.append_array(Acts.one("dash").go(s, data, f))
	var routes := Move.routes(s, data, f)
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
	_walk(s, data, f, FightGrid.route(routes, best), lines)
	if str(f.get("status")) != "active":
		return
	var lost := FightGrid.dist_to(f, hero) >= int(cfg(data)["flee_lost"]) and not FightGrid.clear(FightGrid.grid(s, data), FightGrid.cell(f), hero)
	if lost or FightField.at_way_out(s, data, FightGrid.cell(f)):
		lines.append_array(Acts.one("flee").go(s, data, f, "", {"lost": true}))


## Walks up to `t` and no more: a helper's turn. True when it stands beside.
static func go_to(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, lines: Array[String]) -> bool:
	first(s, data, f, lines)
	if not FightGrid.touching(f, t):
		var routes := Move.routes(s, data, f)
		var best := FightGrid.cell(f)
		var least := FightGrid.dist(f, t)
		var ghost := f.duplicate()
		for at: Vector2i in FightGrid.stops(s, f, routes):
			FightGrid.put(ghost, at)
			var d := FightGrid.dist(ghost, t)
			if d < least:
				least = d
				best = at
		_walk(s, data, f, FightGrid.route(routes, best), lines)
	return str(f.get("status")) == "active" and FightGrid.touching(f, t)
