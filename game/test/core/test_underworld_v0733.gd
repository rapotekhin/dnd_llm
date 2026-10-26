extends GdUnitTestSuite
## The underworld (v0.7.33): a fence known by a criminal's past or a membership, stolen goods refused by an honest
## trader; burglary, robbery and smuggling with their preparations, hours and failures; the Night Rats — the trial,
## the cut and its debt, the hideout; the hero's own band and its members; the master's fence, heist and org.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-square", hour: int = 12) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = hour * 60
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


## Acts on fresh sessions until the outcome wanted ("fail" or not) comes; `prep` runs before the act.
func _act_until(fail: bool, prep: Callable) -> Dictionary:
	for seed_value in 200:
		var s: GameSession = prep.call()
		s.rng.seed = seed_value
		var r := HeistRules.act(s, data, str(s.get_meta("heist")))
		var failed := HeistRules.status(s.character, str(s.get_meta("heist"))) == "failed"
		if failed == fail:
			return {"s": s, "r": r}
	return {}


func _burglar() -> GameSession:
	var s := _hero("brod-townhall", 23)
	HeistRules.take(s, data, "heist_townhall")
	s.set_meta("heist", "heist_townhall")
	return s


func test_a_criminal_knows_fern_as_a_fence_and_an_honest_trader_refuses_the_stolen() -> void:
	var s := _hero()
	assert_bool(FenceRules.known(s, data, "npc_merchant")).is_false()
	s.character["background"] = "criminal"
	assert_bool(FenceRules.known(s, data, "npc_merchant")).is_true()
	OwnerRules.mark(s, ItemRules.found(s.character, data, s.items, "signet_ring", 1), 1, "npc_clerk")
	var value := int(ItemRules.def_of(data["items"], s.items, "signet_ring")["value_cp"])
	assert_int(TradeRules.sell_total(s, data, "npc_merchant", "signet_ring", 1)).is_equal(value * 40 / 100)
	assert_str(str(TradeRules.quote(s, data, "npc_merchant", {"sell": {"signet_ring": 1}})["error"])).is_empty()
	s.room_id = "brod-smithy"
	assert_str(str(TradeRules.quote(s, data, "npc_smith", {"sell": {"signet_ring": 1}})["error"])).is_equal("TRADE_ERR_STOLEN")
	s.room_id = "brod-square"
	assert_int(int(TradeRules.merchant(s, data, "npc_merchant")["stock"].get("thieves_tools", 0))).is_greater_equal(2)


func test_a_burglary_needs_the_night_the_place_and_an_empty_house() -> void:
	var s := _hero("brod-square", 23)
	HeistRules.take(s, data, "heist_townhall")
	assert_str(HeistRules.act_why(s, data, "heist_townhall")).is_equal("HEIST_NOT_THERE")
	s.room_id = "brod-townhall"
	s.minute = 12 * 60
	assert_str(HeistRules.act_why(s, data, "heist_townhall")).is_equal("HEIST_NOT_NOW")
	s.minute = 23 * 60
	assert_str(HeistRules.act_why(s, data, "heist_townhall")).is_empty()
	assert_str(HeistRules.step_why(s, data, "heist_townhall", "tools")).is_equal("HEIST_NO_ITEM")
	ItemRules.found(s.character, data, s.items, "thieves_tools", 1)
	var before := int(HeistRules.act_check(s, data, "heist_townhall")["bonus"])
	HeistRules.step(s, data, "heist_townhall", "tools")
	assert_int(int(HeistRules.act_check(s, data, "heist_townhall")["bonus"])).is_equal(int(before) + 2)
	HeistRules.step(s, data, "heist_townhall", "scout")
	assert_str(HeistRules.step_why(s, data, "heist_townhall", "scout")).is_not_empty()


func test_a_burglary_brings_the_victims_things_and_a_failure_is_a_known_crime() -> void:
	var won := _act_until(false, _burglar)
	var s: GameSession = won["s"]
	assert_int(int(s.character["gold_cp"])).is_greater_equal(100000 + 1500)
	assert_int(int(OwnerRules.foreign(s).get("signet_ring", {}).get("npc_clerk", 0))).is_equal(1)
	var lost := _act_until(true, _burglar)
	var f: GameSession = lost["s"]
	assert_bool(f.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "burglary" and bool(c["known"]))).is_true()
	assert_bool(f.wanted.has("brod")).is_true()


func test_a_robbery_without_the_mask_is_known_and_a_failure_is_a_fight() -> void:
	var robber := func() -> GameSession:
		var s := _hero("outpost-road", 12)
		HeistRules.take(s, data, "heist_convoy")
		s.set_meta("heist", "heist_convoy")
		return s
	var won := _act_until(false, robber)
	var s: GameSession = won["s"]
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "robbery" and str(c["location"]) == "brod")).is_true()
	var lost := _act_until(true, robber)
	assert_array(lost["r"]["fight"]).has_size(1)


func test_smuggled_casks_are_seized_on_a_failure() -> void:
	var s := _hero("brod-gate")
	HeistRules.take(s, data, "heist_casks")
	assert_int(int(s.character["inventory"].get("contraband_cask", 0))).is_equal(2)
	var smuggler := func() -> GameSession:
		var x := _hero("brod-gate")
		HeistRules.take(x, data, "heist_casks")
		x.set_meta("heist", "heist_casks")
		return x
	var lost := _act_until(true, smuggler)
	var f: GameSession = lost["s"]
	assert_int(int(f.character["inventory"].get("contraband_cask", 0))).is_equal(0)
	var won := _act_until(false, smuggler)
	assert_int(int(won["s"].character["gold_cp"])).is_equal(100000 + 2000)


