extends GdUnitTestSuite
## v0.8.4.44.7, the dream's last hall (docs/design/systems/tutorial/description.md, decisions 9 and 12): the adult red dragon
## imported above the danger ceiling; Frightful Presence comes with its blows once and spares whom it caught; Legendary
## Resistance turns three failed saves into successes; legendary actions at the end of another's turn — a tail at one, a Wing
## Attack at two with a flight after; the area of a save action read by its shape. A death in the dream brings the hero back to
## the entry of the hall; in the last hall the dream is over and the wake comes.

const DRAGON := "adult_red_dragon"

var data: Dictionary
var _done: bool
var _settings_path: String
var _saved_dir: String


func before_test() -> void:
	data = TestUtils.data()
	_settings_path = SaveManager.settings_path
	_done = SaveManager.tutorial_done
	SaveManager.tutorial_done = false
	SaveManager.settings_path = "user://test_dragon_settings.cfg"
	_saved_dir = SaveManager.save_dir
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)


func after_test() -> void:
	SaveManager.delete_slot(GameState.DREAM_SAVE)
	GameState.session = null
	GameState.busy_turn = ""
	Catalog.activate("frontier")
	DirAccess.remove_absolute(SaveManager.settings_path)
	SaveManager.settings_path = _settings_path
	SaveManager.tutorial_done = _done
	SaveManager.save_dir = _saved_dir


func _action(en: String) -> Dictionary:
	for a: Dictionary in data["monsters"][DRAGON]["actions"]:
		if str(a["name_en"]) == en:
			return a
	return {}


## A fight with the dragon beside the hero, the hero made strong enough to stand its blows; `allies` beside the hero.
func _fight(allies: Array = []) -> GameSession:
	var s := ChecklistProbe.session(data)
	CombatRules.start(s, data, [{"monster": DRAGON, "x": 41, "y": 30}], {"field": {"w": 80, "h": 60}, "allies": allies})
	FightGrid.put(CombatRules.player(s), Vector2i(40, 30))
	s.character["max_hp"] = 900
	s.character["hp"] = 900
	return s


func _dragon(s: GameSession) -> Dictionary:
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func test_the_dragon_is_imported_whole() -> void:
	var m: Dictionary = data["monsters"][DRAGON]
	assert_int(int(m["legendary"]["per_round"])).is_equal(3)
	var costs := {}
	for row: Dictionary in m["legendary"]["actions"]:
		costs[str(row["name_en"])] = int(row["cost"])
	assert_dict(costs).is_equal({"Detect": 1, "Tail Attack": 1, "Wing Attack": 2})
	assert_int(int(MonsterRules.trait_of(data, {"monster": DRAGON}, "legendary_resistance")["per_day"])).is_equal(3)
	var fp := MonsterRules.area_of(_action("Frightful Presence"))
	assert_dict(fp).is_equal({"type": "sphere", "size": 120, "around": true, "choice": true})
	assert_str(str(_action("Fire Breath")["save"]["success"])).is_equal("half")


func test_the_area_of_a_save_action_is_read_by_its_shape() -> void:
	assert_dict(MonsterRules.area_of(_action("Fire Breath"))).is_equal({"type": "cone", "size": 60, "around": false, "choice": false})
	assert_str(str(MonsterRules.area_of({"effect": {"area": {"shape": "burst", "ft": 10}}})["type"])).is_equal("sphere")
	assert_dict(MonsterRules.area_of({"effect": {}})).is_empty()


func test_frightful_presence_comes_with_the_blows_once() -> void:
	var s := _fight()
	var dragon := _dragon(s)
	var p := CombatRules.player(s)
	var plan: Array = Attack._plan(s, data, dragon, p, _action("Bite")).map(func(a: Dictionary) -> String: return str(a["name_en"]))
	assert_array(plan).contains_exactly(["Frightful Presence", "Bite", "Claw", "Claw"])
	assert_str(str(MonsterRules.save_action(s, data, dragon, p, 1).get("name_en", ""))).is_equal("Fire Breath")  # the fear is never an action of its own
	var lines: Array[String] = []
	Attack.one(s, data, dragon, p, _action("Frightful Presence"), lines)
	assert_bool(MonsterRules.spared(dragon, _action("Frightful Presence"), str(p["id"]))).is_true()
	plan = Attack._plan(s, data, dragon, p, _action("Bite")).map(func(a: Dictionary) -> String: return str(a["name_en"]))
	assert_array(plan).contains_exactly(["Bite", "Claw", "Claw"])


func test_legendary_resistance_turns_three_failures_into_successes() -> void:
	var s := _fight()
	var dragon := _dragon(s)
	for left: int in [2, 1, 0]:
		var r := Sheet.save(s, data, dragon, "dex", 60)
		assert_bool(bool(r["ok"])).is_true()
		assert_str(str(r["text"]) + str(r.get("line", ""))).contains("легендарное сопротивление (осталось %d)" % left)
	assert_bool(bool(Sheet.save(s, data, dragon, "dex", 60)["ok"])).is_false()
	assert_int(MonsterRules.legendary_resist(s, data, CombatRules.player(s))).is_equal(-1)  # the hero has none


func test_legendary_actions_come_at_the_end_of_anothers_turn() -> void:
	var s := _fight()
	var dragon := _dragon(s)
	var p := CombatRules.player(s)
	var lines: Array[String] = []
	MonsterRules.start_turn(s, data, dragon, lines)
	assert_int(MonsterRules.legendary_left(data, dragon)).is_equal(3)
	lines.clear()
	FightAI.legendary(s, data, dragon, lines)  # its own turn's end: none
	assert_array(lines).is_empty()
	for left: int in [2, 1, 0]:
		lines.clear()
		FightAI.legendary(s, data, p, lines)
		assert_str("\n".join(lines)).contains("«Атака хвостом» (осталось %d)" % left)
	lines.clear()
	FightAI.legendary(s, data, p, lines)
	assert_array(lines).is_empty()


