class_name Fact
extends RefCounted
## One record of what happened (v0.7.68): {at, room, text} and what a kind adds. The chronicle, the master's notes, an
## NPC's memory and an object's chronicle keep it; a rumour adds a weight, an origin and its `truth`. Who knows a fact is
## whose store it lies in: each has its own limit and goes with its holder, so there is no shared list with an audience
## to filter on every read. What the master may not see of a record is in HIDDEN: `told` is the only way out to it.

const HIDDEN: Array[String] = ["truth"]


static func of(s: GameSession, text: String, room: String = "") -> Dictionary:
	return {"at": TimeRules.abs_minute(s), "room": room, "text": text}


static func day(f: Dictionary) -> int:
	return TimeRules.day_of(int(f["at"]))


static func clock(f: Dictionary) -> String:
	var m := int(f["at"]) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


## The record as the master sees it.
static func told(f: Dictionary) -> Dictionary:
	var out := f.duplicate()
	for k: String in HIDDEN:
		out.erase(k)
	return out
