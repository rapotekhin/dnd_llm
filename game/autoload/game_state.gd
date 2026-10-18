extends Node
## The current session and the turn loop (ADR-0009): player input → turn.request with a snapshot →
## engine.* callbacks (checks, effect reserves, lookup, item search) → turn.result → apply listed reserves.
## Modes: exploration, social and trade with an NPC of the room. One turn at a time.
## Deterministic moves (exits, talking to an NPC, leaving a conversation) do not ask the model to decide.

var session: GameSession
## turn_id of the turn in flight, "" when idle.
var busy_turn: String = ""
var effects := EffectEngine.new()

var _last_kind: String = ""
var _last_input: String = ""


func has_session() -> bool:
	return session != null


func is_busy() -> bool:
	return not busy_turn.is_empty()


func world() -> WorldView:
	return WorldView.new(Catalog.data["world"])


## A new game with a created character (CharacterBuilder.build); {} = the ready-made start character.
func new_game(character: Dictionary = {}, game_seed: int = -1) -> void:
	if game_seed < 0:
		game_seed = int(LaunchArgs.value("--seed", str(randi())))
	if character.is_empty():
		character = CharacterBuilder.build(Catalog.data["character"], Catalog.data)
	var w := world()
	start(GameSession.create(game_seed, Time.get_datetime_string_from_system(), w.start_room(), character))
	_request("enter", "")


func start(s: GameSession) -> void:
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	session = s
	busy_turn = ""
	_last_kind = ""
	effects = EffectEngine.new()
	EventBus.session_started.emit()


func close_session() -> void:
	cancel_turn()
	session = null
	busy_turn = ""
	EventBus.session_closed.emit()


## Returns false when the input cannot be sent now (empty, a turn in flight, no master).
func submit(text: String) -> bool:
	text = text.strip_edges()
	if session == null or text.is_empty() or is_busy() or not Backend.is_ready():
		return false
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	_request("action", text)
	return true


## Exit button: the engine moves the player (no model decision), then the master describes the new room.
func go(room_id: String) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not world().exits(session.room_id).has(room_id):
		return false
	_end_conversation()
	session.room_id = room_id
	_add(GameSession.effect_entry(["Переход: %s" % world().room(room_id).get("name", room_id)]))
	EventBus.state_changed.emit()
	_request("enter", "")
	return true


## NPC button: start a conversation (or trade with a trader); the NPC greets the player.
func talk_to(npc_id: String, trade: bool = false) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not world().npcs_in(session.room_id).has(npc_id):
		return false
	if trade and not world().is_trader(npc_id):
		return false
	_begin_conversation(npc_id, GameSession.MODE_TRADE if trade else GameSession.MODE_SOCIAL)
	_request("enter", "")
	return true


func leave_conversation() -> bool:
	if session == null or is_busy() or not session.in_conversation() or not Backend.is_ready():
		return false
	_end_conversation()
	_request("resume", "")
	return true


## Repeats the last failed request as a new turn (ADR-0009 §5: no idempotency, a retry is a new turn_id).
func retry() -> void:
	if can_retry():
		_request(_last_kind, _last_input)


## The last turn failed and can be repeated.
func can_retry() -> bool:
	return session != null and not is_busy() and not _last_kind.is_empty()


func cancel_turn() -> void:
	if is_busy() and Backend.is_ready():
		Backend.request("turn.cancel", {"turn_id": busy_turn}, 5.0)


## Puts an owned item into an equipment slot (CharacterRules.SLOTS). "" on success, else a localization key.
## Not while the master thinks: the snapshot of the turn in flight would no longer match.
func equip(item_id: String, slot: String) -> String:
	if session == null or is_busy():
		return "EQUIP_BUSY"
	var c := session.character
	var why := CharacterRules.can_equip(c, Catalog.data, session.items, item_id, slot)
	if not why.is_empty():
		return why
	c["equipped"][slot] = item_id
	if slot == "main_hand" and str(c["equipped"].get("off_hand", "")) == item_id and int(c["inventory"][item_id]) < 2:
		c["equipped"]["off_hand"] = ""
	CharacterRules.refresh(c, Catalog.data, session.items)
	EventBus.state_changed.emit()
	return ""


