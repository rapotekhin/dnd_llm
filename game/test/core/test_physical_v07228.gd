extends GdUnitTestSuite
## Things are physical (roadmap v0.7.22.8): a weapon stolen from an NPC is not in its hands in a fight; a trader's
## wares lie in its shop — a deal, a theft and its death show there; what the hero left is gone after a day.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_a_stolen_weapon_leaves_the_hands() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-smithy"
	var mace := {}
	for e: Dictionary in TheftRules.pockets(s, data, "npc_smith"):
		if str(e.get("item_id", "")) == "mace":
			mace = e
	assert_dict(mace).is_not_empty()
	TheftRules.steal(s, data, "npc_smith", str(mace["id"]), true)
	assert_array(TheftRules.lost_weapons(s, data, "npc_smith")).contains(["Булава"])
	CombatRules.start(s, data, [{"monster": "thug", "npc_id": "npc_smith", "name": "Гуннар"}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var names: Array = MonsterRules.monster(data, f)["actions"].map(func(a: Dictionary) -> String: return str(a["name"]))
	assert_bool(names.has("Булава")).is_false()
	assert_bool(names.has("Безоружный удар") or names.has("Тяжёлый арбалет")).is_true()
	s.day += int(data["rules"]["theft"]["rearm_days"])
	assert_array(TheftRules.lost_weapons(s, data, "npc_smith")).is_empty()  # a new one bought


func test_the_wares_lie_in_the_shop() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-smithy"
	PropRules.ensure_wares(s, data, s.room_id)
	var w := PropRules.find(s, s.room_id, "w_npc_smith")
	assert_dict(w).is_not_empty()
	assert_str(str(w["owner"])).is_equal("npc_smith")
	var stock: Dictionary = TradeRules.merchant(s, data, "npc_smith")["stock"]
	assert_int(int(w["contents"].get("longsword", 0))).is_equal(int(stock.get("longsword", 0)))
	stock["longsword"] = int(stock["longsword"]) - 1  # sold
	assert_int(int(PropRules.find(s, s.room_id, "w_npc_smith")["contents"]["longsword"])).is_equal(int(stock["longsword"]))
	assert_bool(bool(w["locked"])).is_true()  # under the lock: picked or forced first (v0.7.49.4)
	assert_dict(ContainerRules.plan_take(s, data, "w_npc_smith", "dagger", 1)).contains_keys(["reason"])
	ContainerRules.unlock(w, "force")
	var r := ContainerRules.plan_take(s, data, "w_npc_smith", "dagger", 1)  # taken from the shelf
	assert_bool(r.has("plan")).override_failure_message(str(r)).is_true()
	var before := int(stock.get("dagger", 0))
	ContainerRules.apply_take(s, data, r["plan"])
	assert_int(int(TradeRules.merchant(s, data, "npc_smith")["stock"].get("dagger", 0))).is_equal(before - 1)
	PropRules.ensure_wares(s, data, s.room_id)
	assert_bool(bool(w["locked"])).is_false()  # still open today
	s.day += 1
	PropRules.ensure_wares(s, data, s.room_id)
	assert_bool(bool(w["locked"])).is_true()  # the smith locks it again in the morning, the lock mended
	assert_str(str(w["state"])).is_empty()


func test_a_dead_traders_wares_stay_and_do_not_restock() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-smithy"
	var stock: Dictionary = TradeRules.merchant(s, data, "npc_smith")["stock"]
	stock.erase("longsword")
	s.dead_npcs.append("npc_smith")
	s.day += 2
	assert_bool(TradeRules.merchant(s, data, "npc_smith")["stock"].has("longsword")).is_false()
	PropRules.ensure_wares(s, data, s.room_id)
	assert_bool((PropRules.find(s, s.room_id, "w_npc_smith")["contents"] as Dictionary).has("shortsword")).is_true()
	var back := GameSession.from_dict(s.to_dict(5))
	PropRules.ensure_wares(back, data, back.room_id)  # relinked after a load
	TradeRules.merchant(back, data, "npc_smith")["stock"]["shortsword"] = 0
	assert_int(int(PropRules.find(back, back.room_id, "w_npc_smith")["contents"]["shortsword"])).is_equal(0)


func test_what_was_left_is_gone_after_a_day() -> void:
	var s := TestUtils.new_session()
	s.character["inventory"]["rope"] = 1
	var r := ContainerRules.plan_drop(s, data, "rope", 1)
	ContainerRules.apply_drop(s, data, r["plan"])
	assert_array(PropRules.abandon(s, data, s.room_id)).is_empty()
	TimeRules.advance(s, data, int(data["rules"]["props"]["abandon_hours"]) * 60)
	assert_array(PropRules.abandon(s, data, s.room_id)).has_size(1)
	assert_bool(PropRules.room_props(s, s.room_id).any(func(p: Dictionary) -> bool: return str(p.get("item_id", "")) == "rope")).is_false()
