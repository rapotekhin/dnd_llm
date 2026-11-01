extends GdUnitTestSuite
## The arena and tournaments (v0.7.45): enlisting at the manager, a bout to surrender — the hero's blows only knock
## out, the hero at 0 HP loses, not dies, gives up, cannot leave the ring; the prize, the bet on oneself, the rank and
## the fame after a win; a bet on the day's bout of two fighters; the estimate and Insight;
## the blood pit; a duel by the contest's way; the festival's tournament.

const RING := "brod-arena-ring"
const ARENA := "brod-arena"
const PIT := "brod-pit"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = RING, day: int = 2) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.day = day
	s.character["gold_cp"] = 10000
	CalendarRules.sync(s, data["world"])
	return s


func _bout(s: GameSession, sid: String = ARENA, bet: int = 0) -> Dictionary:
	if not ArenaRules.enlisted(s, sid):
		ArenaRules.enlist(s, data, sid)
	var r := ArenaRules.bout(s, data, sid, bet)
	assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
	TestUtils.fight(s, data, r["foes"], r["source"])
	return r


func test_the_manager_enlists_the_hero_for_a_fee() -> void:
	var s := _session()
	assert_str(ArenaRules.of_manager(data, "npc_arena_master")).is_equal(ARENA)
	assert_str(ArenaRules.of_manager(data, "npc_pit_master")).is_equal(PIT)
	assert_str(ArenaRules.bout_why(s, data, ARENA)).contains("запишитесь")
	ArenaRules.enlist(s, data, ARENA)
	assert_int(int(s.character["gold_cp"])).is_equal(10000 - int(ArenaRules.cfg(data)["fee_cp"]))
	assert_str(ArenaRules.rank_name(data, ArenaRules.rank(s, ARENA))).is_equal("Новичок")
	assert_str(ArenaRules.bout_why(s, data, ARENA)).is_empty()
	var away := _session("brod-square")
	assert_str(ArenaRules.enlist_why(away, data, ARENA)).contains("распорядителя")
	assert_str(ObjectRules.text(s, data, RING)).contains("до сдачи")


func test_a_bout_to_surrender_knocks_out_and_nobody_dies() -> void:
	var s := _session()
	_bout(s)
	assert_bool(ArenaRules.yield_bout(s)).is_true()
	assert_bool(bool(s.combat["nonlethal"])).is_true()
	assert_array(CombatRules.allies(s)).is_empty()
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, foe, 999, lines)  # not a melee blow: still only knocked out
	assert_str(str(foe["status"])).is_equal("unconscious")
	var s2 := _session()
	_bout(s2)
	CombatRules._hurt_player(s2, data, 9999, true, lines)
	assert_str(str(s2.combat["outcome"])).is_equal("arena_lost")
	assert_int(int(s2.character["hp"])).is_equal(0)


func test_the_hero_gives_up_but_cannot_leave_the_ring() -> void:
	var s := _session()
	_bout(s)
	while not CombatRules.is_player_turn(s):
		CombatRules.next_actor(s, data)
	assert_str(CombatRules.can_flee(s, data)).is_equal("COMBAT_ARENA_RING")
	assert_str(CombatRules.can_surrender(s, data)).is_empty()
	CombatRules.surrender(s)
	assert_str(str(s.combat["outcome"])).is_equal("arena_lost")


func test_a_foe_gives_up_at_a_quarter_of_its_hp() -> void:
	var s := _session()
	_bout(s)
	var id := CombatRules.enemies(s)[0]
	var foe := CombatRules.fighter(s, id)
	foe["hp"] = maxi(1, int(foe["max_hp"]) / 5)
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, foe, lines)
	assert_str(str(foe["status"])).is_equal("surrendered")
	CombatRules._check_end(s, data, lines)
	assert_str(str(s.combat["outcome"])).is_equal("victory")


func test_a_win_pays_the_prize_and_the_bet_and_lifts_the_rank() -> void:
	var s := _session()
	var r := _bout(s, ARENA, 500)
	var src: Dictionary = r["source"]["arena"]
	var gold := int(s.character["gold_cp"])
	var fame := ReputationRules.points(s, "brod")
	var lines := ArenaRules.after_bout(s, data, src, true)
	s.combat = {}  # finish_combat ends the fight
	var prize := int(ArenaRules.ranks(data)[0]["prize_cp"])
	assert_int(int(s.character["gold_cp"])).is_equal(gold + prize + roundi(500 * float(src["mult"])))
	assert_int(ReputationRules.points(s, "brod")).is_greater(fame)
	assert_str(" ".join(lines)).contains("приз")
	assert_str(ArenaRules.bout_why(s, data, ARENA)).contains("завтра")
	s.day += 1
	ArenaRules.after_bout(s, data, ArenaRules.bout(s, data, ARENA)["source"]["arena"], true)
	assert_int(ArenaRules.rank(s, ARENA)).is_equal(1)
	s.day += 1
	assert_int(int(ArenaRules.opponent(s, data, ARENA)["rank"])).is_equal(1)
	var lost := ArenaRules.after_bout(s, data, ArenaRules.bout(s, data, ARENA, 100)["source"]["arena"], false)
	assert_str(" ".join(lost)).contains("проиграна")
	assert_int(int(ArenaRules.rec(s, ARENA)["losses"])).is_equal(1)


