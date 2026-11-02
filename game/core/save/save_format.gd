class_name SaveFormat
extends RefCounted
## Save file layout (docs/tech/godot-client.md §«Сейвы»). Bump SAVE_VERSION on any change of the `session` layout.
## During the unified models saves do not carry over and there are no migrations (ADR-0012): only a save of this very
## version loads, the player starts a new game.

const SAVE_VERSION := 64

const ERR_UNREADABLE := "MSG_LOAD_FAILED"
const ERR_TOO_NEW := "MSG_SAVE_TOO_NEW"
const ERR_TOO_OLD := "MSG_SAVE_TOO_OLD"


static func build(session: GameSession, game_version: String, saved_at: String, kept_chat: int) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"game_version": game_version,
		"saved_at": saved_at,
		"meta": session.meta(),
		"session": session.to_dict(kept_chat),
	}


## "" when `data` can be loaded, otherwise a localization key.
static func check(data: Variant) -> String:
	if not (data is Dictionary) or not (data.get("session") is Dictionary):
		return ERR_UNREADABLE
	var v := int(data.get("save_version", 0))
	if v > SAVE_VERSION:
		return ERR_TOO_NEW
	if v < 1:
		return ERR_UNREADABLE
	if v < SAVE_VERSION:
		return ERR_TOO_OLD
	return ""
