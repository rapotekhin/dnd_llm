class_name ExplorationRules
extends RefCounted
## Exploration rules of the engine (ADR-0008 §2, ADR-0010 §6, roadmap v0.5.2):
## - a failed skill check is locked by «skill + target» (the room when no target) until a long rest; a repeat
##   returns the old result without a roll, unless the situation changed — a new source of advantage;
## - hidden things of a room (world.json `secrets`: id, dc, text, skill perception | investigation) are noticed
##   by passive Perception on entering, or found by a successful search check with total ≥ DC (Investigation
##   finds any secret, Perception only the perception ones);
##   the master sees only what was noticed or found;
## - a long rest in a safe room (`safe.rest_cost_cp`) restores HP, spell slots and half the hit dice, clears
##   the locks and starts a new day.

const SEARCH_SKILLS: Array[String] = ["perception", "investigation"]


static func lock_key(params: Dictionary, room_id: String) -> String:
	var target := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	return "%s|%s" % [params.get("skill", ""), target if not target.is_empty() else room_id]


## The lock for these check params, or {} when the check may be rolled.
static func locked(s: GameSession, params: Dictionary, room_id: String) -> Dictionary:
	if params.get("skill") == null or str(params.get("skill", "")).is_empty():
		return {}
	var lock: Dictionary = s.locks.get(lock_key(params, room_id), {})
	if lock.is_empty():
		return {}
	var adv := str(params.get("advantage_reason", "")) if params.get("advantage_reason") != null else ""
	if not adv.is_empty() and not (lock.get("advantages", []) as Array).has(adv):
		return {}  # a new source of advantage changes the situation
	return lock


## Remembers a failed skill check (with the advantage it already used).
static func lock(s: GameSession, params: Dictionary, room_id: String, result: Dictionary) -> void:
	if params.get("skill") == null or bool(result.get("success", false)):
		return
	var key := lock_key(params, room_id)
	var prev: Dictionary = s.locks.get(key, {})
	var advantages: Array = (prev.get("advantages", []) as Array).duplicate()
	if params.get("advantage_reason") != null and not str(params["advantage_reason"]).is_empty():
		advantages.append(str(params["advantage_reason"]))
	var kept := result.duplicate()
	kept.erase("revealed")
	s.locks[key] = {"result": kept, "advantages": advantages}


static func secrets(world: Dictionary, room_id: String) -> Array:
	return world["rooms"].get(room_id, {}).get("secrets", [])


static func _reveal(s: GameSession, room_id: String, secret: Dictionary) -> bool:
	var ids: Array = s.revealed.get(room_id, [])
	if ids.has(secret["id"]):
		return false
	ids.append(str(secret["id"]))
	s.revealed[room_id] = ids
	return true


## Moves the player into `room_id`: visited, passive Perception against the room's perception secrets.
## Returns the texts noticed just now.
static func enter_room(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	s.room_id = room_id
	if not s.visited.has(room_id):
		s.visited.append(room_id)
	var out: Array[String] = []
	var passive := int(s.character.get("passive_perception", 10))
	for sec: Dictionary in secrets(world, room_id):
		if str(sec.get("skill", "perception")) == "perception" and passive >= int(sec["dc"]) and _reveal(s, room_id, sec):
			out.append(str(sec["text"]))
	return out


## A successful search check finds the room's secrets with DC ≤ total: Perception finds what can be noticed,
## Investigation (a thorough search) finds that too and also mechanisms and caches. Returns their texts.
static func active_reveal(s: GameSession, world: Dictionary, skill: String, total: int) -> Array[String]:
	var out: Array[String] = []
	if not SEARCH_SKILLS.has(skill):
		return out
	for sec: Dictionary in secrets(world, s.room_id):
		var needs := str(sec.get("skill", "perception"))
		if (needs == skill or skill == "investigation") and total >= int(sec["dc"]) and _reveal(s, s.room_id, sec):
			out.append(str(sec["text"]))
	return out


## What the player already noticed or found in a room (for the snapshot and the journal).
static func found_texts(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = s.revealed.get(room_id, [])
	for sec: Dictionary in secrets(world, room_id):
		if ids.has(sec["id"]):
			out.append(str(sec["text"]))
	return out


## {"cost_cp": n} when a long rest is possible in this room, {} otherwise.
static func rest_place(world: Dictionary, room_id: String) -> Dictionary:
	var safe: Variant = world["rooms"].get(room_id, {}).get("safe")
	if not (safe is Dictionary):
		return {}
	return {"cost_cp": int(safe.get("rest_cost_cp", 0))}


## "" when the character can take a long rest here now, otherwise a localization key.
static func can_rest(s: GameSession, world: Dictionary) -> String:
	var place := rest_place(world, s.room_id)
	if place.is_empty():
		return "REST_NOT_SAFE"
	if s.in_conversation():
		return "REST_IN_CONVERSATION"
	if int(s.character.get("gold_cp", 0)) < int(place["cost_cp"]):
		return "REST_NO_MONEY"
	return ""


## Applies a long rest; returns the effect lines for the chat. Call can_rest first.
static func long_rest(s: GameSession, world: Dictionary) -> Array[String]:
	var c := s.character
	var cost := int(rest_place(world, s.room_id).get("cost_cp", 0))
	var lines: Array[String] = ["Долгий отдых"]
	if cost > 0:
		c["gold_cp"] = int(c["gold_cp"]) - cost
		lines.append("−" + Money.format(cost))
	c["hp"] = int(c.get("max_hp", c.get("hp", 1)))
	lines.append("HP %d/%d" % [c["hp"], c["max_hp"]])
	c["slots_used"] = [0, 0, 0, 0, 0]
	var level := int(c.get("level", 1))
	c["hit_dice_used"] = maxi(0, int(c.get("hit_dice_used", 0)) - maxi(1, level / 2))
	if not s.locks.is_empty():
		lines.append("можно снова пробовать проваленное")
	s.locks.clear()
	s.day += 1
	return lines