func test_the_night_rats_trial_cut_and_expulsion() -> void:
	var s := _hero("brod-den")
	assert_str(OrgRules.join_why(s, data, "night_rats")).is_empty()
	OrgRules.join(s, data, "night_rats")
	assert_bool(OrgRules.candidate(s.character, "night_rats")).is_true()
	assert_str(HeistRules.status(s.character, "heist_townhall")).is_equal("active")
	OrgRules.on_heist(s, data, "heist_townhall", "done", 1500)
	assert_bool(OrgRules.member(s.character, "night_rats")).is_true()
	assert_int(int(OrgRules.view(s.character)["night_rats"]["owed_cp"])).is_equal(300)
	assert_bool(FenceRules.known(s, data, "npc_merchant")).is_true()
	assert_bool(OrgRules.offered(s, data, "night_rats").has("heist_convoy")).is_true()
	OrgRules.pay(s, data, "night_rats")
	assert_str(OrgRules.pay_why(s, data, "night_rats")).is_equal("ORG_NOTHING_OWED")
	OrgRules.on_heist(s, data, "heist_townhall", "done", 1000)
	s.day += 8
	OrgRules.tick(s, data)
	assert_bool(OrgRules.member(s.character, "night_rats")).is_false()
	assert_str(OrgRules.join_why(s, data, "night_rats")).is_equal("ORG_EXPELLED")


func test_the_hideout_gives_rest_and_hides_from_the_guard() -> void:
	var s := _hero("brod-den")
	OrgRules.join(s, data, "night_rats")
	OrgRules.on_heist(s, data, "heist_townhall", "done", 0)
	assert_bool(bool(ExplorationRules.rest_place(data["world"], s.room_id, s, data).get("free", false))).is_true()
	assert_str(OrgRules.hideout_of(s, data, "brod-den", "hide")).is_empty()
	OrgRules.view(s.character)["night_rats"]["points"] = 40
	assert_str(OrgRules.hideout_of(s, data, "brod-den", "hide")).is_equal("night_rats")
	assert_str(SiteRules.unwelcome(s, data, "brod-den")).is_empty()


func test_an_own_band_in_the_river_house_with_a_friend() -> void:
	var s := _hero("brod-river-yard")
	assert_str(OrgRules.found_why(s, data, "Тени", "river_house")).is_equal("ORG_NO_PLACE")
	PropertyRules.buy(s, data, "river_house")
	assert_str(OrgRules.found_why(s, data, "", "river_house")).is_equal("ORG_BAD_NAME")
	OrgRules.found(s, data, "Тени", "river_house")
	assert_str(OrgRules.own(s, data)).is_equal("own")
	s.room_id = "brod-tavern-hall"
	assert_str(OrgRules.recruit_why(s, data, "npc_serving")).is_equal("ORG_NOT_CLOSE")
	s.character["bonds"] = {"npc_serving": {"kind": "friend", "points": 40}}
	assert_str(OrgRules.recruit_why(s, data, "npc_serving")).is_empty()
	OrgRules.recruit(s, data, "npc_serving")
	s.room_id = "brod-gate"
	assert_str(OrgRules.recruit_why(s, data, "npc_captain")).is_equal("ORG_NOT_FOR_HIM")
	var cash := int(s.character["property"]["river_house"].get("cash", 0))
	s.day += 1
	OrgRules.tick(s, data)
	var gained := int(s.character["property"]["river_house"].get("cash", 0)) - cash
	assert_bool(gained == 30 or OrgRules.members(s, data, "own").is_empty()).is_true()


func test_the_masters_fence_heist_and_org() -> void:
	var s := _hero("brod-smithy")
	var f := FenceRules.make(s, data, {"npc_id": "npc_smith", "buy_pct": 35})
	assert_bool(f.has("plan")).is_true()
	FenceRules.apply_make(s, data, f["plan"])
	assert_bool(FenceRules.known(s, data, "npc_smith")).is_true()
	assert_bool(FenceRules.make(s, data, {"npc_id": "npc_smith", "buy_pct": 90}).has("reason")).is_false()
	s.room_id = "brod-tavern-hall"
	assert_bool(FenceRules.make(s, data, {"npc_id": "npc_veteran", "buy_pct": 35}).has("reason")).is_true()
	var h := HeistRules.make(s, data, {"heist_kind": "burglary", "name": "Погреб трактира", "target_room": "brod-tavern-cellar",
		"victim_npc": "npc_innkeeper", "giver_npc": "npc_mercenary", "loot_cp": 99999, "dc_tier": "easy", "text": "бочки и касса"})
	assert_bool(h.has("reason")).is_true()
	h = HeistRules.make(s, data, {"heist_kind": "burglary", "name": "Погреб трактира", "target_room": "brod-tavern-cellar",
		"victim_npc": "npc_innkeeper", "giver_npc": "npc_mercenary", "loot_cp": 1000, "dc_tier": "easy", "text": "бочки и касса"})
	assert_bool(h.has("plan")).is_true()
	HeistRules.apply_make(s, data, h["plan"])
	assert_int(HeistRules.active(s.character).size()).is_equal(1)
	var o := OrgRules.make(s, data, {"npc_id": "npc_mercenary", "name": "Вольные клинки", "org_kind": "criminal", "cut_pct": 15})
	assert_bool(o.has("plan")).is_true()
	OrgRules.apply_make(s, data, o["plan"])
	assert_array(OrgRules.of_head(s, data, "npc_mercenary")).has_size(1)
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"].get("underworld", ""))).contains("Погреб трактира")