func test_a_bet_on_the_bout_of_the_day_is_a_fight_to_watch() -> void:
	var s := _session()
	var c := ArenaRules.card(s, data, ARENA)
	assert_str(str(ArenaRules.card(s, data, ARENA)["a"]["name"])).is_equal(str(c["a"]["name"]))  # the same all day
	var gold := int(s.character["gold_cp"])
	var r := ArenaRules.bet(s, data, ARENA, "a", 1000)
	assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 1000)
	assert_str(" ".join(r["lines"])).contains(str(c["a"]["name"]))
	CombatRules.start(s, data, r["foes"], r["source"])
	assert_bool(ArenaRules.watching(s)).is_true()
	assert_bool((s.combat["order"] as Array).has(CombatRules.PLAYER)).is_false()
	assert_int(CombatRules.allies(s).size()).is_equal(1)
	assert_str(str(CombatRules.fighter(s, CombatRules.allies(s)[0])["name"])).is_equal(str(c["a"]["name"]))
	assert_int(CombatRules.enemies(s).size()).is_equal(1)
	var hp := int(s.character["hp"])
	for i in 400:
		if not str(s.combat["outcome"]).is_empty():
			break
		CombatRules.next_actor(s, data)
	assert_str(str(s.combat["outcome"])).is_equal("watched")
	assert_int(int(s.character["hp"])).is_equal(hp)  # nobody touches the one at the fence
	var won := bool(s.combat["arena"]["won"])
	ArenaRules.after_bout(s, data, s.combat["arena"], won)
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 1000 + (roundi(1000 * float(c["mult_a"])) if won else 0))
	CombatRules.close(s)
	assert_str(ArenaRules.card_why(s, data, ARENA)).contains("уже")
	assert_str(ArenaRules.bet_why(s, data, 10)).contains("от")


func test_the_estimate_follows_strength_and_insight_shows_it() -> void:
	var s := _session()
	var weak := ArenaRules.hero_odds(s, data, ARENA, "bandit")
	var strong := ArenaRules.hero_odds(s, data, ARENA, "knight")
	assert_float(float(weak["p"])).is_greater(float(strong["p"]))
	assert_float(float(strong["mult"])).is_greater_equal(1.05)
	assert_bool(ArenaRules.knows(s, ARENA)).is_false()
	ArenaRules.set_insight(s, data, ARENA, true)
	assert_bool(ArenaRules.knows(s, ARENA)).is_true()
	assert_str(ArenaRules.insight_why(s, data, ARENA)).contains("уже")


func test_the_blood_pit_is_to_the_death() -> void:
	var s := _session("brod-pit")
	_bout(s, PIT)
	assert_bool(ArenaRules.yield_bout(s)).is_false()
	assert_bool(bool(s.combat["nonlethal"])).is_false()
	while not CombatRules.is_player_turn(s):
		CombatRules.next_actor(s, data)
	assert_str(CombatRules.can_surrender(s, data)).is_equal("COMBAT_NO_SURRENDER_PIT")
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, foe, 999, lines)
	assert_str(str(foe["status"])).is_equal("dead")
	var prize := ArenaRules.after_bout(s, data, s.combat["arena"], true)
	assert_str(" ".join(prize)).contains(Money.format(int(ArenaRules.ranks(data)[0]["prize_cp"]) * 2))


func test_a_duel_is_a_bout_with_the_stake() -> void:
	var s := _session("brod-tavern-hall")
	assert_bool(ContestRules.is_bout(data, "bout")).is_true()
	var st := ContestRules.start(s, data, "npc_innkeeper", "bout", 0, 200)
	assert_bool(st.has("reason")).override_failure_message(str(st)).is_false()
	var d := ContestRules.duel(s, data)
	TestUtils.fight(s, data, d["foes"], d["source"])
	assert_bool(ArenaRules.yield_bout(s)).is_true()
	var gold := int(s.character["gold_cp"])
	var cp := int(ContestRules.state(s)["cp"])  # no more than the NPC's purse
	var lines := ArenaRules.after_bout(s, data, s.combat["arena"], true)
	assert_int(int(s.character["gold_cp"])).is_equal(gold + cp * 2)
	assert_bool(ContestRules.state(s).is_empty()).is_true()
	assert_str(" ".join(lines)).contains("Победа")


