extends GdUnitTestSuite
## «Генерация предметов» (roadmap v0.7.18.2): carried containers — a bag for each container item in the pack, what lies
## in it weighs (a bag of holding — not) and is not at hand, a full bag is not sold until emptied, it is dropped and
## picked up with what is in it.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = [{"id": "p1", "name": "Стол", "item_id": "", "owner": "", "text": "", "state": ""}]  # furnished
	s.character["inventory"] = {"backpack": 1, "torch": 4, "rope": 1}
	CharacterRules.refresh(s.character, data, s.items)
	fx = EffectEngine.new()


func _do(effect: Dictionary, turn := "t-1") -> Dictionary:
	var r := fx.validate(s, data, turn, effect)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_a_bag_for_each_container_item() -> void:
	assert_array(ContainerRules.bags_of(s.character, "backpack")).has_size(1)
	s.character["inventory"]["pouch"] = 2
	CharacterRules.refresh(s.character, data, s.items)
	var pouches := ContainerRules.bags_of(s.character, "pouch")
	assert_array(pouches).has_size(2)  # two small bags at a time (v0.7.22.9)
	assert_str(ContainerRules.bag_name(data, s.character, pouches[1])).is_equal("Мешочек 2")


func test_putting_into_a_bag_halves_the_weight_and_takes_it_out_of_hand() -> void:
	var bag := ContainerRules.bags_of(s.character, "backpack")[0]
	var before := CharacterRules.carried_weight(s.character, data, s.items)
	assert_bool(bool(_do({"kind": "put_in", "prop_id": bag, "item_id": "torch", "qty": 3})["accepted"])).is_true()
	assert_int(int(s.character["inventory"]["torch"])).is_equal(1)
	var torch := float(data["items"]["catalog"]["torch"]["weight"])
	assert_float(CharacterRules.carried_weight(s.character, data, s.items)).is_equal_approx(before - torch * 3 * 0.5, 0.01)  # v0.7.22.9
	assert_str(" ".join(ContainerRules.bags_text(s.character, data, s.items))).contains("Факел ×3")
	assert_int(TradeRules.sellable(s, "backpack", data)).is_equal(0)  # a full bag is not sold
	assert_bool(bool(_do({"kind": "take_from", "prop_id": bag, "item_id": "torch", "qty": 1}, "t-2")["accepted"])).is_true()
	assert_int(int(s.character["inventory"]["torch"])).is_equal(2)


func test_a_bag_of_holding_weighs_nothing_inside() -> void:
	s.character["inventory"].erase("backpack")  # one big bag at a time (v0.7.22.9): the bag of holding instead
	s.character["inventory"]["bag_of_holding"] = 1
	s.character["inventory"]["chain_mail"] = 1
	CharacterRules.refresh(s.character, data, s.items)
	var before := CharacterRules.carried_weight(s.character, data, s.items)
	var bag := ContainerRules.bags_of(s.character, "bag_of_holding")[0]
	assert_bool(bool(_do({"kind": "put_in", "prop_id": bag, "item_id": "chain_mail"})["accepted"])).is_true()
	assert_float(CharacterRules.carried_weight(s.character, data, s.items)).is_less(before - 50)


func test_a_bag_is_dropped_and_picked_up_with_what_is_in_it() -> void:
	var bag := ContainerRules.bags_of(s.character, "backpack")[0]
	_do({"kind": "put_in", "prop_id": bag, "item_id": "rope"})
	assert_bool(bool(_do({"kind": "drop_item", "item_id": bag}, "t-2")["accepted"])).is_true()
	assert_bool(s.character["inventory"].has("backpack")).is_false()
	assert_dict(ContainerRules.bags(s.character)).is_empty()
	var left := PropRules.find(s, s.room_id, "d1")
	assert_dict(left["contents"]).is_equal({"rope": 1})
	assert_bool(PropRules.needs_furnish(s, s.room_id)).is_false()
	assert_bool(bool(_do({"kind": "take_prop", "prop_id": str(left["id"])}, "t-3")["accepted"])).is_true()
	var again := ContainerRules.bags_of(s.character, "backpack")
	assert_dict(ContainerRules.bags(s.character)[again[0]]["contents"]).is_equal({"rope": 1})


func test_dropping_in_an_unfurnished_room_keeps_the_furnishing() -> void:
	s.props.erase(s.room_id)
	_do({"kind": "drop_item", "item_id": "torch"})
	assert_bool(PropRules.needs_furnish(s, s.room_id)).is_true()
	assert_bool(bool(_do({"kind": "furnish", "props": [{"name": "Стол"}]}, "t-2")["accepted"])).is_true()
	assert_array(PropRules.room_props(s, s.room_id)).has_size(2)


func test_bags_survive_a_save() -> void:
	var bag := ContainerRules.bags_of(s.character, "backpack")[0]
	_do({"kind": "put_in", "prop_id": bag, "item_id": "rope"})
	var back := GameSession.from_dict(s.to_dict(5))
	assert_dict(ContainerRules.bags(back.character)[bag]["contents"]).is_equal({"rope": 1})
