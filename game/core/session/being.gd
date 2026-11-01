class_name Being
extends RefCounted
## One record of a character (v0.7.61, ADR-0012): `s.beings` {id: record}, whatever the character is to the hero now.
## The pack's template stays in the world; the record holds only what the game added, and a part that is absent means
## nothing happened: no such key. A change of state is a change of a field, not a move between stores.
##
## attitude, attitude_base — the mood towards the hero and where it starts; memory [{day, text}] — what it remembers;
## pockets [{...}], picked, caught — its pockets, the day they were tried and the day it caught a thief;
## hp — its wounds between fights, full when absent; effects, conditions, next_effect — its statuses as on the hero
## (ConditionRules, v0.7.63): a spell on it, a poison kept after a fight; sick {id, until} — it passes then, id "" — healed; dead true; body — the room it lies in, body_at — since when (an absolute minute), searched
## true; disarmed {item: day} — stolen out of its hands; follows — the turn it joined the hero, fed {at, hungry} — its
## last meal; at — the room it was left in, "" on the road; discount {pct, until_day}, favor — the day of the last free
## service: what it granted by words.
##
## v0.7.62: whom the pack does not name is made here (`spawn`) and has an id `c#` for life. id, n — its id and the order it
## came in; monster, name, base — the SRD template, its name and the name without a number. encounter, at — a head of an
## encounter and its room (EncounterRules).
## A part is a nested dictionary that comes and goes whole, with its own id and n (`put`, `parts`): a change of what a
## character is now is one part put or dropped. creature — it lies or stands in a room (CreatureRules): the enemy that
## surrendered, a person knocked out, a pet, a mount; summon — a spell called it (AllyRules); fight — it is in a fight
## (CombatRules): the fighter is this part, with the record's id, its hp counts while the fight goes on and the fight's end
## writes it back; was — a creature attacked, back in the room if the hero runs. The hero's fighter has the id `p`.
## The form of a record is declared: PARTS and NESTED, read by `check` (TYPE_NIL — a field of several shapes).

const PARTS := {
	"id": TYPE_STRING, "n": TYPE_INT, "monster": TYPE_STRING, "name": TYPE_STRING, "base": TYPE_STRING, "desc": TYPE_STRING,
	"col": TYPE_INT, "faction": TYPE_STRING, "encounter": TYPE_STRING, "no_xp": TYPE_BOOL,
	"attitude": TYPE_INT, "attitude_base": TYPE_INT, "memory": TYPE_ARRAY, "pockets": TYPE_ARRAY, "picked": TYPE_INT, "caught": TYPE_INT,
	"hp": TYPE_INT, "effects": TYPE_ARRAY, "conditions": TYPE_ARRAY, "next_effect": TYPE_INT, "sick": TYPE_DICTIONARY, "dead": TYPE_BOOL, "body": TYPE_STRING,
	"body_at": TYPE_INT, "searched": TYPE_BOOL, "disarmed": TYPE_DICTIONARY, "follows": TYPE_INT, "fed": TYPE_DICTIONARY, "at": TYPE_STRING,
	"discount": TYPE_DICTIONARY, "favor": TYPE_INT, "creature": TYPE_DICTIONARY, "summon": TYPE_DICTIONARY, "fight": TYPE_DICTIONARY,
	"was": TYPE_DICTIONARY,
}
const NESTED := {
	"creature": {
		"id": TYPE_STRING, "n": TYPE_INT, "name": TYPE_STRING, "monster": TYPE_STRING, "state": TYPE_STRING, "at": TYPE_STRING,
		"bound": TYPE_BOOL, "led": TYPE_BOOL, "since": TYPE_INT, "hp": TYPE_INT, "max_hp": TYPE_INT, "xp_given": TYPE_BOOL,
		"npc_id": TYPE_STRING, "kept": TYPE_BOOL, "faction": TYPE_STRING, "ally": TYPE_BOOL, "owner": TYPE_STRING, "serf": TYPE_STRING,
		"searched": TYPE_BOOL, "cause": TYPE_STRING, "pet": TYPE_BOOL, "close": TYPE_INT, "named": TYPE_BOOL, "fed_day": TYPE_INT,
		"hand_day": TYPE_INT, "bond_day": TYPE_INT, "tame_day": TYPE_INT, "hungry": TYPE_INT, "scout_day": TYPE_INT, "scouts": TYPE_INT,
		"pack": TYPE_DICTIONARY, "cart": TYPE_DICTIONARY, "waiting": TYPE_BOOL, "rent_day": TYPE_INT, "rent_from": TYPE_STRING,
	},
	"summon": {
		"id": TYPE_STRING, "n": TYPE_INT, "spell": TYPE_STRING, "monster": TYPE_STRING, "name": TYPE_STRING, "until": TYPE_INT,
		"concentration": TYPE_BOOL, "hp": TYPE_INT, "helper": TYPE_BOOL,
	},
	"fight": {
		"id": TYPE_STRING, "n": TYPE_INT, "side": TYPE_STRING, "name": TYPE_STRING, "base": TYPE_STRING, "desc": TYPE_STRING, "col": TYPE_INT,
		"status": TYPE_STRING, "init": TYPE_INT, "monster": TYPE_STRING, "hp": TYPE_INT, "max_hp": TYPE_INT, "ac": TYPE_INT,
		"npc_id": TYPE_STRING, "by_hero": TYPE_BOOL, "morale": TYPE_BOOL, "no_xp": TYPE_BOOL, "law": TYPE_BOOL, "helper": TYPE_BOOL,
		"ally": TYPE_STRING, "summon_id": TYPE_STRING, "spell": TYPE_STRING, "creature_id": TYPE_STRING, "actions": TYPE_ARRAY,
		"effects": TYPE_ARRAY, "conditions": TYPE_ARRAY, "next_effect": TYPE_INT, "surprised": TYPE_BOOL, "dodging": TYPE_BOOL, "hidden": TYPE_BOOL,
		"reckless": TYPE_BOOL, "disengaged": TYPE_BOOL, "swooped": TYPE_BOOL, "no_heal": TYPE_BOOL, "blinked": TYPE_BOOL, "retching": TYPE_BOOL, "reacted": TYPE_BOOL,
		"lethargy": TYPE_BOOL, "fleeing": TYPE_BOOL, "grappled_by_player": TYPE_BOOL, "relentless_used": TYPE_BOOL, "slowed": TYPE_INT,
		"oiled": TYPE_INT, "seen_col": TYPE_INT, "moved": TYPE_INT, "last_total": TYPE_INT, "temp_hp": TYPE_INT, "acid": TYPE_STRING,
		"burning": TYPE_STRING, "target": TYPE_STRING, "last_spell": TYPE_STRING, "zoned": TYPE_ARRAY, "used": TYPE_NIL, "once": TYPE_NIL,
		"recharge": TYPE_NIL, "spent": TYPE_NIL,
	},
}


