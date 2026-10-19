extends GdUnitTestSuite
## Fixes after playtest-1 (roadmap v0.6.5): quest things handed over by the giver, paid options, waiting and the
## master's time, theft by words, foes that cannot act, condition spells, sneaking among people, NPC lines.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.combat_playing = false


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func _fight(s: GameSession, foes: Array) -> void:
	CombatRules.start(s, data, foes)
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT


# --- quests: the letter is a thing -------------------------------------------------------------------


func test_the_letter_comes_from_bruno_and_only_it_goes_to_ilva() -> void:
	var s := _session()
	var world: Dictionary = data["world"]
	assert_array(XpRules.quest_list(s, world).map(func(q: Dictionary) -> String: return q["id"])).not_contains(["letter_to_ilva"])
	s.room_id = "brod-tavern-hall"
	assert_array(QuestRules.offers_here(s, world)).contains(["letter_to_ilva"])
	var lines := QuestRules.accept(s, data, "letter_to_ilva")
	assert_str("\n".join(lines)).contains("Запечатанное письмо Бруно")
	assert_int(int(s.character["inventory"]["bruno_letter"])).is_equal(1)
	s.room_id = "brod-temple"
	s.character["inventory"].erase("bruno_letter")
	assert_str(QuestRules.can_talk(s, world, "letter_to_ilva")).is_equal("QUEST_NEEDS_ITEM")
	s.character["inventory"]["bruno_letter"] = 1
	QuestRules.talk(s, data, "letter_to_ilva")
	assert_bool(s.quests_done.has("letter_to_ilva")).is_true()
	assert_int(int(s.character["xp"])).is_equal(300)
	assert_bool(s.character["inventory"].has("bruno_letter")).is_false()


func test_the_captain_hands_the_writ_and_pack_items_are_in_the_catalog() -> void:
	var s := _session()
	s.room_id = "brod-gate"
	QuestRules.accept(s, data, "ash_over_the_march")
	assert_int(int(s.character["inventory"]["brod_writ"])).is_equal(1)
	assert_str(ItemRules.display_name(data["items"], s.items, "brod_writ")).is_equal("Грамота капитана Ратмира")
	assert_str(str(ItemRules.def_of(data["items"], s.items, "bruno_letter")["text"])).contains("Печать цела")


# --- paid options, waiting, the master's time ---------------------------------------------------------


func test_a_paid_option_needs_the_money() -> void:
	var s := _session()
	GameState.session = s
	s.options = ["Заплатить пять серебряных и выслушать всё"] as Array[String]
	s.option_costs = [50] as Array[int]
	s.character["gold_cp"] = 10
	assert_str(GameState.choose_option(0)).is_equal("MSG_NO_MONEY")
	assert_int(int(s.character["gold_cp"])).is_equal(10)


func test_waiting_until_a_part_of_the_day() -> void:
	var s := _session()
	s.minute = 600
	assert_int(TimeRules.minutes_until(s, data, "hour")).is_equal(60)
	assert_int(TimeRules.minutes_until(s, data, "night")).is_equal(1320 - 600)
	assert_int(TimeRules.minutes_until(s, data, "morning")).is_equal(1440 - 600 + 360)
	assert_str(TimeRules.clock_after(s, 90)).is_equal("11:30")
	s.minute = 360
	assert_int(TimeRules.minutes_until(s, data, "morning")).is_equal(1440)


func test_the_master_moves_the_time_within_its_limit_and_never_in_a_fight() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	var ok := fx.validate(s, data, "t-1", {"kind": "advance_time", "minutes": 240, "reason": "ждёт ночи"})
	assert_bool(ok["accepted"]).is_true()
	assert_bool(fx.validate(s, data, "t-1", {"kind": "advance_time", "minutes": 30})["accepted"]).is_false()  # once a turn
	fx.apply(s, "t-1", [ok["effect_id"]])
	assert_int(s.minute).is_equal(480 + 240)
	assert_bool(fx.validate(s, data, "t-2", {"kind": "advance_time", "minutes": 2000})["accepted"]).is_false()
	_fight(s, [{"monster": "wolf", "col": 2}])
	assert_bool(fx.validate(s, data, "t-3", {"kind": "advance_time", "minutes": 10})["accepted"]).is_false()


