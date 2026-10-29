extends GdUnitTestSuite
## Hunting and fishing (v0.7.41): a room's ground has a stock spent by the catch and grown back by days; the catch by
## the check's margin and the hours; fishing without tackle at a disadvantage; a big beast or a predator to fight;
## poaching in an owner's grounds; the master's `wilds` and grounds of a made room; an order of several hides.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String, skill: int) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 9 * 60
	s.character["skills"]["survival"] = skill
	return s


func _count(s: GameSession, id: String) -> int:
	return int(s.character["inventory"].get(id, 0))


func test_the_pack_has_grounds_in_the_pushcha_and_waters_at_the_river() -> void:
	var s := _session("pushcha-edge", 0)
	assert_array(WildsRules.here(s, data)).contains(["game"])
	s.room_id = "brod-river-yard"
	assert_array(WildsRules.here(s, data)).contains(["fish"])
	s.room_id = "brod-tavern-hall"
	assert_array(WildsRules.here(s, data)).is_empty()
	assert_str(WildsRules.why_not(s, data, "game")).is_not_empty()


func test_fishing_spends_the_stock_and_it_grows_back_by_days() -> void:
	var s := _session("brod-river-yard", 30)
	s.character["inventory"]["fishing_tackle"] = 1
	assert_dict(WildsRules.gear(s, data, "fish")).contains_key_value("dis", "")
	var full := WildsRules.stock(s, data, "fish")
	var r := WildsRules.go(s, data, "fish", 4)
	assert_int(_count(s, "fresh_fish")).override_failure_message(str(r["lines"])).is_greater(0)
	assert_int(WildsRules.stock(s, data, "fish")).is_equal(full - _count(s, "fresh_fish"))
	assert_array((r["lines"] as Array).filter(func(l: String) -> bool: return l.contains("Свежая рыба"))).is_not_empty()
	s.day += 1
	assert_int(WildsRules.stock(s, data, "fish")).is_equal(mini(full, full - _count(s, "fresh_fish") + int(WildsRules.kind(data, "fish")["regen_per_day"])))
	s.day += 30
	assert_int(WildsRules.stock(s, data, "fish")).is_equal(full)


func test_the_catch_grows_with_the_margin_and_stops_at_an_empty_stock() -> void:
	var s := _session("brod-river-yard", 30)
	s.character["inventory"]["fishing_tackle"] = 1
	WildsRules.go(s, data, "fish", 8)  # a margin of 20+: max per try × 8 tries — more than the stock
	assert_int(_count(s, "fresh_fish")).is_equal(int(WildsRules.kind(data, "fish")["stock"]))
	assert_int(WildsRules.stock(s, data, "fish")).is_equal(0)
	assert_str(WildsRules.why_not(s, data, "fish")).contains("выбито")


func test_fishing_without_tackle_is_at_a_disadvantage_and_a_net_gives_advantage() -> void:
	var s := _session("brod-river-yard", 0)
	assert_str(str(WildsRules.gear(s, data, "fish")["dis"])).is_not_empty()
	s.character["inventory"]["fishing_net"] = 1
	var g := WildsRules.gear(s, data, "fish")
	assert_str(str(g["dis"])).is_empty()
	assert_str(str(g["adv"])).is_not_empty()


func test_a_hunt_in_the_forest_gives_meat_or_a_beast_to_fight() -> void:
	var meat := 0
	var fights := 0
	for seed_value in 12:
		var s := TestUtils.new_session(seed_value)
		s.room_id = "pushcha-edge"
		s.character["skills"]["survival"] = 30
		var r := WildsRules.go(s, data, "game", 4)
		meat += _count(s, "raw_meat")
		if not (r["fight"] as Array).is_empty():
			fights += 1
			assert_array(["boar", "elk"]).contains([str(r["fight"][0]["monster"])])
	assert_int(meat).is_greater(0)
	assert_int(fights).override_failure_message("a big beast should turn up in a dozen hunts").is_greater(0)


