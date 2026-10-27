extends GdUnitTestSuite
## The entry turn's search (v0.7.34.4): everyday things in the catalog, a search by words, a portable thing the
## master makes when the catalog lacks it.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"


func _ids(query: String) -> Array:
	return ItemRules.find(data["items"], s.items, query, "", []).map(func(i: Dictionary) -> String: return i["item_id"])


func test_a_query_of_several_words_finds_by_a_word_after_the_exact_hits() -> void:
	assert_array(_ids("кувшин глиняный")).contains(["jug_or_pitcher"])
	assert_array(_ids("мешок с зерном")).contains(["sack"])
	assert_array(_ids("бочка")).contains(["barrel"])
	assert_array(_ids("репа")).contains(["vegetables"])  # by the description: «Репа, лук и морковь»


func test_everyday_things_are_in_the_catalog_and_food_is_eaten() -> void:
	for q: String in ["табурет", "грабли", "записка", "яблоки", "гвозди", "метла", "чаша", "ладан", "ступка", "огниво", "тачка", "оберег"]:
		assert_array(_ids(q)).override_failure_message(q).is_not_empty()
	assert_bool(data["rules"]["consumables"].has("cheese")).is_true()


func test_a_portable_thing_the_catalog_lacks_is_made_when_furnishing() -> void:
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Межевой колышек",
		"item": {"name": "Межевой колышек", "item_type": "gear", "rarity": "common", "value_cp": 1}}, {"name": "Очаг"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var stake: Dictionary = PropRules.find(s, s.room_id, "p1")
	assert_str(str(stake["item_id"])).starts_with("gen_")
	assert_bool(s.items.has(str(stake["item_id"]))).is_true()
	assert_str(str(PropRules.find(s, s.room_id, "p2")["item_id"])).is_empty()
