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


## "" when the hero may read this empty board now (once a day), else a localization key.
static func board_why_not(s: GameSession, data: Dictionary, prop_id: String) -> String:
	var key := "board:%s:%s" % [s.room_id, prop_id]
	if int(WorldGen.generated(s).get("boards_read", {}).get(key, 0)) == s.day:
		return "BOARD_READ_TODAY"
	return ""


static func mark_board_read(s: GameSession, prop_id: String) -> void:
	var gen := WorldGen.generated(s)
	var read: Dictionary = gen.get("boards_read", {})
	read["board:%s:%s" % [s.room_id, prop_id]] = s.day
	gen["boards_read"] = read


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


## Checks a `create_quest`: {plan, summary} or {reason}. `searched` — find_quests was called this turn.
static func plan_quest(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool) -> Dictionary:
	var c := cfg(data)
	if not searched:
		return {"reason": "сначала find_quests: может, такое задание уже есть"}
	var world := WorldView.new(data["world"])
	var own := bool(spec.get("own", false))
	var giver := "" if own else str(spec.get("giver", "")) if spec.get("giver") != null else ""
	var board := str(spec.get("board_prop_id", "")) if spec.get("board_prop_id") != null else ""
	var keys: Array = []
	for n: Variant in spec.get("new_npcs", []) if spec.get("new_npcs") is Array else []:
		if n is Dictionary:
			keys.append(str(n.get("key", "")))
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
			if not keys.has(giver.trim_prefix("new:")):
				return {"reason": "заказчик %s — нет такого нового человека в задании" % giver}
		elif not data["world"]["npcs"].has(giver) or s.dead_npcs.has(giver):
			return {"reason": "заказчик заказа на доске — живой человек мира (find_npcs) или новый «new:<key>»"}
	else:
		if not s.npcs_here(data["world"], s.room_id).has(giver):
			return {"reason": "заказчик %s — только NPC этой сцены (или заказ на доске — board_prop_id, или своё дело — own)" % giver}
		if offered_by(s, giver).size() >= int(c["max_offered"]):
			return {"reason": "%s уже предлагает %d дела — сначала их" % [world.npc(giver).get("name", giver), int(c["max_offered"])]}
	if not giver.is_empty() and not giver.begins_with("new:") and SocialRules.refuses(s, data, giver):
		return {"reason": "%s враждебен герою и работы не даст" % world.npc(giver).get("name", giver)}
	if not own and s.wanted.has(world.location_id(s.room_id)):
		return {"reason": "герой в розыске: здесь ему работы не дают"}
	var depth := int(world.npc(giver).get("quest_depth", 0)) if not giver.is_empty() and not giver.begins_with("new:") else 0
	if depth >= int(c["quest_depth"]):
		return {"reason": "%s сам(а) появился(лась) из задания — своих заданий не даёт (глубина %d)" % [world.npc(giver).get("name", giver), depth]}
	var scale := str(spec.get("scale", ""))
	if not (c["scales"] as Dictionary).has(scale):
		return {"reason": "величина задания — из %s" % ", ".join((c["scales"] as Dictionary).keys())}
	var title := str(spec.get("title", "")).strip_edges()
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
	var content := _plan_content(s, data, spec, depth + 1)
	if content.has("reason"):
		return content
	var raw: Array = spec.get("steps", []) if spec.get("steps") is Array else []
	if raw.is_empty() or raw.size() > int(c["max_steps"]):
		return {"reason": "шагов — от 1 до %d" % int(c["max_steps"])}
	var steps: Array = []
	var danger := scale == "major"
	for r: Variant in raw:
		if not (r is Dictionary):
			return {"reason": "шаг — объект: text, kind, target"}
		var st := _step(s, data, r, content)
		if st.has("reason"):
			return st
		danger = danger or bool(st.get("danger", false)) or (st["when"] as Dictionary).has("encounter")
		steps.append(st)
	var last: Dictionary = steps[-1]
	var who := _name(data, giver, content)
	if not own and str(last["when"].get("talk", "")) != giver:  # the quest ends where it began: back to the giver
		last = {"text": "Вернуться к %s" % who, "when": {"talk": giver}, "action": "Рассказать %s" % who}
		steps.append(last)
	var handed := steps.any(func(st: Dictionary) -> bool: return str(st["when"].get("item", "")) == "item")
	if not (content["item"] as Dictionary).is_empty() and not handed and str(last["when"].get("talk", "")) == giver:
		last["when"]["item"] = "item"  # the quest's thing goes back to the giver
		last["text"] = "Отдать %s: %s" % [who, content["item"]["name"]]
		last.erase("action")
	var level := clampi(int(s.character.get("level", 1)), 1, 5)
	var sc: Dictionary = c["scales"][scale]
	var cp := 0 if own else int(sc["reward_cp"][level - 1])  # one's own deed pays with what it finds
	var reward_item := str(spec.get("reward_item_id", "")) if spec.get("reward_item_id") != null else ""
	if not reward_item.is_empty() and own:
		return {"reason": "у своего дела нет заказчика — награды-вещи нет"}
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
	if not own:
		last["attitude"] = {giver: int(sc["attitude"])}
	if danger:
		last["danger"] = true  # class XP for the whole quest at its end (v0.7.19: only the dangerous)
	var q := {"title": title.left(60), "description": str(spec.get("description", "")).left(400), "giver": giver,
		"offer_text": str(spec.get("offer_text", "")).left(300), "steps": steps, "generated": true, "scale": scale, "depth": depth}
	if scale == "major":
		q["major"] = true
	if own:
		q["own"] = true
	if for_goal:
		q["for_goal"] = true
	if not board.is_empty():
		q["board"] = {"room": s.room_id, "prop": board}
	var brings: Array = (content["npcs"] as Array).map(func(n: Dictionary) -> String: return str(n["plan"]["npc"]["name"]))
	if not (content["place"] as Dictionary).is_empty():
		brings.append_array((content["place"]["place"]["rooms"] as Array).map(func(r: Dictionary) -> String: return str(r["name"])))
	if not (content["item"] as Dictionary).is_empty():
		brings.append(str(content["item"]["name"]))
	var from := "своё дело" if own else ("заказ на доске, заказчик %s" % who) if not board.is_empty() else "от %s" % who
	return {"plan": {"quest": q, "content": content}, "summary": "Новое задание: «%s» — %s (%s)%s" % [q["title"],
		from, sc["name"], ("; с ним: " + ", ".join(brings)) if not brings.is_empty() else ""]}


