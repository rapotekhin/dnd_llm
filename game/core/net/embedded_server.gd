class_name EmbeddedServer
extends RefCounted
## The master's server as a child of the game (ADR-0014): server.exe (`server` on Linux) beside the game, on 127.0.0.1 and a port the system
## picks. The token is new at every start and lives in memory; it and the player's key reach the child through its
## environment, never its command line. The server tells its port through a file when it is up, keeps a log of its
## own and ends with the game even when the game crashes (llm_server/embedded.py).

signal started
signal restarting
signal failed

enum State { OFF, STARTING, RUNNING, FAILED }

const EXE_NAME := "server.exe"
const EXE_NAME_UNIX := "server"  ## the Linux build's (tools/build_game.py --linux)
const EXE_ENV := "BTR_SERVER_EXE"  ## a frozen server for a run from the editor
const STUB_ENV := "LLM_SERVER_TURN_HANDLER"
const EXIT_KEY_REJECTED := 3  # llm_server/__main__.py
const START_TIMEOUT_S := 60.0  # the key check and the model lists, each with a timeout of 10 s
const MAX_RESTARTS := 3
const STABLE_S := 60.0  ## alive this long, the next crash is counted anew
const POLL_MS := 200

const PROBLEM_KEY_REJECTED := "key_rejected"
const PROBLEM_CRASHED := "crashed"

var state: State = State.OFF
var problem: String = ""  ## why FAILED: one of PROBLEM_*
var url: String = ""
var token: String = ""
var key: String = ""
var pid: int = 0
var exe: String = ""
var args: PackedStringArray = []  ## for a test's stand-in; the server takes none

var _dir: String = ""
var _restarts: int = 0
var _deadline_ms: int = 0
var _running_since_ms: int = 0
var _next_poll_ms: int = 0


## The server to run, "" when there is none: a run from the editor without one uses the developer's own.
static func find_exe() -> String:
	var path := OS.get_environment(EXE_ENV)
	if path.is_empty():
		path = OS.get_executable_path().get_base_dir().path_join(EXE_NAME if OS.get_name() == "Windows" else EXE_NAME_UNIX)
	return path if FileAccess.file_exists(path) else ""


## Without a key a server can only stub: the turn handler comes from the environment in the build's own check.
static func needs_key() -> bool:
	return OS.get_environment(STUB_ENV) != "stub"


static func ws_url(port: int) -> String:
	return "ws://127.0.0.1:%d/ws" % port


## (Re)starts for `api_key`; `dir` — an absolute folder for the port file, the log and the server's data.
func start(api_key: String, dir: String) -> void:
	stop()
	key = api_key
	_dir = dir
	_restarts = 0
	_spawn()


func stop() -> void:
	if state in [State.STARTING, State.RUNNING]:
		OS.kill(pid)
	_remove_port_file()
	state = State.OFF
	problem = ""
	url = ""
	token = ""


func serves(api_key: String) -> bool:
	return state in [State.STARTING, State.RUNNING] and key == api_key


## Once in a while: notices the port and the child's end.
func poll() -> void:
	var now := Time.get_ticks_msec()
	if state not in [State.STARTING, State.RUNNING] or now < _next_poll_ms:
		return
	_next_poll_ms = now + POLL_MS
	if not OS.is_process_running(pid):
		_on_exit(OS.get_process_exit_code(pid), now)
	elif state == State.STARTING:
		var port := _read_port()
		if port > 0:
			state = State.RUNNING
			url = ws_url(port)
			_running_since_ms = now
			started.emit()
		elif now >= _deadline_ms:
			OS.kill(pid)
			_fail(PROBLEM_CRASHED)


func _spawn() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	_remove_port_file()
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	var env := {
		"LLM_SERVER_TOKEN": token,
		"OPENROUTER_API_KEY": key,
		"LLM_SERVER_PORT_FILE": _port_path(),
		"LLM_SERVER_LOG_FILE": _dir.path_join("server.log"),
		"LLM_SERVER_DATA_DIR": _dir,
		"LLM_SERVER_PARENT_PID": str(OS.get_process_id()),
	}
	for name: String in env:
		OS.set_environment(name, str(env[name]))
	pid = OS.create_process(exe if not exe.is_empty() else find_exe(), args, false)
	for name: String in env:  # the game keeps no copy for what it starts later
		OS.unset_environment(name)
	if pid <= 0:
		_fail(PROBLEM_CRASHED)
		return
	state = State.STARTING
	problem = ""
	url = ""
	_deadline_ms = Time.get_ticks_msec() + int(START_TIMEOUT_S * 1000.0)


func _on_exit(code: int, now: int) -> void:
	_remove_port_file()
	if code == EXIT_KEY_REJECTED:
		_fail(PROBLEM_KEY_REJECTED)
		return
	push_warning("EmbeddedServer: the server ended, code %d" % code)
	if state == State.RUNNING and now - _running_since_ms >= int(STABLE_S * 1000.0):
		_restarts = 0
	if _restarts >= MAX_RESTARTS:
		_fail(PROBLEM_CRASHED)
		return
	_restarts += 1
	_spawn()
	restarting.emit()


func _fail(why: String) -> void:
	state = State.FAILED
	problem = why
	url = ""
	token = ""
	failed.emit()


func _port_path() -> String:
	return _dir.path_join("port")


func _read_port() -> int:
	return FileAccess.get_file_as_string(_port_path()).strip_edges().to_int()


func _remove_port_file() -> void:
	if not _dir.is_empty():
		DirAccess.remove_absolute(_port_path())
