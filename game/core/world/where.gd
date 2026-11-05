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
	if Being.view(s, npc_id).has("body"):
		return room(str(Being.of(s, npc_id)["body"]))
	if Being.follows(s, npc_id):
		return room(s.room_id)
	if Being.view(s, npc_id).has("at"):
		return room(str(Being.of(s, npc_id)["at"])) if not str(Being.of(s, npc_id)["at"]).is_empty() else {"road": true}
	var guest := CalendarRules.guest_room(s, data["world"], npc_id)  # v0.8.4.29.5: a festival's guest, as the room's people say
	if not guest.is_empty():
		return room(guest)
	var at: Variant = SceneRules.scheduled(s, data["world"], npc_id)
	if at != null:
		return room(str(at))
	var home := SceneRules.home(s, data["world"], npc_id)  # by the rooms' variants
	if home.is_empty() and FamilyRules.household(s, data).any(func(h: Dictionary) -> bool: return str(h.get("npc", "")) == npc_id):
		home = str(FamilyRules.view(s.character).get("home_room", ""))  # one of the hero's family with no pack room
	return room(home)


## The room an NPC stands in now (v0.8.4.16: the one answer, not a search of the pack's rooms); "" — on the road.
static func npc_room(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return room_of(s, data, of_npc(s, data, npc_id))


## The location an NPC stands in now; "" — on the road.
static func npc_location(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var r := npc_room(s, data, npc_id)
	return WorldView.new(data["world"]).location_id(r) if not r.is_empty() else ""


## The pack people of a location (v0.8.4.29.5, one list for the law, the bonds, the offices): who lives there — moved or at
## home by the rooms' variants — and is alive.
static func people_of(s: GameSession, data: Dictionary, loc: String) -> Array[String]:
	var out: Array[String] = []
	var w := WorldView.new(data["world"])
	for n: String in data["world"].get("npcs", {}):
		var r := base_room(s, data, n)
		if not r.is_empty() and w.location_id(r) == loc and not Being.dead(s, n):
			out.append(n)
	return out


## The room to look for an NPC in, whatever the hour: moved or at home. "" — on the road.
static func base_room(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return str(Being.view(s, npc_id).get("at", SceneRules.home(s, data["world"], npc_id)))


## The room of a position: what carries a thing leads to it; "" — in no room.
static func room_of(s: GameSession, data: Dictionary, at: Dictionary) -> String:
	if at.has("room"):
		return str(at["room"])
	for key: String in ["in", "hand", "saddle", "cart"]:
		if at.has(key):
			return room_of(s, data, of(s, data, str(at[key])))
	return ""
