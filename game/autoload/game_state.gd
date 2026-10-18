extends Node
## The current session and the turn loop: player input → turn.request → engine.check callbacks → turn.result.
## One turn at a time (ADR-0009 §2). Views read `session` and redraw on EventBus signals.

var session: GameSession
## turn_id of the turn in flight, "" when idle.
var busy_turn: String = ""

var _last_kind: String = ""
var _last_input: String = ""


func has_session() -> bool:
	return session != null


func is_busy() -> bool:
	return not busy_turn.is_empty()


func new_game(game_seed: int = -1) -> void:
	if game_seed < 0:
		game_seed = int(LaunchArgs.value("--seed", str(randi())))
	start(GameSession.create(game_seed, Time.get_datetime_string_from_system()))
	_request("enter", "")


func start(s: GameSession) -> void:
	session = s
	busy_turn = ""
	_last_kind = ""
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
	_request("action", text)
	return true


## Repeats the last failed request as a new turn (ADR-0009 §5: no idempotency, a retry is a new turn_id).
func retry() -> void:
	if session != null and not is_busy() and not _last_kind.is_empty():
		_request(_last_kind, _last_input)


## The last turn failed and can be repeated.
func can_retry() -> bool:
	return session != null and not is_busy() and not _last_kind.is_empty()


func cancel_turn() -> void:
	if is_busy() and Backend.is_ready():
		Backend.request("turn.cancel", {"turn_id": busy_turn}, 5.0)


func save_to(slot: String) -> bool:
	return SaveManager.save_slot(slot, session)


## "" on success or a localization key.
func load_from(slot: String) -> String:
	var res: Variant = SaveManager.read_slot(slot)
	if res is String:
		return res
	start(res)
	return ""


func _add(entry: Dictionary) -> void:
	session.append(entry)
	EventBus.chat_appended.emit(entry)


func _set_options(options: Array[String]) -> void:
	session.options = options
	EventBus.options_changed.emit(options)


func _request(kind: String, input: String) -> void:
	var s := session
	var turn_id := s.next_turn_id()
	_last_kind = kind
	_last_input = input
	busy_turn = turn_id
	_set_options([])
	EventBus.turn_started.emit(turn_id)
	var call := await Backend.request("turn.request", {
		"turn_id": turn_id,
		"mode": "exploration",
		"kind": kind,
		"input": input,
		"snapshot": {"history": s.history(int(Catalog.game()["chat"]["history_in_snapshot"]))},
	}, float(Catalog.game()["turn"]["client_timeout_s"]))
	if session != s or busy_turn != turn_id:
		return  # the session was closed or replaced while the master was thinking
	busy_turn = ""
	if call.is_error():
		_add(GameSession.system_entry(_error_key(call.reason())))
		_set_options([])
		EventBus.turn_finished.emit(turn_id, false)
		return
	var result: Dictionary = call.result
	_add(GameSession.dm_entry(str(result.get("narration", "")), turn_id))
	var options: Array[String] = []
	for o: Variant in result.get("options", []):
		options.append(str(o))
	_set_options(options)
	_last_kind = ""
	EventBus.turn_finished.emit(turn_id, true)
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)


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
		_:
			return "MSG_NO_MASTER"


## engine.check from the backend: only for the turn in flight (ADR-0009 §3).
func handle_engine_check(params: Dictionary) -> Dictionary:
	if session == null or str(params.get("turn_id", "")) != busy_turn:
		return JsonRpcPeer.fail(-32041, "no such active turn")
	# Bonus is 0 until characters arrive (v0.5.0).
	var result := CheckEngine.roll(Catalog.rules(), session.rng, params, 0, session.next_check_id())
	if result.has("error"):
		return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, str(result["error"]))
	_add(GameSession.check_entry(params, result))
	return result