## A giver's name: of the world, or of a person the quest brings («new:<key>»).
static func _name(data: Dictionary, giver: String, content: Dictionary) -> String:
	if giver.begins_with("new:"):
		for n: Dictionary in content.get("npcs", []):
			if "new:" + str(n["key"]) == giver:
				return str(n["plan"]["npc"]["name"])
	return str(WorldView.new(data["world"]).npc(giver).get("name", giver))


## What the quest brings: {npcs: [{key, plan, room}], npc_keys, place: plan of create_place | {}, room_keys,
## item: {id, def, room, text, dc, name} | {}} or {reason}. `depth` — of the people it makes.
static func _plan_content(s: GameSession, data: Dictionary, spec: Dictionary, depth: int) -> Dictionary:
	var c := cfg(data)
	var out := {"npcs": [], "npc_keys": [], "place": {}, "room_keys": [], "item": {}}
	if spec.get("new_place") is Dictionary:
		var p := WorldGen.plan_place(s, data, spec["new_place"], true)
		if p.has("reason"):
			return {"reason": "место задания: %s" % p["reason"]}
		out["place"] = p["plan"]
		out["room_keys"] = (p["plan"]["place"]["rooms"] as Array).map(func(r: Dictionary) -> String: return str(r["key"]))
	var npcs: Array = spec.get("new_npcs", []) if spec.get("new_npcs") is Array else []
	if npcs.size() > int(c["max_new_npcs"]):
		return {"reason": "новых людей в задании — не больше %d" % int(c["max_new_npcs"])}
	for n: Variant in npcs:
		if not (n is Dictionary):
			return {"reason": "новый человек — объект схемы NPC с key"}
		var key := str(n.get("key", ""))
		if key.is_empty() or (out["npc_keys"] as Array).has(key) or (out["room_keys"] as Array).has(key):
			return {"reason": "у каждого нового человека свой key"}
		(out["npc_keys"] as Array).append(key)
		var spec_n := (n as Dictionary).duplicate(true)
		var room := str(spec_n.get("room_id", "")) if spec_n.get("room_id") != null else ""
		if room.begins_with("new:"):
			if not (out["room_keys"] as Array).has(room.trim_prefix("new:")):
				return {"reason": "человек %s: нет комнаты %s в новом месте задания" % [key, room]}
			spec_n.erase("room_id")  # checked here, put into the new room when it is made
		var p := WorldGen.plan_npc(s, data, spec_n, true)
		if p.has("reason"):
			return {"reason": "человек задания %s: %s" % [key, p["reason"]]}
		p["plan"]["npc"]["quest_depth"] = depth
		(out["npcs"] as Array).append({"key": key, "plan": p["plan"], "room": room if room.begins_with("new:") else str(p["plan"]["room"])})
	if spec.get("quest_item") is Dictionary:
		var qi: Dictionary = spec["quest_item"]
		var id := str(qi.get("item_id", "")) if qi.get("item_id") != null else ""
		var def := {}
		if qi.get("item") is Dictionary:
			var chk := ItemRules.check_generated(data["items"], qi["item"], int(s.character.get("level", 1)), data.get("spells", {}))
			if not bool(chk["ok"]):
				return {"reason": "вещь задания: %s" % chk["reason"]}
			def = chk["def"]
			id = ItemRules.generated_id(def)
		elif ItemRules.def_of(data["items"], s.items, id).is_empty():
			return {"reason": "вещь задания: нет предмета %s — find_items или новая `item`" % id}
		var room := str(qi.get("room", ""))
		if room.begins_with("new:"):
			if not (out["room_keys"] as Array).has(room.trim_prefix("new:")):
				return {"reason": "вещь задания: нет комнаты %s в новом месте" % room}
		elif not data["world"]["rooms"].has(room):
			return {"reason": "вещь задания: нет места %s (find_places)" % room}
		var tier := str(qi.get("dc_tier", "medium"))
		if not (data["rules"]["dc_tiers"] as Dictionary).has(tier) or str(qi.get("hint", "")).length() < 5:
			return {"reason": "вещь задания: hint (где она спрятана, по-русски) и dc_tier из %s" % ", ".join((data["rules"]["dc_tiers"] as Dictionary).keys())}
		out["item"] = {"id": id, "def": def, "room": room, "text": str(qi["hint"]).left(240), "dc": int(data["rules"]["dc_tiers"][tier]),
			"name": str((def if not def.is_empty() else ItemRules.def_of(data["items"], s.items, id)).get("name", id))}
	return out


