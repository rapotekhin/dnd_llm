class_name QuestGen
extends RefCounted
## Quests the master makes (roadmap v0.7.21, batch 1; pillar 6): a quest of the pack's schema from a giver of the scene,
## after a search (`find_quests`), on what the world already has. Its steps are the engine's facts — talk to someone
## (and hand over a thing), visit a place, find a hidden thing, win an encounter; the master names a scale and the
## engine sets the reward by `rules.quest_gen` (coins, class XP only for the dangerous — v0.7.19, the giver's
## goodwill). A made quest lives in this game's save (`s.generated.quests`) and in its copy of the world, so it is
## offered, taken, followed and rewarded like a pack quest.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["quest_gen"]


## Made quests not done and not failed (offered or taken): the limit counts them.
static func open_made(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in WorldGen.generated(s).get("quests", {}):
		if not s.quests_done.has(id) and not s.quests_failed.has(id):
			out.append(id)
	return out


## Quests of the world by a query: [{quest_id, title, giver, status, source}]; status — offered | taken | done | failed.
static func find_quests(s: GameSession, data: Dictionary, query: String) -> Array[Dictionary]:
	var world := WorldView.new(data["world"])
	var words := query.to_lower().replace("ё", "е").split(" ", false)
	var all := QuestRules.stepped(data["world"])
	var out: Array[Dictionary] = []
	for id: String in all:
		var q: Dictionary = all[id]
		var giver := str(world.npc(str(q.get("giver", ""))).get("name", q.get("giver", "")))
		var hay := ("%s %s %s %s" % [q.get("title", ""), q.get("description", ""), q.get("offer_text", ""), giver]).to_lower().replace("ё", "е")
		if not words.is_empty() and not Array(words).any(func(w: String) -> bool: return w.length() >= 3 and hay.contains(w.left(5))):
			continue
		var status := "done" if s.quests_done.has(id) else "failed" if s.quests_failed.has(id) else "taken" if s.quests_active.has(id) else "offered"
		out.append({"quest_id": id, "title": str(q.get("title", id)), "giver": giver, "status": status,
			"source": "made" if WorldGen.generated(s).get("quests", {}).has(id) else "pack"})
	return out


## Checks a `create_quest`: {plan, summary} or {reason}. `searched` — find_quests was called this turn.
static func plan_quest(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool) -> Dictionary:
	var c := cfg(data)
	if not searched:
		return {"reason": "сначала find_quests: может, такое задание уже есть"}
	var world := WorldView.new(data["world"])
	var giver := str(spec.get("giver", ""))
	if not s.npcs_here(data["world"], s.room_id).has(giver):
		return {"reason": "заказчик %s — только NPC этой сцены" % giver}
	if SocialRules.refuses(s, data, giver):
		return {"reason": "%s враждебен герою и работы не даст" % world.npc(giver).get("name", giver)}
	if s.wanted.has(world.location_id(s.room_id)):
		return {"reason": "герой в розыске: здесь ему работы не дают"}
	if open_made(s).size() >= int(c["max_open"]):
		return {"reason": "у героя уже %d созданных заданий в работе или предложенных — сначала их" % open_made(s).size()}
	var scale := str(spec.get("scale", ""))
	if not (c["scales"] as Dictionary).has(scale):
		return {"reason": "величина задания — из %s" % ", ".join((c["scales"] as Dictionary).keys())}
	var title := str(spec.get("title", "")).strip_edges()
	if title.length() < 3:
		return {"reason": "у задания нужно название"}
	for q: Dictionary in QuestRules.stepped(data["world"]).values():
		if str(q.get("title", "")).to_lower() == title.to_lower():
			return {"reason": "задание «%s» уже есть" % title}
	var raw: Array = spec.get("steps", []) if spec.get("steps") is Array else []
	if raw.is_empty() or raw.size() > int(c["max_steps"]):
		return {"reason": "шагов — от 1 до %d" % int(c["max_steps"])}
	var steps: Array = []
	var danger := scale == "major"
	for r: Variant in raw:
		if not (r is Dictionary):
			return {"reason": "шаг — объект: text, kind, target"}
		var st := _step(s, data, r)
		if st.has("reason"):
			return st
		danger = danger or bool(st.get("danger", false)) or (st["when"] as Dictionary).has("encounter")
		steps.append(st)
	var last: Dictionary = steps[-1]
	if str(last["when"].get("talk", "")) != giver:  # the quest ends where it began: back to the giver
		if steps.size() >= int(c["max_steps"]) + 1:
			return {"reason": "шагов слишком много"}
		last = {"text": "Вернуться к %s" % world.npc(giver).get("name", giver), "when": {"talk": giver},
			"action": "Рассказать %s" % world.npc(giver).get("name", giver)}
		steps.append(last)
	var level := clampi(int(s.character.get("level", 1)), 1, 5)
	var sc: Dictionary = c["scales"][scale]
	var cp := int(sc["reward_cp"][level - 1])
	var reward_item := str(spec.get("reward_item_id", "")) if spec.get("reward_item_id") != null else ""
	if not reward_item.is_empty():
		var item: Dictionary = data["items"]["catalog"].get(reward_item, {})
		if item.is_empty():
			return {"reason": "награда-вещь — id каталога (find_items)"}
		if int(item.get("value_cp", 0)) > cp:
			return {"reason": "%s дороже награды за такое задание (%s)" % [item.get("name", reward_item), Money.format(cp)]}
		cp -= int(item.get("value_cp", 0))
		last["items"] = {reward_item: 1}
	last["reward_cp"] = cp
	last["xp"] = int(sc["xp"][level - 1])
	last["attitude"] = {giver: int(sc["attitude"])}
	if danger:
		last["danger"] = true  # class XP for the whole quest at its end (v0.7.19: only the dangerous)
	var q := {"title": title.left(60), "description": str(spec.get("description", "")).left(400), "giver": giver,
		"offer_text": str(spec.get("offer_text", "")).left(300), "steps": steps, "generated": true, "scale": scale}
	if scale == "major":
		q["major"] = true
	return {"plan": {"quest": q}, "summary": "Новое задание: «%s» от %s (%s)" % [q["title"], world.npc(giver).get("name", giver), sc["name"]]}


## One step of the master's spec as a pack step: {text, when, action?, danger?} or {reason}.
static func _step(s: GameSession, data: Dictionary, r: Dictionary) -> Dictionary:
	var world := WorldView.new(data["world"])
	var text := str(r.get("text", "")).strip_edges().left(120)
	var target := str(r.get("target", ""))
	if text.length() < 3:
		return {"reason": "у шага нужен текст"}
	var st := {"text": text}
	if bool(r.get("danger", false)):
		st["danger"] = true
	match str(r.get("kind", "")):
		"talk":
			if not data["world"]["npcs"].has(target) or s.dead_npcs.has(target):
				return {"reason": "шаг «%s»: нет живого NPC %s (find_npcs)" % [text, target]}
			st["when"] = {"talk": target}
			var item := str(r.get("item_id", "")) if r.get("item_id") != null else ""
			if not item.is_empty():
				if not data["items"]["catalog"].has(item):
					return {"reason": "шаг «%s»: вещь %s — id каталога (find_items)" % [text, item]}
				st["when"]["item"] = item
				st["action"] = "Отдать %s: %s" % [world.npc(target).get("name", target), ItemRules.display_name(data["items"], s.items, item)]
			else:
				st["action"] = "Поговорить: %s" % world.npc(target).get("name", target)
		"visit":
			if not data["world"]["rooms"].has(target):
				return {"reason": "шаг «%s»: нет места %s (find_places)" % [text, target]}
			if s.visited.has(target):
				return {"reason": "шаг «%s»: герой уже был в %s — шаг закрылся бы сразу" % [text, world.room(target).get("name", target)]}
			st["when"] = {"room": target}
		"find":
			var room := target.get_slice(":", 0)
			var sid := target.get_slice(":", 1)
			var secrets: Array = world.room(room).get("secrets", [])
			if not secrets.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == sid):
				return {"reason": "шаг «%s»: нет тайны %s — «комната:id тайны»" % [text, target]}
			if (s.revealed.get(room, []) as Array).has(sid):
				return {"reason": "шаг «%s»: эта тайна уже найдена" % text}
			st["when"] = {"secret": target}
		"fight":
			var found := false
			for rid: String in data["world"]["rooms"]:
				if str(data["world"]["rooms"][rid].get("encounter", {}).get("id", "")) == target:
					found = true
			if not found or s.encounters_done.has(target):
				return {"reason": "шаг «%s»: нет непобеждённой встречи %s" % [text, target]}
			st["when"] = {"encounter": target}
			st["danger"] = true
		_:
			return {"reason": "вид шага — talk, visit, find или fight"}
	return st


## Makes the quest: in the save and in this game's world; offered by its giver at once. Its id.
static func apply_quest(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var gen := WorldGen.generated(s)
	if not gen.has("quests"):
		gen["quests"] = {}
	var n := 1
	while data["world"].get("quests", {}).has("gen_quest_%d" % n):
		n += 1
	var id := "gen_quest_%d" % n
	gen["quests"][id] = (plan["quest"] as Dictionary).duplicate(true)
	if not data["world"].has("quests"):
		data["world"]["quests"] = {}
	data["world"]["quests"][id] = (plan["quest"] as Dictionary).duplicate(true)
	return id
