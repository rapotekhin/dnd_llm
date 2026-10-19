class_name SaveFormat
extends RefCounted
## Save file layout and migrations (docs/tech/godot-client.md §«Сейвы»). Bump SAVE_VERSION on any change
## of the `session` layout and add a step to MIGRATIONS with a fixture of the old version.
##
## v1 (0.4.0): seed, RNG, counters, chat, options.
## v2 (0.4.1): world state — room, mode, character, items, attitudes, flags, summaries.
## v3 (0.5.0): the full 5e character (CharacterRules). Saves before v3 do not load: the game is not released
##   and their character had no sheet to rebuild from (decision of v0.5.0).
## v4 (0.5.1): world pack id and version, master settings. A v3 game moves to the start of the default pack.
## v5 (0.5.2): check locks, found secrets, visited rooms, the day.
## v6 (0.5.3): merchants — purses, stock left, haggling.
## v7 (0.5.4): completed quests.
## v8 (0.6.0): feature uses, condition ends, concentration, prepared day, short rests today.
## v9 (0.6.1): the fight in progress, encounters fought, NPCs killed.

const SAVE_VERSION := 12
## The oldest version that still loads (through MIGRATIONS).
const MIN_VERSION := 3

const ERR_UNREADABLE := "MSG_LOAD_FAILED"
const ERR_TOO_NEW := "MSG_SAVE_TOO_NEW"
const ERR_TOO_OLD := "MSG_SAVE_TOO_OLD"

## from_version -> Callable(data: Dictionary, ctx: Dictionary) -> void that upgrades `data` to from_version + 1.
## `ctx` = {"world": pack bundle of the default world} for values an old save never had.
static var MIGRATIONS: Dictionary[int, Callable] = {
	3: _v3_to_v4,
	4: _v4_to_v5,
	5: _v5_to_v6,
	6: _v6_to_v7,
	7: _v7_to_v8,
	8: _v8_to_v9,
	9: _v9_to_v10,
	10: _v10_to_v11,
	11: _v11_to_v12,
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
	if int(data.get("save_version", 0)) < MIN_VERSION:
		return ERR_TOO_OLD
	return ""


## Upgrades `data` in place step by step up to SAVE_VERSION.
static func migrate(data: Dictionary, ctx: Dictionary = {}) -> void:
	var v := int(data.get("save_version", MIN_VERSION))
	while v < SAVE_VERSION:
		(MIGRATIONS[v] as Callable).call(data, ctx)
		v += 1
		data["save_version"] = v


## A 0.5.0 game played the prototype tavern (no packs yet): the character and chat stay, the player starts
## over in the default world's start room, in exploration, with no world memory.
static func _v3_to_v4(data: Dictionary, ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	var w: Dictionary = ctx.get("world", {})
	s["world_id"] = str(w.get("id", ""))
	s["world_version"] = str(w.get("pack", {}).get("version", ""))
	s["settings"] = WorldPack.default_settings(w.get("pack", {}))
	s["room_id"] = str(w.get("world", {}).get("start_room", ""))
	s["mode"] = GameSession.MODE_EXPLORATION
	s["npc_id"] = ""
	for key: String in ["attitudes", "summaries"]:
		s[key] = {}
	for key: String in ["flags", "dialogue_log", "location_log", "options"]:
		s[key] = []


## A 0.5.1 game had no locks, secrets or map: the current room is the only one visited.
static func _v4_to_v5(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	s["locks"] = {}
	s["revealed"] = {}
	s["visited"] = [str(s.get("room_id", ""))]
	s["day"] = 1


## A 0.5.2 game traded only through the master: every merchant starts from the pack.
static func _v5_to_v6(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["merchants"] = {}


## A 0.5.3 game had no quests: none done.
static func _v6_to_v7(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["quests_done"] = []


## A 0.5.4 character had no tracked feature uses or condition ends: everything fresh, conditions until a long rest.
static func _v7_to_v8(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	var c: Dictionary = s.get("character", {})
	c["resources_used"] = {}
	var ends := {}
	for id: Variant in c.get("conditions", []):
		ends[str(id)] = "long_rest"
	c["condition_ends"] = ends
	c["concentration"] = ""
	c["prepared_day"] = 1
	s["short_rests"] = 0


## A 0.6.0 game had no fights.
static func _v8_to_v9(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	s["combat"] = {}
	s["encounters_done"] = []
	s["dead_npcs"] = []


## A 0.6.1 game had no «Красться» toggle.
static func _v9_to_v10(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["sneaking"] = false


## A 0.6.2 game had no time of day, quests with steps, traps or caches; it goes on in the morning.
static func _v10_to_v11(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	s["minute"] = 480
	s["quests_active"] = {}
	s["traps"] = {}
	s["caches_taken"] = []


## A 0.6.3 game had no quest steps with parts.
static func _v11_to_v12(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["quest_parts"] = {}
