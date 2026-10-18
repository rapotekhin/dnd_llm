class_name SaveFormat
extends RefCounted
## Save file layout and migrations (docs/tech/godot-client.md §«Сейвы»). Bump SAVE_VERSION on any change
## of the `session` layout and add a step to MIGRATIONS; never delete old steps or their fixtures.
##
## v1 (0.4.0): seed, RNG, counters, chat, options.
## v2 (0.4.1): world state — room, mode, character, items, attitudes, flags, summaries.

const SAVE_VERSION := 2

const ERR_UNREADABLE := "MSG_LOAD_FAILED"
const ERR_TOO_NEW := "MSG_SAVE_TOO_NEW"

## from_version -> Callable(data: Dictionary, start: Dictionary) -> void that upgrades `data` to from_version + 1.
## `start` = {"start_room": String, "character": Dictionary} for values an old save never had.
static var MIGRATIONS: Dictionary[int, Callable] = {
	1: _v1_to_v2,
}


static func build(session: GameSession, game_version: String, saved_at: String, kept_chat: int) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"game_version": game_version,
		"saved_at": saved_at,
		"meta": session.meta(),
		"session": session.to_dict(kept_chat),
	}


## "" when `data` can be loaded (after migrate), otherwise a localization key.
static func check(data: Variant) -> String:
	if not (data is Dictionary) or not (data.get("session") is Dictionary):
		return ERR_UNREADABLE
	if int(data.get("save_version", 0)) > SAVE_VERSION:
		return ERR_TOO_NEW
	if int(data.get("save_version", 0)) < 1:
		return ERR_UNREADABLE
	return ""


## Upgrades `data` in place step by step up to SAVE_VERSION.
static func migrate(data: Dictionary, start: Dictionary = {}) -> void:
	var v := int(data.get("save_version", 1))
	while v < SAVE_VERSION:
		(MIGRATIONS[v] as Callable).call(data, start)
		v += 1
		data["save_version"] = v


## A 0.4.0 game had no world: put the player in the start room with the start character, in exploration.
static func _v1_to_v2(data: Dictionary, start: Dictionary) -> void:
	var s: Dictionary = data["session"]
	s["room_id"] = str(start.get("start_room", ""))
	s["mode"] = GameSession.MODE_EXPLORATION
	s["npc_id"] = ""
	s["character"] = GameSession.character_from_template(start.get("character", {}))
	s["effect_counter"] = 0
	for key: String in ["items", "attitudes", "summaries"]:
		s[key] = {}
	for key: String in ["flags", "dialogue_log", "location_log"]:
		s[key] = []
