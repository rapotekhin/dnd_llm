extends GdUnitTestSuite
## The author's trace of 2026-11-09 (v0.8.4.42.11): a quest act's lair («Шатёр вожака» with its leader Рвач Косой) was
## made on an open edge of the Pushcha while the hero stood by the swamp; the step «Одолеть вожака» led there, but
## nothing told the hero where — no mark on the map, no «где» in the journal, the master narrated the leader into the
## hero's own room. A quest's current step now marks the rooms it leads to and the open way there.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.visited.clear()
	s.visited.append("brod-tavern-hall")
	fx = EffectEngine.new()


## A taken quest by acts whose act puts its leader in a tent off the Pushcha trail, the hero in the tavern. Its id.
func _camp_quest() -> String:
	fx.searched_quests["t-1"] = true
	var r := fx.validate(s, data, "t-1", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Обоз до заставы",
		"difficulty": "medium", "description": "Обоз пропал у лога.", "acts": [{"title": "Шайка", "goal": "Найти вожака шайки"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[-1])
	QuestRules.accept(s, data, id)
	var act := {"kind": "quest_act", "quest_id": id, "act": 1,
		"steps": [{"text": "Расспросить Миру, где лагерь", "kind": "talk", "target": "npc_serving"},
			{"text": "Одолеть вожака Рвача в шатре", "kind": "fight", "target": "leader", "defeat": true}],
		"new_places": [{"room_id": "pushcha-trail", "edge": 0, "name": "Лагерь у лога", "rooms": [
			{"key": "yard", "name": "Лагерь у лога", "description": "Костровище и навесы.", "exits": ["tent"]},
			{"key": "tent", "name": "Шатёр вожака", "description": "Кожаный шатёр.", "exits": []}]}],
		"encounters": [{"key": "leader", "room": "new:tent", "kind": "target",
			"enemies": [{"monster": "giant_rat", "name": "Рвач Косой"}, {"monster": "rat"}]}]}
	var a := fx.validate(s, data, "t-2", act)
	assert_bool(bool(a["accepted"])).override_failure_message(str(a)).is_true()
	fx.apply(s, "t-2", [a["effect_id"]])
	return id


func _room_named(name: String) -> String:
	for r: String in s.generated["rooms"]:
		if str(data["world"]["rooms"][r].get("name", "")) == name:
			return r
	return ""


func test_the_fight_step_marks_the_far_lair_and_the_way_there() -> void:
	var id := _camp_quest()
	var tent := _room_named("Шатёр вожака")
	var yard := _room_named("Лагерь у лога")
	assert_str(tent).is_not_empty()
	assert_bool(Knows.has(s, Knows.SCOUTED, tent)).is_false()  # the talk step leads to the tavern: nothing to tell yet
	var lines := QuestRules.talk(s, data, id)
	assert_str(" ".join(lines)).contains("Шатёр вожака (").contains("отмечено на карте")
	for r: String in [tent, yard, "pushcha-trail"]:
		assert_bool(Knows.has(s, Knows.SCOUTED, r)).override_failure_message(r).is_true()
	assert_bool(WorldMap.known(s, data["world"])["rooms"].has(tent)).is_true()
	assert_array(WorldMap.step_rooms(s, data, id)).contains_exactly([tent])
	assert_str(", ".join(WorldMap.step_where(s, data, id))).starts_with("Шатёр вожака (")
	assert_bool(WorldMap.quest_marks(s, data).has(tent)).is_true()
	assert_array(QuestRules.advance(s, data)).is_empty()  # told once


func test_the_master_hears_where_the_step_leads() -> void:
	var id := _camp_quest()
	QuestRules.talk(s, data, id)
	var snap := TurnSnapshot.build(s, data, 2000)
	var q: Array = (snap["quests"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) == id)
	assert_str(str(q[0].get("where", ""))).starts_with("Шатёр вожака (")


func test_a_hidden_way_is_not_told() -> void:
	s.visited.clear()
	s.visited.append("pushcha-hollow")
	assert_array(WorldMap.way_to(s, data["world"], "pushcha-burrow")).is_empty()  # the crawl is still to be found
	Knows.add(s, Knows.SECRET, "pushcha-hollow:burrow")
	assert_array(WorldMap.way_to(s, data["world"], "pushcha-burrow")).contains_exactly(["pushcha-burrow"])
	s.visited.append("pushcha-burrow")
	assert_array(WorldMap.way_to(s, data["world"], "pushcha-burrow")).is_empty()  # walked: nothing to tell
