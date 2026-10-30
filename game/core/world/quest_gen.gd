class_name QuestGen
extends RefCounted
## Quests the master makes (roadmap v0.7.21; pillar 6): a quest of the pack's schema from a giver of the scene, after a
## search (`find_quests`). Its steps are the engine's facts — talk to someone (and hand over a thing), visit a place,
## find a hidden thing, win an encounter; the master names a scale and the engine sets the reward by
## `rules.quest_gen` (coins, class XP only for the dangerous — v0.7.19, the giver's goodwill). A made quest lives in
## this game's save (`s.generated.quests`) and in its copy of the world, so it is offered, taken, followed and rewarded
## like a pack quest.
##
## Batch 2: a quest brings what it needs in one deal — up to `max_new_npcs` new people (WorldGen.plan_npc), a new place
## on an open edge (WorldGen.plan_place) and the quest's thing in a hiding place of a room (a secret with loot, as the
## pack's amulet in the mine); its steps name them `new:<key>` and `item`. The engine takes the whole deal or none.
## A person a quest made may give quests too, but no deeper than `quest_depth` (its own depth is on the NPC).
##
## Batch 3: an order on a board — a thing of the room (`board_prop_id`) offers it whoever stands there, its customer
## (the giver) may be anyone alive in the world or a person the order brings; the player's own deed (`own`) has no
## giver — it is taken at once, ends with its last fact and pays only class XP for the dangerous. Taken made quests
## are limited (`max_open`), offered ones — per giver or board (`max_offered`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["quest_gen"]


