extends GdUnitTestSuite
## The interactive world (roadmap v0.7.0): furnishing a room on the first visit and its limits, taking and changing
## things, owners who see it, NPC pockets and their DCs, caught thefts by the NPC's kind, the snapshot and the save.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	s.room_id = "brod-tavern-hall"
	return s


func _furnish(s: GameSession, fx: EffectEngine) -> void:
	var r := fx.validate(s, data, "t-1", {"kind": "furnish", "props": [
		{"name": "Доска объявлений", "description": "Листки на гвоздях", "text": "Пропал лесоруб Влас. Видевших — к капитану Ратмиру."},
		{"name": "Кружка Бруно", "item_id": "flask_or_tankard", "owner": "npc_innkeeper"},
		{"name": "Свеча на столе", "item_id": "candle"},
	]})
	assert_bool(r["accepted"]).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])


func test_a_room_is_furnished_once_and_kept() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	assert_bool(PropRules.needs_furnish(s, s.room_id)).is_true()
	assert_bool(TurnSnapshot.build(s, data, 4000)["scene"]["furnish"]).is_true()
	_furnish(s, fx)
	assert_bool(PropRules.needs_furnish(s, s.room_id)).is_false()
	var snap: Dictionary = TurnSnapshot.build(s, data, 4000)
	assert_bool(snap["scene"]["furnish"]).is_false()
	assert_int((snap["scene"]["props"] as Array).size()).is_equal(3)
	assert_str(str(snap["scene"]["props"][0]["text"])).contains("Пропал лесоруб")
	assert_bool(snap["scene"]["props"][1]["portable"]).is_true()
	assert_str(str(fx.validate(s, data, "t-2", {"kind": "furnish", "props": [{"name": "Стул"}]}).get("reason", ""))).contains("уже обставлена")


