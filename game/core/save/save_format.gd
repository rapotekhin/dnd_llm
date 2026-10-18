class_name SaveFormat
extends RefCounted
## Save file layout and migrations (docs/tech/save-format.md). Bump SAVE_VERSION on any change of the
## `session` layout and add a step to MIGRATIONS; never delete old steps or their fixtures.

const SAVE_VERSION := 1

const ERR_UNREADABLE := "MSG_LOAD_FAILED"
const ERR_TOO_NEW := "MSG_SAVE_TOO_NEW"

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
	return ""


## Upgrades `data` in place step by step up to SAVE_VERSION.
static func migrate(data: Dictionary) -> void:
	var v := int(data.get("save_version", 1))
	while v < SAVE_VERSION:
		(MIGRATIONS[v] as Callable).call(data)
		v += 1
		data["save_version"] = v
