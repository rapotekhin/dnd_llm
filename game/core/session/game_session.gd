class_name GameSession
extends RefCounted
## One playthrough: seeded RNG, turn counters and the chat log. Character and world join in v0.5.x
## (new sections + a save migration). Pure data: no nodes, no autoloads, no tr().

const KIND_PLAYER := "player"
const KIND_DM := "dm"
const KIND_CHECK := "check"
## Engine/system notice; `key` is a localization key, `args` its format arguments.
const KIND_SYSTEM := "system"

var game_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn_counter: int = 0
var check_counter: int = 0
var chat: Array[Dictionary] = []
## The master's last «interesting» options (turn.result.options), shown as buttons.
var options: Array[String] = []
var created_at: String = ""


static func create(new_seed: int, now: String) -> GameSession:
	var s := GameSession.new()
	s.game_seed = new_seed
	s.rng.seed = new_seed
	s.created_at = now
	return s


func next_turn_id() -> String:
	turn_counter += 1
	return "t-%d" % turn_counter


func next_check_id() -> String:
	check_counter += 1
	return "c-%d" % check_counter


func append(entry: Dictionary) -> Dictionary:
	chat.append(entry)
	return entry


static func player_entry(text: String) -> Dictionary:
	return {"kind": KIND_PLAYER, "text": text}


static func dm_entry(text: String, turn_id: String) -> Dictionary:
	return {"kind": KIND_DM, "text": text, "turn_id": turn_id}


static func system_entry(key: String, args: Dictionary = {}) -> Dictionary:
	return {"kind": KIND_SYSTEM, "key": key, "args": args}


static func check_entry(params: Dictionary, result: Dictionary) -> Dictionary:
	var e := result.duplicate()
	e["kind"] = KIND_CHECK
	e["skill"] = str(params.get("skill", ""))
	e["save"] = str(params.get("save", ""))
	if params.has("advantage_reason"):
		e["advantage_reason"] = str(params["advantage_reason"])
	return e


## The last `limit` player/master lines for the turn snapshot (ADR-0009 §4, history part).
func history(limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in chat:
		match str(e["kind"]):
			KIND_PLAYER:
				out.append({"role": "player", "text": e["text"]})
			KIND_DM:
				out.append({"role": "dm", "text": e["text"]})
	return out.slice(maxi(0, out.size() - limit))


## Short info for the slot list.
func meta() -> Dictionary:
	var preview := ""
	for i in range(chat.size() - 1, -1, -1):
		if str(chat[i]["kind"]) == KIND_DM:
			preview = str(chat[i]["text"]).left(80)
			break
	return {"turns": turn_counter, "preview": preview, "created_at": created_at}


func to_dict(kept_chat: int) -> Dictionary:
	return {
		"seed": game_seed,
		"rng_state": str(rng.state),  # 64-bit: a JSON number would lose precision
		"turn_counter": turn_counter,
		"check_counter": check_counter,
		"chat": chat.slice(maxi(0, chat.size() - kept_chat)),
		"options": options,
		"created_at": created_at,
	}


static func from_dict(d: Dictionary) -> GameSession:
	var s := GameSession.new()
	s.game_seed = int(d.get("seed", 0))
	s.rng.seed = s.game_seed
	s.rng.state = str(d.get("rng_state", "0")).to_int()
	s.turn_counter = int(d.get("turn_counter", 0))
	s.check_counter = int(d.get("check_counter", 0))
	for e: Variant in d.get("chat", []):
		if e is Dictionary:
			s.chat.append(_normalized(e))
	for o: Variant in d.get("options", []):
		s.options.append(str(o))
	s.created_at = str(d.get("created_at", ""))
	return s


## JSON brings every number back as float; check cards keep ints so a loaded session equals the saved one.
static func _normalized(e: Dictionary) -> Dictionary:
	if str(e.get("kind", "")) != KIND_CHECK:
		return e
	for k: String in ["bonus", "total", "dc", "nat"]:
		if e.has(k):
			e[k] = int(e[k])
	if e.get("rolls") is Array:
		e["rolls"] = (e["rolls"] as Array).map(func(r: Variant) -> int: return int(r))
	return e