## One step of the master's spec as a pack step: {text, when, action?, danger?} or {reason}.
static func _step(s: GameSession, data: Dictionary, r: Dictionary, content: Dictionary) -> Dictionary:
	var world := WorldView.new(data["world"])
	var text := str(r.get("text", "")).strip_edges().left(120)
	var target := str(r.get("target", ""))
	if text.length() < 3:
		return {"reason": "у шага нужен текст"}
	var st := {"text": text}
	if bool(r.get("danger", false)):
		st["danger"] = true
	var item_ref := str(r.get("item_id", "")) if r.get("item_id") != null else ""
	if target.begins_with("new:") or target == "item" or item_ref == "item":  # what the quest brings (batch 2)
		return _new_step(st, r, target, item_ref, content)
	match str(r.get("kind", "")):
		"talk":
			if not data["world"]["npcs"].has(target) or s.dead_npcs.has(target):
				return {"reason": "шаг «%s»: нет живого NPC %s (find_npcs)" % [text, target]}
			st["when"] = {"talk": target}
			if not item_ref.is_empty():
				if not data["items"]["catalog"].has(item_ref):
					return {"reason": "шаг «%s»: вещь %s — id каталога (find_items)" % [text, item_ref]}
				st["when"]["item"] = item_ref
				st["action"] = "Отдать %s: %s" % [world.npc(target).get("name", target), ItemRules.display_name(data["items"], s.items, item_ref)]
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
				return {"reason": "шаг «%s»: нет тайны %s — «комната:id тайны» или item" % [text, target]}
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


## A step on what the quest brings: its `when` keeps refs (`new:<key>`, `item`) that `apply_quest` turns into ids.
static func _new_step(st: Dictionary, r: Dictionary, target: String, item_ref: String, content: Dictionary) -> Dictionary:
	var key := target.trim_prefix("new:")
	var has_item := not (content.get("item", {}) as Dictionary).is_empty()
	if item_ref == "item" and not has_item:
		return {"reason": "шаг «%s»: вещи задания нет (quest_item)" % st["text"]}
	match str(r.get("kind", "")):
		"talk":
			if target.begins_with("new:") and not (content.get("npc_keys", []) as Array).has(key):
				return {"reason": "шаг «%s»: нет нового человека %s" % [st["text"], target]}
			st["when"] = {"talk": target}
			if not item_ref.is_empty():
				st["when"]["item"] = item_ref
		"visit":
			if not (content.get("room_keys", []) as Array).has(key):
				return {"reason": "шаг «%s»: нет комнаты %s в новом месте" % [st["text"], target]}
			st["when"] = {"room": target}
		"fight":
			var rooms: Array = content.get("place", {}).get("place", {}).get("rooms", [])
			if not rooms.any(func(rm: Dictionary) -> bool: return str(rm["key"]) == key and not (rm["encounter"] as Dictionary).is_empty()):
				return {"reason": "шаг «%s»: в комнате %s нового места нет встречи" % [st["text"], target]}
			st["when"] = {"encounter": target}
			st["danger"] = true
		"find":
			if target != "item" or not has_item:
				return {"reason": "шаг «%s»: найти можно вещь задания (target item) или тайну мира «комната:id»" % st["text"]}
			st["when"] = {"secret": "item"}
		_:
			return {"reason": "вид шага — talk, visit, find или fight"}
	return st


