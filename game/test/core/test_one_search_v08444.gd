extends GdUnitTestSuite
## v0.8.4.44, the author's decision for the tutorial: the search is one check. «Осмотреться» only describes (a master's turn
## with no roll), «Обыскать» rolls Perception and finds what can be noticed and what is hidden. A thing not noticed in
## passing is `passive: false` (was `skill: investigation`); a thing hidden for another skill (Survival…) is found by it too.

var data: Dictionary
var world: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	world = data["world"]
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data)


func test_no_secret_of_the_pack_is_hidden_for_investigation() -> void:
	for rid: String in world["rooms"]:
		for sec: Dictionary in world["rooms"][rid].get("secrets", []):
			assert_str(str(sec.get("skill", ""))).override_failure_message("%s:%s" % [rid, sec["id"]]).is_not_equal("investigation")


func test_a_thing_not_seen_in_passing_waits_for_the_search() -> void:
	s.character["passive_perception"] = 30
	assert_array(ExplorationRules.enter_room(s, world, "brod-tavern-cellar")).has_size(1)  # the tracks, not the tunnel
	var found := ExplorationRules.active_reveal(s, world, ExplorationRules.SEARCH_SKILL, 15)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("лаз")


func test_one_rule_of_who_finds_what() -> void:
	var plain := {"id": "a", "dc": 10, "text": "царапины"}
	var hidden := {"id": "b", "dc": 10, "text": "тайник", "passive": false}
	var root := {"id": "c", "dc": 10, "text": "корень", "skill": "survival"}
	assert_bool(ExplorationRules.noticed_passively(plain)).is_true()
	assert_bool(ExplorationRules.noticed_passively(hidden)).is_false()
	assert_bool(ExplorationRules.noticed_passively(root)).is_false()
	for sec: Dictionary in [plain, hidden, root]:
		assert_bool(ExplorationRules.found_by(sec, "perception")).is_true()
		assert_bool(ExplorationRules.found_by(sec, "investigation")).is_false()
	assert_bool(ExplorationRules.found_by(root, "survival")).is_true()
	assert_bool(ExplorationRules.found_by(plain, "survival")).is_false()


func test_the_pack_refuses_a_secret_for_investigation() -> void:
	var w: Dictionary = world.duplicate(true)
	w["rooms"]["brod-tavern-cellar"]["secrets"].append({"id": "old", "dc": 12, "text": "старый тайник", "skill": "investigation"})
	assert_str("\n".join(WorldPack._validate_world(w, data))).contains("секрет")
	w["rooms"]["brod-tavern-cellar"]["secrets"][-1] = {"id": "old", "dc": 12, "text": "старый тайник", "passive": false}
	assert_str("\n".join(WorldPack._validate_world(w, data))).not_contains("секрет")


func test_a_place_of_the_master_keeps_a_secret_only_the_search_finds() -> void:
	var game := data.duplicate()
	game["world"] = data["world"].duplicate(true)
	s.room_id = "brod-tavern-hall"
	var p := WorldGen.plan_place(s, game, {"inside": true, "room_id": "brod-tavern-hall", "rooms": [{"key": "bath", "name": "Баня при таверне",
		"description": "Парная.", "indoor": true, "role": "bedroom", "size": "small",
		"secrets": [{"text": "мешок с двойным дном", "dc_tier": "easy", "passive": false}, {"text": "мучные следы к печи", "dc_tier": "easy"}]}]}, true)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	var secs: Array = p["plan"]["place"]["rooms"][0]["secrets"]
	assert_bool(secs[0].has("skill")).is_false()
	assert_bool(bool(secs[0]["passive"])).is_false()
	assert_bool(bool(secs[1]["passive"])).is_true()
