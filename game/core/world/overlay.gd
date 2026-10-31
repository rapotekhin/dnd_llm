class_name Overlay
extends RefCounted
## A template and what this game changed in it (v0.7.60.1, ADR-0012): the pack stays as it is, the save holds the
## differences `s.generated["overlay"]` {ref: {field: value}}, and the game's copy of the world carries them too.

const _BUCKETS := {EntityRef.NPC: "npcs", EntityRef.ROOM: "rooms", EntityRef.SITE: "sites", EntityRef.LOCATION: "locations"}


## The record of `ref` in a world; empty when there is none.
static func target(world: Dictionary, ref: String) -> Dictionary:
	return world.get(str(_BUCKETS.get(EntityRef.kind_of(ref), "")), {}).get(EntityRef.id_of(ref), {})


## Changes one field of `ref` for this game: in the save and in the world being played.
static func put(s: GameSession, data: Dictionary, ref: String, key: String, value: Variant) -> void:
	var gen := WorldGen.generated(s)
	if not gen.has("overlay"):
		gen["overlay"] = {}
	var changed: Dictionary = gen["overlay"].get(ref, {})
	changed[key] = value
	gen["overlay"][ref] = changed
	target(data["world"], ref)[key] = value.duplicate(true) if value is Array or value is Dictionary else value


## What this game changed in `ref`.
static func of(gen: Dictionary, ref: String) -> Dictionary:
	return gen.get("overlay", {}).get(ref, {})


## Lays the differences over a world: made records are merged before it.
static func apply(world: Dictionary, gen: Dictionary) -> void:
	for ref: String in gen.get("overlay", {}):
		target(world, ref).merge(gen["overlay"][ref].duplicate(true), true)
