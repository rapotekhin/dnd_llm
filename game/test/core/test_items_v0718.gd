extends GdUnitTestSuite
## «Генерация предметов» (roadmap v0.7.18, batch 1): a thing the master makes may have a `use` — a wand with charges
## of a spell of the engine's book, a scroll, a potion — priced in rarity points; a thing without mechanics may carry
## what is written in it.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _check(item: Dictionary, level := 1) -> Dictionary:
	return ItemRules.check_generated(data["items"], item, level, data["spells"])


func test_a_wand_of_a_spell_with_charges() -> void:
	var r := _check({"name": "Жезл искр", "item_type": "wondrous", "value_cp": 40000, "use": {"spell": "magic_missile", "charges": 5}})
	assert_bool(bool(r["ok"])).is_true()
	assert_str(str(r["def"]["rarity"])).is_equal("uncommon")
	assert_dict(r["def"]["use"]).is_equal({"spell": "magic_missile", "level": 1})
	assert_int(int(r["def"]["charges"]["max"])).is_equal(5)
	assert_str(str(_check({"name": "Жезл", "item_type": "wondrous", "value_cp": 1, "use": {"spell": "fireball", "charges": 3}})["reason"])).contains("уровне")
	assert_str(str(_check({"name": "Жезл", "item_type": "wondrous", "value_cp": 1, "use": {"spell": "nope", "charges": 3}})["reason"])).contains("нет в книге")


func test_scrolls_and_potions_are_once() -> void:
	var scroll := _check({"name": "Свиток щита", "item_type": "consumable", "value_cp": 5000, "use": {"spell": "shield"}})
	assert_bool(bool(scroll["def"]["use"]["scroll"])).is_true()
	assert_str(str(scroll["def"]["rarity"])).is_equal("common")
	var potion := _check({"name": "Настой Веданы", "item_type": "consumable", "value_cp": 3000, "use": {"heal": "light"}})
	assert_array(potion["def"]["use"]["heal"]).is_equal([2, 4, 2])
	assert_str(str(_check({"name": "Бочонок", "item_type": "gear", "value_cp": 1, "use": {"heal": "light"}})["reason"])).contains("consumable")
	assert_str(str(_check({"name": "Зелье", "item_type": "consumable", "value_cp": 1, "use": {"heal": "light", "charges": 3}})["reason"])).contains("заряды")


func test_a_made_potion_is_used_like_a_catalog_one() -> void:
	var s := TestUtils.new_session()
	CharacterRules.refresh(s.character, data)
	var fx := EffectEngine.new()
	s.character["hp"] = 1
	fx.mark_searched("t-1")  # the master looked for a like thing first
	var r := fx.validate(s, data, "t-1", {"kind": "give_item", "item": {"name": "Настой Веданы", "item_type": "consumable", "rarity": "common",
		"value_cp": 3000, "use": {"heal": "light"}}})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var id := str(r["item_id"])
	assert_dict(ItemRules.consumable(data, id, s.items)).is_not_empty()
	assert_str(ItemRules.can_use(s.character, data, s.items, id)).is_empty()
	ItemRules.use(s.character, data, s.items, id, s.rng, s)
	assert_int(int(s.character["hp"])).is_greater(1)


func test_a_letter_carries_its_text() -> void:
	var r := _check({"name": "Письмо Бруно", "item_type": "gear", "value_cp": 0, "text": "Илва, приходи вечером — надо поговорить о погребе."})
	assert_str(str(r["def"]["text"])).contains("о погребе")
	assert_str(str(r["def"]["rarity"])).is_equal("common")
	var s := TestUtils.new_session()
	s.items["gen_letter"] = r["def"]
	assert_str(" ".join(ItemInfo.lines(s.character, data, s.items, "gen_letter"))).contains("Написано: «Илва")
