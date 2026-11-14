class_name Acts
extends RefCounted
## Every act of a fight, read from core/acts/ by itself: there is no list to add a new one to (v0.8.4.7, ADR-0016). The buttons
## of the player and the choice of the AI both come from here.

const DIR := "res://core/acts/"

static var _all: Dictionary = {}


static func _load() -> Dictionary:
	if _all.is_empty():
		var names: Array = Array(ResourceLoader.list_directory(DIR))
		names.sort()
		for file: String in names:  # an exported game lists its scripts as .gdc too
			var at := file.get_basename()
			if file.get_extension() in ["gd", "gdc"] and at != "act" and not _all.has(at):
				var a: Act = load(DIR + at + ".gd").new()
				a.id = at
				_all[at] = a
	return _all


static func all() -> Array[Act]:
	var out: Array[Act] = []
	out.assign(_load().values())
	return out


static func one(id: String) -> Act:
	return _load()[id]


## The moments at which the hero's reaction goes by itself, with no window: a shield raised for a friend, a fall slowed
## (v0.8.4.26.1).
const HERO_BY_ITSELF: Array[String] = ["attacked", "fall"]


## `f` answers what happened with its reaction, when it has one left: the best of what any act offers. The hero has its window
## instead (`FeatureRules.reactions`), the same features and the same `apply_reaction`, but at `HERO_BY_ITSELF`. True when it did.
static func react(s: GameSession, data: Dictionary, f: Dictionary, when: String, ctx: Dictionary, lines: Array[String]) -> bool:
	if Sheet.is_hero(f) and not HERO_BY_ITSELF.has(when):
		return false
	if bool(f.get("reacted", false)) or str(f.get("status")) != "active" or CombatRules.incapacitated(f):
		return false
	var best := {}
	for a: Act in all():
		for o: Dictionary in a.reacts(s, data, f, when, ctx):
			if FeatureRules.policy(s, f, key_of(o)) == "never":  # its own choice of this reaction (v0.8.4.43.7)
				continue
			if best.is_empty() or float(o["worth"]) > float(best["worth"]):
				best = o
	if best.is_empty():
		return false
	f["reacted"] = true
	lines.append_array(one(str(best["act"])).run(s, data, f, str(best["to"]), best["how"]))
	return true


## The reaction an offer of `reacts` is chosen by (FeatureRules.policy): its spell, the feature it answers with, else the act.
static func key_of(o: Dictionary) -> String:
	var how: Dictionary = o.get("how", {})
	return FeatureRules.reaction_key(str(how.get("spell", how.get("answer", o.get("act", "")))))


## The reasons a walk may take away: out of reach, out of range, no line to the target (v0.8.4.43.51).
const WALK_FIXES: Array[String] = ["COMBAT_OUT_OF_REACH", "COMBAT_OUT_OF_RANGE", "COMBAT_NO_LINE"]


## The way `f` walks first so that act `id` at `to` can be done from where it stops, as in BG3 (v0.8.4.43.51, the author:
## «пунктиром путь куда мой персонаж пойдёт и как, чтобы ударить врага»): only when the act is refused for a reason a walk
## takes away (`WALK_FIXES`) and a stop of this turn's walk lets it — the cheapest such stop. The act's own `can` decides at
## every stop, as the AI's `step_to` does. [] — no walk needed or none helps.
static func approach(s: GameSession, data: Dictionary, f: Dictionary, id: String, to: String, how: Dictionary = {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var act := one(id)
	var why := act.can(s, data, f, to, how)
	if not WALK_FIXES.has(why) or not Move.stuck(s, data, f).is_empty():
		return out
	var routes := Move.routes(s, data, f)
	var t := {} if FightGrid.is_aim(to) else CombatRules.fighter(s, to)
	var nearer := why != "COMBAT_NO_LINE" and not t.is_empty()  # reach and range come only by coming closer
	var stops := FightGrid.stops(s, data, f, routes)
	stops.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return int(routes[a][0]) < int(routes[b][0]))
	var ghost := f.duplicate()
	for at: Vector2i in stops:
		FightGrid.put(ghost, at)
		if nearer and FightGrid.shown_dist(ghost, t) >= FightGrid.shown_dist(f, t):
			continue
		if act.can(s, data, ghost, to, how).is_empty():
			return FightGrid.route(routes, at)
	return out


## Why `f` cannot do act `id` at `to` now, a walk up first counted (`approach`): "" — it can.
static func near_why(s: GameSession, data: Dictionary, f: Dictionary, id: String, to: String, how: Dictionary = {}) -> String:
	var why := one(id).can(s, data, f, to, how)
	return "" if WALK_FIXES.has(why) and not approach(s, data, f, id, to, how).is_empty() else why


## What `f` has a button for on a tab, in the tab's order.
static func on_tab(s: GameSession, data: Dictionary, f: Dictionary, tab: String) -> Array[Act]:
	var out := all().filter(func(a: Act) -> bool: return a.tab() == tab and a.shown(s, data, f))
	out.sort_custom(func(x: Act, y: Act) -> bool: return x.order() < y.order())
	return out


## The acts it would take for nothing but points, best first: `action` true — those that cost the action, else the rest of
## `when`. Only what needs no aim and it can do now.
static func wanted(s: GameSession, data: Dictionary, f: Dictionary, action: bool, when: String = "") -> Array[Act]:
	var out: Array[Act] = []
	for a: Act in all():
		if not a.aim().is_empty() or a.worth(s, data, f) <= 0.0 or not a.can(s, data, f).is_empty():
			continue
		if (a.cost(s, data, f, {}) == "action") == action and (action or a.when() == when):
			out.append(a)
	out.sort_custom(func(x: Act, y: Act) -> bool: return x.worth(s, data, f) > y.worth(s, data, f))
	return out
