class_name Where
extends RefCounted
## One answer to «where is it» (v0.7.60.1, ADR-0012). A position is a small record with one of these:
## {"room": id, "cell": [x, y]} — in a room; `cell` comes with the map (v0.8.0);
## {"in": ref} — in a container; {"hand": ref, "slot": slot} — worn or held by a being;
## {"saddle": ref} — on a mount; {"cart": ref} — on a vehicle; {"road": true} — on the way, in no place of the world.
## What carries a thing is itself somewhere, so `room_of` walks up to a room.


static func room(id: String) -> Dictionary:
	return {"room": id}


static func inside(ref: String) -> Dictionary:
	return {"in": ref}


static func hand(ref: String, slot: String = "") -> Dictionary:
	return {"hand": ref, "slot": slot}


static func saddle(ref: String) -> Dictionary:
	return {"saddle": ref}


static func cart(ref: String) -> Dictionary:
	return {"cart": ref}


## The position of what `ref` names; empty when the world has no answer yet (items: v0.7.65).
static func of(s: GameSession, data: Dictionary, ref: String) -> Dictionary:
	match EntityRef.kind_of(ref):
		EntityRef.HERO:
			return room(s.room_id)
		EntityRef.ROOM:
			return room(EntityRef.id_of(ref))
		EntityRef.NPC:
			return of_npc(s, data, EntityRef.id_of(ref))
	return {}


## Where an NPC is now: a body lies, a follower walks with the hero, a moved one stands where it was left, the rest keep
## their hours in the room of their pack.
static func of_npc(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	if s.bodies.has(npc_id):
		return room(str(s.bodies[npc_id]))
	if s.followers.has(npc_id):
		return room(s.room_id)
	if s.npc_at.has(npc_id):
		return room(str(s.npc_at[npc_id])) if not str(s.npc_at[npc_id]).is_empty() else {"road": true}
	var at: Variant = SceneRules.scheduled(s, data["world"], npc_id)
	return room(str(at) if at != null else ReputationRules.home_room(data, npc_id))


## The room to look for an NPC in, whatever the hour: moved or at home. "" — on the road.
static func base_room(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return str(s.npc_at.get(npc_id, ReputationRules.home_room(data, npc_id)))


## The room of a position: what carries a thing leads to it; "" — in no room.
static func room_of(s: GameSession, data: Dictionary, at: Dictionary) -> String:
	if at.has("room"):
		return str(at["room"])
	for key: String in ["in", "hand", "saddle", "cart"]:
		if at.has(key):
			return room_of(s, data, of(s, data, str(at[key])))
	return ""
