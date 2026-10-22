class_name GoalRules
extends RefCounted
## The hero's life goal (roadmap v0.7.22, the author's request — as in The Sims): written by the player, changed or
## cleared at any time (`c.goal`); the hero's thoughts, not a fact of the world — NPCs do not know it, and it has no
## reward of its own. The master assesses it (`goal_assess`: the concepts it is made of, its scale, the direction it
## needs — the class or a peaceful direction, v0.7.19.1); the engine sets the threshold by `rules.goal.thresholds` —
## the level of that direction from which the master may lead to the goal. Until then the world answers the player's
## questions in its own way and makes nothing for the goal; the master never brings it up by itself.
## Batch 2 (v0.7.22.1): past the threshold, when the player asks or seeks in a fitting place, the master hints
## (`goal_hint`, counted on the goal); after `rules.goal.hints` of them for its scale it may make the quest for the
## goal (`create_quest` with `for_goal`) — a simple goal at once, a great one through a chain of hints.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["goal"]


static func goal(c: Dictionary) -> Dictionary:
	return c.get("goal", {}) if c.get("goal") is Dictionary else {}


## Writes the player's goal ("" clears it); a new text waits for the master's assessment again.
static func write(c: Dictionary, text: String) -> void:
	var t := text.strip_edges().left(int(80 * 3))
	if t.is_empty():
		c.erase("goal")
		return
	if str(goal(c).get("text", "")) != t:
		c["goal"] = {"text": t}


## Checks a `goal_assess`: {plan, summary} or {reason}.
static func plan_assess(c: Dictionary, data: Dictionary, e: Dictionary) -> Dictionary:
	if goal(c).is_empty():
		return {"reason": "у героя нет жизненной цели"}
	var scale := str(e.get("scale", ""))
	if not (cfg(data)["thresholds"] as Dictionary).has(scale):
		return {"reason": "масштаб цели — из %s" % ", ".join((cfg(data)["thresholds"] as Dictionary).keys())}
	var dir := str(e.get("direction", "class")) if e.get("direction") != null else "class"
	if dir != "class" and not (DevelopmentRules.cfg(data)["directions"] as Dictionary).has(dir):
		return {"reason": "направление — class или мирное: %s" % ", ".join((DevelopmentRules.cfg(data)["directions"] as Dictionary).keys())}
	var concepts: Array = (e.get("concepts", []) as Array).slice(0, 6).map(func(x: Variant) -> String: return str(x).left(40)) \
		if e.get("concepts") is Array else []
	var plan := {"goal_scale": scale, "direction": dir, "concepts": concepts}
	return {"plan": plan, "summary": "Цель оценена: %s" % text_of({"goal": goal(c).merged(plan, true)}, data)}


static func apply_assess(c: Dictionary, plan: Dictionary) -> void:
	var g := goal(c).duplicate()
	g["scale"] = plan["goal_scale"]
	g["direction"] = plan["direction"]
	g["concepts"] = plan["concepts"]
	c["goal"] = g


## The level the goal needs; -1 — not assessed yet.
static func threshold(c: Dictionary, data: Dictionary) -> int:
	var g := goal(c)
	return int(cfg(data)["thresholds"].get(str(g.get("scale", "")), -1)) if g.has("scale") else -1


## The hero's level in the goal's direction now.
static func level(c: Dictionary, data: Dictionary) -> int:
	var dir := str(goal(c).get("direction", "class"))
	return int(c.get("level", 1)) if dir == "class" else DevelopmentRules.level(c, data, dir)


static func reached(c: Dictionary, data: Dictionary) -> bool:
	var need := threshold(c, data)
	return need >= 0 and level(c, data) >= need


## Hints the goal needs before its quest; given so far.
static func hints_needed(c: Dictionary, data: Dictionary) -> int:
	return int(cfg(data)["hints"].get(str(goal(c).get("scale", "")), 0))


static func hints(c: Dictionary) -> int:
	return int(goal(c).get("hints", 0))


## "" when the master may hint now, else the reason.
static func hint_why_not(c: Dictionary, data: Dictionary) -> String:
	if goal(c).is_empty() or not goal(c).has("scale"):
		return "у героя нет оценённой жизненной цели"
	if not reached(c, data):
		return "цель героя ещё не по силам (%s) — до порога мир к ней не ведёт" % text_of(c, data)
	return ""


## "" when the quest for the goal may be made now, else the reason.
static func quest_why_not(c: Dictionary, data: Dictionary) -> String:
	var why := hint_why_not(c, data)
	if not why.is_empty():
		return why
	if hints(c) < hints_needed(c, data):
		return "к заданию цели ещё рано: намёков %d из %d — сначала goal_hint, когда игрок снова спросит" % [hints(c), hints_needed(c, data)]
	return ""


static func plan_hint(c: Dictionary, data: Dictionary) -> Dictionary:
	var why := hint_why_not(c, data)
	if not why.is_empty():
		return {"reason": why}
	return {"plan": {"goal_hint": true}, "summary": "Намёк о цели: %d из %d перед заданием" % [hints(c) + 1, hints_needed(c, data)]}


static func apply_hint(c: Dictionary) -> void:
	var g := goal(c).duplicate()
	g["hints"] = int(g.get("hints", 0)) + 1
	c["goal"] = g


## For the sheet and the master: «Открыть свою таверну — по силам: Торговля 2 из 2» / «… — рано: уровень класса 1 из 3».
static func text_of(c: Dictionary, data: Dictionary) -> String:
	var g := goal(c)
	if g.is_empty():
		return ""
	if not g.has("scale"):
		return "«%s» — ещё не оценена" % g["text"]
	var need := threshold(c, data)
	var dir := str(g.get("direction", "class"))
	var what := "уровень класса" if dir == "class" else str(DevelopmentRules.direction(data, dir).get("name", dir))
	if need > int(cfg(data)["max_level"]):
		return "«%s» — %s: пока недостижима (%s выше %d)" % [g["text"], cfg(data)["names"].get(g["scale"], g["scale"]), what, int(cfg(data)["max_level"])]
	var out := "«%s» — %s, %s: %s %d из %d" % [g["text"], cfg(data)["names"].get(g["scale"], g["scale"]),
		"по силам" if reached(c, data) else "рано", what, level(c, data), need]
	if reached(c, data):
		out += "; намёков %d из %d перед заданием" % [mini(hints(c), hints_needed(c, data)), hints_needed(c, data)]
	return out
