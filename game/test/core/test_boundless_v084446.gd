extends GdUnitTestSuite
## v0.8.4.44.6, the dream's sixth hall (docs/design/systems/tutorial/description.md, decision 8): a room marked
## `boundless` lets the master make things, recipes and spells of any price and power, as many as asked — no budget,
## no «magic only as a find», no rarity's level, no cap of a wand's charges, a spell's circle or a build's points —
## and only there: the hall before it keeps every limit. The shapes of the parts stay.

var dream: Dictionary


func before_test() -> void:
	dream = WorldPack.apply_rules(TestUtils.base(), WorldPack.load_bundle("res://data/worlds/tutorial", "builtin"))


func _at(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.world_id = "tutorial"
	s.room_id = room
	s.visited = [room] as Array[String]
	CharacterRules.refresh(s.character, dream)
	return s


func _sword(n: int) -> Dictionary:
	return {"kind": "move_item", "source": "world", "target": "hero", "item": {"name": "Меч архангела %d" % n, "base": "longsword", "item_type": "weapon",
		"rarity": "legendary", "value_cp": 5000000, "description": "Тяжёлый клинок в белых перьях.",
		"properties": ["magic_plus3", "radiant_damage", "fire_damage", "force_damage", "thunder_damage", "no_crit", "regeneration"]}}


func _storm(amount: int, extra: Dictionary = {}) -> Dictionary:
	var e := {"kind": "make", "what": "spell", "key": "storm", "name": "Цепная буря %d" % amount, "text": "Молния скачет от врага к врагу.",
		"parts": [{"part": "target", "value": "area"}, {"part": "roll", "value": "dex"}, {"part": "half"}, {"part": "damage", "value": "lightning", "amount": amount}]}
	e.merge(extra)
	return e


func test_the_mark_is_the_sixth_hall_s_alone() -> void:
	assert_bool(MakeRules.boundless(_at("dream-6"), dream)).is_true()
	assert_int(MakeRules.level_of(_at("dream-6"), dream)).is_equal(ItemRules.BOUNDLESS)
	for room: String in ["dream-5", "dream-7"]:
		assert_bool(MakeRules.boundless(_at(room), dream)).is_false()
		assert_int(MakeRules.level_of(_at(room), dream)).is_equal(1)
	var mark := TestUtils.new_session()
	assert_bool(MakeRules.boundless(mark, TestUtils.data())).is_false()


func test_legendary_swords_as_many_as_asked_outside_the_budget() -> void:
	var s := _at("dream-6")
	var fx := EffectEngine.new()
	fx.mark_searched("t-1")  # no check passed this turn: a magic thing is no find here
	var ids: Array = []
	for n in 3:
		var r := fx.validate(s, dream, "t-1", _sword(n))
		assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
		ids.append(r["effect_id"])
	fx.apply(s, "t-1", ids)
	assert_int(s.reward_spent).is_equal(0)  # the counters stay for after the hall
	assert_int(s.magic_given).is_equal(0)
	var id := ItemRules.generated_id({"name": "Меч архангела 0", "base": "longsword", "properties": _sword(0)["item"]["properties"]})
	assert_str(str(ItemRules.def_of(dream["items"], s.items, id).get("rarity", ""))).is_equal("legendary")
	assert_int(Gear.count(s, dream, Being.HERO, id)).is_equal(1)
	var before := _at("dream-5")
	var fx5 := EffectEngine.new()
	fx5.mark_searched("t-5")
	var no := fx5.validate(before, dream, "t-5", _sword(0))
	assert_bool(bool(no["accepted"])).is_false()


func test_a_spell_past_the_engine_s_points_its_scroll_and_a_wand_of_ten_charges() -> void:
	var s := _at("dream-6")
	var spell := MakeRules.plan(s, dream, _storm(20, {"scroll": "Свиток бури"}))
	assert_bool(spell.has("plan")).override_failure_message(str(spell)).is_true()
	assert_int(int(spell["plan"]["def"]["circle"])).is_equal(5)  # the top circle of the engine
	assert_dict(spell["plan"]["scroll"]).is_not_empty()
	MakeRules.apply(s, dream, spell["plan"])
	var id := str(spell["plan"]["id"])
	var wand := {"name": "Жезл цепной бури", "item_type": "wondrous", "rarity": "legendary", "value_cp": 100000, "description": "Жезл с медным навершием.",
		"use": {"spell": id, "charges": 10}}
	var chk := ItemRules.check_generated(dream, wand, MakeRules.level_of(s, dream))
	assert_bool(bool(chk["ok"])).override_failure_message(str(chk)).is_true()
	assert_int(int(chk["def"]["charges"]["max"])).is_equal(10)
	var kept := _at("dream-5")
	assert_str(str(MakeRules.plan(kept, dream, _storm(20)).get("reason", ""))).contains("не собирает")
	assert_str(str(MakeRules.plan(kept, dream, _storm(10, {"scroll": "Свиток"})).get("reason", ""))).contains("не выше 3 круга")
	assert_bool(bool(ItemRules.check_generated(dream, wand, MakeRules.level_of(kept, dream))["ok"])).is_false()


func test_a_recipe_of_a_legendary_thing_takes_the_master_s_hours() -> void:
	var s := _at("dream-6")
	s.character["tools"] = ["smiths_tools"]
	var spec := {"tool": "smiths_tools", "hours": 8, "dc_tier": "medium", "materials": {"iron_bar": 2}, "qty": 1, "output": _sword(9)["item"]}
	var made := CraftRules.make(s, dream, spec)
	assert_bool(made.has("reason")).override_failure_message(str(made)).is_false()
	assert_int(int(made["def"]["hours"])).is_equal(8)
	assert_str(str(made["item"]["rarity"])).is_equal("legendary")
	var kept := _at("dream-5")
	kept.character["tools"] = ["smiths_tools"]
	assert_bool(CraftRules.make(kept, dream, spec).has("reason")).is_true()
	s.character["tools"] = []
	assert_str(str(CraftRules.make(s, dream, spec).get("reason", ""))).contains("не владеет")  # the tool stays
