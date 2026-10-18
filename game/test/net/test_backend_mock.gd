extends GdUnitTestSuite
## Backend + GameState against MockBackend (roadmap v0.4.2): handshake, a turn with an effect reserve, a drop
## mid-turn, cancel, reconnect. Reserves must burn on drop and cancel, and the world must stay untouched.

const TOKEN := "server-token-0123456789"

var server: MockBackend
var _saved_save_dir: String


func before_test() -> void:
	_saved_save_dir = SaveManager.save_dir
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	server = MockBackend.new()
	assert_int(server.start()).is_greater(0)
	var cfg := BackendConfig.new()
	cfg.url = server.url()
	cfg.token = TOKEN
	Backend.connect_with(cfg)
	assert_bool(await _wait(func() -> bool: return Backend.is_ready(), 5.0)).is_true()
	GameState.start(TestUtils.new_session())


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	Backend.client.stop()
	server.stop()
	SaveManager.save_dir = _saved_save_dir


func _wait(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		server.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


## The mock master: on turn.request asks engine.validate for `effect`, then `finish` decides what happens next.
func _script(effect: Dictionary, finish: Callable) -> void:
	var state := {"turn": {}}
	server.on_message = func(m: MockBackend, msg: Dictionary) -> void:
		match str(msg.get("method", "")):
			"turn.request":
				state["turn"] = msg
				m.call_engine("s-1", "engine.validate", {"turn_id": msg["params"]["turn_id"], "effect": effect})
			"turn.cancel":
				m.reply(msg, {"ok": true})
				m.reply_error(state["turn"], -32011, "turn_cancelled")
			"":
				if str(msg.get("id", "")) == "s-1":
					finish.call(m, state["turn"], msg.get("result", {}))


func test_hello_gives_models() -> void:
	assert_str(Backend.default_model()).is_equal("mock/model")
	assert_int(Backend.models().size()).is_equal(1)


func test_turn_applies_the_reserved_effect() -> void:
	_script({"kind": "give_item", "item_id": "torch", "qty": 1}, func(m: MockBackend, turn: Dictionary, validated: Dictionary) -> void:
		m.reply(turn, {"turn_id": turn["params"]["turn_id"], "narration": "Ты берёшь факел.", "options": ["Зажечь"],
			"effect_ids": [validated["effect_id"]], "check_ids": [], "usage": {"model": "mock/model"}}))
	assert_bool(GameState.submit("беру факел со стены")).is_true()
	assert_bool(await _wait(func() -> bool: return not GameState.is_busy(), 5.0)).is_true()
	var s := GameState.session
	assert_int(s.character["inventory"]["torch"]).is_equal(11)  # 10 from the pack + 1
	assert_dict(GameState.effects.reserves).is_empty()
	var kinds: Array = s.chat.map(func(e: Dictionary) -> String: return e["kind"])
	assert_array(kinds).contains([GameSession.KIND_PLAYER, GameSession.KIND_DM, GameSession.KIND_EFFECT])
	var turn: Dictionary = server.received.filter(func(m: Dictionary) -> bool: return m.get("method") == "turn.request")[0]
	assert_str(turn["params"]["snapshot"]["scene"]["room_id"]).is_equal(TestUtils.START_ROOM)
	assert_array(GameState.session.options).is_equal(["Зажечь"])


func test_drop_mid_turn_burns_reserves_and_keeps_the_world() -> void:
	var gold := int(GameState.session.character["gold_cp"])
	_script({"kind": "coins", "delta_cp": -500, "reason": "эль"}, func(m: MockBackend, _turn: Dictionary, _v: Dictionary) -> void:
		m.drop())
	GameState.submit("плачу за эль")
	assert_bool(await _wait(func() -> bool: return not GameState.is_busy(), 5.0)).is_true()
	assert_int(GameState.session.character["gold_cp"]).is_equal(gold)
	assert_dict(GameState.effects.reserves).is_empty()
	assert_str(GameState.session.chat[-1]["key"]).is_equal("MSG_NO_MASTER")
	assert_bool(GameState.can_retry()).is_true()
	# the client reconnects by itself and the turn can be repeated
	assert_bool(await _wait(func() -> bool: return Backend.is_ready(), 6.0)).is_true()
	assert_int(server.connections).is_equal(2)


func test_cancel_burns_reserves() -> void:
	var gold := int(GameState.session.character["gold_cp"])
	_script({"kind": "coins", "delta_cp": -500, "reason": "эль"}, func(_m: MockBackend, _turn: Dictionary, _v: Dictionary) -> void:
		GameState.cancel_turn())
	GameState.submit("плачу за эль")
	assert_bool(await _wait(func() -> bool: return not GameState.is_busy(), 5.0)).is_true()
	assert_int(GameState.session.character["gold_cp"]).is_equal(gold)
	assert_dict(GameState.effects.reserves).is_empty()
	assert_str(GameState.session.chat[-1]["key"]).is_equal("MSG_TURN_CANCELLED")


func test_engine_calls_for_another_turn_are_refused() -> void:
	var answers: Array[Dictionary] = []
	server.on_message = func(m: MockBackend, msg: Dictionary) -> void:
		if msg.get("method") == "turn.request":
			m.call_engine("s-9", "engine.check", {"turn_id": "t-999", "skill": "perception", "dc_tier": "easy"})
		elif str(msg.get("id", "")) == "s-9":
			answers.append(msg)
	GameState.submit("осматриваюсь")
	assert_bool(await _wait(func() -> bool: return not answers.is_empty(), 5.0)).is_true()
	assert_int(int(answers[0]["error"]["code"])).is_equal(-32041)
	GameState.busy_turn = ""


func test_long_rest_asks_the_master_for_the_morning() -> void:
	server.on_message = func(m: MockBackend, msg: Dictionary) -> void:
		if str(msg.get("method", "")) == "turn.request":
			m.reply(msg, {"turn_id": msg["params"]["turn_id"], "narration": "Утро.", "options": [], "effect_ids": [],
				"check_ids": [], "usage": {"model": "mock/model"}})
	assert_str(GameState.long_rest()).is_equal("REST_NOT_SAFE")
	ExplorationRules.enter_room(GameState.session, Catalog.data["world"], "brod-tavern-upstairs")
	GameState.session.character["hp"] = 1
	assert_str(GameState.long_rest()).is_empty()
	assert_bool(await _wait(func() -> bool: return not GameState.is_busy(), 5.0)).is_true()
	var turn: Dictionary = server.received.filter(func(m: Dictionary) -> bool: return m.get("method") == "turn.request")[-1]
	assert_str(turn["params"]["kind"]).is_equal("rest")
	assert_int(GameState.session.character["hp"]).is_equal(int(GameState.session.character["max_hp"]))
