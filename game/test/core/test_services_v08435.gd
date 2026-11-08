extends GdUnitTestSuite
## «Услуга» (v0.8.4.35, pillar 6): a paid act of any person — a status on the hero for hours or until the long rest, a
## mark on one copy of a thing (a silvered sword stays the same sword); the master builds one at a person of the scene
## (`create:service`), the engine sets its price; the hero buys it by a button.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String, level := 1) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	s.character["level"] = level
	s.character["gold_cp"] = 100000
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _turn(s: GameSession, fx: EffectEngine, effects: Array, turn := "t-1") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = []
	for e: Dictionary in effects:
		var r := fx.validate(s, data, turn, e)
		out.append(r)
		if bool(r["accepted"]):
			ids.append(r["effect_id"])
	fx.apply(s, turn, ids)
	return out


func _ward() -> Dictionary:
	return {"kind": "make", "what": "status", "key": "ward", "name": "Оберег путника", "text": "Тропа бережёт.",
		"parts": [{"part": "save_adv", "value": "con"}]}


func test_silver_marks_the_sword_in_the_hand_not_a_new_thing() -> void:
	var s := _hero("brod-smithy")
	var c := s.character
	var sword := str(c["equipped"]["main_hand"])
	ItemRules.add(c, sword, 1)  # a second one in the pack
	var made := s.items.size()
	ServiceRules.buy(s, data, "npc_smith", "silver")
	assert_str(str(c["equipped"]["main_hand"])).is_equal(sword)
	assert_int(s.items.size()).is_equal(made)
	assert_bool(bool(CombatRules.weapon_profile(c, data, s.items, sword)["silvered"])).is_true()
	assert_array(ItemRules.marks(c, sword, 0)).contains(["silvered"])
	assert_array(ItemRules.marks(c, sword, 1)).is_empty()
	assert_str(ItemInfo.marks_line(c, data, sword)).contains("1 из 2")
	Thing.take(c, sword, 1)  # the plain one leaves first
	assert_array(ItemRules.marks(c, sword, 0)).contains(["silvered"])
	assert_array(ServiceRules.targets(s, data, "silver")).not_contains([sword])  # both copies? one left, and it is marked


func test_a_mark_counts_in_what_works_and_on_the_sheet() -> void:
	var s := _hero("brod-smithy")
	var c := s.character
	var armor := str(c["equipped"].get("armor", ""))
	assert_str(armor).is_not_empty()
	var ac := CharacterRules.gear_ac(c, data, s.items)
	ItemRules.mark(c, armor, "ac_plus1")
	CharacterRules.refresh(c, data, s.items)
	assert_int(CharacterRules.gear_ac(c, data, s.items)).is_equal(ac + 1)
	ItemRules.mark(c, armor, "resist_fire")
	CharacterRules.refresh(c, data, s.items)
	assert_array(c["item_props"]).contains(["resist_fire"])


func test_the_master_builds_a_status_service_at_any_person() -> void:
	var s := _hero("pushcha-glade", 3)
	var fx := EffectEngine.new()
	var r := _turn(s, fx, [_ward(), {"kind": "create", "what": "service", "npc_id": "npc_hermit", "op": "status", "name": "Наложить оберег путника",
		"done": "оберег наложен", "status": "new:ward", "hours": 8}])
	assert_bool(bool(r[1]["accepted"])).override_failure_message(str(r[1])).is_true()
	var offer := ServiceRules.of(s, data, "npc_hermit").filter(func(x: Dictionary) -> bool: return str(x["name"]) == "Наложить оберег путника")
	assert_int(offer.size()).is_equal(1)
	var cfg := ServiceRules.cfg(data)
	assert_int(int(offer[0]["cost_cp"])).is_equal(int(cfg["status_point_cp"]) * 2 * 2)  # save_adv 2 points, 8 hours ×2
	var id := str(offer[0]["id"])
	assert_str(ServiceRules.why(s, data, "npc_hermit", id)).is_empty()
	var gold := Ledger.balance(s)
	var lines := ServiceRules.buy(s, data, "npc_hermit", id)
	assert_str(" ".join(lines)).contains("оберег наложен")
	assert_int(Ledger.balance(s)).is_equal(gold - int(offer[0]["cost_cp"]))
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == id)).is_true()
	assert_str(ServiceRules.why(s, data, "npc_hermit", id)).is_equal("SERVICE_ACTIVE")
	TimeRules.advance(s, data, 9 * 60)
	assert_str(ServiceRules.why(s, data, "npc_hermit", id)).is_empty()  # it ran out


func test_a_status_until_the_long_rest_costs_by_the_rest_hours() -> void:
	var s := _hero("pushcha-glade", 3)
	var fx := EffectEngine.new()
	var r := _turn(s, fx, [_ward(), {"kind": "create", "what": "service", "npc_id": "npc_hermit", "op": "status", "name": "Оберег до ночлега",
		"status": "new:ward", "rest": true}])
	assert_bool(bool(r[1]["accepted"])).override_failure_message(str(r[1])).is_true()
	var sv: Dictionary = ServiceRules.of(s, data, "npc_hermit").filter(func(x: Dictionary) -> bool: return str(x["name"]) == "Оберег до ночлега")[0]
	ServiceRules.buy(s, data, "npc_hermit", str(sv["id"]))
	var e: Dictionary = ConditionRules.effects(s.character).filter(func(x: Dictionary) -> bool: return str(x.get("source", {}).get("id", "")) == str(sv["id"]))[0]
	assert_str(str(e["ends"].get("rest", ""))).is_equal("long")


