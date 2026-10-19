class_name XpRules
extends RefCounted
## Experience (roadmap v0.5.4, decision of the author): only for combat (monster CR, rules.xp.by_cr) and for
## quests of the world pack (`quests` in world.json). There is no effect for the master to grant experience —
## no farming through the model. Combat itself comes in M3; combat_xp is the hook it will call.
##
## A pack quest: {title, description, room, action, xp, reward_cp, done_text}. In this version a quest is known
## from the start and completed by one button in its room (a test of the loop before quests grow in M2).


## Experience for a won fight: the sum by CR of the defeated monsters ("1/4", "2", …).
static func combat_xp(data: Dictionary, crs: Array) -> int:
	var table: Dictionary = data["rules"]["xp"]["by_cr"]
	var total := 0
	for cr: Variant in crs:
		total += int(table.get(str(cr), 0))
	return total


## Adds experience; returns the chat lines (with «можно повысить уровень» when it is time).
static func award(c: Dictionary, data: Dictionary, amount: int, source: String) -> Array[String]:
	var lines: Array[String] = []
	if amount <= 0:
		return lines
	c["xp"] = int(c.get("xp", 0)) + amount
	lines.append("+%d опыта (%s)" % [amount, source])
	if LevelUp.can_level_up(c, data):
		lines.append("можно повысить уровень")
	return lines


static func quests(world: Dictionary) -> Dictionary:
	return world.get("quests", {})


## Quest ids that can be completed in this room now.
static func quests_here(s: GameSession, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var all := quests(world)
	for id: String in all:
		if not all[id].has("steps") and str(all[id].get("room", "")) == s.room_id and not s.quests_done.has(id):
			out.append(id)
	return out


## "" when the quest can be completed now, otherwise a localization key.
static func can_complete(s: GameSession, world: Dictionary, quest_id: String) -> String:
	var q: Dictionary = quests(world).get(quest_id, {})
	if q.is_empty():
		return "QUEST_UNKNOWN"
	if s.quests_done.has(quest_id):
		return "QUEST_DONE"
	if str(q.get("room", "")) != s.room_id:
		return "QUEST_WRONG_PLACE"
	if s.in_conversation():
		return "QUEST_IN_CONVERSATION"
	return ""


## Completes a quest (can_complete first): reward coins and experience. Returns the chat lines.
static func complete(s: GameSession, data: Dictionary, quest_id: String) -> Array[String]:
	var q: Dictionary = quests(data["world"])[quest_id]
	s.quests_done.append(quest_id)
	var lines: Array[String] = ["Задание выполнено: %s" % q["title"]]
	var cp := int(q.get("reward_cp", 0))
	if cp > 0:
		s.character["gold_cp"] = int(s.character.get("gold_cp", 0)) + cp
		lines.append("+" + Money.format(cp))
	lines.append_array(award(s.character, data, int(q.get("xp", 0)), "задание"))
	return lines


## Quests for the snapshot and the journal: [{id, title, description, done, step}] — one-button quests (always
## known) and taken quests with steps (QuestRules, the current step).
static func quest_list(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := quests(world)
	for id: String in all:
		if all[id].has("steps"):
			continue
		out.append({"id": id, "title": str(all[id]["title"]), "description": str(all[id].get("description", "")),
			"done": s.quests_done.has(id), "step": ""})
	out.append_array(QuestRules.info(s, world))
	return out
