extends GdUnitTestSuite
## GameSession: ids, history for the snapshot, slot meta, to_dict/from_dict round trip with the RNG state.


func test_ids_are_sequential() -> void:
	var s := TestUtils.new_session(1)
	assert_str(s.next_turn_id()).is_equal("t-1")
	assert_str(s.next_turn_id()).is_equal("t-2")
	assert_str(s.next_check_id()).is_equal("c-1")


func test_history_keeps_only_player_and_master_lines() -> void:
	var h := TestUtils.session_with_chat().history(4000)
	assert_int(h.size()).is_equal(3)
	assert_dict(h[0]).is_equal({"role": "dm", "text": "Таверна «Пьяный гусь»."})
	assert_dict(h[1]).is_equal({"role": "player", "text": "осматриваюсь"})


func test_history_limit_takes_the_latest() -> void:
	var h := TestUtils.session_with_chat().history(5)
	assert_int(h.size()).is_equal(1)
	assert_str(h[0]["text"]).is_equal("Ничего необычного.")


func test_meta_previews_the_last_narration() -> void:
	var m := TestUtils.session_with_chat().meta()
	assert_int(m["turns"]).is_equal(2)
	assert_str(m["preview"]).is_equal("Ничего необычного.")


func test_round_trip_keeps_everything_and_the_rng_continues() -> void:
	var s := TestUtils.session_with_chat()
	s.rng.randi()  # move the state away from the seed
	var json := JSON.stringify(s.to_dict(500))
	var back := GameSession.from_dict(JSON.parse_string(json))
	assert_int(back.game_seed).is_equal(42)
	assert_int(back.turn_counter).is_equal(s.turn_counter)
	assert_int(back.check_counter).is_equal(s.check_counter)
	assert_array(back.chat).is_equal(s.chat)
	assert_array(back.options).is_equal(["Подойти к стойке"])
	assert_str(back.room_id).is_equal(TestUtils.START_ROOM)
	assert_dict(back.character).is_equal(s.character)
	assert_int(back.rng.randi()).is_equal(s.rng.randi())


func test_saved_chat_is_trimmed_to_the_latest() -> void:
	var d := TestUtils.session_with_chat().to_dict(2)
	assert_int(d["chat"].size()).is_equal(2)
	assert_str(d["chat"][1]["text"]).is_equal("Ничего необычного.")


func test_history_keeps_applied_effects() -> void:
	var s := TestUtils.session_with_chat()
	s.append(GameSession.effect_entry(["−4 мм", "Получено: Кружка эля"]))
	var h := s.history(4000)
	assert_dict(h[-1]).is_equal({"role": "dm", "text": "[Движок уже применил: −4 мм · Получено: Кружка эля]"})


## The pre-fight save keeps the fight about to start (v0.7.2: loading it after a lost fight skipped the fight).
func test_the_fight_on_load_survives_the_save() -> void:
	var s := TestUtils.new_session()
	s.fight_on_load = {"foes": [{"monster": "wolf", "name": "Волк", "col": 1}], "source": {"encounter": "trail_wolves", "room_from": "brod-gate"}}
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_str(str(back.fight_on_load["source"]["encounter"])).is_equal("trail_wolves")
	assert_int((back.fight_on_load["foes"] as Array).size()).is_equal(1)
	assert_dict(GameSession.from_dict(JSON.parse_string(JSON.stringify(TestUtils.new_session().to_dict(500)))).fight_on_load).is_empty()