func test_furnishing_is_checked_by_the_engine() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	var too_many: Array = []
	for i in 11:
		too_many.append({"name": "Стул %d" % i})
	assert_bool(fx.validate(s, data, "t-1", {"kind": "furnish", "props": too_many})["accepted"]).is_false()
	assert_str(str(fx.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Меч", "item_id": "longsword_plus_1"}]}).get("reason", ""))).contains("дорог")
	assert_str(str(fx.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Шарф", "owner": "npc_captain"}]}).get("reason", ""))).contains("не NPC этой комнаты")
	assert_str(str(fx.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Х", "item_id": "nothing_like_it"}]}).get("reason", ""))).contains("нет такого предмета")


func test_taking_a_free_thing_and_an_owned_one_before_its_owner() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	_furnish(s, fx)
	var board := fx.validate(s, data, "t-2", {"kind": "take_prop", "prop_id": "p1"})
	assert_str(str(board.get("reason", ""))).contains("не унести")
	var candle := fx.validate(s, data, "t-2", {"kind": "take_prop", "prop_id": "p3"})
	fx.apply(s, "t-2", [candle["effect_id"]])
	assert_int(int(s.character["inventory"].get("candle", 0))).is_greater_equal(1)
	assert_int(PropRules.room_props(s, s.room_id).size()).is_equal(2)
	var gold := int(s.character["gold_cp"])
	var mug := fx.validate(s, data, "t-3", {"kind": "take_prop", "prop_id": "p2"})
	assert_str(str(mug["summary"])).contains("на глазах")
	var lines := fx.apply(s, "t-3", [mug["effect_id"]])
	assert_str("\n".join(lines)).contains("захлопывает лавку")  # Bruno is a trader
	assert_bool(TheftRules.shop_closed_for(s, "npc_innkeeper")).is_true()
	assert_int(s.attitude("npc_innkeeper")).is_equal(-2)
	assert_int(int(s.character["gold_cp"])).is_equal(gold)


func test_a_thing_can_be_broken_and_stays_broken() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	_furnish(s, fx)
	var r := fx.validate(s, data, "t-2", {"kind": "prop_state", "prop_id": "p1", "state": "burned"})
	fx.apply(s, "t-2", [r["effect_id"]])
	assert_str(str(PropRules.find(s, s.room_id, "p1")["state"])).is_equal("burned")
	assert_bool(fx.validate(s, data, "t-3", {"kind": "prop_state", "prop_id": "p1", "state": "open"})["accepted"]).is_false()


func test_pockets_are_filled_once_with_dcs_by_weight_value_and_wear() -> void:
	var s := _session()
	var list: Array = TheftRules.pockets(s, data, "npc_veteran")
	assert_bool(list.any(func(e: Dictionary) -> bool: return int(e["cp"]) > 0)).is_true()
	var purse: Dictionary = list.filter(func(e: Dictionary) -> bool: return int(e["cp"]) > 0)[0]
	assert_int(int(purse["dc"])).is_equal(12)  # the guard's passive Perception
	var worn: Array = list.filter(func(e: Dictionary) -> bool: return bool(e["worn"]))
	assert_bool(worn.is_empty()).is_false()  # the spear of the guard template
	assert_int(int(worn[0]["dc"])).is_greater(12 + 2)
	assert_bool(list.any(func(e: Dictionary) -> bool: return str(e.get("item_id", "")) == "chain_shirt")).is_false()  # no armor
	assert_array(TheftRules.pockets(s, data, "npc_veteran")).is_equal(list)


func test_stealing_and_getting_caught_by_the_kind_of_npc() -> void:
	var s := _session()
	var purse: Dictionary = TheftRules.pockets(s, data, "npc_serving").filter(func(e: Dictionary) -> bool: return int(e["cp"]) > 0)[0]
	var gold := int(s.character["gold_cp"])
	var got := TheftRules.steal(s, data, "npc_serving", str(purse["id"]), true)
	assert_str(got[0]).contains("украдено")
	assert_int(int(s.character["gold_cp"])).is_greater(gold)
	var item: Dictionary = TheftRules.pockets(s, data, "npc_serving")[0]
	gold = int(s.character["gold_cp"])
	var caught := TheftRules.steal(s, data, "npc_serving", str(item["id"]), false)
	assert_str("\n".join(caught)).contains("зовёт стражу")  # a commoner: the guard and a fine
	assert_int(int(s.character["gold_cp"])).is_equal(gold - int(data["rules"]["theft"]["fine_cp"]))
	assert_str(TheftRules.can_steal(s, data, "npc_serving")).is_equal("THEFT_CAUGHT")
	var v := _session()
	TheftRules.pockets(v, data, "npc_veteran")
	TheftRules.steal(v, data, "npc_veteran", "k1", false)
	assert_array(v.pending_fight).has_size(1)  # a guard fights
	assert_str(str(v.pending_fight[0]["npc_id"])).is_equal("npc_veteran")
	var poor := _session()
	poor.character["gold_cp"] = 0
	TheftRules.pockets(poor, data, "npc_cook")
	poor.room_id = "brod-tavern-kitchen"
	TheftRules.steal(poor, data, "npc_cook", "k1", false)
	assert_str(str(poor.pending_fight[0]["monster"])).is_equal("guard")  # cannot pay the fine


func test_props_and_pockets_survive_the_save_and_v14_migrates() -> void:
	var s := _session()
	_furnish(s, EffectEngine.new())
	TheftRules.pockets(s, data, "npc_serving")
	s.shop_closed["npc_innkeeper"] = 3
	s.caught_by["npc_serving"] = 2
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_int((back.props["brod-tavern-hall"] as Array).size()).is_equal(3)
	assert_int(int(back.pockets["npc_serving"][0]["dc"])).is_equal(int(s.pockets["npc_serving"][0]["dc"]))
	assert_int(int(back.shop_closed["npc_innkeeper"])).is_equal(3)
	var v14: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v14.json"))
	SaveFormat.migrate(v14, {})
	assert_dict(v14["session"]["props"]).is_empty()