func unequip(slot: String) -> void:
	if session == null or is_busy():
		return
	session.character["equipped"][slot] = ""
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	EventBus.state_changed.emit()


func save_to(slot: String) -> bool:
	return SaveManager.save_slot(slot, session)


## "" on success or a localization key.
func load_from(slot: String) -> String:
	var res: Variant = SaveManager.read_slot(slot)
	if res is String:
		return res
	start(res)
	return ""


# --- turn --------------------------------------------------------------------------


func _add(entry: Dictionary) -> void:
	session.append(entry)
	EventBus.chat_appended.emit(entry)


func _set_options(options: Array[String]) -> void:
	session.options = options
	EventBus.options_changed.emit(options)


func _log(line: String) -> void:
	var cap := int(Catalog.game()["summaries"]["events_max"])
	session.location_log.append(line)
	if session.location_log.size() > cap:
		session.location_log = session.location_log.slice(session.location_log.size() - cap)
	if session.in_conversation():
		session.dialogue_log.append(line)


func _request(kind: String, input: String) -> void:
	var s := session
	var turn_id := s.next_turn_id()
	_last_kind = kind
	_last_input = input
	busy_turn = turn_id
	_set_options([])
	EventBus.turn_started.emit(turn_id)
	var params := {
		"turn_id": turn_id,
		"mode": s.mode,
		"kind": kind,
		"input": input,
		"snapshot": TurnSnapshot.build(s, Catalog.data, int(Catalog.game()["chat"]["history_chars"])),
	}
	if s.in_conversation():
		params["npc_id"] = s.npc_id
	if not SaveManager.master_model.is_empty():
		params["model"] = SaveManager.master_model
	var call := await Backend.request("turn.request", params, float(Catalog.game()["turn"]["client_timeout_s"]))
	if session != s or busy_turn != turn_id:
		return  # the session was closed or replaced while the master was thinking
	busy_turn = ""
	if call.is_error():
		effects.discard(turn_id)
		_add(GameSession.system_entry(_error_key(call.reason())))
		EventBus.turn_finished.emit(turn_id, false)
		return
	_last_kind = ""
	var follow_up := _apply_result(s, turn_id, call.result)
	EventBus.turn_finished.emit(turn_id, true)
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_maybe_summarize_location()
	if not follow_up.is_empty():
		_request(follow_up, "")


## Shows the narration, applies listed reserves, handles next_mode. Returns the follow-up turn kind or "".
func _apply_result(s: GameSession, turn_id: String, result: Dictionary) -> String:
	var text := str(result.get("narration", ""))
	if s.in_conversation():
		_add(GameSession.npc_entry(s.npc_id, str(world().npc(s.npc_id).get("name", s.npc_id)), text, turn_id))
	else:
		_add(GameSession.dm_entry(text, turn_id))
	_log(("%s: " % world().npc(s.npc_id).get("name", "")) + text if s.in_conversation() else "Мастер: " + text)
	var room_before := s.room_id
	var lines := effects.apply(s, turn_id, result.get("effect_ids", []))
	CharacterRules.refresh(s.character, Catalog.data, s.items)  # an item given away is unequipped
	if not lines.is_empty():
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))
	var options: Array[String] = []
	for o: Variant in result.get("options", []):
		options.append(str(o))
	_set_options(options)

	if s.room_id != room_before:
		_end_conversation()
		return "enter"
	var next: Variant = result.get("next_mode")
	if not (next is Dictionary):
		return ""
	var mode := str(next.get("mode", ""))
	var npc_id := str(next.get("npc_id", "")) if next.get("npc_id") != null else ""
	if mode == GameSession.MODE_EXPLORATION and s.in_conversation():
		_end_conversation()
		return "resume"
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and world().npcs_in(s.room_id).has(npc_id):
		if mode == GameSession.MODE_TRADE and not world().is_trader(npc_id):
			mode = GameSession.MODE_SOCIAL
		if s.mode == mode and s.npc_id == npc_id:
			return ""
		_begin_conversation(npc_id, mode)
		return "enter"
	return ""


