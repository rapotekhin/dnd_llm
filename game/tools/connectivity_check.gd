extends SceneTree
## Headless connectivity check against a running llm_server (M0 spike, ADR-0009).
##   godot --headless --path game --script res://tools/connectivity_check.gd -- \
##       --backend-url=wss://localhost:8443/ws --backend-ca=<root.crt> [--expect=ok|reject] [--idle-s=45]
## --idle-s keeps the connection idle before the turns: server WS pings must keep it alive through the proxy.
## Token: env BTR_BACKEND_TOKEN (or user://backend.cfg). Exit code 0 = expectation met, 1 = not.
## Prints one "RESULT {json}" line with timings; never prints the token.

const OVERALL_TIMEOUT_MS := 30000
const DC_BY_TIER: Dictionary[String, int] = {
	"very_easy": 5, "easy": 10, "medium": 15, "hard": 20, "very_hard": 25, "nearly_impossible": 30,
}

var _client: BackendClient
var _expect: String = "ok"
var _idle_s: float = 0.0
var _rng := RandomNumberGenerator.new()
var _started_ms: int = 0
var _turn_counter: int = 0
var _check_counter: int = 0
var _engine_calls: int = 0
var _finished: bool = false
var _report: Dictionary = {}


func _initialize() -> void:
	_rng.seed = 20261018
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect="):
			_expect = arg.trim_prefix("--expect=")
		elif arg.begins_with("--idle-s="):
			_idle_s = arg.trim_prefix("--idle-s=").to_float()
	var config := BackendConfig.load_from()
	print("connectivity_check: %s, expect %s" % [config.describe(), _expect])
	_report = {"url": config.url, "expect": _expect}
	_client = BackendClient.new(config)
	_client.auto_reconnect = false
	_client.peer.register_handler("engine.check", _engine_check)
	_client.state_changed.connect(_on_state_changed)
	_started_ms = Time.get_ticks_msec()
	_client.start()


func _process(_delta: float) -> bool:
	if _finished:
		return false
	_client.poll()
	if Time.get_ticks_msec() - _started_ms > OVERALL_TIMEOUT_MS + int(_idle_s * 1000.0):
		_finish(false, "overall timeout")
	return false


func _on_state_changed(state: BackendClient.State, detail: String) -> void:
	print("  state %s %s" % [BackendClient.State.keys()[state], detail])
	match state:
		BackendClient.State.READY:
			_report["connect_ms"] = Time.get_ticks_msec() - _started_ms
			_report["server"] = _client.server_info
			if _expect == "reject":
				_finish(false, "connected although the connection should be rejected")
			else:
				_run_turns()
		BackendClient.State.OFFLINE, BackendClient.State.FAILED:
			if _finished:
				return
			if _expect == "reject" and state == BackendClient.State.OFFLINE:
				_finish(true, "rejected as expected: %s" % detail)
			else:
				_finish(false, detail)


func _run_turns() -> void:
	if _idle_s > 0.0:
		await create_timer(_idle_s).timeout
		if not _client.is_ready():
			_finish(false, "connection dropped while idle")
			return
		_report["idle_s"] = _idle_s
	var enter := await _turn("enter", "")
	if enter.is_error():
		_finish(false, "enter turn failed: %s" % enter.error)
		return
	_report["enter_ms"] = _report.get("_last_ms", 0)

	var calls_before := _engine_calls
	var action := await _turn("action", "осматриваю комнату")
	if action.is_error():
		_finish(false, "action turn failed: %s" % action.error)
		return
	_report["action_ms"] = _report.get("_last_ms", 0)
	if _engine_calls != calls_before + 1:
		_finish(false, "expected exactly one engine.check, got %d" % (_engine_calls - calls_before))
		return
	var check_ids: Array = action.result.get("check_ids", [])
	if check_ids != ["c-%d" % _check_counter]:
		_finish(false, "turn.result check_ids %s do not match engine.check" % [check_ids])
		return
	_report["narration"] = action.result.get("narration", "")
	_finish(true, "hello + enter + action with engine.check round trip")


func _turn(kind: String, input: String) -> RpcCall:
	_turn_counter += 1
	var sent := Time.get_ticks_msec()
	var call := await _client.request("turn.request", {
		"turn_id": "t-%d" % _turn_counter,
		"mode": "exploration",
		"kind": kind,
		"input": input,
		"snapshot": {},
	}, 95.0).wait()
	_report["_last_ms"] = Time.get_ticks_msec() - sent
	print("  turn.request %s -> %s (%d ms)" % [kind, "error " + call.reason() if call.is_error() else "ok", _report["_last_ms"]])
	return call


## Stand-in for the real check engine (v0.6.0): seeded d20 + fixed bonus, nat 20/1 house rule (ADR-0008 §2).
func _engine_check(params: Dictionary) -> Dictionary:
	_engine_calls += 1
	var tier := str(params.get("dc_tier", ""))
	if not DC_BY_TIER.has(tier):
		return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, "unknown dc_tier %s" % tier)
	_check_counter += 1
	var roll := _rng.randi_range(1, 20)
	var bonus := 3
	var dc := DC_BY_TIER[tier]
	var success := roll == 20 or (roll != 1 and roll + bonus >= dc)
	print("  engine.check %s %s: %d + %d vs %d" % [params.get("skill", params.get("save", "?")), tier, roll, bonus, dc])
	return {
		"check_id": "c-%d" % _check_counter, "rolls": [roll], "bonus": bonus, "total": roll + bonus,
		"dc": dc, "success": success, "nat": roll, "blocked": false,
	}


func _finish(ok: bool, detail: String) -> void:
	if _finished:
		return
	_finished = true
	_report.erase("_last_ms")
	_report["ok"] = ok
	_report["detail"] = detail
	print("RESULT %s" % JSON.stringify(_report))
	_client.stop()
	quit(0 if ok else 1)
