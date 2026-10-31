extends "res://tools/playtest/playtest_base.gd"
## The master's server started by the game (ADR-0014): python tools/godot_playtest.py --scenario embedded [--real].
## The frozen server.exe of the build comes through BTR_SERVER_EXE, no address is set. A turn, the server killed and
## started anew by the game with a new port and token, a turn again, then the window that asks for the key: none, and refused.

const TURN_TIMEOUT := 200.0


func run() -> void:
	var backend := node("Backend")
	var gs := node("GameState")
	step("no address is set", backend.stored.url.is_empty())
	if not step("the game's own server is up", await wait_until(func() -> bool: return backend.is_ready(), 60.0), backend.address()):
		return
	step("it is on this machine", backend.config.url.begins_with("ws://127.0.0.1:"))
	step("the token is not in the settings", backend.stored.token != backend.config.token)
	if not step("character created", await quick_character()):
		return
	step("enter turn", await _turn_done(gs))
	await _say(gs, "Осматриваю зал")
	step("a turn through the frozen server", not gs.can_retry())
	await shot("turn")

	var url: String = backend.config.url
	var token: String = backend.config.token
	OS.kill(backend.server.pid)
	step("the crash is noticed", await wait_until(func() -> bool: return not backend.is_ready(), 10.0))
	step("the server is started anew", await wait_until(func() -> bool: return backend.is_ready(), 60.0), backend.config.url)
	step("a new port or token", backend.config.url != url or backend.config.token != token)
	await _say(gs, "Прислушиваюсь к разговорам")
	step("a turn after the crash", not gs.can_retry())

	OS.unset_environment(EmbeddedServer.STUB_ENV)
	gs.session = null
	var cfg: RefCounted = backend.stored.copy()
	cfg.openrouter_key = ""
	backend.connect_with(cfg)
	root.get_node("EventBus").navigate.emit("menu", {})
	await frames(5)
	var box := find_all(root, "KeyBox")
	step("no key: the window asks for it", box.size() == 1 and backend.needs_key())
	step("no server without a key", backend.server.state == EmbeddedServer.State.OFF)
	await shot("no_key")
	if not box.is_empty():
		box[0].queue_free()
		await frames(2)
	backend.save_key("sk-or-not-a-real-key")
	step("a wrong key: refused", await wait_until(func() -> bool: return backend.server.problem == EmbeddedServer.PROBLEM_KEY_REJECTED, 60.0))
	await frames(5)
	box = find_all(root, "KeyBox")
	step("a wrong key: the window says so", box.size() == 1 and find(box[0], "KeyText").text == "KEY_REJECTED")
	await shot("key_rejected")
	backend.save_key("")


func _turn_done(gs: Node) -> bool:
	await frames(2)
	return await wait_until(func() -> bool: return not gs.is_busy(), TURN_TIMEOUT) and not gs.can_retry()


func _say(gs: Node, text: String) -> void:
	var game := screen()
	game.get("input").text = text
	game.get("send_button").pressed.emit()
	await _turn_done(gs)
