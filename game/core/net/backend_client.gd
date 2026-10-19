class_name BackendClient
extends RefCounted
## Session with the LLM backend: connect → session.hello → READY, reconnect with a growing pause (ADR-0009 §1).
## The future Backend autoload wraps this and shows the state in the menu and HUD.

enum State { OFFLINE, CONNECTING, HANDSHAKE, READY, WAITING_RETRY, FAILED }

signal state_changed(state: State, detail: String)

## Keep in sync with llm_server/src/llm_server/protocol.py and contract/schema/protocol_version.json.
const PROTOCOL_VERSION := "0.10.0"
const RETRY_DELAYS_S: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]
## WebSocketPeer may sit in CONNECTING forever (e.g. a refused IPv6 address), so the client gives up itself.
const CONNECT_TIMEOUT_S := 10.0

const REASON_CONFIG := "config"  # no token or a bad URL (BackendConfig.validate)
const REASON_UNREACHABLE := "unreachable"  # closed before opening: server down, HTTP 401 or TLS
const REASON_TIMEOUT := "timeout"
const REASON_CLOSED := "closed"
const REASON_VERSION := "version"
const REASON_STOPPED := "stopped"

var config: BackendConfig
var peer: JsonRpcPeer = JsonRpcPeer.new()
var state: State = State.OFFLINE
var auto_reconnect: bool = true
## session.hello result: protocol_version, server_version, model, limits.
var server_info: Dictionary = {}
## Why the client is not READY, for the UI: one of the REASON_* constants, "" when READY.
var reason: String = ""

var _attempt: int = 0
var _retry_at_ms: int = 0
var _connect_deadline_ms: int = 0


func _init(backend_config: BackendConfig) -> void:
	config = backend_config
	peer.opened.connect(_on_opened)
	peer.closed.connect(_on_closed)


static func protocol_compatible(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	if pa.size() < 2 or pb.size() < 2 or pa[0] != pb[0]:
		return false
	# While major is 0, a minor bump is breaking too.
	return pa[0] != "0" or pa[1] == pb[1]


func start() -> void:
	var problem := config.validate()
	if not problem.is_empty():
		reason = REASON_CONFIG
		_set_state(State.FAILED, problem)
		return
	_connect()


func stop() -> void:
	auto_reconnect = false
	peer.close()
	reason = REASON_STOPPED
	_set_state(State.OFFLINE, "stopped")


func poll() -> void:
	peer.poll()
	var now := Time.get_ticks_msec()
	if state == State.WAITING_RETRY and now >= _retry_at_ms:
		_connect()
	elif state == State.CONNECTING and now >= _connect_deadline_ms:
		peer.abort()
		reason = REASON_TIMEOUT
		_schedule_retry("connect timeout after %.0f s" % CONNECT_TIMEOUT_S)


func is_ready() -> bool:
	return state == State.READY


func request(method: String, params: Dictionary, timeout_s: float) -> RpcCall:
	if state != State.READY:
		var call := RpcCall.new("", method, 0.0)
		call.finish(null, {"code": JsonRpcPeer.ERR_CONNECTION_LOST, "message": "not_connected",
			"data": {"reason": "not_connected", "retryable": true}})
		return call
	return peer.request(method, params, timeout_s)


func _connect() -> void:
	var err := peer.open(config.url, config.token, config.tls_options())
	if err != OK:
		_schedule_retry("cannot open socket (error %d)" % err)
		return
	_connect_deadline_ms = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_S * 1000.0)
	_set_state(State.CONNECTING, config.url)


func _on_opened() -> void:
	_set_state(State.HANDSHAKE, "")
	var call := await peer.request("session.hello", {
		"protocol_version": PROTOCOL_VERSION,
		"client_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
	}, config.hello_timeout_s).wait()
	if call.is_error():
		if call.reason() == "version_mismatch":
			auto_reconnect = false
			reason = REASON_VERSION
			_set_state(State.FAILED, str(call.error.get("message", "version_mismatch")))
		peer.close()
		return
	var info: Dictionary = call.result
	if not protocol_compatible(PROTOCOL_VERSION, str(info.get("protocol_version", ""))):
		auto_reconnect = false
		reason = REASON_VERSION
		_set_state(State.FAILED, "server protocol %s" % info.get("protocol_version"))
		peer.close()
		return
	server_info = info
	_attempt = 0
	reason = ""
	_set_state(State.READY, "%s, model %s" % [info.get("server_version"), info.get("model")])


func _on_closed(code: int, close_reason: String) -> void:
	server_info = {}
	if state == State.FAILED:
		return
	# Godot cannot tell "no server" from "HTTP 401" or a TLS failure: all of them close before opening.
	reason = REASON_UNREACHABLE if code == -1 else REASON_CLOSED
	var detail := "could not connect (server down, bad token or TLS)" if code == -1 else "closed %d %s" % [code, close_reason]
	if auto_reconnect:
		_schedule_retry(detail)
	else:
		_set_state(State.OFFLINE, detail)


func _schedule_retry(detail: String) -> void:
	if not auto_reconnect:
		_set_state(State.OFFLINE, detail)
		return
	var delay := RETRY_DELAYS_S[mini(_attempt, RETRY_DELAYS_S.size() - 1)]
	_attempt += 1
	_retry_at_ms = Time.get_ticks_msec() + int(delay * 1000.0)
	_set_state(State.WAITING_RETRY, "%s; retry in %.0f s" % [detail, delay])


func _set_state(new_state: State, detail: String) -> void:
	state = new_state
	state_changed.emit(new_state, detail)
