extends GdUnitTestSuite
## «Аудит по столпу 6» (roadmap v0.7.16): a service is data over an operation of the engine — a pack adds its own
## without code; the guard who comes for a caught thief is the one of the place's law.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_a_pack_adds_a_service_of_its_own() -> void:
	var d := data.duplicate(true)
	d["world"]["services"] = {"rune": {"cost_cp": 5000, "op": "enchant", "needs": "weapon", "property": "fire_damage",
		"suffix": "с огненной руной", "done": "вырезана руна", "name": "Вырезать огненную руну", "short": "огненная руна"}}
	(d["world"]["npcs"]["npc_smith"]["services"] as Array).append("rune")
	var s := _hero("brod-smithy")
	s.character["gold_cp"] = 10000
	var offer := TradeRules.services(s, d, "npc_smith").filter(func(x: Dictionary) -> bool: return x["id"] == "rune")
	assert_str(str(offer[0]["name"])).is_equal("Вырезать огненную руну")
	assert_str(str(offer[0]["why"])).is_empty()
	var main := str(s.character["equipped"]["main_hand"])
	var lines := TradeRules.buy_service(s, d, "npc_smith", "rune", main)
	assert_str(" ".join(lines)).contains("вырезана руна")
	var now := str(s.character["equipped"]["main_hand"])
	assert_array(ItemRules.def_of(d["items"], s.items, now)["properties"]).contains(["fire_damage"])
	assert_int(int(s.character["gold_cp"])).is_equal(5000)


func test_the_built_in_services_are_data_too() -> void:
	var s := _hero("brod-smithy")
	assert_str(str(TradeRules.services(s, data, "npc_smith")[0]["name"])).is_equal("Посеребрить оружие")
	assert_str(SocialRules.tr_service(data, "identify")).is_equal("опознание вещей")


func test_a_caught_thief_meets_the_guard_of_the_law() -> void:
	var s := _hero("brod-tavern-hall")
	s.character["gold_cp"] = 0  # nothing to pay the fine with: the guard comes
	TheftRules.react(s, data, "npc_serving")
	assert_str(str(s.pending_fight[0]["monster"])).is_equal("guard")
	assert_str(str(s.pending_fight[0]["name"])).is_equal("Ополченец")
	assert_str(str(s.pending_fight[0]["desc"])).contains("Ольхового Брода")
