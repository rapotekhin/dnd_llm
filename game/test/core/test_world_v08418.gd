extends GdUnitTestSuite
## v0.8.4.18: the world's records and money — a change of a record goes through Overlay (a made record changes itself),
## the engine's people through the NPC factory, one registry of the pack and the master, a room's tags and roof by the
## places above it, the hero's coins by Ledger.balance and a share by Price.share.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session(d: Dictionary) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	s.generated = {}
	WorldGen.generated(s)
	d["world"] = WorldGen.merged(d["world"], s.generated)
	return s


func _own() -> Dictionary:
	var d := data.duplicate()
	d["world"] = (data["world"] as Dictionary).duplicate(true)
	return d


func test_a_pack_room_changed_keeps_it_in_the_overlay_and_after_a_load() -> void:
	var d := _own()
	var s := _session(d)
	var sec := {"id": "q_x_ring", "dc": 12, "text": "кольцо под половицей", "skill": "perception", "loot": {"items": {"rope": 1}}}
	Overlay.add(s, d, EntityRef.room("brod-tavern-hall"), "secrets", sec)
	assert_bool(s.generated.has("room_secrets")).is_false()
	var again := WorldGen.merged(data["world"], s.generated)
	var ids: Array = (again["rooms"]["brod-tavern-hall"].get("secrets", []) as Array).map(func(x: Dictionary) -> String: return str(x.get("id", "")))
	assert_array(ids).contains(["q_x_ring"])


func test_a_made_record_changes_itself_not_the_overlay() -> void:
	var d := _own()
	var s := _session(d)
	var id := WorldGen.apply_npc(s, d, {"npc": {"name": "Тестовый", "role": "путник", "monster": "commoner", "tags": []}, "room": "brod-tavern-hall"})
	Overlay.put(s, d, EntityRef.npc(id), "role", "кузнец")
	assert_str(str(s.generated["npcs"][id]["role"])).is_equal("кузнец")
	assert_bool(Overlay.of(s.generated, EntityRef.npc(id)).is_empty()).is_true()
	assert_str(str(d["world"]["npcs"][id]["role"])).is_equal("кузнец")


func test_a_child_is_made_by_the_npc_factory_with_a_faction() -> void:
	var d := _own()
	var s := _session(d)
	var p := WorldGen.new_person(s, d, FamilyRules.cfg(d)["names"])
	assert_array(FamilyRules.cfg(d)["names"][str(p["gender"])]).contains([p["name"]])
	var id := WorldGen.apply_npc(s, d, {"npc": {"name": str(p["name"]), "role": "младенец", "monster": "commoner", "tags": []}, "room": "brod-tavern-hall"}, "kin")
	assert_str(id).is_equal("kin_1")
	assert_array(d["world"]["rooms"]["brod-tavern-hall"]["npcs"]).contains([id])
	WorldGen.place_npc(s, d, id, "")
	assert_array(d["world"]["rooms"]["brod-tavern-hall"]["npcs"]).not_contains([id])
	WorldGen.forget_npc(s, d, id)
	assert_bool(d["world"]["npcs"].has(id) or s.generated["npcs"].has(id)).is_false()


func test_one_registry_the_master_over_the_pack() -> void:
	var d := _own()
	var s := _session(d)
	WorldGen.generated(s)["orgs"] = {"night_rats": {"name": "Крысы мастера"}}
	WorldGen.generated(s)["heists"] = {"heist_casks": {"name": "Бочки мастера"}}
	assert_str(str(OrgRules.def(s, d, "night_rats")["name"])).is_equal("Крысы мастера")
	assert_str(str(HeistRules.def(s, d, "heist_casks")["name"])).is_equal("Бочки мастера")
	assert_bool(OrgRules.all(s, d).has("drovers")).is_true()


func test_a_room_of_the_temple_is_the_temple_for_an_acolyte() -> void:
	var d := _own()
	d["world"]["rooms"]["brod-temple-cell"] = {"name": "Келья", "location_id": "brod", "site_id": "brod-temple", "exits": ["brod-temple"]}
	var s := _session(d)
	s.character["background"] = "acolyte"
	assert_array(SceneRules.tags(s, d["world"], "brod-temple-cell")).contains(["temple"])
	assert_bool(BackgroundRules.free_rest(s, d, "brod-temple-cell")).is_true()
	assert_bool(bool(ExplorationRules.rest_place(d["world"], "brod-temple-cell", s, d).get("free", false))).is_true()


func test_a_roof_by_the_place_above() -> void:
	var d := _own()
	d["world"]["sites"]["roofed"] = {"name": "Амбар", "location_id": "brod", "indoor": true}
	d["world"]["rooms"]["roofed-loft"] = {"name": "Сеновал", "location_id": "brod", "site_id": "roofed", "exits": []}
	var s := _session(d)
	assert_bool(SceneRules.indoor(s, d["world"], "roofed-loft")).is_true()
	assert_bool(WeatherRules.sheltered(s, d, "roofed-loft")).is_true()


func test_the_hero_s_coins_and_a_share() -> void:
	var s := _session(_own())
	Ledger.add(s, 250, "test")
	assert_int(Ledger.balance(s)).is_equal(int(s.character["gold_cp"]))
	assert_int(Price.share(1000, 15.0)).is_equal(150)
	assert_int(Price.share(5, 50.0)).is_equal(3)  # rounded, never cut down
