extends GdUnitTestSuite
## «Генерация NPC и локаций» (roadmap v0.7.20.1): a room or a small place grows only from an open edge the pack marked,
## by the schema of a pack room, connected, within the encounter budget; it lives in this game and on its map.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "pushcha-trail"
	fx = EffectEngine.new()


func _place(spec: Dictionary, turn := "t-1") -> Dictionary:
	fx.searched_places[turn] = true
	var e := spec.duplicate(true)
	e["kind"] = "create_place"
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _thicket() -> Dictionary:
	return {"edge": 0, "rooms": [
		{"key": "a", "name": "Бурелом", "description": "Поваленные ели.", "exits": ["b"], "hooks": ["под корнями что-то белеет"],
			"secrets": [{"text": "под корнями — старые кости и ржавый нож", "dc_tier": "easy"}]},
		{"key": "b", "name": "Барсучья нора", "description": "Тёмный лаз.", "dark": true,
			"encounter": {"enemies": [{"monster": "wolf", "count": 1}]}}]}


func test_only_from_an_open_edge() -> void:
	s.room_id = "brod-tavern-hall"
	assert_str(str(_place(_thicket())["reason"])).contains("нет открытых краёв")
	s.room_id = "pushcha-trail"
	assert_array(WorldGen.open_edges(s, data, s.room_id)).has_size(1)


func test_a_place_grows_from_the_trail() -> void:
	var r := _place(_thicket())
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var first := str(s.generated["edge_exits"]["pushcha-trail"][0])
	assert_array(ExplorationRules.open_exits(s, data["world"], "pushcha-trail")).contains([first])
	var room: Dictionary = data["world"]["rooms"][first]
	assert_str(str(room["location_id"])).is_equal("pushcha")
	assert_array(room["exits"]).contains(["pushcha-trail"])
	assert_int(int(room["secrets"][0]["dc"])).is_equal(10)
	var second := str(room["exits"][0])
	assert_bool(bool(data["world"]["rooms"][second]["dark"])).is_true()
	assert_str(str(data["world"]["rooms"][second]["encounter"]["enemies"][0]["monster"])).is_equal("wolf")
	assert_array(WorldGen.open_edges(s, data, "pushcha-trail")).has_size(1)  # v0.7.39.4: an edge is not used up
	assert_str(str(WorldGen.find_places(s, data, "бурелом")[0]["source"])).is_equal("made")


func test_a_new_location_only_where_the_edge_allows() -> void:
	var spec := _thicket()
	spec["new_location"] = true
	spec["name"] = "Ручьи"
	spec["terrain"] = "forest"
	assert_str(str(_place(spec)["reason"])).contains("только продолжение")
	s.room_id = "pushcha-edge"
	spec["terrain"] = "desert"
	assert_str(str(_place(spec, "t-2")["reason"])).contains("местность")
	spec["terrain"] = "forest"
	assert_bool(bool(_place(spec, "t-3")["accepted"])).is_true()
	var first := str(s.generated["edge_exits"]["pushcha-edge"][0])
	assert_str(str(data["world"]["locations"][str(data["world"]["rooms"][first]["location_id"])]["name"])).is_equal("Ручьи")


func test_the_engine_refuses_a_broken_place() -> void:
	var lone := _thicket()
	lone["rooms"][0]["exits"] = []
	assert_str(str(_place(lone)["reason"])).contains("связаны")
	var strong := _thicket()
	strong["rooms"][1]["encounter"] = {"enemies": [{"monster": "ogre", "count": 3}]}
	assert_str(str(_place(strong, "t-2")["reason"])).contains("не по силам")
	var same := _thicket()
	same["rooms"][0]["name"] = "Тропа лесорубов"
	assert_str(str(_place(same, "t-3")["reason"])).contains("новое имя")


func test_a_place_survives_a_save_with_its_people() -> void:
	_place(_thicket())
	var first := str(s.generated["edge_exits"]["pushcha-trail"][0])
	s.room_id = first
	fx.searched_npcs["t-2"] = true
	var r := fx.validate(s, data, "t-2", {"kind": "create_npc", "npc": {"name": "Бортник Ян", "role": "бортник"}})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-2", [r["effect_id"]])
	var back := GameSession.from_dict(s.to_dict(5))
	var world := WorldGen.merged(TestUtils.data()["world"], back.generated)
	assert_array(world["rooms"]["pushcha-trail"]["exits"]).contains([first])
	assert_int((world["rooms"][first]["npcs"] as Array).size()).is_equal(1)
