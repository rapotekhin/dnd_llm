extends GdUnitTestSuite
## One road, review 2, group B·C·D (v0.8.4.29.1): a pocket picked by words or by the window, by the hero or a person, is one
## TheftRules.steal and a caught one is the crime `pickpocket`; a tool goes by the check's own `tool` with one
## BackgroundRules.has_tool; Stealth against the watchers is one WatchRules.against with the doer's own invisibility.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	return s


func test_a_purse_by_words_is_the_pockets_road() -> void:
	var s := _hero("brod-tavern-hall")
	var before := Ledger.balance(s)
	TheftRules.steal(s, data, "npc_serving", TheftRules.PURSE, true)
	assert_int(Ledger.balance(s)).is_greater(before)
	var lines := TheftRules.steal(s, data, "npc_serving", TheftRules.PURSE, false)
	assert_str("\n".join(lines)).contains("замечает руку")
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "pickpocket")).is_true()
	assert_bool(s.wanted.is_empty()).is_false()


func test_a_tool_is_one_has_and_goes_by_the_spec() -> void:
	var s := _hero("brod-square")
	s.character["inventory"].erase("thieves_tools")
	assert_bool(BackgroundRules.has_tool(s.character, "thieves_tools")).is_false()
	assert_bool(BackgroundRules.has_tool(s.character, "")).is_false()
	var spec := {"skill": "sleight_of_hand", "dc": 10, "tool": "thieves_tools"}
	assert_bool(Roll.odds(s, data, Sheet.HERO, spec)["failed"]).is_true()
	s.character["inventory"]["thieves_tools"] = 1
	assert_bool(BackgroundRules.has_tool(s.character, "thieves_tools")).is_true()
	assert_bool(Roll.odds(s, data, Sheet.HERO, spec)["failed"]).is_false()


func test_the_heros_invisibility_does_not_hide_another() -> void:
	var s := _hero("brod-square")
	var goblin := {"monster": "goblin"}
	var plain := WatchRules.notice(s, data, Sheet.HERO, goblin)
	ConditionRules.add_effect(s.character, {"condition": "invisible", "ends_on_attack": true, "ends": {"rest": "long"},
		"source": {"kind": "spell", "id": "invisibility", "name": "Невидимость"}})
	assert_int(WatchRules.notice(s, data, goblin)).is_less(Sheet.passive(s, data, goblin))  # the hero is hard to notice
	assert_int(WatchRules.notice(s, data, Sheet.HERO, goblin)).is_equal(plain)  # the goblin is as plain to the hero as before


func test_stealth_against_the_best_watcher() -> void:
	var s := _hero("brod-square")
	var weak := {"monster": "commoner"}
	var sharp := {"monster": "scout"}
	var vs := WatchRules.against(s, data, [weak, sharp], Sheet.HERO, 0)
	assert_int(int(vs["best"])).is_equal(maxi(WatchRules.notice(s, data, weak), WatchRules.notice(s, data, sharp)))
	assert_bool(vs["ok"]).is_false()
	assert_bool(WatchRules.against(s, data, [weak, sharp], Sheet.HERO, 99)["ok"]).is_true()
