extends Node
## Connection to the LLM backend (ADR-0007/0009): wraps BackendClient, logs the protocol, answers engine.*
## through GameState and diagnoses why the master is unreachable. Connects at start and keeps reconnecting.
## With no address set it runs the master's server itself (EmbeddedServer, ADR-0014).

const DIAG_SERVER_DOWN := "server_down"
const DIAG_CERTIFICATE := "certificate"
const DIAG_TOKEN := "token"
const DIAG_UNKNOWN := "unknown"
const DIAG_NO_KEY := "no_key"
const DIAG_KEY_REJECTED := "key_rejected"
const DIAG_SERVER_CRASHED := "server_crashed"
const DIAG_STARTING := "starting"

signal diagnosed(diag: String)
signal key_needed

## What the player set; `config` is what the client uses (the embedded server's address and one-time token).
var stored: BackendConfig
var config: BackendConfig
var client: BackendClient
var server := EmbeddedServer.new()
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
	server.started.connect(func() -> void: connect_with(stored))
	server.restarting.connect(func() -> void: connect_with(stored))
	server.failed.connect(_on_server_failed)
	connect_with(BackendConfig.load_from(config_path()))


func config_path() -> String:
	return SaveManager.path_in_profile("backend.cfg")


func _process(_delta: float) -> void:
	server.poll()
	if client != null:
		client.poll()


## The game's end stops the child; a crash of the game is the child's own watch.
func _exit_tree() -> void:
	server.stop()


## (Re)connects with `cfg`; the old client is stopped first. With no address — through the embedded server, which
## is started here and calls back when it is up.
func connect_with(cfg: BackendConfig) -> void:
	stored = cfg
	var use := cfg.copy()
	var go := true
	if not use.url.is_empty():
		server.stop()
	elif EmbeddedServer.find_exe().is_empty():
		use.url = BackendConfig.DEV_URL
	else:
		go = _prepare_embedded(use)
	_open(use, go)
	if not go:
		_on_state_changed(state(), "")
		if diagnosis_now() == DIAG_NO_KEY:
			key_needed.emit()


## True when the server is up and `use` holds its address and token; else it is on its way or cannot run.
func _prepare_embedded(use: BackendConfig) -> bool:
	if use.openrouter_key.is_empty() and EmbeddedServer.needs_key():
		server.stop()
		return false
	if not server.serves(use.openrouter_key):
		server.start(use.openrouter_key, ProjectSettings.globalize_path(SaveManager.path_in_profile("master")))
	if server.state != EmbeddedServer.State.RUNNING:
		return false
	use.url = server.url
	use.token = server.token
	return true


func _open(cfg: BackendConfig, go: bool) -> void:
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
	if go:
		client.start()


func reconnect() -> void:
	connect_with(stored)


## Saves address, token, CA and the OpenRouter key to backend.cfg (outside the repo) and reconnects.
func save_config(url: String, token: String, ca_cert_path: String, openrouter_key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("backend", "url", url)
	cfg.set_value("backend", "token", token)
	cfg.set_value("backend", "ca_cert", ca_cert_path)
	cfg.set_value("backend", "openrouter_key", openrouter_key)
	cfg.save(config_path())
	# Re-read so env and command-line overrides keep winning.
	connect_with(BackendConfig.load_from(config_path()))


## The key alone, from the window that asks for it.
func save_key(openrouter_key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path())
	cfg.set_value("backend", "openrouter_key", openrouter_key)
	cfg.save(config_path())
	connect_with(BackendConfig.load_from(config_path()))


## Where the master is, for the player: the address, or the embedded server's name.
func address() -> String:
	return tr("BACKEND_EMBEDDED") if stored != null and stored.url.is_empty() else config.url


func needs_key() -> bool:
	return diagnosis_now() in [DIAG_NO_KEY, DIAG_KEY_REJECTED]


func is_ready() -> bool:
	return client != null and client.is_ready()


func state() -> int:
	if server.state == EmbeddedServer.State.STARTING:
		return BackendClient.State.CONNECTING
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


## The server's spending today and its daily limit (session.status): {daily_usd (null = none), spent_today_usd,
## account — the OpenRouter balance of the key, 0.113.0}, or {}.
func budget() -> Dictionary:
	if not is_ready():
		return {}
	return _budget_of(await request("session.status", {}, 10.0))


func _budget_of(call: RpcCall) -> Dictionary:
	if call.is_error() or not call.result is Dictionary or not call.result.get("budget") is Dictionary:
		return {}
	var b: Dictionary = (call.result["budget"] as Dictionary).duplicate()
	b["account"] = call.result.get("account")
	return b


## Sets the server's daily limit from the game's settings (session.set_budget, 0.13.0); null = no limit. The new
## budget, or {} on an error.
func set_budget(daily_usd: Variant) -> Dictionary:
	if not is_ready():
		return {}
	return _budget_of(await request("session.set_budget", {"daily_usd": daily_usd}, 10.0))


func request(method: String, params: Dictionary, timeout_s: float) -> RpcCall:
	var started := Time.get_ticks_msec()
	var call := await client.request(method, params, timeout_s).wait()
	last_ms[method] = Time.get_ticks_msec() - started
	return call


func _on_state_changed(new_state: BackendClient.State, detail: String) -> void:
	print("Backend: %s %s" % [BackendClient.State.keys()[new_state], detail])
	EventBus.backend_state_changed.emit(new_state, detail)


func _on_server_failed() -> void:
	_on_state_changed(BackendClient.State.FAILED, server.problem)
	if server.problem == EmbeddedServer.PROBLEM_KEY_REJECTED:
		key_needed.emit()


## What is known about the embedded server without asking anyone; "" — nothing wrong with it.
func diagnosis_now() -> String:
	if stored == null or not stored.url.is_empty() or EmbeddedServer.find_exe().is_empty():
		return ""
	if server.state == EmbeddedServer.State.STARTING:
		return DIAG_STARTING
	if server.problem == EmbeddedServer.PROBLEM_KEY_REJECTED:
		return DIAG_KEY_REJECTED
	if server.problem == EmbeddedServer.PROBLEM_CRASHED:
		return DIAG_SERVER_CRASHED
	return DIAG_NO_KEY if stored.openrouter_key.is_empty() and EmbeddedServer.needs_key() else ""


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
	var known := diagnosis_now()
	if not known.is_empty():
		return known
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
