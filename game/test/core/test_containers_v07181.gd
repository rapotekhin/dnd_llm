extends GdUnitTestSuite
## «Генерация предметов» (roadmap v0.7.18.1): containers of a room — the master fills them when furnishing (what
## nobody owns — out of the reward budget at once), the hero takes and puts within the capacity, a lock opens by a
## key or a passed check, someone else's before its owner is a theft.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _do(effect: Dictionary, turn := "t-1") -> Dictionary:
	var r := fx.validate(s, data, turn, effect)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _furnish(props: Array) -> Dictionary:
	return _do({"kind": "furnish", "props": props})


func test_the_master_fills_a_chest_within_the_budget() -> void:
	var r := _furnish([{"name": "Сундук под лестницей", "container": "chest", "lock": "simple", "key": "candle",
		"contents": [{"item_id": "dagger", "qty": 2}, {"item": {"name": "Письмо без подписи", "item_type": "gear", "rarity": "common", "value_cp": 0, "text": "Встреча у дуба."}}]}])
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_int(s.reward_spent).is_equal(400)  # two daggers: the master's gift
	var chest: Dictionary = PropRules.snapshot(s, data, s.room_id)[0]
	assert_str(str(chest["container"])).is_equal("Сундук")
	assert_bool(bool(chest["locked"])).is_true()
	assert_str(str(chest["contents"])).contains("Кинжал ×2").contains("Письмо без подписи")
	var greedy := TestUtils.new_session()
	greedy.room_id = "brod-tavern-hall"
	var r2 := EffectEngine.new().validate(greedy, data, "t-1", {"kind": "furnish", "props": [{"name": "Ларец", "container": "strongbox",
		"contents": [{"item_id": "chain_mail"}]}]})
	assert_str(str(r2.get("reason", ""))).contains("ёмкость").override_failure_message(str(r2))


func test_a_lock_needs_its_key_or_a_passed_check() -> void:
	_furnish([{"name": "Сундук", "container": "chest", "lock": "good", "key": "candle", "contents": [{"item_id": "dagger"}]}])
	assert_str(str(_do({"kind": "take_from", "prop_id": "p1", "item_id": "dagger"}, "t-2")["reason"])).contains("заперт")
	assert_str(str(_do({"kind": "unlock", "prop_id": "p1", "how": "force"}, "t-3")["reason"])).contains("сначала проверка")
	fx.note_roll("t-4", "athletics", 18, true)  # good lock 15 + 2 to force
	assert_bool(bool(_do({"kind": "unlock", "prop_id": "p1", "how": "force"}, "t-4")["accepted"])).is_true()
	assert_str(str(PropRules.find(s, s.room_id, "p1")["state"])).is_equal("broken")
	assert_bool(bool(_do({"kind": "take_from", "prop_id": "p1", "item_id": "dagger"}, "t-5")["accepted"])).is_true()
	assert_int(int(s.character["inventory"].get("dagger", 0))).is_greater(0)


func test_putting_in_keeps_the_capacity_and_a_full_box_is_not_carried_off() -> void:
	_furnish([{"name": "Корзина", "container": "basket", "item_id": "basket"}])
	s.character["inventory"]["chest"] = 2  # 25 lb each, the basket holds 40
	assert_str(str(_do({"kind": "put_in", "prop_id": "p1", "item_id": "chest", "qty": 2}, "t-2")["reason"])).contains("не влезет")
	s.character["inventory"]["candle"] = 3
	assert_bool(bool(_do({"kind": "put_in", "prop_id": "p1", "item_id": "candle", "qty": 2}, "t-3")["accepted"])).is_true()
	assert_int(int(s.character["inventory"]["candle"])).is_equal(1)
	assert_bool(bool(_do({"kind": "take_prop", "prop_id": "p1"}, "t-4")["accepted"])).is_true()  # a basket goes with what is in it (v0.7.18.2)
	# The hero has a backpack — the one big bag (v0.7.22.9): the basket is a plain thing, the candles go loose.
	assert_array(ContainerRules.bags_of(s.character, "basket")).is_empty()
	assert_int(int(s.character["inventory"]["candle"])).is_equal(3)



func test_taking_from_someone_elses_chest_before_them_is_a_theft() -> void:
	_furnish([{"name": "Сундук Бруно", "container": "chest", "owner": "npc_innkeeper", "contents": [{"item_id": "dagger"}]}])
	assert_int(s.reward_spent).is_equal(0)  # his own goods, no gift
	var r := _do({"kind": "take_from", "prop_id": "p1", "item_id": "dagger"}, "t-2")
	assert_str(str(r["summary"])).contains("на глазах у хозяина")
	assert_int(s.attitude("npc_innkeeper")).is_less(0)