## Made quests the hero has taken and not finished: `max_open` limits them.
static func open_made(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in WorldGen.generated(s).get("quests", {}):
		if s.quests_active.has(id):
			out.append(id)
	return out


## A notice board (v0.7.22.13): a thing of the room whose name has one of rules.quest_gen.board_words.
static func is_board(data: Dictionary, p: Dictionary) -> bool:
	var name := str(p.get("name", "")).to_lower()
	return (cfg(data).get("board_words", []) as Array).any(func(w: Variant) -> bool: return name.contains(str(w)))


## A board's state (the author, after v0.7.22.33): {read_day, fresh_day}; {} — never read. `fresh_day` > 0 — the day
## it fills again, rolled when an order is first taken off it (rules.quest_gen.board_refresh_days).
static func board_state(s: GameSession, room_id: String, prop_id: String) -> Dictionary:
	return WorldGen.generated(s).get("boards_read", {}).get("board:%s:%s" % [room_id, prop_id], {})


## Not looked at yet, or filled again since: reading it puts new orders up.
static func board_unread(s: GameSession, room_id: String, prop_id: String) -> bool:
	var st := board_state(s, room_id, prop_id)
	return st.is_empty() or (int(st.get("fresh_day", 0)) > 0 and s.day >= int(st["fresh_day"]))


## "" when the hero may read this board now, else a localization key. A read board that stayed empty — again next day.
static func board_why_not(s: GameSession, data: Dictionary, prop_id: String) -> String:
	if board_unread(s, s.room_id, prop_id):
		return ""
	if offered_by(s, "board:%s:%s" % [s.room_id, prop_id]).is_empty() and int(board_state(s, s.room_id, prop_id).get("read_day", 0)) < s.day:
		return ""
	return "BOARD_READ_TODAY"


static func mark_board_read(s: GameSession, prop_id: String) -> void:
	var gen := WorldGen.generated(s)
	var read: Dictionary = gen.get("boards_read", {})
	read["board:%s:%s" % [s.room_id, prop_id]] = {"read_day": s.day, "fresh_day": 0}
	gen["boards_read"] = read


## An order taken off a board: the first one starts its refresh in board_refresh_days (5e-style dice, "1d4").
static func board_taken(s: GameSession, data: Dictionary, q: Dictionary) -> void:
	if not q.has("board"):
		return
	var read: Dictionary = WorldGen.generated(s).get("boards_read", {})
	var key := "board:%s:%s" % [q["board"]["room"], q["board"]["prop"]]
	var st: Dictionary = read.get(key, {"read_day": s.day, "fresh_day": 0})
	if int(st.get("fresh_day", 0)) <= s.day:
		st["fresh_day"] = s.day + maxi(1, CombatRules.roll_dice(s.rng, str(cfg(data).get("board_refresh_days", "1d4"))))
	read[key] = st
	WorldGen.generated(s)["boards_read"] = read


## Made quests offered and not taken by this giver or on this board («board:<room>:<prop>»).
static func offered_by(s: GameSession, source: String) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = WorldGen.generated(s).get("quests", {})
	for id: String in all:
		if s.quests_active.has(id) or s.quests_done.has(id) or s.quests_failed.has(id):
			continue
		if _source(all[id]) == source:
			out.append(id)
	return out


static func _source(q: Dictionary) -> String:
	return "board:%s:%s" % [q["board"]["room"], q["board"]["prop"]] if q.has("board") else str(q.get("giver", ""))


## "" when a made quest may be taken (the limit of taken ones), else a localization key; a pack quest — always "".
static func can_take(s: GameSession, data: Dictionary, quest_id: String) -> String:
	if not WorldGen.generated(s).get("quests", {}).has(quest_id):
		return ""
	return "QUEST_TOO_MANY" if open_made(s).size() >= int(cfg(data)["max_open"]) else ""


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


## --- v0.7.39.6: a quest by acts ------------------------------------------------------------------------------------
## The master writes the skeleton (`create_quest`): the difficulty, the acts with their goals, the villain and the
## finale; the engine sets the reward by the difficulty and the hero's level. An act is built when it opens (the first
## on taking): the designer's turn (`quest_act`) brings its steps — the pack's facts, parts in any order, knowledge as a
## key — its people, places, things and fights, and in the last act the choice; the engine checks each part by the
## difficulty and makes it all or nothing. A fight in a known room is a variant of that room while the quest is taken.


static func difficulty(data: Dictionary, id: String) -> Dictionary:
	return cfg(data)["difficulties"].get(id, {})


## «Сложность: сложное · актов: 3» of a made quest; "" for a pack quest or an old one without acts.
static func difficulty_line(data: Dictionary, q: Dictionary) -> String:
	var d := difficulty(data, str(q.get("difficulty", "")))
	if d.is_empty():
		return ""
	return TranslationServer.translate("QUEST_DIFFICULTY_LINE").format({"name": d["name"], "acts": (q.get("acts", [1]) as Array).size()})


## The coins a quest pays at its end: a made one by acts knows it before its last act is built.
static func reward_cp(q: Dictionary) -> int:
	if q.has("reward_cp"):
		return int(q["reward_cp"])
	var steps: Array = q.get("steps", [])
	return int(steps[-1].get("reward_cp", 0)) if not steps.is_empty() else 0


## Taking it asks «Точно?» first (the near-impossible).
static func warns(data: Dictionary, q: Dictionary) -> bool:
	return bool(difficulty(data, str(q.get("difficulty", ""))).get("warn", false))


static func _level(s: GameSession) -> int:
	return clampi(int(s.character.get("level", 1)), 1, 5)


## The DMG budget of one fight of a tier for the hero's level (raw XP of the foes, as xp_budget_hard).
static func tier_xp(data: Dictionary, tier: String, level: int) -> int:
	return int(cfg(data)["encounter_xp"].get(tier, [0, 0, 0, 0, 0])[clampi(level, 1, 5) - 1])


## The tier one step harder (the boss of the last act) or one step easier (the floor of a fight).
static func tier_step(data: Dictionary, tier: String, by: int) -> String:
	var order: Array = cfg(data)["tier_order"]
	var i := order.find(tier) + by
	return str(order[i]) if i >= 0 and i < order.size() else ""


static func _arr(spec: Dictionary, key: String) -> Array:
	return spec.get(key, []) if spec.get(key) is Array else []


static func _str(spec: Dictionary, key: String) -> String:
	return str(spec.get(key, "")) if spec.get(key) != null else ""


## Checks a `create_quest` — the skeleton: {plan, summary} or {reason}. `searched` — find_quests was called this turn.
static func plan_quest(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool) -> Dictionary:
	var c := cfg(data)
	if not searched:
		return {"reason": "сначала find_quests: может, такое задание уже есть"}
	var world := WorldView.new(data["world"])
	var own := bool(spec.get("own", false))
	var giver := "" if own else _str(spec, "giver")
	var board := _str(spec, "board_prop_id")
	var people := _arr(spec, "new_npcs")
	if own:
		if open_made(s).size() >= int(c["max_open"]):
			return {"reason": "у героя уже %d созданных дел в работе — сначала их" % open_made(s).size()}
	elif not board.is_empty():
		var prop := PropRules.find(s, s.room_id, board)
		if prop.is_empty():
			return {"reason": "доски %s в этой комнате нет — вещь из «Вокруг» (prop_id)" % board}
		if offered_by(s, "board:%s:%s" % [s.room_id, board]).size() >= int(c["max_offered"]):
			return {"reason": "на %s уже %d заказа — больше не помещается" % [prop.get("name", board), int(c["max_offered"])]}
		if giver.begins_with("new:"):
			if people.size() != 1 or str((people[0] as Dictionary).get("key", "")) != giver.trim_prefix("new:"):
				return {"reason": "заказчик %s — один новый человек в new_npcs с этим key" % giver}
		elif not data["world"]["npcs"].has(giver) or s.dead_npcs.has(giver):
			return {"reason": "заказчик заказа на доске — живой человек мира (find_npcs) или новый «new:<key>»"}
	else:
		if not s.npcs_here(data["world"], s.room_id).has(giver):
			return {"reason": "заказчик %s — только NPC этой сцены (или заказ на доске — board_prop_id, или своё дело — own)" % giver}
		if offered_by(s, giver).size() >= int(c["max_offered"]):
			return {"reason": "%s уже предлагает %d дела — сначала их" % [world.npc(giver).get("name", giver), int(c["max_offered"])]}
	if not people.is_empty() and not giver.begins_with("new:"):
		return {"reason": "new_npcs — только новый заказчик заказа на доске; люди дела появятся в его актах"}
	if not giver.is_empty() and not giver.begins_with("new:") and SocialRules.refuses(s, data, giver):
		return {"reason": "%s враждебен герою и работы не даст" % world.npc(giver).get("name", giver)}
	if not own and s.wanted.has(world.location_id(s.room_id)):
		return {"reason": "герой в розыске: здесь ему работы не дают"}
	var depth := int(world.npc(giver).get("quest_depth", 0)) if not giver.is_empty() and not giver.begins_with("new:") else 0
	if depth >= int(c["quest_depth"]):
		return {"reason": "%s сам(а) появился(лась) из задания — своих заданий не даёт (глубина %d)" % [world.npc(giver).get("name", giver), depth]}
	var diff := _str(spec, "difficulty")
	var d := difficulty(data, diff)
	if d.is_empty():
		var names: Array = (c["difficulties"] as Dictionary).keys().map(func(k: String) -> String: return "%s (%s)" % [k, c["difficulties"][k]["name"]])
		return {"reason": "сложность задания — из %s" % ", ".join(names)}
	var title := _str(spec, "title").strip_edges()
	if title.length() < 3:
		return {"reason": "у задания нужно название"}
	for q: Dictionary in QuestRules.stepped(data["world"]).values():
		if str(q.get("title", "")).to_lower() == title.to_lower():
			return {"reason": "задание «%s» уже есть" % title}
	var for_goal := bool(spec.get("for_goal", false))
	if for_goal:  # the quest for the hero's life goal (v0.7.22.1)
		var why := GoalRules.quest_why_not(s.character, data)
		if not why.is_empty():
			return {"reason": why}
	var follows := _str(spec, "follows")
	if not follows.is_empty() and not s.quests_done.has(follows):
		return {"reason": "продолжение — только сделанного задания (find_quests: «сделано»), а %s не сделано" % follows}
	var raw := _arr(spec, "acts")
	var lo := int(d["acts"][0])
	var hi := int(d["acts"][1])
	if raw.size() < lo or raw.size() > hi:
		return {"reason": "у задания «%s» — %s: актов %d–%d (каждый — title и goal), а их %d" % [d["name"], diff, lo, hi, raw.size()]}
	var acts: Array = []
	for a: Variant in raw:
		if not (a is Dictionary) or _str(a, "title").strip_edges().length() < 3 or _str(a, "goal").strip_edges().length() < 5:
			return {"reason": "акт — объект: title (название) и goal (что герою сделать в этом акте, одной фразой)"}
		acts.append({"title": _str(a, "title").strip_edges().left(60), "goal": _str(a, "goal").strip_edges().left(200)})
	var giver_npc := {}
	if giver.begins_with("new:"):
		var spec_n := (people[0] as Dictionary).duplicate(true)
		spec_n.erase("key")
		var p := WorldGen.plan_npc(s, data, spec_n, true)
		if p.has("reason"):
			return {"reason": "заказчик %s: %s" % [giver, p["reason"]]}
		p["plan"]["npc"]["quest_depth"] = depth + 1
		giver_npc = p["plan"]
	var level := _level(s)
	var q := {"title": title.left(60), "description": _str(spec, "description").left(400), "giver": giver,
		"offer_text": _str(spec, "offer_text").left(300), "steps": [], "acts": acts, "built": 0, "fights": 0, "made_steps": 0,
		"difficulty": diff, "generated": true, "depth": depth, "reward_cp": 0 if own else int(d["reward_cp"][level - 1]),
		"xp": int(d["xp"][level - 1]), "attitude": int(d["attitude"]), "xp_paid": 0,
		"villain": _str(spec, "villain").strip_edges().left(200), "finale": _str(spec, "finale").strip_edges().left(200)}
	if bool(d.get("major", false)):
		q["major"] = true
	if own:
		q["own"] = true
	if for_goal:
		q["for_goal"] = true
	if not follows.is_empty():
		q["follows"] = follows
	if not board.is_empty():
		q["board"] = {"room": s.room_id, "prop": board}
	var who := str(giver_npc["npc"]["name"]) if not giver_npc.is_empty() else str(world.npc(giver).get("name", giver))
	var from := "своё дело" if own else ("заказ на доске, заказчик %s" % who) if not board.is_empty() else "от %s" % who
	return {"plan": {"quest": q, "giver_npc": giver_npc}, "summary": "Новое задание: «%s» — %s (%s, актов %d: %s). Подробности акта соберёт мастер, когда герой его откроет" % [
		q["title"], from, d["name"], acts.size(), "; ".join(acts.map(func(a: Dictionary) -> String: return a["title"]))]}


## Makes the skeleton: in the save and in this game's world; offered by its giver at once. Its id.
static func apply_quest(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var id := "gen_quest_%d" % _next_n(data)
	var q: Dictionary = (plan["quest"] as Dictionary).duplicate(true)
	var made: Dictionary = plan.get("giver_npc", {})
	if not made.is_empty():
		q["giver"] = WorldGen.apply_npc(s, data, {"npc": made["npc"], "room": made["room"], "items": made.get("items", {})})
	_store(s, data, id, q)
	return id


static func _store(s: GameSession, data: Dictionary, id: String, q: Dictionary) -> void:
	var gen := WorldGen.generated(s)
	if not gen.has("quests"):
		gen["quests"] = {}
	gen["quests"][id] = q.duplicate(true)
	if not data["world"].has("quests"):
		data["world"]["quests"] = {}
	data["world"]["quests"][id] = q


static func _next_n(data: Dictionary) -> int:
	var n := 1
	while data["world"].get("quests", {}).has("gen_quest_%d" % n):
		n += 1
	return n


## The frame of the act to build, for the designer's turn: the quest, what happened, the act's budget by the difficulty,
## the hero, the places and edges near, the SRD foes that fit. The first line is for machines (the stub master).
static func act_frame(s: GameSession, data: Dictionary, quest_id: String) -> String:
	var world := WorldView.new(data["world"])
	var q := QuestRules.quest(data["world"], quest_id)
	var d := difficulty(data, str(q["difficulty"]))
	var n := int(q.get("built", 0))
	var acts: Array = q["acts"]
	var last := n + 1 == acts.size()
	var level := _level(s)
	var giver := str(q.get("giver", ""))
	var near := ""
	for x: Variant in world.room(s.room_id).get("exits", []):
		near = str(x)
		break
	var out: Array[String] = ["[quest %s | act %d | giver %s | here %s | near %s]" % [quest_id, n + 1, giver, s.room_id, near]]
	out.append("Задание «%s» — %s. %s" % [q["title"], d["name"], q.get("description", "")])
	if not giver.is_empty():
		out.append("Заказчик: %s [%s], %s." % [world.npc(giver).get("name", giver), giver, world.room(ReputationRules.home_room(data, giver)).get("name", "")])
	else:
		out.append("Своё дело героя, без заказчика.")
	if not str(q.get("villain", "")).is_empty():
		out.append("Кто стоит за этим: %s" % q["villain"])
	if not str(q.get("finale", "")).is_empty():
		out.append("Что решится в финале: %s" % q["finale"])
	if q.has("follows"):
		var prev := QuestRules.quest(data["world"], str(q["follows"]))
		out.append("Продолжение задания «%s»: %s" % [prev.get("title", ""), " ".join(QuestRules.history(s, data["world"], str(q["follows"])))])
	out.append("Акты:")
	for i in acts.size():
		var mark := " ← СОБРАТЬ СЕЙЧАС" if i == n else " (пройден)" if i < n else ""
		out.append("%d. «%s» — %s%s" % [i + 1, acts[i]["title"], acts[i]["goal"], mark])
	var done := QuestRules.history(s, data["world"], quest_id)
	if not done.is_empty():
		out.append("Что герой уже сделал: " + " ".join(done))
	var facts := s.chronicle_tail(data["world"], 8)
	if not facts.is_empty():
		out.append("Летопись (последнее): " + "; ".join(facts))
	var steps_cap := act_steps_cap(data, q, d, n)
	var fights_cap := act_fights_cap(q, d, last)
	var steps_min := maxi(1, int(d["steps"][0]) - int(q.get("made_steps", 0))) if last else 1
	var fights_min := maxi(0, int(d["fights"][0]) - int(q.get("fights", 0))) if last else 0
	var tier := str(d["fight"])
	var floor_tier := tier_step(data, tier, -1)
	if last:
		out.append("Рамка последнего акта %d из %d: шагов в акте %d–%d — сколько нужно, чтобы довести задание до конца; боёв %d–%d." % [n + 1, acts.size(),
			steps_min, steps_cap, fights_min, fights_cap])
	else:
		out.append("Рамка акта %d из %d: шагов в акте 1–%d (по шагу оставлено на каждый следующий акт), боёв 0–%d." % [n + 1, acts.size(), steps_cap, fights_cap])
	out.append("Бой задания — «%s»: опыт врагов %d–%d на бой (уровень героя %d)%s." % [tier, tier_xp(data, floor_tier, level) + 1 if not floor_tier.is_empty() else 1,
		tier_xp(data, tier, level), level, ("; главарь (boss) в последнем акте — до %d" % tier_xp(data, tier_step(data, tier, 1) if not tier_step(data, tier, 1).is_empty() else tier, level)) if bool(d["boss"]) else ""])
	if last and bool(d["choice"]):
		out.append("Финал: шаг choice с 2–3 выборами обязателен (флаг, отношение, перемена места).")
	out.append("Награду назначит движок: %s и опыт к концу задания — не указывай её." % Money.format(int(q.get("reward_cp", 0))))
	var c := s.character
	out.append("Герой: %s, %s %d ур., ОЗ %d/%d." % [c.get("name", ""), c.get("class", ""), level, int(c.get("hp", 0)), int(c.get("max_hp", 0))])
	out.append("Герой сейчас: %s [%s]." % [world.room(s.room_id).get("name", s.room_id), s.room_id])
	var places: Array[String] = []
	for rid: String in s.visited:
		var r := SceneRules.room(s, data["world"], rid)
		if r.is_empty():
			continue
		var enc: Dictionary = r.get("encounter", {})
		var busy := " — ждёт встреча %s" % enc.get("id", "") if not enc.is_empty() and not s.encounters_done.has(str(enc.get("id", ""))) else ""
		places.append("[%s] %s (%s)%s%s" % [rid, r.get("name", rid), world.location(world.location_id(rid)).get("name", ""), " — люди" if not s.npcs_here(data["world"], rid).is_empty() else "", busy])
		if places.size() >= 24:
			break
	out.append("Места, где герой бывал: " + "; ".join(places))
	var edges := WorldGen.reach_edges(s, data).map(func(e: Dictionary) -> String: return "[%s] %s, край %d: %s (%s)" % [e["room_id"], e["room"], int(e["edge"]), e["text"], ", ".join(e.get("terrain", []))])
	if not edges.is_empty():
		out.append("Открытые края мира (для new_places — room_id и edge): " + "; ".join(edges))
	var cap := tier_xp(data, tier_step(data, tier, 1) if bool(d["boss"]) and not tier_step(data, tier, 1).is_empty() else tier, level)
	var foes: Array[String] = []
	var ids: Array = (data["monsters"] as Dictionary).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(data["monsters"][a]["xp"]) < int(data["monsters"][b]["xp"]))
	for mid: String in ids:
		var m: Dictionary = data["monsters"][mid]
		if int(m["xp"]) > cap or int(m["xp"]) <= 0:
			continue
		foes.append("%s (%s, %s, ПО %s, %d оп.)" % [mid, m.get("name", mid), m.get("type", ""), str(m.get("cr", "")), int(m["xp"])])
	out.append("Враги SRD по силам (id, имя, тип, ПО, опыт за одного): " + "; ".join(foes))
	return "\n".join(out)


## How many steps act `n` may have (v0.7.49.1): an act before the last leaves one step for each act after it within the
## difficulty's total; the last act finishes the quest and may go past the total: what is left of it, but at least
## act_max.last_steps (the earlier acts spent it all — the ending still needs its steps), never past act_max.steps.
static func act_steps_cap(data: Dictionary, q: Dictionary, d: Dictionary, n: int) -> int:
	var mx: Dictionary = cfg(data)["act_max"]
	var left := int(d["steps"][1]) - int(q.get("made_steps", 0))
	var later := (q["acts"] as Array).size() - n - 1
	if later <= 0:
		return clampi(left, int(mx.get("last_steps", 3)), int(mx["steps"]))
	return clampi(left - later, 1, int(mx["steps"]))


## How many fights an act may have: what is left of the difficulty's total, and one at least in the last act (its boss).
static func act_fights_cap(q: Dictionary, d: Dictionary, last: bool) -> int:
	var left := maxi(0, int(d["fights"][1]) - int(q.get("fights", 0)))
	return maxi(left, 1) if last else left


## Checks a `quest_act`: {plan, summary} or {reason}.
static func plan_act(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var mx: Dictionary = cfg(data)["act_max"]
	var qid := _str(spec, "quest_id")
	var q: Dictionary = WorldGen.generated(s).get("quests", {}).get(qid, {})
	if q.is_empty() or not q.has("acts"):
		return {"reason": "нет задания по актам %s" % qid}
	var n := int(q.get("built", 0))
	if not QuestRules.awaiting(s, data["world"]).has(qid):
		return {"reason": "у «%s» сейчас нечего собирать: задание не взято или акт %d уже есть" % [q["title"], n]}
	if spec.get("act") != null and int(spec["act"]) != n + 1:
		return {"reason": "собирается акт %d, не %d" % [n + 1, int(spec["act"])]}
	var d := difficulty(data, str(q["difficulty"]))
	var last := n + 1 == (q["acts"] as Array).size()
	var content := _plan_act_content(s, data, spec, q, d, last, n == 0)
	if content.has("reason"):
		return content
	var raw := _arr(spec, "steps")
	if raw.is_empty() or raw.size() > int(mx["steps"]):
		return {"reason": "шагов в акте — от 1 до %d" % int(mx["steps"])}
	var made := int(q.get("made_steps", 0)) + raw.size()
	var cap := act_steps_cap(data, q, d, n)
	if raw.size() > cap:
		return {"reason": "у «%s» задания в этом акте не больше %d шагов (по шагу оставлено на каждый следующий акт), сейчас %d" % [d["name"], cap, raw.size()]}
	if last and made < int(d["steps"][0]):
		return {"reason": "у «%s» задания всего не меньше %d шагов — в последнем акте их нужно больше (сейчас %d)" % [d["name"], int(d["steps"][0]), made]}
	var steps: Array = []
	var used: Array = []  # refs the steps name: people, encounters, things
	var choice_step := false
	for r: Variant in raw:
		if not (r is Dictionary):
			return {"reason": "шаг — объект: text, kind, target"}
		var st := _act_step(s, data, r, content, q, last, used)
		if st.has("reason"):
			return st
		if (st["when"] as Dictionary).has("choice"):
			choice_step = true
		if steps.is_empty() and str(st["when"].get("arrive", "")) == s.room_id:
			return {"reason": "шаг «%s»: герой уже здесь — первый шаг закрылся бы сразу" % st["text"]}
		steps.append(st)
	if last and bool(d["choice"]) and not choice_step:
		return {"reason": "в финале «%s» задания нужен шаг choice с выборами (choices)" % d["name"]}
	if not choice_step and not _arr(spec, "choices").is_empty():
		return {"reason": "choices — только у шага choice"}
	for e: Dictionary in content["encounters"]:
		if not used.has("enc:" + str(e["key"])):
			return {"reason": "бой %s не нужен ни одному шагу — шаг fight (или часть all/any) с target %s" % [e["key"], e["key"]]}
	for npc: Dictionary in content["npcs"]:
		if not used.has("new:" + str(npc["key"])):
			return {"reason": "человек new:%s не нужен ни одному шагу — talk с target new:%s или убери его" % [npc["key"], npc["key"]]}
	for it: Dictionary in content["items"]:
		if not used.has("item:" + str(it["key"])):
			return {"reason": "вещь %s не нужна ни одному шагу — find (спрятанная) или item_id в talk / visit" % it["key"]}
	var fights := used.filter(func(u: String) -> bool: return u.begins_with("enc:") or u.begins_with("pack:")).size()
	var total := int(q.get("fights", 0)) + fights
	if fights > act_fights_cap(q, d, last):
		return {"reason": "боёв у «%s» задания в этом акте — не больше %d, сейчас %d" % [d["name"], act_fights_cap(q, d, last), fights]}
	if last and total < int(d["fights"][0]):
		return {"reason": "боёв у «%s» задания — не меньше %d: в последнем акте добавь бой (encounters и шаг fight), сейчас %d" % [d["name"], int(d["fights"][0]), total]}
	var choices: Array = []
	if choice_step:
		var ch := _plan_choices(s, data, _arr(spec, "choices"), content, qid, int(q.get("reward_cp", 0)))
		if ch.has("reason"):
			return ch
		choices = ch["choices"]
		for st: Dictionary in steps:
			if (st["when"] as Dictionary).has("choice"):
				st["choices"] = choices
	var teach := {}
	if spec.get("teaches") is Dictionary and not (spec["teaches"] as Dictionary).is_empty():
		teach = _plan_teach(s, data, spec["teaches"], content, steps, qid, str(q["title"]))
		if teach.has("reason"):
			return teach
	var giver := str(q.get("giver", ""))
	var own := bool(q.get("own", false))
	if last and not own and str(steps[-1]["when"].get("talk", "")) != giver:  # the quest ends where it began
		var who := str(WorldView.new(data["world"]).npc(giver).get("name", giver))
		steps.append({"text": "Вернуться к %s" % who, "when": {"talk": giver}, "action": "Рассказать %s" % who})
	var tail: Dictionary = steps[-1]
	var share := int(q["xp"]) - int(q.get("xp_paid", 0)) if last else floori(float(q["xp"]) / (q["acts"] as Array).size())
	tail["xp"] = share
	if fights > 0:
		tail["danger"] = true  # class XP of the act at its end (v0.7.19: only the dangerous)
	var reward_item := _str(spec, "reward_item_id")
	if last:
		var cp := int(q.get("reward_cp", 0))
		var top := 0
		for ch: Dictionary in choices:
			top = maxi(top, int(ch.get("value_cp", 0)))
		cp -= top
		if not reward_item.is_empty():
			if own:
				return {"reason": "у своего дела нет заказчика — награды-вещи нет"}
			var item: Dictionary = data["items"]["catalog"].get(reward_item, {})
			if item.is_empty():
				return {"reason": "награда-вещь — id каталога (find_items)"}
			if int(item.get("value_cp", 0)) > cp:
				return {"reason": "%s дороже награды за такое задание (%s)" % [item.get("name", reward_item), Money.format(cp)]}
			cp -= int(item.get("value_cp", 0))
			tail["items"] = {reward_item: 1}
		tail["reward_cp"] = maxi(0, cp)
		if not own:
			tail["attitude"] = {giver: int(q["attitude"])}
	elif not reward_item.is_empty():
		return {"reason": "награда-вещь — только в последнем акте"}
	var brings: Array = []
	for p: Dictionary in content["places"]:
		brings.append_array((p["place"]["rooms"] as Array).map(func(r: Dictionary) -> String: return str(r["name"])))
	brings.append_array((content["npcs"] as Array).map(func(x: Dictionary) -> String: return str(x["plan"]["npc"]["name"])))
	brings.append_array((content["items"] as Array).map(func(x: Dictionary) -> String: return str(x["name"])))
	brings.append_array((content["encounters"] as Array).map(func(x: Dictionary) -> String: return "бой: " + ", ".join((x["enemies"] as Array).map(func(f: Dictionary) -> String: return "%s ×%d" % [f["name"], f["count"]]))))
	if not teach.is_empty():
		brings.append("курс у учителя: %s" % teach["summary"])
	return {"plan": {"quest_id": qid, "act": n, "steps": steps, "content": content, "fights": fights, "made": raw.size(), "share": share,
		"teach": teach.get("spec", {})},
		"summary": "«%s», акт %d «%s»: %s%s" % [q["title"], n + 1, q["acts"][n]["title"], "; ".join(steps.map(func(st: Dictionary) -> String: return str(st["text"]))),
			("; с ним: " + "; ".join(brings)) if not brings.is_empty() else ""]}


## The course an act opens at the teacher the hero is sent to find (v0.7.39.7): `teaches` {npc — «new:<key>» of the
## act's people or an NPC of the world, kind, id, name, lessons, fee_cp, skill, dc_tier, recipe} — the fields of the
## effect `course`. A talk step with the teacher sets the quest's flag the course waits for, so it opens when the hero
## reaches the teacher. {spec, summary} or {reason}.
static func _plan_teach(s: GameSession, data: Dictionary, t: Dictionary, content: Dictionary, steps: Array, qid: String, title: String) -> Dictionary:
	var ref := _str(t, "npc")
	var def := {}
	if ref.begins_with("new:"):
		var x: Array = (content["npcs"] as Array).filter(func(p: Dictionary) -> bool: return "new:" + str(p["key"]) == ref)
		if x.is_empty():
			return {"reason": "teaches.npc: нет нового человека %s в new_npcs акта" % ref}
		def = x[0]["plan"]["npc"]
	elif BondRules.npc_def(s, data, ref).is_empty() or s.dead_npcs.has(ref):
		return {"reason": "teaches.npc — «new:<key>» человека акта или живой NPC мира (%s нет)" % ref}
	var step: Dictionary = {}
	for st: Dictionary in steps:
		if str(st["when"].get("talk", "")) == ref:
			step = st
	if step.is_empty():
		return {"reason": "учитель %s: нужен шаг talk с target %s — на нём откроется курс" % [ref, ref]}
	var flag := qid + "_teach"
	var spec := {"npc_id": ref, "name": t.get("name", ""), "teach_kind": t.get("kind", ""), "teach_id": t.get("id", ""),
		"lessons": t.get("lessons", 4) if t.get("lessons") != null else 4, "fee_cp": t.get("fee_cp", 0) if t.get("fee_cp") != null else 0,
		"skill": t.get("skill"), "dc_tier": t.get("dc_tier", "medium") if t.get("dc_tier") != null else "medium", "recipe": t.get("recipe"),
		"requires": {"flag": flag, "flag_text": "«%s»: учитель найден" % title}}
	var chk := StudyRules.make(s, data, spec, def)
	if chk.has("reason"):
		return {"reason": "курс учителя (teaches): " + str(chk["reason"])}
	step["flag"] = flag
	var d: Dictionary = chk["plan"]["def"]
	return {"spec": spec, "summary": "«%s», %d занятий, %s" % [d["name"], int(d["lessons"]), Money.format(int(d["fee_cp"])) if int(d["fee_cp"]) > 0 else "бесплатно"]}


## What the act brings: {places, room_keys, new_rooms, npcs, npc_keys, items, item_keys, encounters, enc_keys} or {reason}.
static func _plan_act_content(s: GameSession, data: Dictionary, spec: Dictionary, q: Dictionary, d: Dictionary, last: bool, first: bool) -> Dictionary:
	var mx: Dictionary = cfg(data)["act_max"]
	var world := WorldView.new(data["world"])
	var level := _level(s)
	var out := {"places": [], "room_keys": [], "new_rooms": {}, "npcs": [], "npc_keys": [], "items": [], "item_keys": [], "encounters": [], "enc_keys": []}
	var tier := str(d["fight"])
	var boss_ok := last and bool(d["boss"])
	var places := _arr(spec, "new_places")
	if places.size() > int(mx["places"]):
		return {"reason": "новых мест в акте — не больше %d" % int(mx["places"])}
	var names: Array = []
	var lairs: Array = []
	for p: Variant in places:
		if not (p is Dictionary):
			return {"reason": "место — объект схемы create_place"}
		var spec_p := (p as Dictionary).duplicate(true)
		for k: String in ["npcs", "sites", "settlement", "law"]:
			spec_p.erase(k)  # the act's people go to new_npcs
		var encs := {}
		for r: Variant in _arr(spec_p, "rooms"):
			if r is Dictionary and r.get("encounter") is Dictionary:
				encs[str(r.get("key", ""))] = r["encounter"]  # the quest's fight: checked by the difficulty below
				(r as Dictionary).erase("encounter")
		var pl := WorldGen.plan_place(s, data, spec_p, true)
		if pl.has("reason"):
			return {"reason": "место акта: %s" % pl["reason"]}
		var loc := "" if bool(pl["plan"]["place"]["new_location"]) else world.location_id(str(pl["plan"]["place"]["from"]))
		for r: Dictionary in pl["plan"]["place"]["rooms"]:
			var k := str(r["key"])
			if (out["room_keys"] as Array).has(k) or names.has(str(r["name"]).to_lower()):
				return {"reason": "комнаты мест акта — каждая со своим key и именем (%s)" % k}
			(out["room_keys"] as Array).append(k)
			names.append(str(r["name"]).to_lower())
			out["new_rooms"][k] = loc
		for k: String in encs:
			lairs.append({"key": "new:" + k, "room": "new:" + k, "kind": "lair", "encounter": encs[k]})
		(out["places"] as Array).append(pl["plan"])
	var npcs := _arr(spec, "new_npcs")
	if npcs.size() > int(mx["npcs"]):
		return {"reason": "новых людей в акте — не больше %d" % int(mx["npcs"])}
	for n: Variant in npcs:
		if not (n is Dictionary):
			return {"reason": "новый человек — объект схемы NPC с key"}
		var key := _str(n, "key")
		if key.is_empty() or (out["npc_keys"] as Array).has(key) or (out["room_keys"] as Array).has(key):
			return {"reason": "у каждого нового человека свой key, не как у комнат"}
		(out["npc_keys"] as Array).append(key)
		var spec_n := (n as Dictionary).duplicate(true)
		var room := _str(spec_n, "room_id")
		if room.begins_with("new:") and not (out["room_keys"] as Array).has(room.trim_prefix("new:")):
			return {"reason": "человек %s: нет комнаты %s в новых местах акта" % [key, room]}
		var p := WorldGen.plan_npc(s, data, spec_n, true, out["new_rooms"], true)
		if p.has("reason"):
			return {"reason": "человек акта %s: %s" % [key, p["reason"]]}
		p["plan"]["npc"]["quest_depth"] = int(q.get("depth", 0)) + 1
		(out["npcs"] as Array).append({"key": key, "plan": p["plan"], "room": room if room.begins_with("new:") else str(p["plan"]["room"])})
	var items := _arr(spec, "items")
	if items.size() > int(mx["items"]):
		return {"reason": "вещей в акте — не больше %d" % int(mx["items"])}
	for qi: Variant in items:
		if not (qi is Dictionary):
			return {"reason": "вещь акта — объект: key, item_id или item, room и hint (или from_giver)"}
		var it := _plan_item(s, data, qi, out, first, bool(q.get("own", false)))
		if it.has("reason"):
			return it
		(out["items"] as Array).append(it)
		(out["item_keys"] as Array).append(str(it["key"]))
	var encs := _arr(spec, "encounters")
	if encs.size() + lairs.size() > int(mx["encounters"]):
		return {"reason": "боёв в акте — не больше %d" % int(mx["encounters"])}
	for e: Variant in encs + lairs:
		if not (e is Dictionary):
			return {"reason": "бой акта — объект: key, room, kind, enemies"}
		var key := _str(e, "key")
		var room := _str(e, "room")
		var kind := _str(e, "kind")
		if key.is_empty() or (out["enc_keys"] as Array).has(key):
			return {"reason": "у каждого боя акта свой key"}
		if not kind in ["ambush", "guard", "target", "lair"]:
			return {"reason": "бой %s: kind — ambush (засада), guard (охрана), target (цель с именем) или lair (логово в новом месте)" % key}
		var why := _encounter_room_why(s, data, room, out, key)
		if not why.is_empty():
			return {"reason": why}
		var src: Dictionary = e["encounter"] if e.has("encounter") else e
		var plan := _plan_encounter(data, src, tier, level, boss_ok, key)
		if plan.has("reason"):
			return plan
		if kind == "target" and not (plan["enemies"] as Array).any(func(f: Dictionary) -> bool: return bool(f.get("named", false))):
			return {"reason": "бой %s — цель: у врага-цели нужно имя (name)" % key}
		if kind == "ambush":
			plan["ambush"] = true
		plan.merge({"key": key, "room": room, "kind": kind, "text": _str(e, "text").left(200)})
		(out["encounters"] as Array).append(plan)
		(out["enc_keys"] as Array).append(key)
	return out


## "" when a quest's fight may stand in that room: a new room of the act, or a known room with no live encounter, no
## people, not a place to rest and not where the hero stands.
static func _encounter_room_why(s: GameSession, data: Dictionary, room: String, content: Dictionary, key: String) -> String:
	if room.begins_with("new:"):
		if not (content["room_keys"] as Array).has(room.trim_prefix("new:")):
			return "бой %s: нет комнаты %s в новых местах акта" % [key, room]
		if (content["encounters"] as Array).any(func(e: Dictionary) -> bool: return str(e["room"]) == room):
			return "бой %s: в %s уже стоит бой акта" % [key, room]
		return ""
	var r := SceneRules.room(s, data["world"], room)
	if r.is_empty():
		return "бой %s: нет места %s (find_places)" % [key, room]
	var enc: Dictionary = r.get("encounter", {})
	if not enc.is_empty() and not s.encounters_done.has(str(enc.get("id", ""))):
		return "бой %s: в %s уже ждёт встреча — выбери другое место" % [key, r.get("name", room)]
	if r.get("safe") != null:
		return "бой %s: %s — место отдыха, там не нападают" % [key, r.get("name", room)]
	if not s.npcs_here(data["world"], room).is_empty():
		return "бой %s: в %s люди — бой задания ставится в безлюдном месте (дорога, лес, руины, подвал)" % [key, r.get("name", room)]
	if room == s.room_id:
		return "бой %s: герой уже в %s — бой ставится там, куда он придёт" % [key, r.get("name", room)]
	if (content["encounters"] as Array).any(func(e: Dictionary) -> bool: return str(e["room"]) == room):
		return "бой %s: в %s уже стоит бой акта" % [key, r.get("name", room)]
	return ""


## One fight by the difficulty: {enemies, xp, boss, loot} or {reason}. Between the tier below and its own budget; the
## boss of the last act — up to the next tier.
static func _plan_encounter(data: Dictionary, e: Dictionary, tier: String, level: int, boss_ok: bool, key: String) -> Dictionary:
	var enemies: Array = []
	var xp := 0
	for f: Variant in _arr(e, "enemies"):
		if not (f is Dictionary):
			return {"reason": "враг — объект: monster, count, name?"}
		var mid := _str(f, "monster")
		if not data["monsters"].has(mid):
			return {"reason": "бой %s: нет такого монстра SRD: %s" % [key, mid]}
		var cnt := clampi(int(f.get("count", 1)) if f.get("count") != null else 1, 1, 6)
		xp += int(data["monsters"][mid]["xp"]) * cnt
		var named := not _str(f, "name").strip_edges().is_empty()
		enemies.append({"monster": mid, "count": cnt, "name": _str(f, "name").strip_edges().left(60) if named else str(data["monsters"][mid]["name"]),
			"desc": _str(f, "desc").left(200), "col": 3, "named": named})
	if enemies.is_empty() or enemies.size() > 4:
		return {"reason": "бой %s: враги — 1–4 вида (enemies: [{monster, count}])" % key}
	var boss := bool(e.get("boss", false))
	if boss and not boss_ok:
		return {"reason": "бой %s: главарь (boss) — только в последнем акте сложного или почти невозможного задания" % key}
	var up := tier_step(data, tier, 1)
	var cap := tier_xp(data, up if boss and not up.is_empty() else tier, level)
	var low := tier_step(data, tier, -1)
	var floor := tier_xp(data, low, level) if not low.is_empty() else 0
	if xp > cap:
		return {"reason": "бой %s не по силам: %d опыта врагов при пределе %d (бой «%s», уровень %d)" % [key, xp, cap, tier, level]}
	if xp <= floor:
		return {"reason": "бой %s слишком лёгкий для этой сложности: %d опыта врагов, нужно больше %d" % [key, xp, floor]}
	return {"enemies": enemies, "xp": xp, "boss": boss, "loot": {"coins_cp": 0, "items": {}}}


## The act's thing: {key, id, def, name, given} or hidden {…, room, text, dc, skill}; or {reason}.
static func _plan_item(s: GameSession, data: Dictionary, qi: Dictionary, content: Dictionary, first: bool, own: bool) -> Dictionary:
	var key := _str(qi, "key")
	if key.is_empty() or (content["item_keys"] as Array).has(key):
		return {"reason": "у каждой вещи акта свой key"}
	var id := _str(qi, "item_id")
	var def := {}
	if qi.get("item") is Dictionary:
		var chk := ItemRules.check_generated(data["items"], qi["item"], _level(s), data.get("spells", {}))
		if not bool(chk["ok"]):
			return {"reason": "вещь %s: %s" % [key, chk["reason"]]}
		def = chk["def"]
		id = ItemRules.generated_id(def)
	elif ItemRules.def_of(data["items"], s.items, id).is_empty():
		return {"reason": "вещь %s: нет предмета %s — find_items или новая `item`" % [key, id]}
	var name := str((def if not def.is_empty() else ItemRules.def_of(data["items"], s.items, id)).get("name", id))
	if bool(qi.get("from_giver", false)):  # a parcel the giver hands over on taking (v0.7.34.5)
		if own or not first:
			return {"reason": "вещь %s: from_giver — только в первом акте задания с заказчиком (он вручает её, когда герой берёт дело)" % key}
		return {"key": key, "id": id, "def": def, "name": name, "given": true}
	var room := _str(qi, "room")
	if room.begins_with("new:"):
		if not (content["room_keys"] as Array).has(room.trim_prefix("new:")):
			return {"reason": "вещь %s: нет комнаты %s в новых местах акта" % [key, room]}
	elif not data["world"]["rooms"].has(room):
		return {"reason": "вещь %s: нет места %s (find_places)" % [key, room]}
	var tier := _str(qi, "dc_tier") if not _str(qi, "dc_tier").is_empty() else "medium"
	if not (data["rules"]["dc_tiers"] as Dictionary).has(tier) or _str(qi, "hint").length() < 5:
		return {"reason": "вещь %s: hint (где она спрятана, по-русски) и dc_tier из %s" % [key, ", ".join((data["rules"]["dc_tiers"] as Dictionary).keys())]}
	var skill := _str(qi, "skill") if not _str(qi, "skill").is_empty() else "perception"
	var skills: Array = cfg(data).get("hide_skills", ["perception", "investigation"])
	if not skills.has(skill):
		return {"reason": "вещь %s: skill — навык, которым её находят: %s" % [key, ", ".join(skills)]}
	return {"key": key, "id": id, "def": def, "name": name, "room": room, "text": _str(qi, "hint").left(240),
		"dc": int(data["rules"]["dc_tiers"][tier]), "skill": skill}


## A fact of the engine for a step, a part or a need: {when, danger?} or {reason}. Kinds visit, find, fight (and talk
## for a whole step). `used` collects the refs it names.
static func _fact(s: GameSession, data: Dictionary, kind: String, target: String, item: String, content: Dictionary, q: Dictionary, used: Array) -> Dictionary:
	var world := WorldView.new(data["world"])
	var w := {}
	match kind:
		"talk":
			if target.begins_with("new:"):
				if not (content["npc_keys"] as Array).has(target.trim_prefix("new:")):
					return {"reason": "нет нового человека %s в new_npcs акта" % target}
			elif not data["world"]["npcs"].has(target) or s.dead_npcs.has(target):
				return {"reason": "нет живого NPC %s (find_npcs)" % target}
			w = {"talk": target}
		"visit":
			if target.begins_with("new:"):
				if not (content["room_keys"] as Array).has(target.trim_prefix("new:")):
					return {"reason": "нет комнаты %s в новых местах акта" % target}
				w = {"room": target}
			elif data["world"]["rooms"].has(target):
				w = {"arrive": target}  # came there on this step, not ever been (v0.7.34.4)
			else:
				return {"reason": "нет места %s (find_places)" % target}
		"find":
			if (content["item_keys"] as Array).has(target):
				var it: Dictionary = (content["items"] as Array).filter(func(x: Dictionary) -> bool: return str(x["key"]) == target)[0]
				if bool(it.get("given", false)):
					return {"reason": "вещь %s у героя с начала — её не ищут" % target}
				w = {"secret": "item:" + target}
				used.append("item:" + target)
			else:
				var room := target.get_slice(":", 0)
				var sid := target.get_slice(":", 1)
				if not (world.room(room).get("secrets", []) as Array).any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == sid):
					return {"reason": "нет тайны %s — «комната:id тайны» мира или key спрятанной вещи акта" % target}
				if (s.revealed.get(room, []) as Array).has(sid):
					return {"reason": "тайна %s уже найдена" % target}
				w = {"secret": target}
		"fight":
			if (content["enc_keys"] as Array).has(target):
				w = {"encounter": "enc:" + target}
				if not used.has("enc:" + target):
					used.append("enc:" + target)
			else:
				var found := false
				for rid: String in data["world"]["rooms"]:
					if str(data["world"]["rooms"][rid].get("encounter", {}).get("id", "")) == target:
						found = true
				if not found or s.encounters_done.has(target):
					return {"reason": "нет непобеждённой встречи %s: key боя акта (encounters или комната места с encounter) или встреча мира" % target}
				w = {"encounter": target}
				if not used.has("pack:" + target):
					used.append("pack:" + target)
			return {"when": w, "danger": true}
		_:
			return {"reason": "вид — talk, visit, find или fight"}
	if not item.is_empty() and kind in ["talk", "visit"]:
		if (content["item_keys"] as Array).has(item):
			w["item"] = "item:" + item
			used.append("item:" + item)
		elif (q.get("items", {}) as Dictionary).has(item):
			w["item"] = str(q["items"][item])  # a thing of an earlier act
		elif data["items"]["catalog"].has(item):
			w["item"] = item
		else:
			return {"reason": "вещь %s — key вещи акта, прежнего акта или id каталога" % item}
	if w.has("talk") and not used.has(str(w["talk"])):
		used.append(str(w["talk"]))
	return {"when": w}


## One step of the act: {text, when, action?, danger?, parts?, needs?, needs_text?} or {reason}.
static func _act_step(s: GameSession, data: Dictionary, r: Dictionary, content: Dictionary, q: Dictionary, last: bool, used: Array) -> Dictionary:
	var mx: Dictionary = cfg(data)["act_max"]
	var text := _str(r, "text").strip_edges().left(120)
	if text.length() < 3:
		return {"reason": "у шага нужен текст"}
	var st := {"text": text}
	var kind := _str(r, "kind")
	var target := _str(r, "target")
	match kind:
		"all", "any":
			var parts := _arr(r, "parts")
			if parts.size() < 2 or parts.size() > int(mx["parts"]):
				return {"reason": "шаг «%s»: частей %s — 2–%d (каждая — text, kind visit|find|fight, target)" % [text, kind, int(mx["parts"])]}
			var facts: Array = []
			var names: Array = []
			for p: Variant in parts:
				if not (p is Dictionary) or not _str(p, "kind") in ["visit", "find", "fight"] or _str(p, "text").strip_edges().length() < 3:
					return {"reason": "шаг «%s»: часть — text и kind visit, find или fight (разговор — отдельным шагом)" % text}
				var f := _fact(s, data, _str(p, "kind"), _str(p, "target"), "", content, q, used)
				if f.has("reason"):
					return {"reason": "шаг «%s», часть «%s»: %s" % [text, _str(p, "text"), f["reason"]]}
				facts.append(f["when"])
				names.append(_str(p, "text").strip_edges().left(60))
				if bool(f.get("danger", false)):
					st["danger"] = true
			st["when"] = {kind: facts}
			if kind == "all":
				st["parts"] = names
		"choice":
			if not last:
				return {"reason": "шаг «%s»: выбор — только в последнем акте" % text}
			if target.begins_with("new:"):
				if not (content["room_keys"] as Array).has(target.trim_prefix("new:")):
					return {"reason": "шаг «%s»: нет комнаты %s в новых местах акта" % [text, target]}
			elif not data["world"]["rooms"].has(target):
				return {"reason": "шаг «%s»: выбор делается в комнате — id места или new:<key>" % text}
			st["when"] = {"choice": target}
		_:
			var f := _fact(s, data, kind, target, _str(r, "item_id"), content, q, used)
			if f.has("reason"):
				return {"reason": "шаг «%s»: %s" % [text, f["reason"]]}
			st["when"] = f["when"]
			var n := clampi(int(r.get("item_qty", 1)) if r.get("item_qty") != null else 1, 1, 12)
			if n > 1 and (st["when"] as Dictionary).has("item"):  # v0.7.41: an order of several (three hides, ten fish)
				if not data["items"]["catalog"].has(str(st["when"]["item"])):
					return {"reason": "шаг «%s»: item_qty — только для вещи каталога (не своей вещи задания)" % text}
				st["when"]["qty"] = n
			if bool(f.get("danger", false)):
				st["danger"] = true
	if bool(r.get("danger", false)):
		st["danger"] = true
	if r.get("needs") is Dictionary:  # knowledge as a key: the step waits for it (v0.7.22.13 for choices; v0.7.39.6 for any)
		var nd: Dictionary = r["needs"]
		if not _str(nd, "kind") in ["visit", "find", "fight"]:
			return {"reason": "шаг «%s»: needs — {kind: find|visit|fight, target}" % text}
		var f := _fact(s, data, _str(nd, "kind"), _str(nd, "target"), "", content, q, used)
		if f.has("reason"):
			return {"reason": "шаг «%s», needs: %s" % [text, f["reason"]]}
		st["needs"] = f["when"]
		if st["needs"].has("arrive"):  # knowledge is having been there, not standing there now
			st["needs"] = {"room": st["needs"]["arrive"]}
		st["needs_text"] = _str(r, "needs_text").strip_edges().left(160) if _str(r, "needs_text").strip_edges().length() >= 5 else "сначала нужно кое-что узнать"
	return st


## The choices of the finale: {choices: [{id, action, done_text, flag, attitude, changes, items?, value_cp}]} or {reason}.
static func _plan_choices(s: GameSession, data: Dictionary, raw: Array, content: Dictionary, qid: String, reward_cp: int) -> Dictionary:
	var mx: Dictionary = cfg(data)["act_max"]
	if raw.size() < 2 or raw.size() > int(mx["choices"]):
		return {"reason": "выборов — 2–%d: id, action, done_text, attitude?, changes?" % int(mx["choices"])}
	var out: Array = []
	var ids: Array = []
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]{0,19}$")
	for c: Variant in raw:
		if not (c is Dictionary):
			return {"reason": "выбор — объект"}
		var id := _str(c, "id")
		if re.search(id) == null or ids.has(id):
			return {"reason": "у каждого выбора свой id латиницей (restore, power)"}
		ids.append(id)
		var action := _str(c, "action").strip_edges()
		var done := _str(c, "done_text").strip_edges()
		if action.length() < 3 or done.length() < 10:
			return {"reason": "выбор %s: action (кнопка) и done_text (что вышло, 1–2 фразы)" % id}
		var ch := {"id": id, "action": action.left(80), "done_text": done.left(400), "flag": "%s_%s" % [qid, id]}
		var att := {}
		var raw_att: Dictionary = c.get("attitude", {}) if c.get("attitude") is Dictionary else {}
		for npc: String in raw_att:
			var known: bool = data["world"]["npcs"].has(npc) or (npc.begins_with("new:") and (content["npc_keys"] as Array).has(npc.trim_prefix("new:")))
			if not known:
				return {"reason": "выбор %s: attitude — NPC мира или new:<key> акта, а не %s" % [id, npc]}
			att[npc] = clampi(int(raw_att[npc]), -2, 2)
		if not att.is_empty():
			ch["attitude"] = att
		var changes: Array = []
		for x: Variant in c.get("changes", []) if c.get("changes") is Array else []:
			if not (x is Dictionary):
				continue
			var room := _str(x, "room_id")
			var text := _str(x, "description").strip_edges()
			if not (data["world"]["rooms"].has(room) or (room.begins_with("new:") and (content["room_keys"] as Array).has(room.trim_prefix("new:")))):
				return {"reason": "выбор %s: changes.room_id — место мира или new:<key> акта" % id}
			if text.length() < 10:
				return {"reason": "выбор %s: changes.description — каким место стало (1–3 фразы)" % id}
			changes.append({"room": room, "description": text.left(600)})
		if changes.size() > int(mx["changes"]):
			return {"reason": "выбор %s: перемен мест — не больше %d" % [id, int(mx["changes"])]}
		ch["changes"] = changes
		var item := _str(c, "reward_item_id")
		ch["value_cp"] = 0
		if not item.is_empty():
			var def: Dictionary = data["items"]["catalog"].get(item, {})
			if def.is_empty() or int(def.get("value_cp", 0)) * 2 > reward_cp:
				return {"reason": "выбор %s: награда-вещь — id каталога не дороже половины награды (%s)" % [id, Money.format(reward_cp / 2)]}
			ch["items"] = {item: 1}
			ch["value_cp"] = int(def.get("value_cp", 0))
		out.append(ch)
	return {"choices": out}


