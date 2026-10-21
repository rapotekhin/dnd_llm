extends GdUnitTestSuite
## «Социальный режим 2.0» (roadmap v0.7.15.2): what an NPC grants by words goes through the engine — a trader's
## discount for a week, a service for free once in a while, a quest taken by words — and only from an NPC who likes
## the hero or was won over by a social check this turn.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _apply(s: GameSession, fx: EffectEngine, effect: Dictionary, turn := "t-1") -> Dictionary:
	var r := fx.validate(s, data, turn, effect)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_a_discount_needs_goodwill_or_a_won_check() -> void:
	var s := _hero("brod-square")
	var fx := EffectEngine.new()
	var stock := (TradeRules.merchant(s, data, "npc_merchant")["stock"] as Dictionary).keys()[0] as String
	var before := TradeRules.buy_price(s, data, "npc_merchant", stock)
	var r := _apply(s, fx, {"kind": "npc_discount", "npc_id": "npc_merchant", "percent": 10, "reason": "уговорил"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("расположен")
	fx.note_check("t-2", "medium", true, "npc_merchant")
	r = _apply(s, fx, {"kind": "npc_discount", "npc_id": "npc_merchant", "percent": 10, "reason": "уговорил"}, "t-2")
	assert_bool(bool(r["accepted"])).is_true()
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", stock)).is_less(before + 1)
	assert_int(int(TradeRules.info(s, data, "npc_merchant")["discount_pct"])).is_equal(10)
	assert_str(" ".join(s.memory_of("npc_merchant"))).contains("скидку 10%")
	s.day += 7
	assert_int(SocialRules.discount(s, "npc_merchant")).is_equal(0)  # a week is over


func test_a_discount_has_bounds_and_only_traders_give_it() -> void:
	var s := _hero("brod-tavern-hall")
	var fx := EffectEngine.new()
	s.attitudes["npc_innkeeper"] = 1
	s.attitudes["npc_veteran"] = 3
	assert_str(str(_apply(s, fx, {"kind": "npc_discount", "npc_id": "npc_innkeeper", "percent": 50, "reason": "друг"})["reason"])).contains("от 5 до 20")
	assert_str(str(_apply(s, fx, {"kind": "npc_discount", "npc_id": "npc_veteran", "percent": 10, "reason": "друг"})["reason"])).contains("не торгует")
	assert_bool(bool(_apply(s, fx, {"kind": "npc_discount", "npc_id": "npc_innkeeper", "percent": 15, "reason": "друг"})["accepted"])).is_true()


func test_a_favor_is_free_once_a_week_and_leaves_a_debt() -> void:
	var s := _hero("brod-smithy")
	var fx := EffectEngine.new()
	s.attitudes["npc_smith"] = 2
	var weapon := TradeRules.silverable(s, data)[0]
	var gold := int(s.character["gold_cp"])
	var r := _apply(s, fx, {"kind": "npc_favor", "npc_id": "npc_smith", "service": "silver", "item_id": weapon, "reason": "по дружбе"})
	assert_bool(bool(r["accepted"])).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(gold)
	assert_bool((s.character["inventory"] as Dictionary).keys().any(func(id: String) -> bool: return ItemRules.display_name(data["items"], s.items, id).contains("посеребр"))).is_true()
	assert_str(" ".join(s.memory_of("npc_smith"))).contains("в долгу")
	var again := _apply(s, fx, {"kind": "npc_favor", "npc_id": "npc_smith", "service": "silver", "reason": "ещё"}, "t-2")
	assert_bool(bool(again["accepted"])).is_false()
	var other := _apply(s, fx, {"kind": "npc_favor", "npc_id": "npc_smith", "service": "identify", "reason": "?"}, "t-3")
	assert_str(str(other["reason"])).contains("нет услуги")


func test_a_quest_is_taken_by_words_from_its_giver_only() -> void:
	var s := _hero("brod-tavern-hall")
	var fx := EffectEngine.new()
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = "npc_serving"
	var r := _apply(s, fx, {"kind": "accept_quest", "quest_id": "letter_to_ilva"})
	assert_str(str(r["reason"])).contains("не собеседник")
	s.npc_id = "npc_innkeeper"
	r = _apply(s, fx, {"kind": "accept_quest", "quest_id": "letter_to_ilva"}, "t-2")
	assert_bool(bool(r["accepted"])).is_true()
	assert_bool(s.quests_active.has("letter_to_ilva")).is_true()
	assert_str(str(_apply(s, fx, {"kind": "accept_quest", "quest_id": "drogin_amulet"}, "t-3")["reason"])).contains("здесь не предлагают")


func test_the_snapshot_shows_services_and_deals() -> void:
	var s := _hero("brod-smithy")
	s.favors["npc_smith"] = 1
	var snap := TurnSnapshot.build(s, data, 2000)
	var smith: Dictionary = (snap["scene"]["npcs"] as Array)[0]
	assert_str(str(smith["services"])).contains("[silver]")
	assert_str(str(smith["deal"])).contains("день 1")


func test_old_saves_have_no_deals() -> void:
	var v24 := {"save_version": 24, "session": {}}
	SaveFormat._v24_to_v25(v24, {})
	assert_dict(v24["session"]["discounts"]).is_empty()
	var s := _hero("brod-square")
	s.discounts["npc_merchant"] = {"pct": 10, "until_day": 5}
	s.favors["npc_smith"] = 2
	var back := GameSession.from_dict(s.to_dict(10))
	assert_int(SocialRules.discount(back, "npc_merchant")).is_equal(10)
	assert_int(int(back.favors["npc_smith"])).is_equal(2)