## The record of `id`, made when there is none: for writing.
static func of(s: GameSession, id: String) -> Dictionary:
	if not s.beings.has(id):
		s.beings[id] = {}
	return s.beings[id]


## The record of `id` for reading: empty when nothing happened to it. Writes into it are lost.
static func view(s: GameSession, id: String) -> Dictionary:
	return s.beings.get(id, {})


## A new character without a template of the pack: its id stays for life.
static func spawn(s: GameSession, fields: Dictionary = {}) -> Dictionary:
	s.being_counter += 1
	var b: Dictionary = GameSession.whole(fields)  # a pack's numbers come from JSON as floats
	b["id"] = "c%d" % s.being_counter
	b["n"] = s.being_counter
	s.beings[b["id"]] = b
	return b


## Puts a part on a record; `parts` gives them in the order they came.
static func put(s: GameSession, id: String, key: String, fields: Dictionary) -> Dictionary:
	s.being_counter += 1
	var p: Dictionary = GameSession.whole(fields)
	p["id"] = id
	p["n"] = s.being_counter
	of(s, id)[key] = p
	return p


## A new character that is only this part.
static func made(s: GameSession, key: String, fields: Dictionary) -> Dictionary:
	return put(s, str(spawn(s)["id"]), key, fields)


## Takes a record out of the game.
static func forget(s: GameSession, id: String) -> void:
	s.beings.erase(id)


## The records with this key, in the order they came. A save sorts the keys of `s.beings`: `n` keeps the order.
static func records(s: GameSession, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in with(s, key):
		out.append(s.beings[id])
	return _by_order(out)


## All the parts of this name, in the order they came.
static func parts(s: GameSession, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in with(s, key):
		out.append(s.beings[id][key])
	return _by_order(out)


static func _by_order(list: Array[Dictionary]) -> Array[Dictionary]:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("n", 0)) < int(b.get("n", 0)))
	return list


## What breaks the declared form of the records: empty when all is well.
static func check(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.beings:
		var b: Dictionary = s.beings[id]
		_against(out, id, b, PARTS)
		for part: String in NESTED:
			if b.get(part) is Dictionary:
				_against(out, "%s.%s" % [id, part], b[part], NESTED[part])
	return out


static func _against(out: Array[String], where: String, d: Dictionary, form: Dictionary) -> void:
	for k: String in d:
		if not form.has(k):
			out.append("%s: unknown key %s" % [where, k])
		elif int(form[k]) != TYPE_NIL and typeof(d[k]) != int(form[k]):
			out.append("%s: %s is %s" % [where, k, type_string(typeof(d[k]))])


## Takes a part off a record.
static func drop(s: GameSession, id: String, key: String) -> void:
	if s.beings.has(id):
		(s.beings[id] as Dictionary).erase(key)


## Everybody with this part, in the order they entered the game.
static func with(s: GameSession, key: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.beings:
		if (s.beings[id] as Dictionary).has(key):
			out.append(id)
	return out


## Takes a part off everybody.
static func clear(s: GameSession, key: String) -> void:
	for id: String in with(s, key):
		drop(s, id, key)


static func dead(s: GameSession, id: String) -> bool:
	return view(s, id).has("dead")


static func die(s: GameSession, id: String) -> void:
	of(s, id)["dead"] = true


static func dead_ids(s: GameSession) -> Array[String]:
	return with(s, "dead")


static func searched(s: GameSession, id: String) -> bool:
	return view(s, id).has("searched")


static func search(s: GameSession, id: String) -> void:
	of(s, id)["searched"] = true


static func follows(s: GameSession, id: String) -> bool:
	return view(s, id).has("follows")


## Who walks with the hero, in the order they joined.
static func followers(s: GameSession) -> Array[String]:
	var out := with(s, "follows")
	out.sort_custom(func(a: String, b: String) -> bool: return int(view(s, a)["follows"]) < int(view(s, b)["follows"]))
	return out


static func follow(s: GameSession, id: String) -> void:
	if follows(s, id):
		return
	var last := 0
	for other: String in with(s, "follows"):
		last = maxi(last, int(view(s, other)["follows"]))
	of(s, id)["follows"] = last + 1


static func unfollow(s: GameSession, id: String) -> void:
	drop(s, id, "follows")
