extends GdUnitTestSuite
## «Генерация NPC и локаций» (roadmap v0.7.20, batch 1): a person the world lacks is made by the pack's schema after a
## search, with the engine's checks, and lives in this game like a pack NPC — in the room, in trade, in a save.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)  # the world grows in this test only
	s = TestUtils.new_session()
	s.room_id = "brod-square"
	fx = EffectEngine.new()


func _make(npc: Dictionary, turn := "t-1", search := true) -> Dictionary:
	if search:
		fx.searched_npcs[turn] = true
	var r := fx.validate(s, data, turn, {"kind": "create_npc", "npc": npc})
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_the_world_is_searched_first() -> void:
	assert_str(str(WorldGen.find_npcs(s, data, "кузнец")[0]["name"])).contains("Гуннар")
	var r := _make({"name": "Олеся", "role": "пекарша"}, "t-1", false)
	assert_str(str(r["reason"])).contains("find_npcs")


func test_a_made_person_lives_in_the_room() -> void:
	var r := _make({"name": "Олеся Румяная", "role": "пекарша", "race": "halfling", "gender": "female", "description": "Вся в муке.",
		"trader": true, "stock": ["bread", "rations"], "links": [{"npc_id": "npc_merchant", "kind": "spouse"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := str(s.generated["npcs"].keys()[0])
	assert_array(s.npcs_here(data["world"], "brod-square")).contains([id])
	assert_str(str(data["world"]["npcs"][id]["race"])).is_equal("Полурослик")
	assert_int(int(TradeRules.merchant(s, data, id)["stock"]["bread"])).is_greater(0)
	assert_str(str(WorldGen.find_npcs(s, data, "пекарша")[0]["source"])).is_equal("made")


func test_the_engine_refuses_what_breaks_the_schema() -> void:
	assert_str(str(_make({"name": "Гуннар Тяжёлая Рука", "role": "кузнец"})["reason"])).contains("уже есть")
	assert_str(str(_make({"name": "Дракон", "role": "дракон", "monster": "young_red_dragon"}, "t-2")["reason"])).contains("не из людских")
	assert_str(str(_make({"name": "Отшельник Два", "role": "отшельник", "room_id": "pushcha-glade"}, "t-3")["reason"])).contains("в этой локации")
	assert_str(str(_make({"name": "Торгаш", "role": "торговец", "trader": true, "stock": ["plate_armor"]}, "t-4")["reason"])).contains("слишком дорог")


func test_a_made_person_survives_a_save() -> void:
	_make({"name": "Олеся Румяная", "role": "пекарша"})
	var id := str(s.generated["npcs"].keys()[0])
	var back := GameSession.from_dict(s.to_dict(5))
	var world := WorldGen.merged(TestUtils.data()["world"], back.generated)
	assert_array(world["rooms"]["brod-square"]["npcs"]).contains([id])
	assert_bool(TestUtils.data()["world"]["npcs"].has(id)).is_false()  # the pack itself is never touched


func test_limits_per_location() -> void:
	for i in 4:
		assert_bool(bool(_make({"name": "Житель %d" % i, "role": "житель"}, "t-%d" % i)["accepted"])).is_true()
	assert_str(str(_make({"name": "Житель 9", "role": "житель"}, "t-9")["reason"])).contains("больше нельзя")
