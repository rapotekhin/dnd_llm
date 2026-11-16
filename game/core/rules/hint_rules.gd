class_name HintRules
extends RefCounted
## Screens of teaching (v0.8.4.44.5, docs/design/systems/tutorial/description.md): a row of the pack's `hints` —
## {id, when, title, text, point, after, once, phrases, button} — darkens the screen, shows its words with an arrow at
## `point` and waits for «Продолжить». The queue is the list in order: the first row due is shown, one at a time.
## A row is due while `when` holds (Cond; none — always) and, with `after`, once the row named there was shown and a
## master's turn went by since (the player did what it asked). `once`: "game" — once in this game, whatever the setting
## (a dream's screens: the tutorial played again teaches again); "profile" (by default) — once for this player, and not
## at all with hints off (first-time hints, SaveManager). `phrases` — the master's options for the moment, his own taken
## away: [text | {text, check}] (`check` — the spec of an option's roll). `button` "wake" — the dream's end, «Проснуться»
## (DreamRules.wake_row, the last row of the queue); else «Продолжить». `point`: a control of the screen by its name,
## "map:<id>" — a person, a creature or a thing of the room's map by its pack id (map_ref), none — the screen itself.
## v0.8.4.44.9 (the author: «инструкцию Осмотреться включать, когда игрок будет за 1 клетку от выхода»): `near`
## {exit, squares} — due only while the hero stands within `squares` (1 by default) of the way to room `exit` on the room's
## map; a walk stops there for it (`stops`). A row is shown over the master's turn too, but one with `phrases` waits for it:
## the master's own options would come after its words.

const GAME := "game"
const PROFILE := "profile"
const WAKE := "wake"
const MAP := "map:"


## The rows in the order of the queue: the pack's own, then the dream's end.
static func rows(data: Dictionary) -> Array:
	var pack: Dictionary = data.get("pack", {})
	var out: Array = (pack.get("hints", []) as Array).duplicate()
	var wake := DreamRules.wake_row(pack)
	if not wake.is_empty():
		out.append(wake)
	return out


static func once(row: Dictionary) -> String:
	return str(row.get("once", PROFILE))


## The row to show now, {} — none. `seen` — the ids this player has seen (the profile), `on` — first-time hints shown.
static func due(s: GameSession, data: Dictionary, seen: Array, on: bool) -> Dictionary:
	for row: Dictionary in rows(data):
		var id := str(row["id"])
		if s.hints.has(id) or (once(row) == PROFILE and (not on or seen.has(id))):
			continue
		var after := str(row.get("after", ""))
		if not after.is_empty() and (not s.hints.has(after) or s.turn_counter <= int(s.hints[after])):
			continue
		if Cond.holds(s, row, data) and (not row.has("near") or near(s, data, row["near"])):
			return row
	return {}


## The hero stands within `at.squares` (1 by default) of the way to room `at.exit` on the room's map.
static func near(s: GameSession, data: Dictionary, at: Variant) -> bool:
	if not at is Dictionary or s.mode != GameSession.MODE_EXPLORATION:
		return false
	var map := WalkRules.view(s, data)
	if map.is_empty():
		return false
	var way := WalkRules.way_cell(map, s.room_id, str(at.get("exit", "")))
	if way.x < 0:
		return false
	var me := WalkRules.settle(s, data, map)
	var d := maxi(absi(me.x - way.x), absi(me.y - way.y))
	return d <= int(at.get("squares", 1))


## A walk stops for the row due now when it waits for the hero at a way out (`near`): the hero is there, it shows.
static func stops(s: GameSession, data: Dictionary, seen: Array, on: bool) -> bool:
	return due(s, data, seen, on).has("near")


## The row is shown: this game keeps it with the turn it came at (a later row's `after` reads it). True — the profile
## keeps it too.
static func shown(s: GameSession, row: Dictionary) -> bool:
	s.hints[str(row["id"])] = s.turn_counter
	return once(row) == PROFILE


## The row's phrases as the master's options: {texts: Array[String], checks: Array}; none — {}.
static func phrases(row: Dictionary, data: Dictionary) -> Dictionary:
	var texts: Array[String] = []
	var checks: Array = []
	for ph: Variant in row.get("phrases", []):
		texts.append(str(ph["text"]) if ph is Dictionary else str(ph))
		checks.append(CheckEngine.option_check(data, (ph as Dictionary).get("check")) if ph is Dictionary else {})
	return {} if texts.is_empty() else {"texts": texts, "checks": checks}


## The ref on the room's map of a pack id: a creature of the room (by its row or its person), a thing, a person here;
## "" — none here now.
static func map_ref(s: GameSession, data: Dictionary, id: String) -> String:
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		if str(c.get("pack_row", "")) == id or str(c.get("npc_id", "")) == id:
			return "cr:" + str(c["id"])
	if not PropRules.find(s, s.room_id, id).is_empty():
		return "prop:" + id
	if s.npcs_here(data["world"], s.room_id).has(id):
		return "npc:" + id
	return ""


## A row as the pack may write it: an error per fault, none — fine.
static func faults(row: Variant, ids: Array) -> Array[String]:
	var e: Array[String] = []
	if not row is Dictionary or str(row.get("id", "")).is_empty() or str(row.get("text", "")).is_empty():
		return ["id и text"]
	var id := str(row["id"])
	if ids.has(id) or id == WAKE:
		e.append("%s: id повторяется" % id)
	if not once(row) in [GAME, PROFILE]:
		e.append("%s: once — game или profile" % id)
	if row.has("after") and not ids.has(str(row["after"])):
		e.append("%s: after — id строки выше" % id)
	if row.has("button") and str(row["button"]) != WAKE:
		e.append("%s: button — только wake" % id)
	if row.has("near") and (not row["near"] is Dictionary or str(row["near"].get("exit", "")).is_empty()):
		e.append("%s: near — {exit, squares}" % id)
	for ph: Variant in row.get("phrases", []):
		if not (ph is String or (ph is Dictionary and not str(ph.get("text", "")).is_empty())):
			e.append("%s: phrases — строки или {text, check}" % id)
	return e
