extends GdUnitTestSuite
## BackendConfig (file → env → args), the ws:// localhost rule; protocol compatibility; RpcCall basics.

const CFG := "user://test_backend.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(CFG)
	OS.set_environment(BackendConfig.TOKEN_ENV, "")


func _write_cfg(url: String, token: String) -> void:
	var f := ConfigFile.new()
	f.set_value("backend", "url", url)
	f.set_value("backend", "token", token)
	f.save(CFG)


func test_file_then_env_then_args() -> void:
	_write_cfg("wss://example.org/ws", "from-file")
	var cfg := BackendConfig.load_from(CFG, PackedStringArray())
	assert_str(cfg.url).is_equal("wss://example.org/ws")
	assert_str(cfg.token).is_equal("from-file")
	OS.set_environment(BackendConfig.TOKEN_ENV, "from-env")
	cfg = BackendConfig.load_from(CFG, PackedStringArray(["--backend-url=ws://127.0.0.1:9000/ws", "--backend-ca=C:/ca.crt"]))
	assert_str(cfg.token).is_equal("from-env")
	assert_str(cfg.url).is_equal("ws://127.0.0.1:9000/ws")
	assert_str(cfg.ca_cert_path).is_equal("C:/ca.crt")


func test_plain_ws_only_for_localhost() -> void:
	var cfg := BackendConfig.new()
	cfg.token = "t"
	for url: String in ["ws://localhost:8765/ws", "ws://127.0.0.1:8765/ws", "ws://[::1]:8765/ws", "wss://example.org/ws"]:
		cfg.url = url
		assert_str(cfg.validate()).override_failure_message(url).is_empty()
	cfg.url = "ws://192.168.1.5:8765/ws"
	assert_str(cfg.validate()).is_not_empty()
	cfg.url = "http://localhost/ws"
	assert_str(cfg.validate()).is_not_empty()


func test_no_token_is_a_config_problem() -> void:
	assert_str(BackendConfig.new().validate()).is_not_empty()


func test_describe_never_shows_the_token() -> void:
	var cfg := BackendConfig.new()
	cfg.token = "super-secret-token"
	assert_str(cfg.describe()).not_contains("super-secret-token")


func test_protocol_compatibility() -> void:
	assert_bool(BackendClient.protocol_compatible("0.1.0", "0.1.5")).is_true()
	assert_bool(BackendClient.protocol_compatible("0.1.0", "0.2.0")).is_false()
	assert_bool(BackendClient.protocol_compatible("1.0.0", "1.3.0")).is_true()
	assert_bool(BackendClient.protocol_compatible("1.0.0", "2.0.0")).is_false()


func test_request_without_connection_fails_at_once() -> void:
	var client := BackendClient.new(BackendConfig.new())
	var call := client.request("turn.request", {}, 5.0)
	assert_bool(call.done).is_true()
	assert_str(call.reason()).is_equal("not_connected")


func test_handler_failure_shape() -> void:
	var f := JsonRpcPeer.fail(-32602, "bad")
	assert_dict(f[JsonRpcPeer.FAILURE_KEY]).is_equal({"code": -32602, "message": "bad"})
