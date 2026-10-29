extends Node
## Connection to the LLM backend (ADR-0007/0009): wraps BackendClient, logs the protocol, answers engine.*
## through GameState and diagnoses why the master is unreachable. Connects at start and keeps reconnecting.

const DIAG_SERVER_DOWN := "server_down"
const DIAG_CERTIFICATE := "certificate"
const DIAG_TOKEN := "token"
const DIAG_UNKNOWN := "unknown"

signal diagnosed(diag: String)

var config: BackendConfig
var client: BackendClient
var protocol_log := ProtocolLog.new()
## Last round-trip times by method, ms (F3 overlay).
var last_ms: Dictionary[String, int] = {}

var _http: HTTPRequest
var _diagnosing: bool = false


func _ready() -> void:
	protocol_log.open(SaveManager.path_in_profile("logs/protocol.jsonl"))
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	connect_with(BackendConfig.load_from(config_path()))


func config_path() -> String:
	return SaveManager.path_in_profile("backend.cfg")


func _process(_delta: float) -> void:
	if client != null:
		client.poll()


## (Re)connects with `cfg`; the old client is stopped first.
func connect_with(cfg: BackendConfig) -> void:
	if client != null:
		client.state_changed.disconnect(_on_state_changed)
		client.stop()
	config = cfg
	client = BackendClient.new(cfg)
	client.peer.traffic.connect(protocol_log.record)
	client.peer.traffic.connect(Trace.record_rpc)
	client.peer.register_handler("engine.check", GameState.handle_engine_check)
	client.peer.register_handler("engine.validate", GameState.handle_engine_validate)
	client.peer.register_handler("engine.lookup", GameState.handle_engine_lookup)
	client.peer.register_handler("engine.find_items", GameState.handle_engine_find_items)
	client.peer.register_handler("engine.find_npcs", GameState.handle_engine_find_npcs)  # v0.7.20
	client.peer.register_handler("engine.find_quests", GameState.handle_engine_find_quests)  # v0.7.21
	client.peer.register_handler("engine.find_places", GameState.handle_engine_find_places)  # v0.7.20.1
	client.peer.register_handler("engine.find_teachers", GameState.handle_engine_find_teachers)  # v0.7.39.7
	client.state_changed.connect(_on_state_changed)
	client.start()


func reconnect() -> void:
	connect_with(config)


## Saves address, token and CA to backend.cfg (outside the repo) and reconnects.
func save_config(url: String, token: String, ca_cert_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("backend", "url", url)
	cfg.set_value("backend", "token", token)
	cfg.set_value("backend", "ca_cert", ca_cert_path)
	cfg.save(config_path())
	# Re-read so env and command-line overrides keep winning.
	connect_with(BackendConfig.load_from(config_path()))


func is_ready() -> bool:
	return client != null and client.is_ready()


func state() -> int:
	return client.state if client != null else BackendClient.State.OFFLINE


## Models the server offers (session.hello): [{id, name, input_usd_per_mtok, output_usd_per_mtok}].
func models() -> Array:
	return client.server_info.get("models", []) if client != null else []


## The image models of the brush (0.71.0): [{id, name, usd_per_image}]; empty — the server draws nothing.
func image_models() -> Array:
	return client.server_info.get("image_models", []) if client != null else []


func default_image_model() -> String:
	return str(client.server_info.get("image_model", "")) if client != null else ""


func default_model() -> String:
	return str(client.server_info.get("model", "")) if client != null else ""


## The server's spending today and its daily limit (session.status): {daily_usd (null = none), spent_today_usd}, or {}.
func budget() -> Dictionary:
	if not is_ready():
		return {}
	var call := await request("session.status", {}, 10.0)
	return call.result.get("budget", {}) if not call.is_error() and call.result is Dictionary else {}


## Sets the server's daily limit from the game's settings (session.set_budget, 0.13.0); null = no limit. The new
## budget, or {} on an error.
func set_budget(daily_usd: Variant) -> Dictionary:
	if not is_ready():
		return {}
	var call := await request("session.set_budget", {"daily_usd": daily_usd}, 10.0)
	return call.result.get("budget", {}) if not call.is_error() and call.result is Dictionary else {}


func request(method: String, params: Dictionary, timeout_s: float) -> RpcCall:
	var started := Time.get_ticks_msec()
	var call := await client.request(method, params, timeout_s).wait()
	last_ms[method] = Time.get_ticks_msec() - started
	return call


func _on_state_changed(new_state: BackendClient.State, detail: String) -> void:
	print("Backend: %s %s" % [BackendClient.State.keys()[new_state], detail])
	EventBus.backend_state_changed.emit(new_state, detail)


## Why the socket does not open (ADR-0009 §9): Godot cannot tell no server / HTTP 401 / TLS apart,
## so ask GET /healthz over plain HTTP(S) with the same TLS options. Emits `diagnosed` with one of DIAG_*.
func request_diagnosis() -> void:
	if _diagnosing:
		return
	_diagnosing = true
	var diag := await _diagnose()
	_diagnosing = false
	diagnosed.emit(diag)


func _diagnose() -> String:
	if client != null and client.reason == BackendClient.REASON_CONFIG:
		return DIAG_TOKEN
	var url := config.url.replace("wss://", "https://").replace("ws://", "http://")
	url = url.get_slice("://", 0) + "://" + url.get_slice("://", 1).get_slice("/", 0) + "/healthz"
	var tls := config.tls_options()
	if tls != null:
		_http.set_tls_options(tls)
	if _http.request(url) != OK:
		return DIAG_UNKNOWN
	var res: Array = await _http.request_completed
	var result: int = res[0]
	var code: int = res[1]
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		return DIAG_TOKEN  # the server answers, so the socket was refused: almost always the token
	if result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
		return DIAG_CERTIFICATE
	if result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_TIMEOUT,
			HTTPRequest.RESULT_CONNECTION_ERROR]:
		return DIAG_SERVER_DOWN
	return DIAG_UNKNOWN