func test_the_harvest_tournament_is_a_ladder_for_one_day() -> void:
	var s := _session(RING, 10)
	assert_bool(ArenaRules.tournament(s, data, ARENA).is_empty()).is_true()
	s.day = 11
	CalendarRules.sync(s, data["world"])
	var t := ArenaRules.tournament(s, data, ARENA)
	assert_str(str(t.get("name", ""))).is_equal("Турнир Дожинок")
	for i in 3:
		var r := ArenaRules.tourney_bout(s, data, ARENA)
		assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
		assert_int(int(r["source"]["arena"]["rank"])).is_equal(i)
		ArenaRules.after_bout(s, data, r["source"]["arena"], true)
	assert_int(int(s.character["inventory"].get("longsword_plus_1", 0))).is_equal(1)
	assert_str(ArenaRules.tourney_why(s, data, ARENA)).contains("выиграли")
	var s2 := _session(RING, 11)
	ArenaRules.after_bout(s2, data, ArenaRules.tourney_bout(s2, data, ARENA)["source"]["arena"], false)
	assert_str(ArenaRules.tourney_why(s2, data, ARENA)).contains("выбыли")


func test_both_sides_are_made_about_equal() -> void:
	var band := float(ArenaRules.cfg(data)["even"]["band"])
	var off := 0
	for day in range(1, 31):
		var s := _session(RING, day)
		var c := ArenaRules.card(s, data, ARENA)
		if absf(float(c["p"]) - 0.5) > band + 0.02:
			off += 1
		for i in ArenaRules.ranks(data).size():
			var opp := ArenaRules.opponent(s, data, ARENA, i)
			assert_bool(data["monsters"].has(str(opp["monster"]))).is_true()
			assert_int(int(opp["hp"])).is_greater(0)
	assert_int(off).is_less_equal(3)


func test_a_tuned_opponent_fights_with_its_hp() -> void:
	var s := _session()
	var opp := ArenaRules.opponent(s, data, ARENA, 0)
	CombatRules.start(s, data, [{"monster": str(opp["monster"]), "name": "Соперник", "max_hp": 40}], {"arena": {"kind": "rank", "rule": "yield", "site": ARENA}})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_int(int(f["hp"])).is_equal(40)
	assert_int(int(f["max_hp"])).is_equal(40)


func test_a_bout_stands_on_the_ring_with_a_crowd_that_goes_with_it() -> void:
	var s := _session()
	_bout(s)
	var map := FightGrid.map(s, data)
	var crowd: Array = s.combat["crowd"]
	assert_int(crowd.size()).is_greater(3)
	var hero := FightGrid.cell(CombatRules.player(s))
	var foe := FightGrid.cell(CombatRules.fighter(s, CombatRules.enemies(s)[0]))
	assert_int(WalkRules.distance(hero, foe)).is_equal(2 * int(ArenaRules.cfg(data)["ring"]["apart"]))
	for c: Dictionary in crowd:
		var at := Vector2i(int(c["x"]), int(c["y"]))
		assert_bool(FightGrid.walkable(FightGrid.grid(s, data), at)).is_true()
		assert_bool(FightGrid.bodies(s).has(at)).is_true()  # nobody walks through them
		assert_bool(s.npcs_here(data["world"], s.room_id).has(str(c["id"]))).is_false()
	var before := s.npcs_here(data["world"], "brod-tavern-hall")
	assert_int(int(map["w"])).is_greater(0)
	assert_int(MapSpots.crowd(s).size()).is_equal(crowd.size())
	CombatRules.close(s)
	assert_int(MapSpots.crowd(s).size()).is_equal(0)
	assert_array(s.npcs_here(data["world"], "brod-tavern-hall")).is_equal(before)



func test_the_cards_play_about_even() -> void:
	var a_wins := 0
	for day in range(1, 101):
		var s := _session(RING, day)
		var r := ArenaRules.bet(s, data, ARENA, "a", 100)
		CombatRules.start(s, data, r["foes"], r["source"])
		for i in 400:
			if not str(s.combat["outcome"]).is_empty():
				break
			CombatRules.next_actor(s, data)
		if bool(s.combat["arena"]["won"]):
			a_wins += 1
	assert_int(a_wins).is_between(30, 70)
