extends GdUnitTestSuite
## Contests (v0.7.40): a game with an NPC of the scene for a stake — coins or a thing of the NPC, both on the table from
## the start; rounds by the totals of both sides, the kind's loss (drinking — poisoned), cheating caught as a theft,
## the games of a day, the master's own kind offered by the effect `contest`.

const NPC := "npc_innkeeper"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-tavern-hall"
	s.minute = 19 * 60
	s.character["gold_cp"] = 10000
	s.pockets[NPC] = [
		{"id": "k1", "name": "Кошель", "item_id": "", "cp": 3000, "qty": 1, "worn": false, "dc": 12},
		{"id": "k2", "name": "Кинжал", "item_id": "dagger", "cp": 0, "qty": 1, "worn": false, "dc": 14},
	]
	return s


func _stake(s: GameSession, kind: String) -> int:
	var list := ContestRules.stakes(s, data, NPC)
	for i in list.size():
		if str(list[i]["kind"]) == kind:
			return i
	return -1


func test_a_coins_game_won_pays_both_stakes_and_fame() -> void:
	var s := _session()
	assert_str(ContestRules.why_not(s, data, NPC)).is_empty()
	var r := ContestRules.start(s, data, NPC, "dice", _stake(s, "coins"), 500)
	assert_bool(r.has("lines")).override_failure_message(str(r)).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(9500)
	assert_int(ContestRules.purse(s, data, NPC)).is_equal(2500)
	ContestRules.round(s, data, 15, 9)
	ContestRules.round(s, data, 9, 9)  # a tie takes nobody
	assert_int(int(ContestRules.state(s)["hero"])).is_equal(1)
	var lines := ContestRules.round(s, data, 18, 3)
	assert_bool(ContestRules.state(s).is_empty()).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(10500)
	assert_str(", ".join(lines)).contains("Победа")
	assert_int(ReputationRules.points(s, "brod")).is_greater(0)


func test_drinking_lost_poisons_the_hero_and_feeds_the_purse() -> void:
	var s := _session()
	ContestRules.start(s, data, NPC, "drinking", _stake(s, "coins"), 200)
	for i in 3:
		ContestRules.round(s, data, 2, 20)
	assert_bool(ContestRules.state(s).is_empty()).is_true()
	assert_bool((s.character.get("conditions", []) as Array).has("poisoned")).is_true()
	assert_int(int(s.character["gold_cp"])).is_equal(9800)
	assert_int(ContestRules.purse(s, data, NPC)).is_equal(3200)


func test_a_thing_on_the_table_goes_to_the_winner() -> void:
	var s := _session()
	var i := _stake(s, "item")
	assert_int(i).is_greater_equal(0)
	var cp := int(ContestRules.stakes(s, data, NPC)[i]["cp"])
	ContestRules.start(s, data, NPC, "arm", i)
	assert_int(int(s.character["gold_cp"])).is_equal(10000 - cp)
	ContestRules.round(s, data, 20, 1)
	ContestRules.round(s, data, 20, 1)
	assert_int(int(s.character.get("inventory", {}).get("dagger", 0))).is_greater(0)
	assert_int(int(s.character["gold_cp"])).is_equal(10000)
	assert_bool(TheftRules.pockets(s, data, NPC).any(func(e: Dictionary) -> bool: return str(e["id"]) == "k2")).is_false()


func test_cheating_caught_loses_the_stake_and_shuts_the_table() -> void:
	var s := _session()
	var before := s.attitude(NPC)
	ContestRules.start(s, data, NPC, "cards", _stake(s, "coins"), 300)
	var lines := ContestRules.round(s, data, 8, 12, true)
	assert_str(", ".join(lines)).contains("жульничестве")
	assert_bool(ContestRules.state(s).is_empty()).is_true()
	assert_int(s.attitude(NPC)).is_less(before)
	assert_int(int(s.character["gold_cp"])).is_less(9800)  # the stake and the fine
	assert_str(ContestRules.why_not(s, data, NPC)).contains("шулер")


func test_cheating_unseen_takes_the_round() -> void:
	var s := _session()
	ContestRules.start(s, data, NPC, "cards", _stake(s, "coins"), 300)
	ContestRules.round(s, data, 16, 11, true)
	assert_int(int(ContestRules.state(s)["hero"])).is_equal(1)


func test_games_of_a_day_with_one_npc_are_counted() -> void:
	var s := _session()
	for i in int(ContestRules.cfg(data)["per_npc_day"]):
		ContestRules.start(s, data, NPC, "song", _stake(s, "coins"), 100)
		ContestRules.forfeit(s, data)
	assert_str(ContestRules.why_not(s, data, NPC)).contains("наигрался")
	s.day += 1
	assert_str(ContestRules.why_not(s, data, NPC)).is_empty()


func test_odds_by_the_template_and_the_chance_of_a_round() -> void:
	var s := _session()
	assert_int(ContestRules.chance(0, 0)).is_between(45, 52)
	assert_int(ContestRules.chance(5, 0)).is_greater(ContestRules.chance(0, 0))
	var o := ContestRules.odds(s, data, NPC, "arm")
	assert_int(int(o["chance"])).is_between(1, 99)


func test_the_master_offers_a_game_of_its_own_kind() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "contest", "npc_id": NPC,
		"new_kind": {"name": "Метание ножей", "check": {"skill": "sleight_of_hand"}, "wins": 9, "lose_condition": "prone"}})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var offer: Dictionary = s.character.get("contest_offer", {})
	assert_str(str(offer.get("npc", ""))).is_equal(NPC)
	var k := ContestRules.kind(data, str(offer["kind"]))
	assert_str(str(k.get("name", ""))).is_equal("Метание ножей")
	assert_int(int(k["wins"])).is_equal(int(ContestRules.cfg(data)["make"]["wins"][1]))
	assert_bool(WorldGen.generated(s).get("contest_kinds", {}).has(str(offer["kind"]))).is_true()
	var bad := engine.validate(s, data, "t-2", {"kind": "contest", "npc_id": NPC, "new_kind": {"name": "x", "check": {"skill": "flying"}}})
	assert_bool(bool(bad["accepted"])).is_false()
	var nobody := engine.validate(s, data, "t-3", {"kind": "contest", "npc_id": "npc_nobody", "game": "dice"})
	assert_bool(bool(nobody["accepted"])).is_false()