func test_a_wing_attack_at_two_and_the_flight_after() -> void:
	var s := _fight([{"monster": "commoner", "x": 41, "y": 33}])
	var dragon := _dragon(s)
	for id: String in CombatRules.friends_of(s, CombatRules.player(s)):
		Sheet.holder(s, CombatRules.fighter(s, id))["hp"] = 900
	MonsterRules.start_turn(s, data, dragon, [] as Array[String])
	var at := FightGrid.cell(dragon)
	var pick := FightAI._legendary_pick(s, data, dragon, MonsterRules.legendary(data, dragon), 3)
	assert_str(str(pick["row"]["name_en"])).is_equal("Wing Attack")
	var lines: Array[String] = []
	FightAI.legendary(s, data, CombatRules.player(s), lines)
	assert_int(MonsterRules.legendary_left(data, dragon)).is_equal(1)
	assert_str("\n".join(lines)).contains("взлетает и отлетает")
	assert_bool(FightGrid.cell(dragon) == at).is_false()


func test_a_death_in_the_dream_is_back_to_the_hall_or_the_end() -> void:
	var tut := WorldPack.apply_rules(TestUtils.base(), WorldPack.load_bundle("res://data/worlds/tutorial", "builtin"))
	var s := TestUtils.new_session()
	s.world_id = "tutorial"
	s.room_id = "dream-3"
	assert_str(DreamRules.fall(s, tut)).is_empty()  # not a dream: a death
	s.dream = {"world": "frontier"}
	assert_str(DreamRules.fall(s, tut)).is_equal(DreamRules.BACK)
	s.room_id = "dream-7"
	assert_str(DreamRules.fall(s, tut)).is_equal(DreamRules.END)
	assert_bool(Cond.holds(s, DreamRules.wake_row(tut["pack"]), tut)).is_false()
	DreamRules.end(s, tut)
	assert_bool(Cond.holds(s, DreamRules.wake_row(tut["pack"]), tut)).is_true()


func _dream() -> GameSession:
	Catalog.activate("frontier")
	var choices: Dictionary = {}
	for p: Dictionary in Catalog.data["presets"]:
		if str(p["id"]) == "wizard_yalika":
			choices = CharacterBuilder.preset_choices(p)
	var settings := WorldPack.default_settings(Catalog.data["pack"])
	settings["tutorial"] = true
	settings["seed"] = "7"
	GameState.new_game(CharacterBuilder.build(choices, Catalog.data), settings, -1, choices)
	GameState.busy_turn = ""
	return GameState.session


func test_a_hall_walked_into_keeps_the_moment_before_and_a_death_brings_it_back() -> void:
	var s := _dream()
	assert_bool(SaveManager.has_slot(GameState.DREAM_SAVE)).is_true()  # the first hall's
	s.character["hp"] = 3  # walked in wounded: the hall comes back whole (DreamRules.again)
	GameState._dream_entry("dream-2")
	assert_bool(s.dream.has("again")).is_false()
	var kept: Variant = SaveManager.read_slot(GameState.DREAM_SAVE)
	assert_bool(kept is GameSession).override_failure_message(str(kept)).is_true()
	var again := ""
	if kept is GameSession:
		again = str((kept as GameSession).dream.get("again", ""))
	assert_bool(again == "dream-2").override_failure_message("again: [%s] %d" % [again, again.length()]).is_true()
	var state := s.rng.state
	s.character["hp"] = 0
	GameState._dream_again()
	var back := GameState.session
	assert_bool(back == s).is_false()
	assert_int(int(back.character["hp"])).is_equal(int(back.character["max_hp"]))
	assert_bool(back.rng.state == state).override_failure_message("the hall again with other dice").is_false()
	assert_bool(back.dream.has("again")).is_false()
	assert_bool(back.chat.any(func(e: Dictionary) -> bool: return str(e.get("key", "")) == "DREAM_AGAIN")).is_true()


func test_the_fight_lost_in_the_last_hall_ends_the_dream() -> void:
	var s := _dream()
	s.room_id = "dream-7"
	s.visited.append("dream-7")
	CombatRules.start(s, Catalog.data, [{"monster": DRAGON, "x": 41, "y": 30}], {"field": {"w": 80, "h": 60}})
	s.combat["outcome"] = "dead"
	GameState._combat_outcome()
	assert_str(str(s.combat["outcome"])).is_equal(GameState.DREAM_END)
	assert_bool(s.flags.has("dream_end")).is_true()
	assert_bool(Cond.holds(s, DreamRules.wake_row(Catalog.data["pack"]), Catalog.data)).is_true()
	GameState.busy_turn = ""
	GameState.finish_combat()
	assert_bool(CombatRules.active(s)).is_false()
	assert_int(int(s.character["hp"])).is_greater(0)


## v0.8.4.44.9 (the tutorial playtest: the hero bound in the goblins' den for good): a dream knows no captivity — taken in
## halls 1–6 is fallen, the hall comes back as after a death.
func test_taken_in_a_hall_before_the_last_is_fallen() -> void:
	var s := _dream()
	ExplorationRules.place(s, "dream-4")
	CombatRules.start(s, Catalog.data, [{"monster": "goblin", "x": 3, "y": 3}], {})
	s.combat["outcome"] = "captured"
	GameState._combat_outcome()
	assert_str(str(s.combat["outcome"])).is_equal("dead")
	assert_bool(s.flags.has("dream_end")).is_false()