func test_a_short_rest_is_an_hour() -> void:
	var s := _session()
	var before := s.minute
	ExplorationRules.short_rest(s, data, 0, s.rng)
	TimeRules.advance(s, data, int(TimeRules.cfg(data)["short_rest_minutes"]))
	assert_int(s.minute - before).is_equal(60)


# --- theft by words -------------------------------------------------------------------------------------


func test_theft_by_words_takes_the_purse_or_the_npc_notices() -> void:
	var s := _session()
	s.room_id = "brod-tavern-hall"
	GameState.session = s
	GameState.busy_turn = "t-1"
	s.character["skills"]["sleight_of_hand"] = 40
	var gold := int(s.character["gold_cp"])
	var r := GameState.handle_engine_check({"turn_id": "t-1", "skill": "sleight_of_hand", "dc_tier": "medium", "target_id": "npc_innkeeper"})
	assert_str(str(r["note"])).contains("движок уже выдал")
	assert_int(int(s.character["gold_cp"])).is_greater(gold)
	var again := GameState.handle_engine_check({"turn_id": "t-1", "skill": "sleight_of_hand", "dc_tier": "medium", "target_id": "npc_innkeeper"})
	assert_str(str(again["note"])).contains("больше ничего нет")
	s.character["skills"]["sleight_of_hand"] = -40
	var miss := GameState.handle_engine_check({"turn_id": "t-1", "skill": "sleight_of_hand", "dc_tier": "medium", "target_id": "npc_serving"})
	assert_str(str(miss["note"])).contains("провалилась")
	assert_int(s.attitude("npc_serving")).is_equal(-2)


# --- foes that cannot act, condition spells -------------------------------------------------------------


func test_an_unconscious_foe_loses_its_turn_and_a_hit_wakes_it_with_a_crit() -> void:
	var s := _session()
	_fight(s, [{"monster": "wolf", "col": 0}])
	var w := CombatRules.fighter(s, "e1")
	w["hp"] = 100
	w["max_hp"] = 100
	CombatRules._add_condition(w, "unconscious", {"rounds": 10, "spell": "sleep", "wake": true, "save": "", "dc": 10})
	var hp := int(s.character["hp"])
	CombatRules.end_player_turn(s, data)
	var lines := CombatRules.next_actor(s, data)
	assert_str("\n".join(lines)).contains("не может действовать")
	assert_int(int(s.character["hp"])).is_equal(hp)
	assert_int(int(w["col"])).is_equal(0)
	var hit := CombatRules.player_attack(s, data, "e1")
	if "\n".join(hit).contains("попадание") or "\n".join(hit).contains("КРИТ"):
		assert_str("\n".join(hit)).contains("КРИТ")
		assert_bool(CombatRules._has(w, "unconscious")).is_false()


func test_sleep_takes_the_weakest_first_from_its_pool() -> void:
	var s := _session("wizard_yalika")
	_fight(s, [{"monster": "wolf", "col": 2}, {"monster": "jackal", "col": 2}, {"monster": "jackal", "col": 2}])
	CombatRules.fighter(s, "e1")["hp"] = 60  # too strong for any pool
	var lines: Array[String] = []
	CombatRules._cast_condition(s, data, "sleep", 1, CombatRules.fighter(s, "e1"), lines)
	assert_str(lines[0]).contains("пул")
	assert_bool(CombatRules._has(CombatRules.fighter(s, "e2"), "unconscious") or CombatRules._has(CombatRules.fighter(s, "e3"), "unconscious")).is_true()
	assert_bool(CombatRules._has(CombatRules.fighter(s, "e1"), "unconscious")).is_false()
	var sk := _session("wizard_yalika")
	_fight(sk, [{"monster": "skeleton", "col": 2}])
	var none: Array[String] = []
	CombatRules._cast_condition(sk, data, "sleep", 1, CombatRules.fighter(sk, "e1"), none)
	assert_bool(CombatRules._has(CombatRules.fighter(sk, "e1"), "unconscious")).is_false()  # the undead do not sleep


