class_name FollowRules
extends RefCounted
## NPCs who go with the hero (roadmap v0.7.20.3): talked into it by words, an NPC follows the hero from room to room
## (`s.followers`) and stands wherever the hero is; told to stay, it stays in that room (`s.npc_at`), or goes back
## home (its pack room and hours). The effect `grant:follow` — the engine allows it to one well disposed to the hero
## (attitude ≥ rules.followers.min_attitude) or won over by a check this turn; at most rules.followers.max at once.
## With the needs on a follower eats once a day from the hero's things (v0.7.39.1, `meals`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["followers"]


## Whether the NPC stands somewhere other than its pack room and hours: it follows the hero or was left in a room.
static func placed(s: GameSession, npc_id: String) -> bool:
	return Being.follows(s, npc_id) or Being.view(s, npc_id).has("at")


## Checks an `grant:follow`: {plan, summary} or {reason}. `won` — the hero won it over by a check this turn.
static func plan(s: GameSession, data: Dictionary, npc_id: String, follow: bool, home: bool, won: bool) -> Dictionary:
	var world := WorldView.new(data["world"])
	var name := str(world.npc_name(npc_id))
	if not s.npcs_here(data["world"], s.room_id).has(npc_id):
		return {"reason": "NPC %s нет в этой комнате" % npc_id}
	if not follow:
		if not placed(s, npc_id):
			return {"reason": "%s и так на своём месте — с героем не идёт" % name}
		return {"plan": {"follow_npc": npc_id, "on": false, "room": "" if home else s.room_id},
			"summary": "%s %s" % [name, "уходит к себе" if home else "остаётся здесь"]}
	if Being.follows(s, npc_id):
		return {"reason": "%s уже идёт с героем" % name}
	if SocialRules.refuses(s, data, npc_id):
		return {"reason": "%s враждебен герою и с ним не пойдёт" % name}
	var need := int(cfg(data)["min_attitude"])
	if s.attitude(npc_id) < need and not won:
		return {"reason": "%s не пойдёт с героем: нужно отношение от %+d или успешная проверка (убеждение, обман, запугивание) с его target_id в этом ходе" % [name, need]}
	if not room_why(s, data).is_empty():
		return {"reason": "с героем уже идут %d человек — больше никто" % Being.followers(s).size()}
	return {"plan": {"follow_npc": npc_id, "on": true, "room": ""}, "summary": "%s идёт с героем" % name}


## "" when one more person may go with the hero (the author, v0.8.4.19): only the people who follow count — summoned
## creatures, creatures on the hero's side and those left waiting somewhere go without a limit.
static func room_why(s: GameSession, data: Dictionary) -> String:
	return "ALLY_TOO_MANY" if Being.followers(s).size() >= int(cfg(data)["max"]) else ""


static func apply(s: GameSession, plan: Dictionary) -> void:
	var id := str(plan["follow_npc"])
	Being.unfollow(s, id)
	Being.drop(s, id, "at")
	Being.drop(s, id, "fed")
	if bool(plan["on"]):
		Being.follow(s, id)
		Being.of(s, id)["fed"] = {"at": TimeRules.abs_minute(s), "hungry": 0}  # it comes fed
	elif not str(plan["room"]).is_empty():
		Being.of(s, id)["at"] = str(plan["room"])


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
	for id: String in Being.followers(s).duplicate():
		if not Being.view(s, id).has("fed"):
			Being.of(s, id)["fed"] = {"at": now, "hungry": 0}
		var rec: Dictionary = Being.of(s, id)["fed"]
		var name := str(world.npc(id).get("name", WorldView.name_of(data, id)))
		var eat := func() -> bool:  # a portion a day: its own food first, then the hero's (v0.8.4.11)
			if not Being.follows(s, id):
				return false
			var bag := Gear.of(s, data, id)
			var food := _portion(s, data, bag)
			if food.is_empty():
				bag = s.character
				food = _portion(s, data, bag)
			if food.is_empty():
				return false
			ItemRules.remove(bag, food)
			lines.append("%s поел: %s" % [name, ItemRules.display_name(data["items"], s.items, food)])
			return true
		var missed := func() -> void:
			if not Being.follows(s, id):
				return
			s.shift_attitude(id, -1, data)
			if int(rec["hungry"]) >= int(cfg(data).get("hungry_days", 2)):
				apply(s, {"follow_npc": id, "on": false, "room": ""})
				lines.append("%s ушёл домой: %d дня без еды" % [name, int(rec["hungry"])])
			else:
				lines.append("%s голоден — у героя нечем поделиться" % name)
		NeedRules.hunger(rec, "at", now, 1440, eat, missed)  # the one hunger of anybody by the day (v0.8.4.29.4)
	return lines


## The portion a follower eats: of the hero's food, what spoils first and is cheapest; foul food last.
static func _portion(s: GameSession, data: Dictionary, c: Dictionary) -> String:
	var ids := FoodRules.portions(s, data, c)  # the hero's own order (v0.8.4.29.4)
	return "" if ids.is_empty() else str(ids[0])


## A long rest fed and watered the followers with the hero (the author's answer): their day starts again.
static func rested(s: GameSession) -> void:
	for id: String in Being.followers(s):
		Being.of(s, id)["fed"] = {"at": TimeRules.abs_minute(s), "hungry": 0}
