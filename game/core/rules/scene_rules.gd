class_name SceneRules
extends RefCounted
## The room as the world is now (roadmap v0.7.14.1): a pack room may carry `variants` [{if_flag | if_not_flag,
## description?, npcs?, hooks?, encounter?, safe?}] — every variant whose flag condition holds overrides those keys,
## in order. The menhir's choice darkens or lights the Pushcha this way, and whoever left a room is gone from it.

const KEYS := ["description", "npcs", "hooks", "encounter", "safe"]


static func matches(s: GameSession, v: Dictionary) -> bool:
	if v.has("if_flag") and not s.flags.has(str(v["if_flag"])):
		return false
	if v.has("if_not_flag") and s.flags.has(str(v["if_not_flag"])):
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


## The pack NPCs standing in the room now (alive or not).
static func npcs(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for n: Variant in room(s, world, room_id).get("npcs", []):
		out.append(str(n))
	return out
