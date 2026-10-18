class_name SaveFormat
extends RefCounted
## Save file layout and migrations (docs/tech/godot-client.md §«Сейвы»). Bump SAVE_VERSION on any change
## of the `session` layout and add a step to MIGRATIONS with a fixture of the old version.
##
## v1 (0.4.0): seed, RNG, counters, chat, options.
## v2 (0.4.1): world state — room, mode, character, items, attitudes, flags, summaries.
## v3 (0.5.0): the full 5e character (CharacterRules). Saves before v3 do not load: the game is not released
##   and their character had no sheet to rebuild from (decision of v0.5.0).

const SAVE_VERSION := 3
## The oldest version that still loads (through MIGRATIONS).
const MIN_VERSION := 3

const ERR_UNREADABLE := "MSG_LOAD_FAILED"
const ERR_TOO_NEW := "MSG_SAVE_TOO_NEW"
const ERR_TOO_OLD := "MSG_SAVE_TOO_OLD"

## from_version -> Callable(data: Dictionary) -> void that upgrades `data` to from_version + 1.
static var MIGRATIONS: Dictionary[int, Callable] = {}


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
	if int(data.get("save_version", 0)) < MIN_VERSION:
		return ERR_TOO_OLD
	return ""


## Upgrades `data` in place step by step up to SAVE_VERSION.
static func migrate(data: Dictionary) -> void:
	var v := int(data.get("save_version", MIN_VERSION))
	while v < SAVE_VERSION:
		(MIGRATIONS[v] as Callable).call(data)
		v += 1
		data["save_version"] = v
