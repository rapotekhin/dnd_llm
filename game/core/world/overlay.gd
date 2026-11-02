class_name Overlay
extends RefCounted
## A template and what this game changed in it (v0.7.60.1, ADR-0012): the pack stays as it is, the save holds the
## differences `s.generated["overlay"]` {ref: {field: value}}, and the game's copy of the world carries them too. A record
## made in this game (by the master or the engine) is its own template: a change goes into it (v0.8.4.18).

const _BUCKETS := {EntityRef.NPC: "npcs", EntityRef.ROOM: "rooms", EntityRef.SITE: "sites", EntityRef.LOCATION: "locations"}


## The record of `ref` in a world; empty when there is none.
static func target(world: Dictionary, ref: String) -> Dictionary:
	return world.get(str(_BUCKETS.get(EntityRef.kind_of(ref), "")), {}).get(EntityRef.id_of(ref), {})


## Changes one field of `ref` for this game: in the save and in the world being played.
static func put(s: GameSession, data: Dictionary, ref: String, key: String, value: Variant) -> void:
	var gen := WorldGen.generated(s)
	var made: Dictionary = gen.get(str(_BUCKETS.get(EntityRef.kind_of(ref), "")), {}).get(EntityRef.id_of(ref), {})
	if not made.is_empty():
		made[key] = _copy(value)
	else:
		if not gen.has("overlay"):
			gen["overlay"] = {}
		var changed: Dictionary = gen["overlay"].get(ref, {})
		changed[key] = _copy(value)
		gen["overlay"][ref] = changed
	target(data["world"], ref)[key] = _copy(value)


## One more entry in a list field of `ref` (a room's secret, a variant) for this game.
static func add(s: GameSession, data: Dictionary, ref: String, key: String, item: Variant) -> void:
	var list: Array = (target(data["world"], ref).get(key, []) as Array).duplicate(true)
	list.append(_copy(item))
	put(s, data, ref, key, list)


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


## What this game changed in `ref`.
static func of(gen: Dictionary, ref: String) -> Dictionary:
	return gen.get("overlay", {}).get(ref, {})


## Lays the differences over a world: made records are merged before it.
static func apply(world: Dictionary, gen: Dictionary) -> void:
	for ref: String in gen.get("overlay", {}):
		target(world, ref).merge(gen["overlay"][ref].duplicate(true), true)
