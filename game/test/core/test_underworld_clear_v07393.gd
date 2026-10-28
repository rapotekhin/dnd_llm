extends GdUnitTestSuite
## The underworld made clear (v0.7.39.3, the author's acceptance of «Своя жизнь»): where the picks are — the giver
## names its fence, a recipe at the forge, a hint on the grey «Взломать»; the job as steps in order; done jobs
## followed until the loot is sold and the cut paid.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.character.erase("orgs")
	s.character.erase("fences_known")
	s.room_id = room
	s.minute = 12 * 60
	return s


func test_the_giver_names_its_fence_and_the_candidate_buys_picks() -> void:
	var s := _hero("brod-den")
	assert_bool(FenceRules.known(s, data, "npc_merchant")).is_false()
	var lines := HeistRules.take(s, data, "heist_townhall")
	assert_str(" ".join(lines)).contains("Отмычки и сбыт — у")
	assert_bool(FenceRules.known(s, data, "npc_merchant")).is_true()
	assert_str(FenceRules.tool_hint(s, data, "thieves_tools")).contains("у скупщика")


func test_picks_are_a_recipe_at_the_forge() -> void:
	var s := _hero("brod-smithy")
	s.character["tools"] = ["smiths_tools"]
	s.character["inventory"]["smiths_tools"] = 1
	assert_array(CraftRules.known(s, data)).contains(["thieves_tools"])
	assert_str(FenceRules.tool_hint(s, data, "thieves_tools")).contains("сделать самому")


func test_the_job_is_a_path_in_order() -> void:
	var s := _hero("brod-square")
	HeistRules.take(s, data, "heist_townhall")
	var p := HeistRules.path(s, data, "heist_townhall")
	var titles := p.map(func(x: Dictionary) -> String: return str(x["title"]))
	assert_str(str(titles[0])).contains("Подготовка")
	assert_str(str(titles[1])).contains("Прийти")
	assert_str(str(titles[3])).contains("Сбыть")
	assert_str(str(titles[4])).contains("долю")
	assert_str(str(p[1]["state"])).is_equal("now")
	assert_str(str(p[1]["text"])).contains("идите туда")
	assert_str(str(p[0]["text"])).contains("у скупщика")  # the picks: where to get them


func test_a_done_job_is_followed_until_sold_and_paid() -> void:
	var s := _hero("brod-townhall")
	HeistRules.take(s, data, "heist_townhall")
	HeistRules._rw(s.character)["heist_townhall"]["status"] = "done"
	ItemRules.found(s.character, data, s.items, "signet_ring", 1)
	assert_array(HeistRules.followed(s, data)).contains(["heist_townhall"])
	var p := HeistRules.path(s, data, "heist_townhall")
	assert_str(str(p[3]["state"])).is_equal("now")
	s.character["inventory"].erase("signet_ring")
	assert_array(HeistRules.followed(s, data)).not_contains(["heist_townhall"])
