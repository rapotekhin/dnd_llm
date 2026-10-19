class_name QuestRules
extends RefCounted
## Quests with steps (roadmap v0.6.3, decision of the author). A pack quest with `giver` and `steps` is taken at the
## giver's button; a step is closed only by a fact of the engine named in its `when`:
##   {"encounter": id} — the encounter is fought, {"secret": "room:secret"} — found, {"room": id} — visited,
##   {"flag": id} — set in the world, {"talk": npc_id, "item"?: id} — a button at that NPC (`action`), the item is
##   handed over.
## The master only narrates and cannot close a step. A step rewards (`reward_cp`, `xp`, `items` {id: qty},
## `attitude` {npc_id: delta}). State: s.quests_active {quest_id: step index}, s.quests_done.
## One-button quests without steps (v0.5.4) stay in XpRules.


static func stepped(world: Dictionary) -> Dictionary:
	var out := {}
	var all: Dictionary = world.get("quests", {})
	for id: String in all:
		if all[id].has("steps"):
			out[id] = all[id]
	return out


static func quest(world: Dictionary, quest_id: String) -> Dictionary:
	return stepped(world).get(quest_id, {})


## Quests the giver in this room offers now.
static func offers_here(s: GameSession, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var here := s.npcs_alive(WorldView.new(world).npcs_in(s.room_id))
	var all := stepped(world)
	for id: String in all:
		if here.has(str(all[id].get("giver", ""))) and not s.quests_active.has(id) and not s.quests_done.has(id):
			out.append(id)
	return out


## "" when the quest can be taken here now, otherwise a localization key.
static func can_accept(s: GameSession, world: Dictionary, quest_id: String) -> String:
	if quest(world, quest_id).is_empty():
		return "QUEST_UNKNOWN"
	if s.quests_active.has(quest_id) or s.quests_done.has(quest_id):
		return "QUEST_DONE"
	if not offers_here(s, world).has(quest_id):
		return "QUEST_WRONG_PLACE"
	return ""


## Takes the quest (can_accept first); steps already done by the facts close at once. Lines.
static func accept(s: GameSession, data: Dictionary, quest_id: String) -> Array[String]:
	var q := quest(data["world"], quest_id)
	s.quests_active[quest_id] = 0
	var lines: Array[String] = ["Новое задание: %s" % q["title"], "Цель: %s" % q["steps"][0]["text"]]
	lines.append_array(advance(s, data))
	return lines


static func current(s: GameSession, world: Dictionary, quest_id: String) -> Dictionary:
	var q := quest(world, quest_id)
	var i := int(s.quests_active.get(quest_id, -1))
	return q["steps"][i] if not q.is_empty() and i >= 0 and i < (q["steps"] as Array).size() else {}


## A fact of the engine (a talk step is closed only by its button).
static func met(s: GameSession, when: Dictionary) -> bool:
	if when.has("encounter"):
		return s.encounters_done.has(str(when["encounter"]))
	if when.has("secret"):
		var key := str(when["secret"])
		return (s.revealed.get(key.get_slice(":", 0), []) as Array).has(key.get_slice(":", 1))
	if when.has("room"):
		return s.visited.has(str(when["room"]))
	if when.has("flag"):
		return s.flags.has(str(when["flag"]))
	return false


## Closes every step whose fact is true now (several in a row too). Call after anything that changes the facts:
## a room entered, a secret found, a fight finished, effects applied. Lines.
static func advance(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for id: String in s.quests_active.keys():
		var guard := 0
		while s.quests_active.has(id) and guard < 20:
			guard += 1
			var step := current(s, data["world"], id)
			if step.is_empty() or (step["when"] as Dictionary).has("talk") or not met(s, step["when"]):
				break
			lines.append_array(_complete_step(s, data, id))
	return lines


## Talk steps that can be closed in this room: [{quest_id, action, npc_id}].
static func talks_here(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := s.npcs_alive(WorldView.new(world).npcs_in(s.room_id))
	for id: String in s.quests_active:
		var step := current(s, world, id)
		var when: Dictionary = step.get("when", {})
		if when.has("talk") and here.has(str(when["talk"])):
			out.append({"quest_id": id, "action": str(step.get("action", step["text"])), "npc_id": str(when["talk"]),
				"item": str(when.get("item", ""))})
	return out


## "" when the talk step can be closed now: the NPC is here, the item (if any) is carried.
static func can_talk(s: GameSession, world: Dictionary, quest_id: String) -> String:
	for t: Dictionary in talks_here(s, world):
		if t["quest_id"] == quest_id:
			if not str(t["item"]).is_empty() and int(s.character.get("inventory", {}).get(t["item"], 0)) <= 0:
				return "QUEST_NEEDS_ITEM"
			return "QUEST_IN_CONVERSATION" if s.in_conversation() and s.npc_id != t["npc_id"] else ""
	return "QUEST_WRONG_PLACE"


## Closes the talk step (can_talk first): the item goes to the NPC. Lines.
static func talk(s: GameSession, data: Dictionary, quest_id: String) -> Array[String]:
	var when: Dictionary = current(s, data["world"], quest_id)["when"]
	var lines: Array[String] = []
	var item := str(when.get("item", ""))
	if not item.is_empty():
		var inv: Dictionary = s.character["inventory"]
		inv[item] = int(inv.get(item, 0)) - 1
		if int(inv[item]) <= 0:
			inv.erase(item)
		lines.append("Отдано: %s" % ItemRules.display_name(data["items"], s.items, item))
	lines.append_array(_complete_step(s, data, quest_id))
	lines.append_array(advance(s, data))
	return lines


static func _complete_step(s: GameSession, data: Dictionary, quest_id: String) -> Array[String]:
	var q := quest(data["world"], quest_id)
	var i := int(s.quests_active[quest_id])
	var step: Dictionary = q["steps"][i]
	var lines: Array[String] = ["«%s»: %s — сделано" % [q["title"], step["text"]]]
	_reward(s, data, step, lines)
	if i + 1 >= (q["steps"] as Array).size():
		s.quests_active.erase(quest_id)
		s.quests_done.append(quest_id)
		lines.append("Задание выполнено: %s" % q["title"])
	else:
		s.quests_active[quest_id] = i + 1
		lines.append("Цель: %s" % q["steps"][i + 1]["text"])
	return lines


static func _reward(s: GameSession, data: Dictionary, r: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var cp := int(r.get("reward_cp", 0))
	if cp > 0:
		c["gold_cp"] = int(c.get("gold_cp", 0)) + cp
		lines.append("+" + Money.format(cp))
	var items: Dictionary = r.get("items", {})
	for id: String in items:
		c["inventory"][id] = int(c["inventory"].get(id, 0)) + int(items[id])
		lines.append("Получено: %s%s" % [ItemRules.display_name(data["items"], s.items, id), " ×%d" % int(items[id]) if int(items[id]) > 1 else ""])
	var att: Dictionary = r.get("attitude", {})
	var world := WorldView.new(data["world"])
	for npc: String in att:
		s.attitudes[npc] = clampi(s.attitude(npc) + int(att[npc]), -3, 3)
		lines.append("%s: отношение %s" % [world.npc(npc).get("name", npc), "лучше" if int(att[npc]) > 0 else "хуже"])
	lines.append_array(XpRules.award(c, data, int(r.get("xp", 0)), "задание"))


## Taken quests for the snapshot and the journal: [{id, title, description, done, step}].
static func info(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := stepped(world)
	for id: String in all:
		if not s.quests_active.has(id) and not s.quests_done.has(id):
			continue
		var step := current(s, world, id)
		out.append({"id": id, "title": str(all[id]["title"]), "description": str(all[id].get("description", "")),
			"done": s.quests_done.has(id), "step": str(step.get("text", ""))})
	return out
