extends GdUnitTestSuite
## v0.8.4.44.5, the screens of teaching (HintRules, docs/design/systems/tutorial/description.md): a row of the pack's
## `hints` is due while its `when` holds, one at a time in the list's order; `after` waits for a master's turn past the
## row named; a dream's screens are once a game whatever the setting, a first-time hint once a profile and not at all
## with hints off; phrases are the master's options for the moment; the dream's end is the last row, «Проснуться».

var dream: Dictionary


func before_test() -> void:
	dream = WorldPack.apply_rules(TestUtils.base(), WorldPack.load_bundle("res://data/worlds/tutorial", "builtin"))


func _at(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.world_id = "tutorial"
	s.room_id = room
	s.visited = [room] as Array[String]
	CreatureRules.seed(s, dream, room)
	return s


## The ids shown one after another while nothing changes in the hall: each due row shown in its turn.
func _queue(s: GameSession, data: Dictionary, seen: Array = [], on: bool = true) -> Array[String]:
	var out: Array[String] = []
	var row := HintRules.due(s, data, seen, on)
	while not row.is_empty() and out.size() < 20:
		out.append(str(row["id"]))
		HintRules.shown(s, row)
		row = HintRules.due(s, data, seen, on)
	return out


func test_the_pack_s_screens_are_valid_and_the_dream_s_end_comes_last() -> void:
	assert_array(Catalog.bundle("tutorial").get("errors", ["нет пакета"])).is_empty()
	var ids: Array = HintRules.rows(dream).map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_array(ids).is_equal(["walk", "look", "search", "body", "gear", "hurt", "captive", "arrows", "improvise", "making", HintRules.WAKE])
	var wake: Dictionary = HintRules.rows(dream).back()
	assert_str(str(wake["button"])).is_equal(HintRules.WAKE)
	assert_str(HintRules.once(wake)).is_equal(HintRules.GAME)
	assert_array(HintRules.rows(TestUtils.data())).is_empty()  # the Mark has no rows yet


func test_the_first_hall_walk_then_look_and_search_after_a_master_s_turn() -> void:
	var s := _at("dream-1")
	assert_array(_queue(s, dream)).is_equal(["walk", "look"])
	s.next_turn_id()  # the player looked around: the master answered
	assert_array(_queue(s, dream)).is_equal(["search"])
	assert_array(_queue(s, dream)).is_empty()  # each once


func test_a_hall_left_takes_its_screens_with_it() -> void:
	var s := _at("dream-3")
	assert_array(_queue(s, dream)).is_equal(["hurt", "captive"])  # the second hall's body and gear are not told late
	Gear.give(s, dream, Being.HERO, "quiver", 1)
	assert_array(_queue(s, dream)).is_equal(["arrows"])


func test_the_gear_screen_waits_for_the_armour_taken() -> void:
	var s := _at("dream-2")
	assert_array(_queue(s, dream)).is_equal(["body"])
	Gear.give(s, dream, Being.HERO, "leather_armor", 1)
	assert_array(_queue(s, dream)).is_equal(["gear"])


func test_the_ready_words_wait_for_the_goblins_and_the_cleric_set_free() -> void:
	var s := _at("dream-4")
	assert_array(_queue(s, dream)).is_empty()
	s.encounters_done.append("dream_goblins")
	assert_bool(Cond.met(s, {"free": "npc_dream_cleric"})).is_false()
	assert_array(_queue(s, dream)).is_empty()
	CreatureRules.act(s, dream, "npc_dream_cleric", "untie")
	assert_bool(Cond.met(s, {"free": "npc_dream_cleric"})).is_true()
	var row := HintRules.due(s, dream, [], true)
	assert_str(str(row["id"])).is_equal("improvise")
	var ph := HintRules.phrases(row, dream)
	assert_array(ph["texts"]).has_size(1)
	var check: Dictionary = ph["checks"][0]
	assert_int(int(CheckEngine.preview(s, dream, check)["dc"])).is_equal(2)  # the pack's own floor


func test_the_phrases_become_the_only_options_of_the_moment() -> void:
	var kept: GameSession = GameState.session
	var s := TestUtils.new_session()
	GameState.session = s
	s.options = ["Свой вариант мастера"] as Array[String]
	var row := {"id": "x", "text": "…", "once": HintRules.GAME, "phrases": ["Раз", {"text": "Два", "check": {"skill": "persuasion", "dc_tier": "easy"}}]}
	GameState.hint_shown(row)
	assert_array(s.options).is_equal(["Раз", "Два"])
	assert_dict(GameState.option_check(1)).contains_keys(["skill", "dc_tier"])
	assert_dict(GameState.option_check(0)).is_empty()
	assert_bool(s.hints.has("x")).is_true()
	GameState.session = kept


func test_a_first_time_hint_is_once_a_profile_and_none_with_hints_off() -> void:
	var data := TestUtils.data().duplicate()
	data["pack"] = (data["pack"] as Dictionary).duplicate(true)
	data["pack"]["hints"] = [{"id": "first_fight", "when": {"room": "tavern_hall"}, "text": "Бой."}, {"id": "dream_only", "text": "Сон.", "once": "game"}]
	var s := TestUtils.new_session()
	s.visited = ["tavern_hall"] as Array[String]
	assert_array(_queue(s, data, [], false)).is_equal(["dream_only"])  # hints off: only the game's own
	var s2 := TestUtils.new_session()
	s2.visited = ["tavern_hall"] as Array[String]
	assert_array(_queue(s2, data, ["first_fight"], true)).is_equal(["dream_only"])  # seen in another game
	var s3 := TestUtils.new_session()
	s3.visited = ["tavern_hall"] as Array[String]
	var row := HintRules.due(s3, data, [], true)
	assert_bool(HintRules.shown(s3, row)).is_true()  # the profile keeps it
	assert_bool(HintRules.shown(s3, data["pack"]["hints"][1])).is_false()


func test_a_screen_points_at_the_hall_s_body_and_captive_by_their_pack_ids() -> void:
	var s2 := _at("dream-2")
	assert_str(HintRules.map_ref(s2, dream, "wanderer")).starts_with("cr:")
	var s3 := _at("dream-3")
	var ref := HintRules.map_ref(s3, dream, "fighter")
	assert_str(ref).starts_with("cr:")
	assert_str(HintRules.map_ref(s3, dream, "npc_dream_fighter")).is_equal(ref)
	assert_str(HintRules.map_ref(s3, dream, "nobody")).is_empty()
	var s1 := _at("dream-1")
	PropRules.ensure(s1, dream, "dream-1")
	assert_str(HintRules.map_ref(s1, dream, "f_chest")).is_equal("prop:f_chest")


func test_a_pack_s_rows_are_checked() -> void:
	assert_array(HintRules.faults({"id": "a"}, [])).has_size(1)  # no text
	assert_array(HintRules.faults({"id": "a", "text": "т"}, ["a"])).has_size(1)
	assert_array(HintRules.faults({"id": "b", "text": "т", "after": "z"}, ["a"])).has_size(1)
	assert_array(HintRules.faults({"id": "b", "text": "т", "once": "always"}, [])).has_size(1)
	assert_array(HintRules.faults({"id": "b", "text": "т", "button": "close"}, [])).has_size(1)
	assert_array(HintRules.faults({"id": "wake", "text": "т"}, [])).has_size(1)
	assert_array(HintRules.faults({"id": "b", "text": "т", "after": "a", "phrases": ["x", {"text": "y"}]}, ["a"])).is_empty()
	var b: Dictionary = Catalog.bundle("tutorial").duplicate(true)
	(b["pack"]["hints"] as Array).append({"id": "walk", "text": "Ещё раз"})
	assert_str("\n".join(WorldPack.validate(b, Catalog.base))).contains("pack.hints")
