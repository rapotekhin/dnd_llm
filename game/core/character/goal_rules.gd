class_name GoalRules
extends RefCounted
## The hero's life goal (roadmap v0.7.22, the author's request — as in The Sims): written by the player, changed or
## cleared at any time (`c.goal`); the hero's thoughts, not a fact of the world — NPCs do not know it, and it has no
## reward of its own. The master assesses it (`goal:assess`: the concepts it is made of, its scale, the direction it
## needs — the class or a peaceful direction, v0.7.19.1); the engine sets the threshold by `rules.goal.thresholds` —
## the level of that direction from which the master may lead to the goal. Until then the world answers the player's
## questions in its own way and makes nothing for the goal; the master never brings it up by itself.
## Batch 2 (v0.7.22.1): past the threshold, when the player asks or seeks in a fitting place, the master hints
## (`goal:hint`, counted on the goal); after `rules.goal.hints` of them for its scale it may make the quest for the
## goal (`create:quest` with `for_goal`) — a simple goal at once, a great one through a chain of hints.
## v0.8.4.36, the author's feedback (the master went on hinting «3 of 2» and never made the quest): each hint keeps its
## clue — what was learned and from whom (`clues`, shown on the sheet's Development tab and to the master, so the next
## rumour does not contradict the last); past the count of hints the engine refuses more and says the quest is due; the
## second line readies the quest for the goal from the one who gave the last clue (PrepareRules, `goal`).


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


## Checks a `goal:assess`: {plan, summary} or {reason}.
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
	var also := ""
	if e.get("item") is Dictionary:  # v0.8.4.42.16: the thing the goal is, by the engine's price, not the level's gate
		var chk := ItemRules.check_generated(data, e["item"], NO_GATE)
		if not bool(chk["ok"]):
			return {"reason": "вещь цели: %s" % chk["reason"]}
		var def: Dictionary = chk["def"]
		var floor := str(cfg(data)["item_scale"].get(str(def["rarity"]), "easy"))
		if _need(data, floor) > _need(data, scale):
			plan["goal_scale"] = floor
		plan["item_id"] = ItemRules.generated_id(def)
		plan["item_def"] = def
		also = " · вещь цели «%s» (%s): масштаб цели не меньше «%s»" % [def["name"], TranslationServer.translate("RARITY_" + str(def["rarity"]).to_upper()).to_lower(),
			cfg(data)["names"].get(floor, floor)]
	return {"plan": plan, "summary": "Цель оценена: %s%s" % [text_of({"goal": goal(c).merged(plan, true)}, data), also]}


const NO_GATE := 99  ## a level past every rarity's: the goal's thing is priced, its level is the goal's threshold


static func _need(data: Dictionary, scale: String) -> int:
	return int(cfg(data)["thresholds"].get(scale, 0))


## Writes the assessment; the goal's thing goes into the game's items and the goal keeps its id (v0.8.4.42.16).
static func apply_assess(s: GameSession, plan: Dictionary) -> void:
	var c := s.character
	var g := goal(c).duplicate()
	g["scale"] = plan["goal_scale"]
	g["direction"] = plan["direction"]
	g["concepts"] = plan["concepts"]
	g.erase("item")
	g.erase("item_name")
	if plan.has("item_id"):
		s.items[str(plan["item_id"])] = plan["item_def"]
		g["item"] = str(plan["item_id"])
		g["item_name"] = str(plan["item_def"].get("name", ""))
	c["goal"] = g


## The thing the goal is ("" — the goal is no thing, or was assessed before v0.8.4.42.16).
static func item_of(c: Dictionary) -> String:
	return str(goal(c).get("item", ""))


## The goal's thing for the master's frames: «Вещь цели: [id] name — what it does» ("" — none).
static func item_line(s: GameSession, data: Dictionary) -> String:
	var id := item_of(s.character)
	if id.is_empty():
		return ""
	return "Вещь цели: [%s] %s — %s" % [id, ItemRules.display_name(data["items"], s.items, id),
		", ".join(ItemRules.power_of(ItemRules.def_of(data["items"], s.items, id)))]


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