func test_a_failed_hunt_gives_nothing_and_may_bring_a_predator() -> void:
	var predators := 0
	for seed_value in 20:
		var s := TestUtils.new_session(seed_value)
		s.room_id = "pushcha-trail"
		s.character["skills"]["survival"] = -30
		var r := WildsRules.go(s, data, "game", 2)
		assert_int(_count(s, "raw_meat")).is_equal(0)
		if not (r["fight"] as Array).is_empty():
			predators += 1
			assert_array(["wolf", "black_bear"]).contains([str(r["fight"][0]["monster"])])
	assert_int(predators).is_greater(0)


func test_poaching_in_an_owners_grounds_is_a_crime_until_the_owner_permits() -> void:
	var s := _session("pushcha-edge", 30)
	data["world"]["rooms"]["pushcha-edge"]["wilds_owner"] = "npc_captain"
	assert_bool(WildsRules.poaching(s, data)).is_true()
	data["rules"]["wilds"]["poach"]["seen_pct"] = 100
	var r := WildsRules.go(s, data, "game", 2)
	assert_bool(bool(r["crime"])).is_true()
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "poaching")).is_true()
	var s2 := _session("pushcha-edge", 30)
	assert_array(WildsRules.closed_grounds(s2, data, "npc_captain")).contains(["pushcha-edge"])
	SiteRules.grant(s2, data, "npc_captain")
	assert_bool(WildsRules.poaching(s2, data)).is_false()
	assert_bool(bool(WildsRules.go(s2, data, "game", 2)["crime"])).is_false()


func test_the_masters_wilds_empties_restores_and_adds_a_ground_for_a_cause() -> void:
	var s := _session("brod-river-yard", 0)
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t1", {"kind": "wilds", "ground": "fish", "op": "deplete", "cause": "выше по реке мельник потравил рыбу"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t1", [r["effect_id"]])
	assert_int(WildsRules.stock(s, data, "fish")).is_equal(0)
	assert_bool(bool(fx.validate(s, data, "t2", {"kind": "wilds", "ground": "fish", "op": "deplete", "cause": "так"})["accepted"])).is_false()
	assert_bool(bool(fx.validate(s, data, "t3", {"kind": "wilds", "ground": "game", "op": "deplete", "cause": "охотники всё выбили"})["accepted"])).is_false()
	s.room_id = "brod-square"
	r = fx.validate(s, data, "t4", {"kind": "wilds", "ground": "fish", "op": "add", "cause": "на площади вырыли и зарыбили пруд"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t4", [r["effect_id"]])
	assert_array(WildsRules.here(s, data)).contains(["fish"])
	assert_array(WorldGen.generated(s)["room_patch"]["brod-square"]["tags"]).contains(["fish"])
	s.room_id = "brod-tavern-hall"
	assert_bool(bool(fx.validate(s, data, "t5", {"kind": "wilds", "ground": "game", "op": "add", "cause": "в таверне завелись кролики"})["accepted"])).is_false()


func test_the_scene_tells_the_master_the_grounds_and_the_stock() -> void:
	var s := _session("brod-river-yard", 0)
	var lines := WildsRules.lines(s, data)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).contains("Рыбачить").contains("запас")


func test_the_catch_is_wanted_by_the_innkeeper_and_hides_by_the_tanner_kind() -> void:
	var kinds: Dictionary = data["rules"]["trade"]["kinds"]
	assert_array(kinds["food"]["wants"]).contains(["catch"])
	assert_array(kinds["tailor"]["wants"]).contains(["hide"])
	assert_array(ItemRules.trade_tags(data["items"]["catalog"]["raw_hide"])).contains(["hide"])
	assert_array(ItemRules.trade_tags(data["items"]["catalog"]["fresh_fish"])).contains(["catch"])


func test_an_order_of_three_hides_waits_for_all_three() -> void:
	var s := _session("brod-tavern-hall", 0)
	var when := {"talk": "npc_innkeeper", "item": "raw_hide", "qty": 3}
	s.character["inventory"]["raw_hide"] = 2
	var lines: Array[String] = []
	assert_bool(QuestRules.met(s, {"item": "raw_hide", "qty": 3, "room": "brod-tavern-hall"})).is_false()
	s.character["inventory"]["raw_hide"] = 3
	QuestRules._hand_over(s, data, str(when["item"]), lines, "Отдано", int(when["qty"]))
	assert_int(_count(s, "raw_hide")).is_equal(0)
	assert_str(lines[0]).contains("×3")