func test_hold_person_only_on_humanoids_and_ends_with_concentration() -> void:
	var s := _session("cleric_branko")
	s.character["spell_dc"] = 99
	_fight(s, [{"monster": "bandit", "col": 1}, {"monster": "wolf", "col": 1}])
	var lines: Array[String] = []
	CombatRules._cast_condition(s, data, "hold_person", 2, CombatRules.fighter(s, "e1"), lines)
	assert_bool(CombatRules._has(CombatRules.fighter(s, "e1"), "paralyzed")).is_true()
	CombatRules._cast_condition(s, data, "hold_person", 2, CombatRules.fighter(s, "e2"), lines)
	assert_str(lines[-1]).contains("не действует")
	assert_array(CombatRules.foe_conditions(data, CombatRules.fighter(s, "e1"))[0].split(" ")).is_not_empty()
	assert_str(CombatRules.foe_conditions(data, CombatRules.fighter(s, "e1"))[0]).contains("10 р.")
	var ended := CombatRules.end_spell(s, data, "hold_person")
	assert_str(ended[0]).contains("концентрация")
	assert_bool(CombatRules._has(CombatRules.fighter(s, "e1"), "paralyzed")).is_false()


func test_conditions_run_out_at_the_end_of_the_foe_turn() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "col": 3}])
	var b := CombatRules.fighter(s, "e1")
	CombatRules._add_condition(b, "incapacitated", {"rounds": 1, "spell": "command", "wake": false, "save": "", "dc": 10})
	CombatRules.end_player_turn(s, data)
	var lines := CombatRules.next_actor(s, data)
	assert_str("\n".join(lines)).contains("проходит")
	assert_bool(CombatRules._has(b, "incapacitated")).is_false()
	assert_dict(CombatRules.cast_preview(s, data, "hold_person", 2, "e1")).contains_keys(["condition", "chance"])


# --- sneaking among people, NPC lines, the save ---------------------------------------------------------


func test_sneaking_among_people_is_a_roll_and_a_failure_sticks_to_the_room() -> void:
	var s := _session()
	s.room_id = "brod-tavern-hall"
	GameState.session = s
	s.character["skills"]["stealth"] = -40
	assert_str(GameState.set_sneaking(true)).is_equal("SNEAK_NOTICED")
	assert_bool(s.sneaking).is_false()
	assert_str(s.sneak_noticed).is_equal("brod-tavern-hall")
	s.character["skills"]["stealth"] = 40
	assert_str(GameState.set_sneaking(true)).is_equal("SNEAK_NOTICED")  # they have seen it already
	s.room_id = "brod-tavern-cellar"  # nobody there
	s.sneak_noticed = ""
	assert_str(GameState.set_sneaking(true)).is_empty()
	assert_bool(s.sneaking).is_true()
	s.room_id = "brod-square"
	s.sneaking = false
	assert_str(GameState.set_sneaking(true)).is_empty()  # a good roll among people


func test_an_npc_line_does_not_repeat_the_name() -> void:
	assert_str(ChatView.without_name("Бруно Хмель понижает голос.", "Бруно Хмель")).is_equal("понижает голос.")
	assert_str(ChatView.without_name("Дрогин медленно кивает.", "Дрогин")).is_equal("медленно кивает.")
	assert_str(ChatView.without_name("«Садись», — говорит Бруно.", "Бруно Хмель")).is_equal("«Садись», — говорит Бруно.")


func test_the_new_state_survives_the_save_and_v12_migrates() -> void:
	var s := _session()
	s.option_costs = [50, 0] as Array[int]
	s.pickpocketed = {"npc_innkeeper": 2}
	s.sneak_noticed = "brod-square"
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_array(back.option_costs).is_equal([50, 0])
	assert_int(int(back.pickpocketed["npc_innkeeper"])).is_equal(2)
	assert_str(back.sneak_noticed).is_equal("brod-square")
	var v12: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v12.json"))
	SaveFormat.migrate(v12, {})
	assert_str(v12["session"]["sneak_noticed"]).is_empty()
