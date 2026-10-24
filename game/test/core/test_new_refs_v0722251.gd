extends GdUnitTestSuite
## The author's trace of v0.7.22.25 (Сарра's bakery): a place, its person and the way in — one turn. The rooms of a place
## made in this turn are «new:<key>» for create_npc and move; the body by Russian words; new goods of a new trader.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-square"
	fx = EffectEngine.new()
	fx.searched_places["t-1"] = true
	fx.searched_npcs["t-1"] = true


func _yard() -> Dictionary:
	return {"kind": "create_place", "inside": true, "room_id": "brod-square",
		"site": {"name": "Двор вдовы Сарры", "tags": ["bakery", "home"], "owner_id": "new"},
		"rooms": [{"key": "yard", "name": "Двор Сарры", "description": "Печь из речного камня.", "exits": ["house"]},
			{"key": "house", "name": "Пекарня вдовы Сарры", "indoor": true, "public": false, "exits": ["yard"]}]}


func _sarra(room: String) -> Dictionary:
	return {"kind": "create_npc", "npc": {"name": "Сарра", "role": "пекарша, вдова", "gender": "female", "race": "human",
		"age": "пожилая", "build": "полная, сутулая", "height": "ниже среднего", "room_id": room, "trader": true,
		"stock": ["rations"], "stock_new": [{"name": "Краюха хлеба", "item_type": "consumable", "rarity": "common", "value_cp": 2}]}}


func test_a_place_its_person_and_the_way_in_in_one_turn() -> void:
	var place := fx.validate(s, data, "t-1", _yard())
	assert_bool(bool(place["accepted"])).override_failure_message(str(place)).is_true()
	assert_str(str(place["summary"])).contains("[new:yard]")
	var npc := fx.validate(s, data, "t-1", _sarra("yard"))  # the bare key, as the master wrote it
	assert_bool(bool(npc["accepted"])).override_failure_message(str(npc)).is_true()
	assert_str(str(npc["summary"])).contains("пожилая, полная")
	assert_str(str(npc["summary"])).contains("Краюха хлеба")
	var move := fx.validate(s, data, "t-1", {"kind": "move", "room_id": "new:yard"})
	assert_bool(bool(move["accepted"])).override_failure_message(str(move)).is_true()
	assert_bool(bool(fx.validate(s, data, "t-1", {"kind": "move", "room_id": "new:house"})["accepted"])).is_false()
	fx.apply(s, "t-1", [move["effect_id"], npc["effect_id"], place["effect_id"]])  # any order
	var yard := s.room_id
	assert_str(yard).starts_with("gen_room_")
	assert_str(str(data["world"]["rooms"][yard]["name"])).is_equal("Двор Сарры")
	var sarra := str(data["world"]["rooms"][yard]["npcs"][0])
	assert_str(str(data["world"]["npcs"][sarra]["name"])).is_equal("Сарра")
	var sid := str(data["world"]["rooms"][yard]["site_id"])
	assert_str(str(data["world"]["sites"][sid]["owner"])).is_equal(sarra)
	assert_str(str(s.generated["sites"][sid]["owner"])).is_equal(sarra)
	var bread := ItemRules.generated_id({"name": "Краюха хлеба"})
	assert_bool(s.items.has(bread)).is_true()
	assert_bool((data["world"]["npcs"][sarra]["stock"] as Dictionary).has(bread)).is_true()


func test_a_new_room_without_a_place_this_turn_is_refused() -> void:
	var r := fx.validate(s, data, "t-1", _sarra("new:yard"))
	assert_str(str(r["reason"])).contains("create_place")


func test_no_new_person_leaves_the_site_without_an_owner() -> void:
	var place := fx.validate(s, data, "t-1", _yard())
	fx.apply(s, "t-1", [place["effect_id"]])
	for sid: String in s.generated["sites"]:
		assert_bool((s.generated["sites"][sid] as Dictionary).has("owner")).is_false()


func test_the_body_by_words_and_unknown_words_left_to_the_engine() -> void:
	assert_dict(BodyRules.check(data, {"age": "пожилая", "build": "полная, сутулая", "height": "ниже среднего"})).is_equal({"age": "elderly", "build": "plump"})
	assert_dict(BodyRules.check(data, {"age": "средних лет"})).is_equal({"age": "middle"})
	var npc := fx.validate(s, data, "t-1", {"kind": "create_npc", "npc": {"name": "Ольма", "role": "прачка", "gender": "female", "age": "древняя"}})
	assert_bool(bool(npc["accepted"])).override_failure_message(str(npc)).is_true()
