extends GdUnitTestSuite
## Worn things and bags (roadmap v0.7.22.9): rings, boots, cloaks, goggles go to their slots and work only worn; a
## bag halves the weight of what is in it; one big bag and two small ones at a time; no bag in a bag.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


func test_worn_things_go_to_their_slots() -> void:
	var items: Dictionary = data["items"]["catalog"]
	assert_str(CharacterRules.slot_for(items["goggles_of_night"], data)).is_equal("eyes")
	assert_str(CharacterRules.slot_for(items["boots_of_elvenkind"], data)).is_equal("feet")
	assert_str(CharacterRules.slot_for(items["ring_of_warmth"], data)).is_equal("ring1")
	assert_str(CharacterRules.slot_for(items["cloak_of_protection"], data)).is_equal("cloak")
	assert_str(CharacterRules.slot_for(items["stone_of_good_luck"], data)).is_empty()
	assert_str(CharacterRules.slot_for({"item_type": "wondrous", "name": "Кольцо тёплого ветра"}, data)).is_equal("ring1")


func test_a_worn_thing_works_only_worn() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["goggles_of_night"] = 1
	CharacterRules.refresh(c, data, s.items)
	assert_bool(CharacterRules.item_prop(c, "darkvision")).is_false()  # in the pack
	assert_str(CharacterRules.can_equip(c, data, s.items, "goggles_of_night", "eyes")).is_empty()
	c["equipped"]["eyes"] = "goggles_of_night"
	CharacterRules.refresh(c, data, s.items)
	assert_bool(CharacterRules.item_prop(c, "darkvision")).is_true()
	c["inventory"]["stone_of_good_luck"] = 1
	c["attuned"] = ["stone_of_good_luck"]
	CharacterRules.refresh(c, data, s.items)
	assert_bool(CharacterRules.item_prop(c, "checks_plus1")).is_true()  # no slot — works carried


func test_two_rings_one_on_each_hand() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["ring_of_swimming"] = 1
	c["inventory"]["ring_of_water_walking"] = 1
	assert_str(CharacterRules.can_equip(c, data, s.items, "ring_of_swimming", "ring1")).is_empty()
	c["equipped"]["ring1"] = "ring_of_swimming"
	assert_str(CharacterRules.can_equip(c, data, s.items, "ring_of_water_walking", "ring2")).is_empty()
	assert_str(CharacterRules.can_equip(c, data, s.items, "ring_of_swimming", "ring2")).is_equal("EQUIP_NOT_OWNED")  # one ring, one finger
	assert_str(CharacterRules.can_equip(c, data, s.items, "ring_of_swimming", "feet")).is_equal("EQUIP_WRONG_SLOT")


func test_a_bag_halves_the_weight_and_takes_no_bag() -> void:
	var s := _hero()
	var c := s.character
	var bag := str(ContainerRules.bags_of(c, "backpack")[0])
	c["inventory"]["rope"] = int(c["inventory"].get("rope", 0)) + 1
	var before := CharacterRules.carried_weight(c, data, s.items)
	var r := ContainerRules.plan_put(s, data, bag, "rope", 1)
	ContainerRules.apply_put(s, data, r["plan"])
	var rope := float(data["items"]["catalog"]["rope"]["weight"])
	assert_float(CharacterRules.carried_weight(c, data, s.items)).is_equal_approx(before - rope * 0.5, 0.01)
	c["inventory"]["sack"] = 1
	ContainerRules.sync_bags(c, data)
	assert_int(ContainerRules.bags_of(c, "sack").size()).is_equal(0)  # a backpack is the one big bag
	assert_str(str(ContainerRules.plan_put(s, data, bag, "sack", 1).get("reason", ""))).contains("сумку в сумку")
	c["inventory"]["pouch"] = 3
	ContainerRules.sync_bags(c, data)
	assert_int(ContainerRules.bags_of(c, "pouch").size()).is_equal(2)  # two small ones at a time
