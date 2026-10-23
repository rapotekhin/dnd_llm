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

const SAVE_VERSION := 40
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
	12: _v12_to_v13,
	13: _v13_to_v14,
	14: _v14_to_v15,
	15: _v15_to_v16,
	16: _v16_to_v17,
	17: _v17_to_v18,
	18: _v18_to_v19,
	19: _v19_to_v20,
	20: _v20_to_v21,
	21: _v21_to_v22,
	22: _v22_to_v23,
	23: _v23_to_v24,
	24: _v24_to_v25,
	25: _v25_to_v26,
	26: _v26_to_v27,
	27: _v27_to_v28,
	28: _v28_to_v29,
	29: _v29_to_v30,
	30: _v30_to_v31,
	31: _v31_to_v32,
	32: _v32_to_v33,
	33: _v33_to_v34,
	34: _v34_to_v35,
	35: _v35_to_v36,
	36: _v36_to_v37,
	37: _v37_to_v38,
	38: _v38_to_v39,
	39: _v39_to_v40,
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


## A 0.6.4 game had no option prices, thefts or noticed sneaking.
static func _v12_to_v13(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	s["option_costs"] = []
	s["pickpocketed"] = {}
	s["sneak_noticed"] = ""


## A 0.6.5 game knew no kinds of foes.
static func _v13_to_v14(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["known_monsters"] = []


## A 0.6.6 game had no things in the rooms and no pockets: the rooms are furnished on the next visit.
static func _v14_to_v15(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	for k: String in ["props", "pockets", "shop_closed", "caught_by"]:
		s[k] = {}


## A 0.7.1 pre-fight save did not keep the fight about to start (loading it skipped a lost fight).
static func _v15_to_v16(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["fight_on_load"] = {}


## A 0.7.3 game kept the master's memory as made-up flags; they stay flags, the notes start empty.
static func _v16_to_v17(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["notes"] = []


## A 0.7.7 hero kept conditions as a list with «until a rest» ends: each becomes an effect of the same end with the
## source «прежнее»; no exhaustion, concentration without an end in time; the clock of exhaustion starts rested now.
static func _v17_to_v18(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	var c: Dictionary = s.get("character", {})
	var ends: Dictionary = c.get("condition_ends", {})
	var effects: Array = []
	var uid := 1
	for id: Variant in c.get("conditions", []):
		effects.append({"uid": uid, "condition": str(id), "source": {"kind": "old", "name": "прежнее"},
			"ends": {"rest": "short" if str(ends.get(id, "long_rest")) == "short_rest" else "long"}})
		uid += 1
	c["effects"] = effects
	c["next_effect"] = uid
	c.erase("condition_ends")
	c["exhaustion"] = 0
	c["concentration_ends"] = -1
	var now := (int(s.get("day", 1)) - 1) * 1440 + int(s.get("minute", 480))
	s["rested_at"] = now
	s["awake_saves"] = 0
	s["march_day"] = int(s.get("day", 1))
	s["march_minutes"] = 0


## A 0.7.9 hero had no temporary hit points (v0.7.10: Dark One's Blessing and the like).
static func _v18_to_v19(data: Dictionary, _ctx: Dictionary) -> void:
	var c: Dictionary = data["session"].get("character", {})
	c["temp_hp"] = 0


## v0.7.12: attunement and charges. Of the 0.7.11 catalog only the Cloak of Protection asks for attunement — a hero
## who had it keeps it working (attuned at load, ADR-0010 §6д).
static func _v19_to_v20(data: Dictionary, _ctx: Dictionary) -> void:
	var c: Dictionary = data["session"].get("character", {})
	c["attuned"] = ["cloak_of_protection"] if int(c.get("inventory", {}).get("cloak_of_protection", 0)) > 0 else []
	c["charges_used"] = {}


## v0.7.14: crimes, wanted, the guard's hold, bodies, failed quests. NPCs killed before were fought in self-defence
## or forgotten — no crime; their bodies are not kept.
static func _v20_to_v21(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	for k: String in ["crimes", "searched", "quests_failed"]:
		s[k] = []
	for k: String in ["wanted", "bodies"]:
		s[k] = {}
	s["arrest"] = ""


## v0.7.14.3: the master's rewards since the long rest — an old game starts with a full budget.
static func _v21_to_v22(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["reward_spent"] = 0


## v0.7.14.4: the chronicle starts with the engine lines still in the saved chat (their day and room unknown — the
## save's own).
static func _v22_to_v23(data: Dictionary, _ctx: Dictionary) -> void:
	var s: Dictionary = data["session"]
	var out: Array = []
	for e: Variant in s.get("chat", []):
		if e is Dictionary and str(e.get("kind", "")) == GameSession.KIND_EFFECT and not (e.get("lines", []) as Array).is_empty():
			out.append({"day": int(s.get("day", 1)), "minute": int(s.get("minute", 480)), "room": str(s.get("room_id", "")),
				"text": " · ".join(e["lines"])})
	s["chronicle"] = out


## v0.7.15: NPCs remember facts about the hero — an old game starts with empty memories (the summaries stay).
static func _v23_to_v24(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["npc_memory"] = {}


## v0.7.15.2: discounts and free services by words — none yet in an old game.
static func _v24_to_v25(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["discounts"] = {}
	data["session"]["favors"] = {}


## v0.7.15.3: the NPC secrets the hero learned — none yet in an old game.
static func _v25_to_v26(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["secrets_told"] = []


## v0.7.17: reputation in settlements — an old game starts as a stranger everywhere.
static func _v26_to_v27(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["reputation"] = {}
	data["session"]["attitude_base"] = {}


## v0.7.18.2: the hero's bags — empty; the first refresh makes one for each container item in the pack.
static func _v27_to_v28(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["character"]["bags"] = {}


## v0.7.19.1: peaceful development — every direction from nothing.
static func _v28_to_v29(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["character"]["development"] = {}


## v0.7.20: what the master made — nothing yet in an old game.
static func _v29_to_v30(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["generated"] = {}


## v0.7.20.3: nobody goes with the hero, everyone in their own place.
static func _v30_to_v31(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["followers"] = []
	data["session"]["npc_at"] = {}


## v0.7.22.2: nobody has let the hero go yet, no talk answer tried.
static func _v31_to_v32(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["let_go"] = {}
	data["session"]["arrest_tried"] = []
	data["session"]["magic_given"] = 0


## v0.7.22.3: no spell of the hero lies on any NPC.
static func _v32_to_v33(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["npc_spells"] = {}


## v0.7.22.5: the hero's age, height and weight — empty; the first refresh rolls them by the race.
static func _v33_to_v34(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["character"]["body"] = {}


## v0.7.22.8: no NPC has lost a weapon to the hero yet.
static func _v34_to_v35(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["disarmed"] = {}


## v0.7.22.10: the bodies already lying fell long ago — buried at the next look of the clock.
static func _v35_to_v36(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["body_at"] = {}


## v0.7.22.11: no creature left behind by a fight yet.
static func _v36_to_v37(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["creatures"] = {}
	data["session"]["creature_counter"] = 0


## v0.7.22.12: no foe lurks unaware, the hero is nobody's captive.
static func _v37_to_v38(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["lurking"] = {}
	data["session"]["captive"] = {}


## v0.7.22.17: a creature the hero has bound is the hero's prisoner; nothing carried is marked as someone else's.
static func _v38_to_v39(data: Dictionary, _ctx: Dictionary) -> void:
	for room: Variant in data["session"].get("creatures", {}):
		for c: Variant in data["session"]["creatures"][room]:
			if c is Dictionary and bool(c.get("bound", false)):
				c["owner"] = OwnerRules.HERO
	data["session"]["foreign"] = {}
	data["session"]["talk_creature"] = ""


## v0.7.22.20: no room counts as described today — the next entry of each gets the master's description.
static func _v39_to_v40(data: Dictionary, _ctx: Dictionary) -> void:
	data["session"]["described"] = {}
