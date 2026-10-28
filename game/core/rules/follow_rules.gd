class_name FollowRules
extends RefCounted
## NPCs who go with the hero (roadmap v0.7.20.3): talked into it by words, an NPC follows the hero from room to room
## (`s.followers`) and stands wherever the hero is; told to stay, it stays in that room (`s.npc_at`), or goes back
## home (its pack room and hours). The effect `npc_follow` — the engine allows it to one well disposed to the hero
## (attitude ≥ rules.followers.min_attitude) or won over by a check this turn; at most rules.followers.max at once.
## With the needs on a follower eats once a day from the hero's things (v0.7.39.1, `meals`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["followers"]


## Whether the NPC stands somewhere other than its pack room and hours: it follows the hero or was left in a room.
static func placed(s: GameSession, npc_id: String) -> bool:
	return s.followers.has(npc_id) or s.npc_at.has(npc_id)


## Checks an `npc_follow`: {plan, summary} or {reason}. `won` — the hero won it over by a check this turn.
static func plan(s: GameSession, data: Dictionary, npc_id: String, follow: bool, home: bool, won: bool) -> Dictionary:
	var world := WorldView.new(data["world"])
	var name := str(world.npc(npc_id).get("name", npc_id))
	if not s.npcs_here(data["world"], s.room_id).has(npc_id):
		return {"reason": "NPC %s нет в этой комнате" % npc_id}
	if not follow:
		if not placed(s, npc_id):
			return {"reason": "%s и так на своём месте — с героем не идёт" % name}
		return {"plan": {"follow_npc": npc_id, "on": false, "room": "" if home else s.room_id},
			"summary": "%s %s" % [name, "уходит к себе" if home else "остаётся здесь"]}
	if s.followers.has(npc_id):
		return {"reason": "%s уже идёт с героем" % name}
	if SocialRules.refuses(s, data, npc_id):
		return {"reason": "%s враждебен герою и с ним не пойдёт" % name}
	var need := int(cfg(data)["min_attitude"])
	if s.attitude(npc_id) < need and not won:
		return {"reason": "%s не пойдёт с героем: нужно отношение от %+d или успешная проверка (убеждение, обман, запугивание) с его target_id в этом ходе" % [name, need]}
	if s.followers.size() >= int(cfg(data)["max"]):
		return {"reason": "с героем уже идут %d — больше никто" % s.followers.size()}
	return {"plan": {"follow_npc": npc_id, "on": true, "room": ""}, "summary": "%s идёт с героем" % name}


static func apply(s: GameSession, plan: Dictionary) -> void:
	var id := str(plan["follow_npc"])
	s.followers.erase(id)
	s.npc_at.erase(id)
	s.follower_fed.erase(id)
	if bool(plan["on"]):
		s.followers.append(id)
		s.follower_fed[id] = {"at": TimeRules.abs_minute(s), "hungry": 0}  # it comes fed
	elif not str(plan["room"]).is_empty():
		s.npc_at[id] = str(plan["room"])


# --- meals (v0.7.39.1) --------------------------------------------------------------------------------------------


## Followers eat (the author: from the hero's things, as «Поесть» and the camp's food; no button): a day after its
## last meal a follower eats one portion — what spoils first, the cheapest, foul food last. Nothing to eat — its
## attitude drops by one; after rules.followers.hungry_days such days it goes home. Lines.
static func meals(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not NeedRules.on(s) or not data["rules"].has("needs"):
		return lines
	var now := TimeRules.abs_minute(s)
	var world := WorldView.new(data["world"])
	for id: String in s.followers.duplicate():
		if not s.follower_fed.has(id):
			s.follower_fed[id] = {"at": now, "hungry": 0}
		var rec: Dictionary = s.follower_fed[id]
		var name := str(world.npc(id).get("name", JobRules.npc_name(s, data, id)))
		while now - int(rec["at"]) >= 1440 and s.followers.has(id):
			var food := _portion(s, data)
			if not food.is_empty():
				NeedRules._take(s.character, food)
				rec["at"] = now
				rec["hungry"] = 0
				lines.append("%s поел: %s" % [name, ItemRules.display_name(data["items"], s.items, food)])
				break
			rec["at"] = int(rec["at"]) + 1440
			rec["hungry"] = int(rec["hungry"]) + 1
			s.shift_attitude(id, -1, data)
			if int(rec["hungry"]) >= int(cfg(data).get("hungry_days", 2)):
				apply(s, {"follow_npc": id, "on": false, "room": ""})
				lines.append("%s ушёл домой: %d дня без еды" % [name, int(rec["hungry"])])
			else:
				lines.append("%s голоден — у героя нечем поделиться" % name)
	return lines


## The portion a follower eats: of the hero's food, what spoils first and is cheapest; foul food last.
static func _portion(s: GameSession, data: Dictionary) -> String:
	var have := NeedRules.food_items(s.character, data)
	if have.is_empty():
		return ""
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	var ids: Array = have.keys()
	var key := func(id: Variant) -> int:
		return int(foul.has(id)) * 1000 + int(FoodRules.spoils_days(data, s.items, str(id)) <= 0) * 100 + int(have[id])
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return key.call(a) < key.call(b))
	return str(ids[0])


## A long rest fed and watered the followers with the hero (the author's answer): their day starts again.
static func rested(s: GameSession) -> void:
	for id: String in s.followers:
		s.follower_fed[id] = {"at": TimeRules.abs_minute(s), "hungry": 0}
