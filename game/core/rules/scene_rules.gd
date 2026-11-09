class_name SceneRules
extends RefCounted
## The room as the world is now (roadmap v0.7.14.1): a pack room may carry `variants` [{when (Cond),
## description?, npcs?, hooks?, encounter?, safe?}] — every variant whose flag condition holds overrides those keys,
## in order. The menhir's choice darkens or lights the Pushcha this way, and whoever left a room is gone from it.
## v0.7.39.6: `when` {quest} — while that quest is taken (a quest's fight in a known room, QuestGen.apply_act).
## NPCs keep hours too (`schedule`, v0.7.14.2): the trader goes home at night, the captain drinks in the tavern.

const KEYS := ["description", "npcs", "hooks", "encounter", "safe"]
const NPC_KEYS := ["description", "personality", "role"]


## The room with the variants that hold now.
static func room(s: GameSession, world: Dictionary, room_id: String) -> Dictionary:
	return Cond.overlay(s, world["rooms"].get(room_id, {}), KEYS)


## A person of the pack as the world is now (v0.8.4.42.18): its `variants` [{when, description?, personality?, role?}] by
## the hero's deeds — the captain no longer waits for the cult the hero burned out.
static func npc(s: GameSession, world: Dictionary, npc_id: String) -> Dictionary:
	return Cond.overlay(s, WorldView.new(world).npc(npc_id), NPC_KEYS)


## The tags of the room by its variants, with those of the places above it (v0.7.66).
static func tags(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out := WorldView.new(world).tags(room_id)
	for t: Variant in room(s, world, room_id).get("tags", []):
		if not out.has(str(t)):
			out.append(str(t))
	return out


## Is the room under a roof: its variant's word, else its own or a place's above it (`indoor`).
static func indoor(s: GameSession, world: Dictionary, room_id: String) -> bool:
	return bool(room(s, world, room_id).get("indoor", WorldView.new(world).flag(room_id, "indoor")))


## The pack NPCs standing in the room now (alive or not): the room's people (by its variants), minus those whose
## `schedule` sends them elsewhere at this hour, plus those it sends here (v0.7.14.2); those who go with the hero stand
## where the hero is, those left in a room stand there (v0.7.20.3, FollowRules).
static func npcs(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = world.get("npcs", {})
	for n: Variant in room(s, world, room_id).get("npcs", []):
		var at: Variant = scheduled(s, world, str(n))
		var guest := CalendarRules.guest_room(s, world, str(n))  # a festival's guest stands there, not at home (v0.8.4.29.5)
		if (at == null or str(at) == room_id) and not FollowRules.placed(s, str(n)) and (guest.is_empty() or guest == room_id):
			out.append(str(n))
	for id: String in all:
		if (all[id].has("schedule") or FamilyRules.home_at(s, id) != null) and not out.has(id) and not FollowRules.placed(s, id) and str(scheduled(s, world, id)) == room_id:
			out.append(id)
	for id: String in Being.with(s, "at"):
		if str(Being.of(s, id)["at"]) == room_id and all.has(id) and not out.has(id):
			out.append(id)
	for id: String in CalendarRules.guests(s, world, room_id):  # v0.7.44: a festival's guests
		if all.has(id) and not out.has(id) and not FollowRules.placed(s, id):
			out.append(id)
	if room_id == s.room_id:
		for id: String in Being.followers(s):
			if all.has(id) and not out.has(id):
				out.append(id)
	return out


## The room an NPC lives in by the rooms' variants (v0.8.4.29.5): its pack room while the room keeps it, else the room whose
## variant puts it there now; "" — none.
static func home(s: GameSession, world: Dictionary, npc_id: String) -> String:
	var raw := ReputationRules.home_room({"world": world}, npc_id)
	if not raw.is_empty() and (room(s, world, raw).get("npcs", []) as Array).has(npc_id):
		return raw
	for rid: String in world.get("rooms", {}):
		if world["rooms"][rid].has("variants") and (room(s, world, rid).get("npcs", []) as Array).has(npc_id):
			return rid
	return raw


## Where the NPC's `schedule` [{from, to, room}] (hours; to < from wraps past midnight; room "" — away, at home)
## puts it at this hour; null when no entry holds — it stands in its pack room.
static func scheduled(s: GameSession, world: Dictionary, npc_id: String) -> Variant:
	var home: Variant = FamilyRules.home_at(s, npc_id)  # v0.7.32: the spouse sleeps at the hero's home
	if home != null:
		return home
	for e: Dictionary in world.get("npcs", {}).get(npc_id, {}).get("schedule", []):
		if TimeRules.in_hours(s, int(e["from"]), int(e["to"])):
			return str(e.get("room", ""))
	return null


## The room's own living people away at this hour: «Ферн Кривой — ушёл, вернётся к 7:00» (for the master and the panel).
static func absent(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for n: Variant in room(s, world, room_id).get("npcs", []):
		var id := str(n)
		var at: Variant = scheduled(s, world, id)
		if at == null or str(at) == room_id or Being.dead(s, id) or FollowRules.placed(s, id):
			continue
		var back := 0
		if FamilyRules.home_at(s, id) != null:
			out.append("%s — дома, вернётся к %d:00" % [world["npcs"][id].get("name", id), int(FamilyRules.view(s.character).get("hours", [20, 7])[1])])
			continue
		for e: Dictionary in world["npcs"][id].get("schedule", []):
			if TimeRules.in_hours(s, int(e["from"]), int(e["to"])):
				back = int(e["to"])
		out.append("%s — %s, вернётся к %d:00" % [world["npcs"][id].get("name", id),
			("ушла домой" if str(world["npcs"][id].get("gender", "")) == "female" else "ушёл домой") if str(at).is_empty() else "сейчас в другом месте", back])
	return out