func _begin_conversation(npc_id: String, mode: String) -> void:
	if session.in_conversation() and session.npc_id != npc_id:
		_end_conversation()
	session.mode = mode
	session.npc_id = npc_id
	EventBus.state_changed.emit()


## Back to exploration; the conversation log goes to summary.request (kept in the save, ADR-0009 §3).
func _end_conversation() -> void:
	if not session.in_conversation():
		return
	var npc_id := session.npc_id
	var events := session.dialogue_log.duplicate()
	session.mode = GameSession.MODE_EXPLORATION
	session.npc_id = ""
	session.dialogue_log.clear()
	EventBus.state_changed.emit()
	if not events.is_empty():
		_summarize("dialogue", npc_id, "dialogue:" + npc_id, events)


func _maybe_summarize_location() -> void:
	var every := int(Catalog.game()["summaries"]["location_every_turns"])
	if session.location_log.size() < every:
		return
	var loc := world().location_id(session.room_id)
	var events := session.location_log.duplicate()
	session.location_log.clear()
	_summarize("location", str(world().location(loc).get("name", loc)), "location:" + loc, events)


func _summarize(kind: String, subject: String, key: String, events: Array) -> void:
	var s := session
	var params := {"kind": kind, "subject_id": subject, "previous": str(s.summaries.get(key, "")), "events": events}
	if not SaveManager.master_model.is_empty():
		params["model"] = SaveManager.master_model
	var call := await Backend.request("summary.request", params, float(Catalog.game()["turn"]["summary_timeout_s"]))
	if session == s and not call.is_error():
		s.summaries[key] = str(call.result.get("summary", ""))


static func _error_key(reason: String) -> String:
	match reason:
		"turn_cancelled":
			return "MSG_TURN_CANCELLED"
		"turn_timeout", "client_timeout", "engine_timeout":
			return "MSG_TURN_TIMEOUT"
		"server_busy", "turn_in_progress":
			return "MSG_SERVER_BUSY"
		"budget_exceeded":
			return "MSG_BUDGET_EXCEEDED"
		"llm_unavailable", "llm_invalid_output":
			return "MSG_MASTER_FAILED"
		_:
			return "MSG_NO_MASTER"


# --- engine.* handlers (only for the turn in flight, ADR-0009 §3) ---------------------


func _active(params: Dictionary) -> bool:
	return session != null and str(params.get("turn_id", "")) == busy_turn


func handle_engine_check(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	var bonus := CheckEngine.bonus_for(session.character, params)
	var result := CheckEngine.roll(Catalog.rules(), session.rng, params, bonus, session.next_check_id())
	if result.has("error"):
		return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, str(result["error"]))
	_add(GameSession.check_entry(params, result))
	return result


func handle_engine_validate(params: Dictionary) -> Dictionary:
	if not _active(params) or not (params.get("effect") is Dictionary):
		return JsonRpcPeer.fail(-32041, "no such active turn or no effect")
	return effects.validate(session, Catalog.data, busy_turn, params["effect"])


func handle_engine_lookup(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	return Lookup.find(session, Catalog.data, str(params.get("kind", "")), str(params.get("id", "")))


func handle_engine_find_items(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.mark_searched(busy_turn)
	var base := str(params.get("base", "")) if params.get("base") != null else ""
	return {"items": ItemRules.find(Catalog.data["items"], session.items, str(params.get("query", "")), base,
		params.get("properties", []))}
