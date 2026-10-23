class_name QuestRules
extends RefCounted
## Quests with steps (roadmap v0.6.3, decision of the author). A pack quest with `giver` and `steps` is taken at the
## giver's button; a step is closed only by a fact of the engine named in its `when`:
##   {"encounter": id} — the encounter is fought, {"secret": "room:secret"} — found, {"room": id} — visited,
##   {"flag": id} — set in the world, {"talk": npc_id, "item"?: id} — a button at that NPC (`action`), the item is
##   handed over; {"all": [...]} / {"any": [...]} of facts (v0.6.4) — `parts` names the facts of "all", each part
##   is announced when done, in any order; {"choice": room_id} — buttons in that room, one per `choices` entry
##   (`id`, `action`, `done_text`, its own rewards and `flag`).
## The master only narrates and cannot close a step. A step rewards (`reward_cp`, `xp`, `items` {id: qty},
## `attitude` {npc_id: delta}) and may set a world `flag`. State: s.quests_active {quest_id: step index},
## s.quest_parts {quest_id: [announced part indexes]}, s.quests_done.
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


## Who stands for `npc_id` now (v0.7.14): the NPC while alive, else its living heir (pack `heir`, in a chain), else "".
static func stand_in(s: GameSession, world: Dictionary, npc_id: String) -> String:
	var id := npc_id
	for i in 5:
		if id.is_empty() or not s.dead_npcs.has(id):
			return id
		id = str(WorldView.new(world).npc(id).get("heir", ""))
	return ""