## Makes the quest with what it brings: in the save and in this game's world; offered by its giver at once. Its id.
static func apply_quest(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var id := "gen_quest_%d" % _next_n(data)
	var refs := _apply_content(s, data, plan.get("content", {}), id)
	var q: Dictionary = (plan["quest"] as Dictionary).duplicate(true)
	if refs.has(str(q["giver"])):  # the customer the order brings
		q["giver"] = refs[str(q["giver"])]
	for st: Dictionary in q["steps"]:
		if st.has("attitude"):
			var att := {}
			for k: String in st["attitude"]:
				att[str(refs.get(k, k))] = st["attitude"][k]
			st["attitude"] = att
		var w: Dictionary = st["when"]
		if w.has("encounter") and refs.has("enc:" + str(w["encounter"])):
			w["encounter"] = refs["enc:" + str(w["encounter"])]
		if w.has("secret") and str(w["secret"]) == "item":
			w["secret"] = refs["secret:item"]
		for k: String in ["talk", "room", "item"]:
			if w.has(k) and refs.has(str(w[k])):
				w[k] = refs[str(w[k])]
		if w.has("talk") and not st.has("action"):
			var who := str(WorldView.new(data["world"]).npc(str(w["talk"])).get("name", w["talk"]))
			st["action"] = ("Отдать %s: %s" % [who, ItemRules.display_name(data["items"], s.items, str(w["item"]))]) if w.has("item") else "Поговорить: %s" % who
	var gen := WorldGen.generated(s)
	if not gen.has("quests"):
		gen["quests"] = {}
	gen["quests"][id] = q.duplicate(true)
	if not data["world"].has("quests"):
		data["world"]["quests"] = {}
	data["world"]["quests"][id] = q
	return id


static func _next_n(data: Dictionary) -> int:
	var n := 1
	while data["world"].get("quests", {}).has("gen_quest_%d" % n):
		n += 1
	return n


## Makes what the quest brings, in the order it depends on (the place, its people, the hidden thing). Refs to ids:
## "new:<key>" — a room or an NPC, "enc:<room key>" — the encounter of that room, "item" — the thing,
## "secret:item" — «room:secret» of its hiding place.
static func _apply_content(s: GameSession, data: Dictionary, content: Dictionary, quest_id: String) -> Dictionary:
	var refs := {}
	if content.is_empty():
		return refs
	var gen := WorldGen.generated(s)
	if not (content["place"] as Dictionary).is_empty():
		var before: Array = (gen.get("rooms", {}) as Dictionary).keys()
		WorldGen.apply_place(s, data, content["place"])
		var made: Array = (gen["rooms"] as Dictionary).keys().filter(func(r: String) -> bool: return not before.has(r))
		for i in made.size():
			var key := str(content["room_keys"][i])
			refs["new:" + key] = made[i]
			var enc: Dictionary = gen["rooms"][made[i]].get("encounter", {})
			if not enc.is_empty():
				refs["enc:new:" + key] = str(enc["id"])
	for n: Dictionary in content["npcs"]:
		var room := str(refs.get(str(n["room"]), n["room"]))
		refs["new:" + str(n["key"])] = WorldGen.apply_npc(s, data, {"npc": n["plan"]["npc"], "room": room})
	var it: Dictionary = content["item"]
	if not it.is_empty():
		if not (it["def"] as Dictionary).is_empty():
			s.items[str(it["id"])] = it["def"]
		var room := str(refs.get(str(it["room"]), it["room"]))
		var sec := {"id": "q_" + quest_id, "dc": int(it["dc"]), "text": it["text"], "skill": "perception",
			"loot": {"items": {str(it["id"]): 1}}}
		if not gen.has("room_secrets"):
			gen["room_secrets"] = {}
		var list: Array = gen["room_secrets"].get(room, [])
		list.append(sec)
		gen["room_secrets"][room] = list
		var secrets: Array = data["world"]["rooms"][room].get("secrets", [])
		secrets.append(sec.duplicate(true))
		data["world"]["rooms"][room]["secrets"] = secrets
		refs["item"] = str(it["id"])
		refs["secret:item"] = "%s:%s" % [room, sec["id"]]
	return refs
