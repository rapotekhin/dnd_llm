class_name EntityRef
extends RefCounted
## One kind of id for all that can be named (v0.7.60.1, ADR-0012): `npc:bruno`, `item:rope`, `room:brod-square`, `hero`.
## A room and a site may share an id in a pack (the site of one room), so places stay three kinds until the tree of
## places (v0.7.66) makes them one.

const HERO := "hero"
const NPC := "npc"
const ITEM := "item"
const ROOM := "room"
const SITE := "site"
const LOCATION := "location"


static func make(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]


static func npc(id: String) -> String:
	return make(NPC, id)


static func item(id: String) -> String:
	return make(ITEM, id)


static func room(id: String) -> String:
	return make(ROOM, id)


static func site(id: String) -> String:
	return make(SITE, id)


static func location(id: String) -> String:
	return make(LOCATION, id)


static func kind_of(ref: String) -> String:
	return ref.get_slice(":", 0)


## The id after the kind; an id may hold colons of its own.
static func id_of(ref: String) -> String:
	return ref.substr(ref.find(":") + 1) if ref.contains(":") else ""
