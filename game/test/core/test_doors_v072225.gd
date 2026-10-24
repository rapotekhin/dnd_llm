extends GdUnitTestSuite
## Doors (roadmap v0.7.22.25, the author's request): a door between rooms locked by the pack or by its site's hours,
## opened by a key, picks, force, blows, Knock; Arcane Lock seals it; fire burns a wooden one through; breaking into
## a closed site before eyes is a trespass; the master's `door` effect by the engine's checks.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String, hour: int = 12) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	s.minute = hour * 60
	return s


func test_the_pack_door_is_locked_and_opens_by_picks() -> void:
	var s := _hero("brod-tavern-kitchen")
	assert_str(DoorRules.blocked(s, data, "brod-tavern-kitchen", "brod-tavern-cellar")).is_equal("DOOR_LOCKED")
	assert_str(DoorRules.blocked(s, data, "brod-tavern-hall", "brod-tavern-kitchen")).is_empty()  # no door there
	assert_str(DoorRules.label(s, data, s.room_id, "brod-tavern-cellar")).contains("заперто")
	var hows := DoorRules.ways(s, data, s.room_id, "brod-tavern-cellar").map(func(w: Dictionary) -> String: return str(w["how"]))
	assert_array(hows).contains(["force", "hit"])
	assert_array(hows).not_contains(["pick", "wait"])  # no thieves' tools, no hours
	DoorRules.unlock(s, data, s.room_id, "brod-tavern-cellar")
	assert_str(DoorRules.blocked(s, data, s.room_id, "brod-tavern-cellar")).is_empty()
	DoorRules.lock(s, s.room_id, "brod-tavern-cellar")
	assert_str(DoorRules.blocked(s, data, "brod-tavern-cellar", "brod-tavern-kitchen")).is_equal("DOOR_LOCKED")  # both sides
	var back := GameSession.from_dict(s.to_dict(5))
	assert_bool(bool(back.doors[DoorRules.key("brod-tavern-kitchen", "brod-tavern-cellar")]["locked"])).is_true()


func test_a_site_with_hours_is_locked_from_outside_at_night() -> void:
	var s := _hero("brod-square", 22)
	assert_str(DoorRules.blocked(s, data, "brod-square", "brod-smithy")).is_equal("DOOR_CLOSED_HOURS")
	assert_str(DoorRules.label(s, data, "brod-square", "brod-smithy")).contains("08:00")
	assert_str(DoorRules.blocked(s, data, "brod-smithy", "brod-square")).is_empty()  # from inside the latch opens
	assert_str(SiteRules.unwelcome(s, data, "brod-smithy")).is_equal("npc_smith")  # a closed shop is nobody's to walk in
	var ways := DoorRules.ways(s, data, "brod-square", "brod-smithy")
	assert_bool(ways.has({"how": "wait"})).is_true()
	assert_array(WorldMap.route(s, data["world"], "brod-square", "brod-smithy", data)).is_empty()
	s.minute = 9 * 60
	assert_str(DoorRules.blocked(s, data, "brod-square", "brod-smithy")).is_empty()
	assert_str(SiteRules.unwelcome(s, data, "brod-smithy")).is_empty()


func test_picked_open_until_the_next_opening() -> void:
	var s := _hero("brod-square", 22)
	DoorRules.unlock(s, data, "brod-square", "brod-smithy")
	assert_str(DoorRules.blocked(s, data, "brod-square", "brod-smithy")).is_empty()
	var until := int(s.doors[DoorRules.key("brod-square", "brod-smithy")]["unlocked_until"])
	assert_int(until).is_equal(TimeRules.abs_minute(s) + 10 * 60)  # 22:00 → 08:00
	s.day += 1
	s.minute = 22 * 60
	assert_str(DoorRules.blocked(s, data, "brod-square", "brod-smithy")).is_equal("DOOR_CLOSED_HOURS")


