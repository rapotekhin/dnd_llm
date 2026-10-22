class_name FollowRules
extends RefCounted
## NPCs who go with the hero (roadmap v0.7.20.3): talked into it by words, an NPC follows the hero from room to room
## (`s.followers`) and stands wherever the hero is; told to stay, it stays in that room (`s.npc_at`), or goes back
## home (its pack room and hours). The effect `npc_follow` — the engine allows it to one well disposed to the hero
## (attitude ≥ rules.followers.min_attitude) or won over by a check this turn; at most rules.followers.max at once.


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
	if bool(plan["on"]):
		s.followers.append(id)
	elif not str(plan["room"]).is_empty():
		s.npc_at[id] = str(plan["room"])
