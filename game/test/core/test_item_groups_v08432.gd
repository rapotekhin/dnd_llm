extends GdUnitTestSuite
## The hero's things by groups, sorts and a search (v0.8.4.32, the inventory as in BG3 and Pathfinder).

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()


func _of(id: String) -> String:
	return ItemGroups.of(data, s.items, id)


func test_each_thing_falls_into_its_group() -> void:
	assert_str(_of("dagger")).is_equal("weapon")
	assert_str(_of("arrows")).is_equal("ammo")
	assert_str(_of("leather_armor")).is_equal("armor")
	assert_str(_of("healing_potion")).is_equal("potion")
	assert_str(_of("spell_scroll_acid_arrow")).is_equal("scroll")
	assert_str(_of("rations")).is_equal("food")
	assert_str(_of("waterskin")).is_equal("food")
	assert_str(_of("oil_flask")).is_equal("consumable")
	assert_str(_of("thieves_tools")).is_equal("tool")
	assert_str(_of("backpack")).is_equal("container")
	assert_str(_of("iron_ore")).is_equal("material")
	assert_str(_of("silver_ring")).is_equal("valuables")
	assert_str(_of("rope")).is_equal("misc")


func test_an_unknown_thing_keeps_its_group_but_not_its_price() -> void:
	var id := ItemRules.UNKNOWN + "dagger"
	assert_str(_of(id)).is_equal("weapon")
	assert_int(ItemGroups.value(data, s.items, id, 1)).is_equal(-1)


func test_counts_go_in_the_order_of_the_groups_and_skip_the_empty() -> void:
	var inv := {"rope": 1, "dagger": 2, "healing_potion": 3, "shortsword": 1}
	var n := ItemGroups.counts(data, s.items, inv)
	assert_array(n.keys()).is_equal(["weapon", "potion", "misc"])
	assert_int(int(n["weapon"])).is_equal(2)


func test_a_group_and_a_search_narrow_the_list() -> void:
	var inv := {"rope": 1, "dagger": 2, "healing_potion": 3, "shortsword": 1}
	assert_array(ItemGroups.view(data, s.items, inv, "weapon")).contains_exactly_in_any_order(["dagger", "shortsword"])
	var name := ItemRules.display_name(data["items"], s.items, "dagger")
	assert_array(ItemGroups.view(data, s.items, inv, ItemGroups.ALL, ItemGroups.TYPE, name.substr(0, 3).to_upper())).contains(["dagger"])
	assert_array(ItemGroups.view(data, s.items, inv, "armor")).is_empty()


func test_sorts_by_type_weight_value_and_the_newest() -> void:
	var inv := {"rope": 1, "healing_potion": 1, "dagger": 1, "leather_armor": 1}
	assert_array(ItemGroups.view(data, s.items, inv)).is_equal(["dagger", "leather_armor", "healing_potion", "rope"])
	assert_array(["leather_armor", "rope"]).contains([ItemGroups.view(data, s.items, inv, ItemGroups.ALL, "weight")[0]])
	assert_str(ItemGroups.view(data, s.items, inv, ItemGroups.ALL, "value")[0]).is_equal("healing_potion")
	assert_str(ItemGroups.view(data, s.items, inv, ItemGroups.ALL, "new")[0]).is_equal("leather_armor")
	assert_str(ItemGroups.view(data, s.items, inv, ItemGroups.ALL, "new", "", true)[0]).is_equal("rope")


func test_every_sort_has_a_name_and_the_rows_end_with_the_rest() -> void:
	assert_array(ItemGroups.sorts(data).keys()).contains([ItemGroups.TYPE, "name", "weight", "value", "rarity", "new"])
	assert_bool((ItemGroups.rows(data).back() as Dictionary).has("when")).is_false()