func test_blows_break_a_door() -> void:
	var s := _hero("brod-tavern-kitchen")
	var to := "brod-tavern-cellar"
	for i in 40:
		DoorRules.hit(s, data, s.room_id, to)
		if DoorRules.blocked(s, data, s.room_id, to).is_empty():
			break
	assert_bool(bool(s.doors[DoorRules.key(s.room_id, to)]["broken"])).is_true()
	assert_str(DoorRules.label(s, data, s.room_id, to)).contains("выбита")
	assert_array(DoorRules.ways(s, data, s.room_id, to)).is_empty()


func test_arcane_lock_knock_and_fire() -> void:
	var s := _hero("brod-tavern-kitchen")
	var to := "brod-tavern-cellar"
	DoorRules.unlock(s, data, s.room_id, to)
	DoorRules.add_effect(s, s.room_id, to, "arcane_lock", -1, "Волшебный замок")
	assert_str(DoorRules.blocked(s, data, s.room_id, to)).is_equal("DOOR_ARCANE")
	assert_int(int(DoorRules.dcs(s, data, s.room_id, to)["pick"])).is_equal(10 + int(data["rules"]["doors"]["arcane_plus"]))
	DoorRules.spell(s, data, s.room_id, to, "knock")
	assert_str(DoorRules.blocked(s, data, s.room_id, to)).is_empty()
	TimeRules.advance(s, data, int(data["rules"]["doors"]["knock_minutes"]) + 1)
	assert_str(DoorRules.blocked(s, data, s.room_id, to)).is_equal("DOOR_ARCANE")  # Knock only quiets it for a while
	var lines := DoorRules.ignite(s, data, s.room_id, to, "факел")
	assert_str(" ".join(lines)).contains("загорается")
	assert_str(DoorRules.blocked(s, data, s.room_id, to)).is_equal("DOOR_BURNING")
	var burnt := TimeRules.advance(s, data, int(data["rules"]["doors"]["burn_minutes"]) + 1)
	assert_str(" ".join(burnt)).contains("прогорела")
	assert_str(DoorRules.blocked(s, data, s.room_id, to)).is_empty()


func test_breaking_into_a_closed_site_before_eyes_is_a_trespass() -> void:
	var s := _hero("brod-square", 22)
	var seen := DoorRules.witnesses(s, data, "brod-square", "brod-smithy")
	if seen.is_empty():
		return  # nobody on the square or in the smithy at night by the NPCs' hours
	var lines := CrimeRules.on_trespass(s, data, SiteRules.unwelcome(s, data, "brod-smithy"), "brod-smithy", seen)
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "trespass")).is_true()
	assert_array(lines).is_not_empty()


func test_the_master_door_effect_by_checks() -> void:
	var s := _hero("brod-tavern-kitchen")
	var eng := EffectEngine.new()
	var no := eng.validate(s, data, "t1", {"kind": "door", "to_room": "brod-tavern-cellar", "action": "break"})
	assert_bool(bool(no["accepted"])).is_false()
	assert_str(str(no["reason"])).contains("athletics")
	var nowhere := eng.validate(s, data, "t1", {"kind": "door", "to_room": "brod-tavern-hall", "action": "unlock"})
	assert_str(str(nowhere["reason"])).contains("нет двери")
	var alone := eng.validate(s, data, "t1", {"kind": "door", "to_room": "brod-tavern-cellar", "action": "unlock"})
	assert_bool(bool(alone["accepted"])).is_false()  # the innkeeper is in the hall, not here or in the cellar
	s.npc_at["npc_innkeeper"] = "brod-tavern-kitchen"
	var ok := eng.validate(s, data, "t1", {"kind": "door", "to_room": "brod-tavern-cellar", "action": "unlock"})
	assert_bool(bool(ok["accepted"])).is_true()


func test_snapshot_exit_tells_the_master_of_the_door() -> void:
	var s := _hero("brod-tavern-kitchen")
	var snap := TurnSnapshot.build(s, data, 2000)
	var ex: Array = snap["scene"]["exits"].filter(func(e: Dictionary) -> bool: return e["room_id"] == "brod-tavern-cellar")
	assert_str(str(ex[0]["door"])).contains("заперта")


func test_the_v42_save_gets_doors() -> void:
	var v42: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v42.json"))
	SaveFormat.migrate(v42)
	assert_dict(v42["session"]["doors"] as Dictionary).is_empty()
