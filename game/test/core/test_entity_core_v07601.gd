extends GdUnitTestSuite
## The core of an entity (v0.7.60.1): one ref, the differences from a template, one answer to «where», a look, and a
## deed told to the world through one list of listeners.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	return TestUtils.new_session()


func _sources() -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = ["res://core", "res://autoload"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for d: String in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(d))
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
	return out


# --- EntityRef -------------------------------------------------------------------------------------------------------


func test_a_ref_keeps_its_kind_and_id() -> void:
	assert_str(EntityRef.npc("npc_innkeeper")).is_equal("npc:npc_innkeeper")
	assert_str(EntityRef.kind_of(EntityRef.room("brod-square"))).is_equal(EntityRef.ROOM)
	assert_str(EntityRef.id_of(EntityRef.item("a:b"))).is_equal("a:b")
	assert_str(EntityRef.kind_of(EntityRef.HERO)).is_equal(EntityRef.HERO)
	assert_str(EntityRef.id_of(EntityRef.HERO)).is_empty()


# --- Overlay ---------------------------------------------------------------------------------------------------------


func test_the_pack_is_not_touched_and_the_game_sees_the_change() -> void:
	var s := _session()
	var pack: Dictionary = data["world"]
	data["world"] = pack.duplicate(true)
	Overlay.put(s, data, EntityRef.room("brod-square"), "tags", ["fish"])
	assert_array(data["world"]["rooms"]["brod-square"]["tags"]).contains(["fish"])
	assert_bool((pack["rooms"]["brod-square"].get("tags", []) as Array).has("fish")).is_false()
	data["world"] = pack


func test_a_room_and_a_site_of_one_id_stay_apart() -> void:
	var s := _session()
	var world: Dictionary = data["world"].duplicate(true)
	var d := data.duplicate()
	d["world"] = world
	assert_bool(world["rooms"].has("brod-square") and world["sites"].has("brod-square")).is_true()
	Overlay.put(s, d, EntityRef.site("brod-square"), "public", false)
	assert_bool(world["rooms"]["brod-square"].has("public") and not bool(world["rooms"]["brod-square"]["public"])).is_false()
	assert_bool(world["sites"]["brod-square"]["public"]).is_false()


func test_the_differences_come_back_from_a_save() -> void:
	var s := _session()
	var d := data.duplicate()
	d["world"] = data["world"].duplicate(true)
	var npc: String = d["world"]["npcs"].keys()[0]
	Overlay.put(s, d, EntityRef.npc(npc), "animals", ["mule"])
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	var w := WorldGen.merged(data["world"], back.generated)
	assert_array(w["npcs"][npc]["animals"]).contains_exactly(["mule"])


func test_a_ref_of_nothing_changes_nothing() -> void:
	var s := _session()
	var d := data.duplicate()
	d["world"] = data["world"].duplicate(true)
	Overlay.put(s, d, EntityRef.npc("nobody"), "animals", ["mule"])
	assert_bool(WorldGen.merged(data["world"], s.generated)["npcs"].has("nobody")).is_false()


# --- Where -----------------------------------------------------------------------------------------------------------


func test_the_room_of_what_is_carried() -> void:
	var s := _session()
	assert_str(Where.room_of(s, data, Where.hand(EntityRef.HERO, "main_hand"))).is_equal(s.room_id)
	assert_str(Where.room_of(s, data, Where.room("brod-gate"))).is_equal("brod-gate")
	assert_str(Where.room_of(s, data, {"road": true})).is_empty()
	s.npc_at["npc_innkeeper"] = "brod-gate"
	assert_str(Where.room_of(s, data, Where.saddle(EntityRef.npc("npc_innkeeper")))).is_equal("brod-gate")


