extends GdUnitTestSuite
## The place window and the journal (roadmap v0.7.22.7): a quest shows what was done and how its choice went; the
## people tab lists everyone met with their attitude, looks and quests.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_a_quest_tells_what_was_done_and_the_choice() -> void:
	var s := TestUtils.new_session()
	var world: Dictionary = data["world"]
	var qid := ""
	var choice := {}
	for id: String in QuestRules.stepped(world):
		for st: Dictionary in QuestRules.stepped(world)[id]["steps"]:
			if st.has("choices"):
				qid = id
				choice = st["choices"][0]
	assert_str(qid).is_not_empty()
	s.quests_active[qid] = 1
	var h := QuestRules.history(s, world, qid)
	assert_int(h.size()).is_equal(1)
	assert_str(h[0]).starts_with("✓ ")
	s.quests_active.erase(qid)
	s.quests_done.append(qid)
	s.flags.append(str(choice["flag"]))
	h = QuestRules.history(s, world, qid)
	assert_int(h.size()).is_equal((QuestRules.quest(world, qid)["steps"] as Array).size())
	assert_str(" ".join(h)).contains(str(choice["action"]))


func test_take_one_thing_of_the_room() -> void:
	var s := TestUtils.new_session()
	s.props[s.room_id] = [{"id": "p1", "name": "Моток верёвки", "item_id": "rope", "owner": "", "state": ""},
		{"id": "p2", "name": "Стол", "item_id": "", "owner": "", "state": ""}]
	var r := PropRules.plan_take(s, data, {"prop_id": "p1"})
	assert_bool(r.has("plan")).is_true()
	PropRules.apply_take(s, data, r["plan"])
	assert_int(int(s.character["inventory"].get("rope", 0))).is_greater_equal(1)
	assert_array(PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return p["id"])).contains_exactly(["p2"])
	assert_str(str(PropRules.plan_take(s, data, {"prop_id": "p2"}).get("reason", ""))).contains("не унести")
