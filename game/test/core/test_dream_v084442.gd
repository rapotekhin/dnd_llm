extends GdUnitTestSuite
## v0.8.4.44.2, the tutorial's own world (docs/design/systems/tutorial/description.md): the dream pack is not a world to
## pick; «Обучение» begins the new game in it with the player's own hero — no things, its spells kept; the master makes
## nothing of the pack's `closed` there; waking begins the real world from the same creation choices, nothing of the
## dream kept, and the profile remembers the tutorial was played.

var _settings_path: String
var _done: bool


func before_test() -> void:
	_settings_path = SaveManager.settings_path
	_done = SaveManager.tutorial_done
	SaveManager.settings_path = "user://test_dream_settings.cfg"
	SaveManager.tutorial_done = false


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	Catalog.activate("frontier")
	DirAccess.remove_absolute(SaveManager.settings_path)
	SaveManager.settings_path = _settings_path
	SaveManager.tutorial_done = _done


func _wizard() -> Dictionary:
	for p: Dictionary in Catalog.data["presets"]:
		if str(p["id"]) == "wizard_yalika":
			return CharacterBuilder.preset_choices(p)
	return {}


func _dream() -> Dictionary:
	Catalog.activate("frontier")
	var choices := _wizard()
	var settings := WorldPack.default_settings(Catalog.data["pack"])
	settings["tutorial"] = true
	settings["seed"] = "7"
	GameState.new_game(CharacterBuilder.build(choices, Catalog.data), settings, -1, choices)
	return choices


func test_the_dream_is_no_world_to_pick_but_the_prologue_of_the_mark() -> void:
	var worlds: Array = Catalog.worlds().map(func(b: Dictionary) -> String: return str(b["id"]))
	assert_array(worlds).contains(["frontier"])
	assert_array(worlds).not_contains(["tutorial"])
	assert_str(Catalog.prologue_of("frontier")).is_equal("tutorial")
	assert_array(Catalog.bundle("tutorial").get("errors", ["нет пакета"])).is_empty()


func test_the_tutorial_begins_in_the_dream_with_no_things_and_its_spells() -> void:
	var choices := _dream()
	var s := GameState.session
	var built := CharacterBuilder.build(choices, WorldPack.apply_rules(Catalog.base, Catalog.bundle("frontier")))
	assert_str(Catalog.active_world).is_equal("tutorial")
	assert_str(s.world_id).is_equal("tutorial")
	assert_str(s.room_id).is_equal("dream-1")
	assert_dict(s.character["inventory"]).is_empty()
	assert_int(int(s.character.get("gold_cp", 0))).is_equal(0)
	assert_bool((s.character["equipped"] as Dictionary).values().all(func(v: Variant) -> bool: return str(v).is_empty())).is_true()
	assert_dict(s.character["spells"]).is_equal(built["spells"])
	assert_bool((built["spells"]["cantrips"] as Array).is_empty()).is_false()
	assert_str(str(s.dream["world"])).is_equal("frontier")
	assert_bool(s.settings.has("tutorial")).is_false()


func test_waking_begins_the_mark_from_the_same_choices_with_nothing_of_the_dream() -> void:
	var choices := _dream()
	var s := GameState.session
	assert_bool(DreamRules.wake_due(s, Catalog.data)).is_false()
	ExplorationRules.place(s, "dream-7")  # the hero came into the last hall
	assert_bool(DreamRules.wake_due(s, Catalog.data)).is_true()
	assert_str(DreamRules.wake_text(Catalog.data)).contains("Пепел над Маркой")
	GameState.wake()
	var woke := GameState.session
	assert_str(Catalog.active_world).is_equal("frontier")
	assert_object(woke).is_not_same(s)
	assert_dict(woke.dream).is_empty()
	assert_str(woke.world_id).is_equal("frontier")
	assert_str(woke.room_id).is_equal(str(Catalog.data["world"]["start_room"]))
	var fresh := CharacterBuilder.build(choices, Catalog.data)
	assert_str(str(woke.character["name"])).is_equal(str(fresh["name"]))
	assert_int(int(woke.character["level"])).is_equal(1)
	assert_dict(woke.character["inventory"]).is_equal(fresh["inventory"])
	assert_bool(SaveManager.tutorial_done).is_true()


func test_without_the_tick_the_game_is_the_world_itself() -> void:
	Catalog.activate("frontier")
	var choices := _wizard()
	var settings := WorldPack.default_settings(Catalog.data["pack"])
	GameState.new_game(CharacterBuilder.build(choices, Catalog.data), settings, 7, choices)
	assert_str(GameState.session.world_id).is_equal("frontier")
	assert_dict(GameState.session.dream).is_empty()
	assert_dict(GameState.session.character["inventory"]).is_not_empty()


func test_the_dream_is_closed_to_the_master_s_making() -> void:
	_dream()
	var s := GameState.session
	var fx := EffectEngine.new()
	var r := fx.validate(s, Catalog.data, "t-1", {"kind": "create", "what": "npc", "name": "Незнакомец", "role": "путник"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r.get("reason", ""))).contains("не создают")
	var info := TurnSnapshot.world_info(s, Catalog.data)
	assert_bool(bool(info["dream"])).is_true()
	assert_array(info["closed"]).contains(["create:npc", "create:place", "create:quest"])
	assert_bool(PrepareRules.gives_work(s, Catalog.data, "anyone")).is_false()


func test_a_dream_pack_needs_its_waking() -> void:
	var b: Dictionary = Catalog.bundle("tutorial").duplicate(true)
	b["pack"]["dream"] = {"wake": {"text": "Проснитесь."}}
	assert_str("\n".join(WorldPack.validate(b, Catalog.base))).contains("pack.dream")
