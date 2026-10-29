class_name SceneRules
extends RefCounted
## The room as the world is now (roadmap v0.7.14.1): a pack room may carry `variants` [{if_flag | if_not_flag,
## description?, npcs?, hooks?, encounter?, safe?}] — every variant whose flag condition holds overrides those keys,
## in order. The menhir's choice darkens or lights the Pushcha this way, and whoever left a room is gone from it.
## v0.7.39.6: `if_quest` — while that quest is taken (a quest's fight in a known room, QuestGen.apply_act).
## NPCs keep hours too (`schedule`, v0.7.14.2): the trader goes home at night, the captain drinks in the tavern.

const KEYS := ["description", "npcs", "hooks", "encounter", "safe"]


static func matches(s: GameSession, v: Dictionary) -> bool:
	if v.has("if_flag") and not s.flags.has(str(v["if_flag"])):
		return false
	if v.has("if_not_flag") and s.flags.has(str(v["if_not_flag"])):
		return false
	if v.has("if_quest") and not s.quests_active.has(str(v["if_quest"])):
		return false
	return true


## The room with the variants that hold now.
static func room(s: GameSession, world: Dictionary, room_id: String) -> Dictionary:
	var base: Dictionary = world["rooms"].get(room_id, {})
	if not base.has("variants") or s == null:
		return base
	var out := base.duplicate()
	for v: Dictionary in base["variants"]:
		if matches(s, v):
			for k: String in KEYS:
				if v.has(k):
					out[k] = v[k]
	return out


## The pack NPCs standing in the room now (alive or not): the room's people (by its variants), minus those whose
## `schedule` sends them elsewhere at this hour, plus those it sends here (v0.7.14.2); those who go with the hero stand
## where the hero is, those left in a room stand there (v0.7.20.3, FollowRules).
static func npcs(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = world.get("npcs", {})
	for n: Variant in room(s, world, room_id).get("npcs", []):
		var at: Variant = scheduled(s, world, str(n))
		if (at == null or str(at) == room_id) and not FollowRules.placed(s, str(n)):
			out.append(str(n))
	for id: String in all:
		if (all[id].has("schedule") or FamilyRules.home_at(s, id) != null) and not out.has(id) and not FollowRules.placed(s, id) and str(scheduled(s, world, id)) == room_id:
			out.append(id)
	for id: String in s.npc_at:
		if str(s.npc_at[id]) == room_id and all.has(id) and not out.has(id):
			out.append(id)
	if room_id == s.room_id:
		for id: String in s.followers:
			if all.has(id) and not out.has(id):
				out.append(id)
	return out


## Where the NPC's `schedule` [{from, to, room}] (hours; to < from wraps past midnight; room "" — away, at home)
## puts it at this hour; null when no entry holds — it stands in its pack room.
static func scheduled(s: GameSession, world: Dictionary, npc_id: String) -> Variant:
	var home: Variant = FamilyRules.home_at(s, npc_id)  # v0.7.32: the spouse sleeps at the hero's home
	if home != null:
		return home
	var hour := s.minute / 60
	for e: Dictionary in world.get("npcs", {}).get(npc_id, {}).get("schedule", []):
		var a := int(e["from"])
		var b := int(e["to"])
		if (a <= b and hour >= a and hour < b) or (a > b and (hour >= a or hour < b)):
			return str(e.get("room", ""))
	return null


## The room's own living people away at this hour: «Ферн Кривой — ушёл, вернётся к 7:00» (for the master and the panel).
static func absent(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for n: Variant in room(s, world, room_id).get("npcs", []):
		var id := str(n)
		var at: Variant = scheduled(s, world, id)
		if at == null or str(at) == room_id or s.dead_npcs.has(id) or FollowRules.placed(s, id):
			continue
		var back := 0
		if FamilyRules.home_at(s, id) != null:
			out.append("%s — дома, вернётся к %d:00" % [world["npcs"][id].get("name", id), int(FamilyRules.view(s.character).get("hours", [20, 7])[1])])
			continue
		for e: Dictionary in world["npcs"][id].get("schedule", []):
			var a := int(e["from"])
			var b := int(e["to"])
			var hour := s.minute / 60
			if (a <= b and hour >= a and hour < b) or (a > b and (hour >= a or hour < b)):
				back = b
		out.append("%s — %s, вернётся к %d:00" % [world["npcs"][id].get("name", id),
			("ушла домой" if str(world["npcs"][id].get("gender", "")) == "female" else "ушёл домой") if str(at).is_empty() else "сейчас в другом месте", back])
	return out
