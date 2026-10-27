extends GdUnitTestSuite
## The author's white root (v0.7.38.5): a quest's hidden thing is found by the skill the master gave it (Investigation
## always), never given by words past its hiding place; and every tool of the catalog is sold somewhere.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _root_quest(skill: Variant) -> String:
	fx.searched_quests["t-1"] = true
	var qi := {"item_id": "lute", "room": "brod-tavern-cellar", "hint": "В чёрной воде у бочек", "dc_tier": "easy"}
	if skill != null:
		qi["skill"] = skill
	var r := fx.validate(s, data, "t-1", {"kind": "create_quest", "giver": "npc_innkeeper", "title": "Корень", "scale": "trifle",
		"quest_item": qi, "steps": [{"text": "Достать корень в погребе", "kind": "find", "target": "item"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	return str(s.generated["quests"].keys()[0])


func test_a_thing_hidden_for_survival_is_found_by_survival_and_investigation() -> void:
	var qid := _root_quest("survival")
	s.room_id = "brod-tavern-cellar"
	var found := func(skill: String) -> bool:
		s.revealed.clear()
		ExplorationRules.active_reveal(s, data["world"], skill, 30)
		return (s.revealed.get("brod-tavern-cellar", []) as Array).has("q_" + qid)
	assert_bool(found.call("perception")).is_false()
	assert_bool(found.call("survival")).is_true()
	assert_bool(found.call("investigation")).is_true()
	assert_bool(found.call("athletics")).is_false()


func test_a_wrong_skill_for_the_thing_is_refused() -> void:
	fx.searched_quests["t-1"] = true
	var r := fx.validate(s, data, "t-1", {"kind": "create_quest", "giver": "npc_innkeeper", "title": "Корень", "scale": "trifle",
		"quest_item": {"item_id": "lute", "room": "brod-tavern-cellar", "hint": "В чёрной воде", "dc_tier": "easy", "skill": "athletics"},
		"steps": [{"text": "Достать корень", "kind": "find", "target": "item"}]})
	assert_str(str(r["reason"])).contains("survival")


func test_the_hidden_thing_is_not_given_by_words_until_found() -> void:
	var qid := _root_quest(null)
	s.room_id = "brod-tavern-cellar"
	var r := fx.validate(s, data, "t-2", {"kind": "give_item", "item_id": "lute"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("request_check perception")
	s.room_id = "brod-tavern-hall"
	assert_str(str(fx.validate(s, data, "t-3", {"kind": "give_item", "item_id": "lute"})["reason"])).contains("спрятана в")
	s.revealed["brod-tavern-cellar"] = ["q_" + qid]  # found: the hiding place no longer holds it back
	assert_str(str(fx.validate(s, data, "t-4", {"kind": "give_item", "item_id": "lute"}).get("reason", ""))).not_contains("спрятан")


func test_every_tool_of_the_catalog_is_sold_somewhere() -> void:
	var sold := JSON.stringify(data["rules"]["trade"]["kinds"]) + JSON.stringify(data["world"]["npcs"])
	var missing: Array = []
	for id: String in data["items"]["catalog"]:
		if bool(data["items"]["catalog"][id].get("tool", false)) and id != "thieves_tools" and not sold.contains("\"%s\"" % id):
			missing.append(id)
	assert_array(missing).is_empty()
	assert_int(int(TradeRules.pack_stock(data["world"]["npcs"]["npc_smith"], data["rules"]).get("smiths_tools", 0))).is_greater(0)
