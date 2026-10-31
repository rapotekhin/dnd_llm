class_name Knows
extends RefCounted
## What the hero knows (v0.7.68): one store s.knows {kind: [key]} instead of a list per system. A key is an id or
## "a:b" when a thing is known within another: a secret of a room, a secret an NPC told, a taste of an NPC.

const SECRET := "secret"  # "room:secret" noticed or found
const TOLD := "told"  # "npc:secret" an NPC told
const SCOUTED := "scouted"  # a room known on the map without a visit: a pet flew over it, a tip marked it
const FENCE := "fence"  # an NPC known to buy stolen goods
const MONSTER := "monster"  # a kind of foes inspected: their numbers show on the cards
const LIKES := "likes"  # "npc:taste" learned from a gift
const DISLIKES := "dislikes"
const RUMOR := "rumor"  # a rumour heard


static func has(s: GameSession, kind: String, a: String, b: String = "") -> bool:
	return (s.knows.get(kind, []) as Array).has(_key(a, b))


## Learned: true when it is new.
static func add(s: GameSession, kind: String, a: String, b: String = "") -> bool:
	var list: Array = s.knows.get(kind, [])
	if list.has(_key(a, b)):
		return false
	list.append(_key(a, b))
	s.knows[kind] = list
	return true


## Everything known of a kind, in the order learned.
static func all(s: GameSession, kind: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(s.knows.get(kind, []))
	return out


## What is known within `a`: the secrets found in a room, the tastes of an NPC.
static func under(s: GameSession, kind: String, a: String) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in s.knows.get(kind, []):
		if str(k).begins_with(a + ":"):
			out.append(str(k).trim_prefix(a + ":"))
	return out


static func _key(a: String, b: String) -> String:
	return a if b.is_empty() else "%s:%s" % [a, b]