func test_where_an_npc_is_now() -> void:
	var s := _session()
	var id := "npc_innkeeper"
	s.npc_at[id] = ""
	assert_bool(bool(Where.of_npc(s, data, id).get("road", false))).is_true()
	assert_str(Where.base_room(s, data, id)).is_empty()
	s.npc_at.erase(id)
	assert_str(Where.base_room(s, data, id)).is_equal(ReputationRules.home_room(data, id))
	s.followers.append(id)
	assert_str(str(Where.of(s, data, EntityRef.npc(id))["room"])).is_equal(s.room_id)
	s.followers.erase(id)
	s.bodies[id] = "brod-gate"
	assert_str(str(Where.of_npc(s, data, id)["room"])).is_equal("brod-gate")


# --- Look ------------------------------------------------------------------------------------------------------------


func test_a_token_is_a_letter_unless_the_pack_says() -> void:
	assert_str(Look.token({}, "волк")).is_equal("В")
	assert_str(Look.token({"look": {"token": "☠"}}, "волк")).is_equal("☠")


# --- WorldEvent ------------------------------------------------------------------------------------------------------


func test_nobody_hears_what_nobody_listens_to() -> void:
	assert_array(WorldEvent.emit(_session(), data, "nothing_of_the_kind")).is_empty()


func test_every_listener_has_its_kinds() -> void:
	var ids: Array[String] = []
	for l: Dictionary in WorldEvent.registry():
		assert_bool((l["run"] as Callable).is_valid()).is_true()
		assert_array(l["on"] as Array).is_not_empty()
		assert_bool(ids.has(str(l["id"]))).is_false()
		ids.append(str(l["id"]))


func test_a_lie_breaks_a_vow_through_the_event() -> void:
	var s := _session()
	FaithRules.start(s.character, "chauntea")
	(FaithRules._rw(s.character)["vows"] as Array).append({"id": "truth", "since": s.day, "broken": -1})
	assert_array(WorldEvent.deed(s, data, "check:deception")).is_not_empty()
	assert_bool(FaithRules.lapsed(s.character) or int(s.character["faith"]["vows"][0]["broken"]) == s.day).is_true()


func test_a_known_crime_reaches_the_people_and_the_law() -> void:
	var s := _session()
	var victim := "npc_innkeeper"
	var loc := ReputationRules.home_of(data, victim)
	var other := ""
	for id: String in CrimeRules.people_of(data, loc):
		if id != victim:
			other = id
			break
	var before := s.attitude(other)
	var crime := {"id": "cr1", "kind": "murder", "victim": victim, "room": s.room_id, "location": loc, "at": 0, "witnesses": [], "known": false, "settled": false}
	s.crimes.append(crime)
	var lines := CrimeRules._known(s, data, crime)
	assert_bool(bool(crime["known"])).is_true()
	assert_int(s.attitude(other)).is_less(before)
	assert_bool(s.wanted.has(loc)).is_true()
	assert_bool(lines.any(func(x: String) -> bool: return x.begins_with("Вы в розыске"))).is_true()


func test_a_death_passes_the_goods_and_the_news() -> void:
	var s := _session()
	var id := "npc_innkeeper"
	var news := JSON.stringify(s.generated.get("rumors", {}))
	CrimeRules.on_death(s, data, id, false, s.room_id)
	assert_bool(s.dead_npcs.has(id)).is_true()
	assert_str(JSON.stringify(s.generated.get("rumors", {}))).is_not_equal(news)


func test_listeners_are_called_only_from_the_list() -> void:
	var calls := RegEx.create_from_string("FaithRules\\.deed\\(|FactionRules\\.on_(bond|crime|source)\\(|RumorRules\\.on_(death|place)\\(")
	for path: String in _sources():
		if path.ends_with("world_event.gd"):
			continue
		assert_object(calls.search(FileAccess.get_file_as_string(path))).override_failure_message(path).is_null()


func test_no_second_store_of_differences() -> void:
	var old := RegEx.create_from_string("\"(site|room|npc)_patch\"")
	for path: String in _sources():
		assert_object(old.search(FileAccess.get_file_as_string(path))).override_failure_message(path).is_null()
