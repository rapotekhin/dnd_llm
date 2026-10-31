extends GdUnitTestSuite
## The child server's life (ADR-0014): the port file, a crash and its restarts, a rejected key, the end by a timeout.
## A shell stands in for server.exe; the real one is checked by llm_server/tests/test_embedded.py and tools/build_game.py.

const SHELL := "cmd.exe"
const DIR := "user://test_embedded"


func _server(script: String) -> EmbeddedServer:
	var server := EmbeddedServer.new()
	server.exe = SHELL
	server.args = PackedStringArray(["/c", script])
	return server


func _dir() -> String:
	return ProjectSettings.globalize_path(DIR)


func _run_until(server: EmbeddedServer, states: Array, timeout_ms: int = 5000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while server.state not in states and Time.get_ticks_msec() < deadline:
		server.poll()
		await get_tree().process_frame


func after_test() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func test_the_port_file_makes_it_running_and_stop_kills_it() -> void:
	var server := _server("ping -n 30 127.0.0.1 > nul")
	server.start("key", _dir())
	assert_int(server.state).is_equal(EmbeddedServer.State.STARTING)
	assert_str(server.token).has_length(64)
	var first := server.token
	var f := FileAccess.open(DIR.path_join("port"), FileAccess.WRITE)
	f.store_string("54321")
	f.close()
	await _run_until(server, [EmbeddedServer.State.RUNNING])
	assert_int(server.state).is_equal(EmbeddedServer.State.RUNNING)
	assert_str(server.url).is_equal("ws://127.0.0.1:54321/ws")
	var pid := server.pid
	assert_bool(OS.is_process_running(pid)).is_true()
	server.stop()
	await get_tree().create_timer(0.3).timeout
	assert_bool(OS.is_process_running(pid)).is_false()
	assert_bool(FileAccess.file_exists(DIR.path_join("port"))).is_false()
	server.start("key", _dir())
	assert_str(server.token).is_not_equal(first)
	server.stop()


func test_the_secrets_do_not_stay_in_the_game() -> void:
	var server := _server("ping -n 30 127.0.0.1 > nul")
	server.start("my-key", _dir())
	assert_str(OS.get_environment("OPENROUTER_API_KEY")).is_empty()
	assert_str(OS.get_environment("LLM_SERVER_TOKEN")).is_empty()
	server.stop()


func test_a_rejected_key_is_not_restarted() -> void:
	var server := _server("exit 3")
	server.start("bad", _dir())
	await _run_until(server, [EmbeddedServer.State.FAILED])
	assert_int(server.state).is_equal(EmbeddedServer.State.FAILED)
	assert_str(server.problem).is_equal(EmbeddedServer.PROBLEM_KEY_REJECTED)


func test_a_crash_restarts_a_few_times_then_gives_up() -> void:
	var server := _server("exit 1")
	var restarts: Array[int] = [0]
	server.restarting.connect(func() -> void: restarts[0] += 1)
	server.start("key", _dir())
	await _run_until(server, [EmbeddedServer.State.FAILED], 10000)
	assert_int(restarts[0]).is_equal(EmbeddedServer.MAX_RESTARTS)
	assert_str(server.problem).is_equal(EmbeddedServer.PROBLEM_CRASHED)


func test_the_key_decides_whether_it_serves() -> void:
	var server := _server("ping -n 30 127.0.0.1 > nul")
	assert_bool(server.serves("key")).is_false()
	server.start("key", _dir())
	assert_bool(server.serves("key")).is_true()
	assert_bool(server.serves("other")).is_false()
	server.stop()