## Makes the act: its places, people, things and fights, its steps on the quest; closes what is already true. Lines.
static func apply_act(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var qid := str(plan["quest_id"])
	var content: Dictionary = plan["content"]
	var gen := WorldGen.generated(s)
	var refs := {}
	var lines: Array[String] = []
	for p: Dictionary in content["places"]:
		WorldGen.apply_place(s, data, p)
		for k: String in p["ids"]:
			refs["new:" + k] = p["ids"][k]
	for n: Dictionary in content["npcs"]:
		var room := str(refs.get(str(n["room"]), n["room"]))
		refs["new:" + str(n["key"])] = WorldGen.apply_npc(s, data, {"npc": n["plan"]["npc"], "room": room, "items": n["plan"].get("items", {})})
	var q: Dictionary = gen["quests"][qid]
	var known: Dictionary = q.get("items", {})
	for it: Dictionary in content["items"]:
		if not (it["def"] as Dictionary).is_empty():
			s.items[str(it["id"])] = it["def"]
		refs["item:" + str(it["key"])] = str(it["id"])
		known[str(it["key"])] = str(it["id"])
		if bool(it.get("given", false)):
			s.character["inventory"][str(it["id"])] = int(s.character["inventory"].get(str(it["id"]), 0)) + 1
			lines.append("Получено: %s" % ItemRules.display_name(data["items"], s.items, str(it["id"])))
			continue
		var room := str(refs.get(str(it["room"]), it["room"]))
		var sec := {"id": "q_%s_%s" % [qid, it["key"]], "dc": int(it["dc"]), "text": it["text"], "skill": str(it.get("skill", "perception")),
			"loot": {"items": {str(it["id"]): 1}}}
		_add_secret(gen, data, room, sec)
		refs["secret:item:" + str(it["key"])] = "%s:%s" % [room, sec["id"]]
	q["items"] = known
	for e: Dictionary in content["encounters"]:
		var room := str(refs.get(str(e["room"]), e["room"]))
		var foes: Array = (e["enemies"] as Array).duplicate(true)
		for f: Dictionary in foes:
			f.erase("named")
		var enc := {"id": "%s_%s" % [qid, str(e["key"]).replace(":", "_")], "enemies": foes, "loot": e["loot"], "quest": qid}
		if bool(e.get("ambush", false)):
			enc["ambush"] = true
		if bool(e.get("boss", false)):
			enc["boss"] = true
		refs["enc:" + str(e["key"])] = enc["id"]
		if gen.get("rooms", {}).has(room):  # a room the act made: the fight is its own
			gen["rooms"][room]["encounter"] = enc
			data["world"]["rooms"][room]["encounter"] = enc.duplicate(true)
		else:  # a known room: a variant of it while the quest is taken (SceneRules)
			add_variant(gen, data, room, {"vid": enc["id"], "if_quest": qid, "encounter": enc})
	var steps: Array = (plan["steps"] as Array).duplicate(true)
	for st: Dictionary in steps:
		st["act"] = int(plan["act"])
		_resolve(st, refs, "when")
		if st.has("needs"):
			_resolve(st, refs, "needs")
		for ch: Dictionary in st.get("choices", []):
			var att := {}
			for k: String in ch.get("attitude", {}):
				att[str(refs.get(k, k))] = ch["attitude"][k]
			if not att.is_empty():
				ch["attitude"] = att
			for x: Dictionary in ch.get("changes", []):
				var room := str(refs.get(str(x["room"]), x["room"]))
				add_variant(gen, data, room, {"vid": ch["flag"], "if_flag": ch["flag"], "description": x["description"]})
			ch.erase("changes")
			ch.erase("value_cp")
		var w: Dictionary = st["when"]
		if w.has("talk") and not st.has("action"):
			var who := str(WorldView.new(data["world"]).npc(str(w["talk"])).get("name", w["talk"]))
			st["action"] = ("Отдать %s: %s" % [who, ItemRules.display_name(data["items"], s.items, str(w["item"]))]) if w.has("item") else "Поговорить: %s" % who
	(q["steps"] as Array).append_array(steps)
	var teach: Dictionary = plan.get("teach", {})
	if not teach.is_empty():  # v0.7.39.7: the teacher's course, open once the hero reaches the teacher
		var t := teach.duplicate(true)
		t["npc_id"] = str(refs.get(str(t["npc_id"]), t["npc_id"]))
		var made := StudyRules.make(s, data, t)
		if made.has("plan"):
			StudyRules.apply_make(s, data, made["plan"])
	q["built"] = int(q.get("built", 0)) + 1
	q["fights"] = int(q.get("fights", 0)) + int(plan["fights"])
	q["made_steps"] = int(q.get("made_steps", 0)) + int(plan["made"])
	q["xp_paid"] = int(q.get("xp_paid", 0)) + int(plan["share"])
	data["world"]["quests"][qid] = q.duplicate(true)
	var act: Dictionary = q["acts"][int(plan["act"])]
	lines.push_front("«%s», акт %d «%s» · Цель: %s" % [q["title"], int(plan["act"]) + 1, act["title"], steps[0]["text"]])
	lines.append_array(QuestRules.advance(s, data))
	return lines


## Refs of a step's fact into ids: «new:<key>», «item:<key>», «enc:<key>», «secret:item:<key>»; in all / any and a choice's room too.
static func _resolve(st: Dictionary, refs: Dictionary, key: String) -> void:
	var w: Dictionary = st[key]
	for k: String in ["all", "any"]:
		if w.has(k):
			for i in (w[k] as Array).size():
				var part := {"x": w[k][i]}
				_resolve(part, refs, "x")
				w[k][i] = part["x"]
	if w.has("secret") and str(w["secret"]).begins_with("item:"):
		w["secret"] = refs["secret:" + str(w["secret"])]
	for k: String in ["talk", "room", "arrive", "item", "encounter", "choice"]:
		if w.has(k) and refs.has(str(w[k])):
			w[k] = refs[str(w[k])]


static func _add_secret(gen: Dictionary, data: Dictionary, room: String, sec: Dictionary) -> void:
	if gen.get("rooms", {}).has(room):
		(gen["rooms"][room]["secrets"] as Array).append(sec)
	else:
		if not gen.has("room_secrets"):
			gen["room_secrets"] = {}
		var list: Array = gen["room_secrets"].get(room, [])
		list.append(sec)
		gen["room_secrets"][room] = list
	var secrets: Array = data["world"]["rooms"][room].get("secrets", [])
	secrets.append(sec.duplicate(true))
	data["world"]["rooms"][room]["secrets"] = secrets


## A variant of a room this game added (a quest's fight, a choice's change): in the save and in this game's world.
static func add_variant(gen: Dictionary, data: Dictionary, room: String, v: Dictionary) -> void:
	if not gen.has("room_variants"):
		gen["room_variants"] = {}
	var list: Array = gen["room_variants"].get(room, [])
	list.append(v.duplicate(true))
	gen["room_variants"][room] = list
	var mine: Array = data["world"]["rooms"][room].get("variants", [])
	mine.append(v.duplicate(true))
	data["world"]["rooms"][room]["variants"] = mine
