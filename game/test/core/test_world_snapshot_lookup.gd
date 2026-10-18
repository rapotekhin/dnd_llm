extends GdUnitTestSuite
## TurnSnapshot, Lookup, ItemRules and character bonuses over the start world.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()


func test_snapshot_scene_and_character() -> void:
	s.attitudes[TestUtils.INNKEEPER] = 2
	s.summaries["dialogue:" + TestUtils.INNKEEPER] = "Борик налил эля."
	s.summaries["dialogue:" + TestUtils.COOK] = "Не в этой комнате."
	var snap := TurnSnapshot.build(s, data, 4000)
	var scene: Dictionary = snap["scene"]
	assert_str(scene["room_id"]).is_equal(TestUtils.START_ROOM)
	assert_str(scene["location_name"]).is_equal("Ольховый Брод")
	assert_int(scene["exits"].size()).is_equal(3)
	var boric: Dictionary = scene["npcs"].filter(func(n: Dictionary) -> bool: return n["npc_id"] == TestUtils.INNKEEPER)[0]
	assert_int(boric["attitude"]).is_equal(2)
	assert_str(boric["gender"]).is_equal("male")
	assert_dict(snap["summaries"]).is_equal({"dialogue:" + TestUtils.INNKEEPER: "Борик налил эля."})
	var c: Dictionary = snap["character"]
	assert_str(c["name"]).is_equal("Айра")
	assert_str(c["race"]).is_equal("Человек")
	assert_str(c["class_name"]).is_equal("Воин")
	assert_int(c["hp"]).is_equal(12)
	assert_int(c["ac"]).is_equal(19)  # chain mail 16 + shield 2 + Defense style 1
	assert_int(c["skills"]["athletics"]).is_equal(5)
	assert_int(c["proficiency_bonus"]).is_equal(2)
	assert_str(c["background"]).is_equal("Ветеран войны")  # renamed by the pack
	assert_array(c["features"]).contains(["Второе дыхание", "Боевой стиль: защита"])
	assert_array(c["equipped"]).contains(["Кольчуга", "Щит", "Длинный меч"])
	assert_bool(c.has("spells")).is_false()
	var names: Array = c["inventory"].map(func(i: Dictionary) -> String: return i["name"])
	assert_array(names).contains(["Длинный меч", "Факел"])
	assert_dict(snap["limits"]).is_equal({"max_checks": 1, "max_effects": 3})


func test_history_budget_keeps_the_newest() -> void:
	for i in 20:
		s.append(GameSession.dm_entry("строка %02d %s" % [i, "x".repeat(90)], "t-%d" % i))
	s.append(GameSession.npc_entry(TestUtils.INNKEEPER, "Борик", "Эля?", "t-99"))
	var h := s.history(500)
	assert_int(h.size()).is_less(10)
	assert_dict(h[-1]).is_equal({"role": "npc", "text": "Борик: Эля?"})


func test_lookup_whitelist() -> void:
	assert_bool(Lookup.find(s, data, "npc", TestUtils.INNKEEPER)["found"]).is_true()
	assert_bool(Lookup.find(s, data, "npc", TestUtils.COOK)["found"]).is_false()  # not in this room
	var torch := Lookup.find(s, data, "item", "torch")
	assert_int(torch["data"]["owned"]).is_equal(10)
	assert_bool(Lookup.find(s, data, "condition", "poisoned")["found"]).is_true()
	assert_bool(Lookup.find(s, data, "spell", "wish")["found"]).is_false()  # only circles 0–3 are in the catalog


func test_lookup_spells_and_features_by_id_or_russian_name() -> void:
	var fireball := Lookup.find(s, data, "spell", "Огненный шар")
	assert_bool(fireball["found"]).is_true()
	assert_str(fireball["data"]["id"]).is_equal("fireball")
	assert_int(int(fireball["data"]["level"])).is_equal(3)
	assert_bool(fireball["data"]["known"]).is_false()
	var wind := Lookup.find(s, data, "feature", "Второе дыхание")
	assert_bool(wind["found"]).is_true()
	assert_bool(wind["data"]["has"]).is_true()
	assert_bool(Lookup.find(s, data, "feature", "darkvision")["data"]["has"]).is_false()  # Айра — человек


func test_trader_lookup_lists_stock_with_prices() -> void:
	var boric: Dictionary = Lookup.find(s, data, "npc", TestUtils.INNKEEPER)["data"]
	assert_bool(boric["trader"]).is_true()
	assert_array(boric["stock"].map(func(i: Dictionary) -> String: return i["item_id"])).contains(["ale"])


func test_find_items() -> void:
	var swords := ItemRules.find(data["items"], {}, "меч", "", [])
	assert_array(swords.map(func(i: Dictionary) -> String: return i["item_id"])).contains(["shortsword", "longsword"])
	var light := ItemRules.find(data["items"], {}, "", "", ["light_source"])
	assert_array(light.map(func(i: Dictionary) -> String: return i["item_id"])).contains(["torch", "lantern", "candle"])
	assert_array(ItemRules.find(data["items"], {}, "", "dagger", [])).is_not_empty()


func test_generated_id_is_stable() -> void:
	var a := {"name": "X", "base": "dagger", "properties": ["light", "finesse"]}
	var b := {"name": "X", "base": "dagger", "properties": ["finesse", "light"]}
	assert_str(ItemRules.generated_id(a)).is_equal(ItemRules.generated_id(b))


func test_check_bonus_from_the_sheet() -> void:
	assert_int(CheckEngine.bonus_for(s.character, {"skill": "perception"})).is_equal(3)
	assert_int(CheckEngine.bonus_for(s.character, {"save": "con"})).is_equal(4)
	assert_int(CheckEngine.bonus_for(s.character, {"skill": "flying"})).is_equal(0)


func test_money_format() -> void:
	assert_str(Money.format(1537)).is_equal("15 зм 3 см 7 мм")
	assert_str(Money.format(-500)).is_equal("−5 зм")
	assert_str(Money.format(0)).is_equal("0 зм")