static func plan_hint(s: GameSession, data: Dictionary, e: Dictionary = {}) -> Dictionary:
	var c := s.character
	var why := hint_why_not(c, data)
	if not why.is_empty():
		return {"reason": why}
	var q := quest_of(c)
	if not q.is_empty():
		return {"reason": "задание цели уже есть: «%s» — веди к нему словами, без новых намёков" % QuestRules.quest(data["world"], q).get("title", q)}
	if hints(c) >= hints_needed(c, data):
		return {"reason": "намёков довольно (%d из %d): пора задание цели — create:quest с for_goal: true, заказчик — тот, кто знает%s" % [
			hints(c), hints_needed(c, data), (" (последняя зацепка — от %s [%s])" % [WorldView.new(data["world"]).npc_name(by(c)), by(c)]) if not by(c).is_empty() else ""]}
	var npc := str(e.get("npc", "")) if e.get("npc") != null else ""
	if not npc.is_empty() and WorldView.new(data["world"]).npc(npc).is_empty():
		return {"reason": "goal:hint.npc — id человека мира, от которого зацепка (find_npcs), или пусто"}
	var clue := (str(e.get("clue", "")) if e.get("clue") != null else "").strip_edges().left(int(cfg(data).get("clue_chars", 200)))
	return {"plan": {"goal_hint": true, "clue": clue, "npc": npc}, "summary": "Намёк о цели: %d из %d перед заданием%s" % [hints(c) + 1, hints_needed(c, data),
		(" · зацепка: " + clue) if not clue.is_empty() else ""]}


static func apply_hint(c: Dictionary, plan: Dictionary = {}, day: int = 0) -> void:
	var g := goal(c).duplicate(true)
	g["hints"] = int(g.get("hints", 0)) + 1
	var clue := str(plan.get("clue", ""))
	if not clue.is_empty():
		var list: Array = g.get("clues", [])
		list.append({"day": day, "npc": str(plan.get("npc", "")), "text": clue})
		g["clues"] = list.slice(maxi(0, list.size() - CLUES_MAX))
	if not str(plan.get("npc", "")).is_empty():
		g["by"] = str(plan["npc"])
	c["goal"] = g


const CLUES_MAX := 8


## The clues the hints gave: [{day, npc, text}], oldest first.
static func clues(c: Dictionary) -> Array:
	return goal(c).get("clues", [])


## Who gave the last clue ("" — nobody named).
static func by(c: Dictionary) -> String:
	return str(goal(c).get("by", ""))


## The quest made for the goal ("" — none yet).
static func quest_of(c: Dictionary) -> String:
	return str(goal(c).get("quest", ""))


static func got_quest(c: Dictionary, id: String) -> void:
	if not goal(c).is_empty():
		c["goal"]["quest"] = id


## The quest for the goal is due and nobody made it: the hints are enough. The one to give it — the last clue's giver,
## alive; "" — the engine readies none (the master makes it when the player asks).
static func quest_due(s: GameSession, data: Dictionary) -> String:
	var c := s.character
	if not quest_of(c).is_empty() or not quest_why_not(c, data).is_empty():
		return ""
	var npc := by(c)
	return npc if not npc.is_empty() and not Being.dead(s, npc) and not WorldView.new(data["world"]).npc(npc).is_empty() else ""


## The clues as one line for the master and the sheet: «Гуннар: …; Ратмир: …».
static func clues_text(c: Dictionary, data: Dictionary) -> String:
	var v := WorldView.new(data["world"])
	return "; ".join(clues(c).map(func(k: Dictionary) -> String:
		return ("%s: %s" % [v.npc_name(str(k["npc"])), k["text"]]) if not str(k.get("npc", "")).is_empty() else str(k["text"])))


## For the sheet and the master: «Открыть свою таверну — по силам: Торговля 2 из 2» / «… — рано: уровень класса 1 из 3».
static func text_of(c: Dictionary, data: Dictionary, more := true) -> String:
	var g := goal(c)
	if g.is_empty():
		return ""
	if not g.has("scale"):
		return "«%s» — ещё не оценена" % g["text"]
	var need := threshold(c, data)
	var dir := str(g.get("direction", "class"))
	var what := "уровень класса" if dir == "class" else str(DevelopmentRules.direction(data, dir).get("name", dir))
	var thing := ("; вещь цели: «%s» [%s]" % [g.get("item_name", ""), g["item"]]) if g.has("item") else ""
	if need > int(cfg(data)["max_level"]):
		return "«%s» — %s: пока недостижима (%s выше %d)%s" % [g["text"], cfg(data)["names"].get(g["scale"], g["scale"]), what, int(cfg(data)["max_level"]), thing]
	var out := "«%s» — %s, %s: %s %d из %d%s" % [g["text"], cfg(data)["names"].get(g["scale"], g["scale"]),
		"по силам" if reached(c, data) else "рано", what, level(c, data), need, thing]
	if reached(c, data):
		out += "; намёков %d из %d перед заданием" % [mini(hints(c), hints_needed(c, data)), hints_needed(c, data)]
	if not more:  # the sheet lists the clues and the quest itself
		return out
	if not clues(c).is_empty():
		out += "; зацепки: " + clues_text(c, data)
	if not quest_of(c).is_empty():
		out += "; задание цели: «%s»" % QuestRules.quest(data["world"], quest_of(c)).get("title", quest_of(c))
	return out