## Quests the giver in this room offers now (its heir, when the giver is dead; nobody gives work to the wanted hero).
static func offers_here(s: GameSession, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var here := s.npcs_here(WorldView.new(world).world, s.room_id)
	var all := stepped(world)
	for id: String in all:
		var giver := stand_in(s, world, str(all[id].get("giver", "")))
		var at_board: bool = all[id].has("board") and str(all[id]["board"]["room"]) == s.room_id  # an order on a board (v0.7.21.2)
		if (here.has(giver) or at_board) and not s.quests_active.has(id) and not s.quests_done.has(id) and not s.quests_failed.has(id) 				and not s.wanted.has(WorldView.new(world).location_id(s.room_id)):
			out.append(id)
	return out


## A pack NPC died (v0.7.14): the taken quests it gave or has a talk step in pass to its heir or fail. Lines.
static func on_death(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var world: Dictionary = data["world"]
	var lines: Array[String] = []
	var all := stepped(world)
	var heir := stand_in(s, world, npc_id)
	var who := str(WorldView.new(world).npc(npc_id).get("name", npc_id))
	for id: String in all:
		if s.quests_done.has(id) or s.quests_failed.has(id):
			continue
		if not s.quests_active.has(id):
			continue  # an untaken quest of the dead is simply never offered (offers_here)
		var talks := (all[id]["steps"] as Array).slice(int(s.quests_active[id])).any(func(st: Dictionary) -> bool:
			return str(st.get("when", {}).get("talk", "")) == npc_id)
		if str(all[id].get("giver", "")) != npc_id and not talks:
			continue
		if not heir.is_empty():
			lines.append("«%s»: дело %s продолжит %s" % [all[id]["title"], who, WorldView.new(world).npc(heir).get("name", heir)])
			continue
		lines.append("Задание провалено: %s — %s мёртв(а)" % [all[id]["title"], who])
		s.quests_active.erase(id)
		s.quest_parts.erase(id)
		s.quests_failed.append(id)
	return lines


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
	s.remember(stand_in(s, data["world"], str(q.get("giver", ""))), "герой взял задание «%s»" % q["title"])
	var lines: Array[String] = ["Новое задание: %s" % q["title"], "Цель: %s" % q["steps"][0]["text"]]
	var given: Dictionary = q.get("offer_items", {})  # what the giver hands over (v0.6.5: the letter, the writ)
	for id: String in given:
		s.character["inventory"][id] = int(s.character["inventory"].get(id, 0)) + int(given[id])
		lines.append("Получено: %s" % ItemRules.display_name(data["items"], s.items, id))
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
	if when.has("all"):
		return (when["all"] as Array).all(func(w: Dictionary) -> bool: return met(s, w))
	if when.has("any"):
		return (when["any"] as Array).any(func(w: Dictionary) -> bool: return met(s, w))
	return false


## A button step (talk or choice): never closed by facts.
static func _by_button(when: Dictionary) -> bool:
	return when.has("talk") or when.has("choice")


## Closes every step whose fact is true now (several in a row too). Call after anything that changes the facts:
## a room entered, a secret found, a fight finished, effects applied. Lines.
static func advance(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for id: String in s.quests_active.keys():
		var guard := 0
		while s.quests_active.has(id) and guard < 20:
			guard += 1
			var step := current(s, data["world"], id)
			if step.is_empty() or _by_button(step["when"]):
				break
			lines.append_array(_announce_parts(s, data["world"], id, step))
			if not met(s, step["when"]):
				break
			lines.append_array(_complete_step(s, data, id))
	return lines


## Parts of an "all" step done just now (in any order): one line each, once.
static func _announce_parts(s: GameSession, world: Dictionary, quest_id: String, step: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var when: Dictionary = step["when"]
	if not when.has("all") or not step.has("parts"):
		return lines
	var done: Array = s.quest_parts.get(quest_id, [])
	for i in (when["all"] as Array).size():
		if not done.has(i) and met(s, when["all"][i]):
			done.append(i)
			lines.append("«%s»: %s — сделано" % [quest(world, quest_id)["title"], step["parts"][i]])
	s.quest_parts[quest_id] = done
	return lines


## What the hero has done in the quest, for the journal (v0.7.22.7, big test #26): the closed steps, and for a choice
## step — which way it went and how it turned out (by the choice's flag). Lines «✓ …».
static func history(s: GameSession, world: Dictionary, quest_id: String) -> Array[String]:
	var q := quest(world, quest_id)
	var out: Array[String] = []
	var steps: Array = q.get("steps", [])
	var n := steps.size() if s.quests_done.has(quest_id) else int(s.quests_active.get(quest_id, 0))
	for i in mini(n, steps.size()):
		var step: Dictionary = steps[i]
		var line := "✓ " + str(step["text"])
		for c: Dictionary in step.get("choices", []):
			if not str(c.get("flag", "")).is_empty() and s.flags.has(str(c["flag"])):
				line += " — %s. %s" % [c["action"], c.get("done_text", "")]
		out.append(line.strip_edges())
	return out


## The step text with its parts: «Разузнать… (✓ застава; шахта)».
static func step_text(s: GameSession, world: Dictionary, quest_id: String) -> String:
	var step := current(s, world, quest_id)
	if step.is_empty():
		return ""
	var text := str(step["text"])
	if step.has("parts"):
		var done: Array = s.quest_parts.get(quest_id, [])
		var bits: Array[String] = []
		for i in (step["parts"] as Array).size():
			bits.append(("✓ " if done.has(i) else "") + str(step["parts"][i]))
		text += " (" + "; ".join(bits) + ")"
	return text


## Choice buttons of the current steps in this room: [{quest_id, choice_id, action}].
static func choices_here(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s.in_conversation():
		return out
	for id: String in s.quests_active:
		var step := current(s, world, id)
		if str(step.get("when", {}).get("choice", "")) == s.room_id:
			for c: Dictionary in step.get("choices", []):
				out.append({"quest_id": id, "choice_id": str(c["id"]), "action": str(c["action"])})
	return out


static func choice(s: GameSession, world: Dictionary, quest_id: String, choice_id: String) -> Dictionary:
	for c: Dictionary in current(s, world, quest_id).get("choices", []):
		if str(c["id"]) == choice_id:
			return c
	return {}


## "" when this choice can be made here now.
static func can_choose(s: GameSession, world: Dictionary, quest_id: String, choice_id: String) -> String:
	for c: Dictionary in choices_here(s, world):
		if c["quest_id"] == quest_id and c["choice_id"] == choice_id:
			return ""
	return "QUEST_WRONG_PLACE"


## Makes the choice (can_choose first): its rewards and flag, then the step closes. Lines.
static func choose(s: GameSession, data: Dictionary, quest_id: String, choice_id: String) -> Array[String]:
	var c := choice(s, data["world"], quest_id, choice_id)
	var lines: Array[String] = ["Выбор: %s" % c["action"]]
	_reward(s, data, c, lines, bool(quest(data["world"], quest_id).get("major", false)))
	lines.append_array(_complete_step(s, data, quest_id))
	lines.append_array(advance(s, data))
	return lines


## Talk steps that can be closed in this room: [{quest_id, action, npc_id}].
static func talks_here(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := s.npcs_here(WorldView.new(world).world, s.room_id)
	for id: String in s.quests_active:
		var step := current(s, world, id)
		var when: Dictionary = step.get("when", {})
		var to := stand_in(s, world, str(when.get("talk", "")))
		if when.has("talk") and here.has(to):
			out.append({"quest_id": id, "action": str(step.get("action", step["text"])), "npc_id": to,
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
	_reward(s, data, step, lines, dangerous(q, step))
	s.quest_parts.erase(quest_id)
	if i + 1 >= (q["steps"] as Array).size():
		s.quests_active.erase(quest_id)
		s.quests_done.append(quest_id)
		var giver := stand_in(s, data["world"], str(q.get("giver", "")))
		s.remember(giver, "герой выполнил задание «%s»" % q["title"])
		lines.append("Задание выполнено: %s" % q["title"])
		lines.append_array(ReputationRules.add(s, data, ReputationRules.home_of(data, giver),
			int(ReputationRules.cfg(data)["points"]["quest_done"]), "задание «%s»" % q["title"]))  # v0.7.17
	else:
		s.quests_active[quest_id] = i + 1
		lines.append("Цель: %s" % q["steps"][i + 1]["text"])
	return lines


## Class experience for a quest (v0.7.19, the author: «a letter brought — 300 XP and new spells» makes no sense): only
## for the dangerous — a step with a fight (`encounter` in its fact) or marked `danger: true` — and for every step of a
## quest marked `major`. A peaceful step pays in coins, things and reputation.
static func dangerous(q: Dictionary, step: Dictionary) -> bool:
	return bool(q.get("major", false)) or bool(step.get("danger", false)) or _has_fight(step.get("when", {}))


static func _has_fight(when: Dictionary) -> bool:
	if when.has("encounter"):
		return true
	for key: String in ["all", "any"]:
		for w: Variant in when.get(key, []):
			if w is Dictionary and _has_fight(w):
				return true
	return false


static func _reward(s: GameSession, data: Dictionary, r: Dictionary, lines: Array[String], class_xp: bool = true) -> void:
	var c := s.character
	var flag := str(r.get("flag", ""))
	if not flag.is_empty() and not s.flags.has(flag):
		s.flags.append(flag)
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
		s.shift_attitude(npc, int(att[npc]), data)
		lines.append("%s: отношение %s" % [world.npc(npc).get("name", npc), "лучше" if int(att[npc]) > 0 else "хуже"])
	if class_xp:
		lines.append_array(XpRules.award(c, data, int(r.get("xp", 0)), "задание"))


## Taken quests for the snapshot and the journal: [{id, title, description, done, failed, step}]; failed ones —
## taken before the NPC died (v0.7.14).
static func info(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := stepped(world)
	for id: String in all:
		if not s.quests_active.has(id) and not s.quests_done.has(id) and not s.quests_failed.has(id):
			continue
		out.append({"id": id, "title": str(all[id]["title"]), "description": str(all[id].get("description", "")),
			"done": s.quests_done.has(id), "failed": s.quests_failed.has(id), "step": step_text(s, world, id)})
	return out


## Every flag the world pack reads or sets (quest facts, closed exits, choices; v0.7.4): only these may be set by
## the master's `flag` effect — its own memory goes to `note`.
static func known_flags(world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	_collect_flags(world.get("quests", {}), out)
	_collect_flags(world.get("rooms", {}), out)
	return out


static func _collect_flags(v: Variant, out: Array[String]) -> void:
	if v is Dictionary:
		for k: Variant in v:
			if str(k) in ["flag", "if_flag", "if_not_flag"] and v[k] is String and not out.has(str(v[k])):
				out.append(str(v[k]))
			else:
				_collect_flags(v[k], out)
	elif v is Array:
		for x: Variant in v:
			_collect_flags(x, out)