func test_harm_a_stranger_and_a_wrong_time_are_refused() -> void:
	var s := _hero("pushcha-glade", 3)
	var fx := EffectEngine.new()
	var hurt := {"kind": "make", "what": "status", "key": "rot", "name": "Порча", "text": "Слабость.", "parts": [{"part": "checks", "value": "disadvantage"}]}
	var r := _turn(s, fx, [hurt, {"kind": "create", "what": "service", "npc_id": "npc_hermit", "op": "status", "name": "Навести порчу", "status": "new:rot", "hours": 2}])
	assert_str(str(r[1]["reason"])).contains("вредит")
	r = _turn(s, fx, [_ward(), {"kind": "create", "what": "service", "npc_id": "npc_smith", "op": "status", "name": "Оберег", "status": "new:ward", "hours": 2}], "t-2")
	assert_str(str(r[1]["reason"])).contains("не в сцене")
	r = _turn(s, fx, [_ward(), {"kind": "create", "what": "service", "npc_id": "npc_hermit", "op": "status", "name": "Оберег", "status": "new:ward"}], "t-3")
	assert_str(str(r[1]["reason"])).contains("hours")


func test_the_master_builds_a_mark_priced_by_its_points_and_gated_by_the_level() -> void:
	var s := _hero("brod-tavern-hall", 1)
	var fx := EffectEngine.new()
	var r := _turn(s, fx, [{"kind": "create", "what": "service", "npc_id": "npc_veteran", "op": "enchant", "name": "Закалить клинок огнём",
		"done": "клинок закалён", "property": "fire_damage", "needs": "weapon"}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var sv: Dictionary = ServiceRules.of(s, data, "npc_veteran").filter(func(x: Dictionary) -> bool: return str(x["name"]) == "Закалить клинок огнём")[0]
	assert_int(int(ServiceRules.def_of(data, str(sv["id"]))["cost_cp"])).is_equal(int(ServiceRules.cfg(data)["property_point_cp"]) * 2)
	var sword := str(s.character["equipped"]["main_hand"])
	assert_array(sv["targets"]).contains([sword])
	ServiceRules.buy(s, data, "npc_veteran", str(sv["id"]), sword)
	assert_array(CharacterRules.item_def(s.character, data, s.items, "main_hand")["properties"]).contains(["fire_damage"])
	r = _turn(s, fx, [{"kind": "create", "what": "service", "npc_id": "npc_veteran", "op": "enchant", "name": "Чары +3", "property": "magic_plus3", "needs": "weapon"}], "t-2")
	assert_str(str(r[0]["reason"])).contains("уровня")


func test_a_new_person_gets_its_service_in_the_same_turn() -> void:
	var s := _hero("brod-tavern-hall", 3)
	var fx := EffectEngine.new()
	fx.searched_npcs["t-1"] = true
	var r := _turn(s, fx, [{"kind": "create", "what": "npc", "npc": {"name": "Лука Серебряник", "role": "серебряных дел мастер", "gender": "male",
		"race": "human", "age": "средних лет", "build": "худой", "height": "среднего роста", "room_id": "brod-tavern-hall", "faction": "brod_folk"}},
		{"kind": "create", "what": "service", "npc_id": "new", "op": "enchant", "name": "Посеребрить клинок", "property": "silvered", "needs": "weapon"}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	assert_bool(bool(r[1]["accepted"])).override_failure_message(str(r[1])).is_true()
	var who := ""
	for id: String in s.npcs_here(data["world"], s.room_id):
		if str(data["world"]["npcs"][id].get("name", "")) == "Лука Серебряник":
			who = id
	assert_str(who).is_not_empty()
	assert_int(ServiceRules.of(s, data, who).size()).is_equal(1)
	var gen: Dictionary = WorldGen.generated(s)
	assert_bool((gen["services"] as Dictionary).has(str(ServiceRules.ids_of(data, who)[0]))).is_true()


func test_a_made_service_comes_back_with_the_world() -> void:
	var s := _hero("pushcha-glade", 3)
	var fx := EffectEngine.new()
	_turn(s, fx, [_ward(), {"kind": "create", "what": "service", "npc_id": "npc_hermit", "op": "status", "name": "Наложить оберег путника",
		"status": "new:ward", "hours": 4}])
	var world := WorldGen.merged(TestUtils.data()["world"], s.generated)
	var ids: Array = world["npcs"]["npc_hermit"].get("services", [])
	assert_bool(ids.any(func(x: Variant) -> bool: return (world["services"] as Dictionary).has(str(x)) and str(world["services"][str(x)]["name"]) == "Наложить оберег путника")).is_true()
