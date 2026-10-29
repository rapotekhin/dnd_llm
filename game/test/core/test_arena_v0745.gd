extends GdUnitTestSuite
## The arena and tournaments (v0.7.45): enlisting at the manager, a bout to surrender — the hero's blows only knock
## out, the hero at 0 HP loses, not dies, gives up, cannot leave the ring; the prize, the bet on oneself, the rank and
## the fame after a win; a bet on the day's bout of two fighters played out by the engine; the estimate and Insight;
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
	CombatRules.start(s, data, r["foes"], r["source"])
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
	CombatRules.player(s)["col"] = -CombatRules.edge(data)
	assert_str(CombatRules.can_move(s, data, -1)).is_equal("COMBAT_ARENA_RING")
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


func test_a_bet_on_the_bout_of_the_day_is_played_out_and_paid() -> void:
	var s := _session()
	var c := ArenaRules.card(s, data, ARENA)
	assert_str(str(ArenaRules.card(s, data, ARENA)["a"]["name"])).is_equal(str(c["a"]["name"]))  # the same all day
	var gold := int(s.character["gold_cp"])
	var r := ArenaRules.bet(s, data, ARENA, "a", 1000)
	assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
	var won := str(r["winner"]) == "a"
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 1000 + (roundi(1000 * float(c["mult_a"])) if won else 0))
	assert_str(" ".join(r["lines"])).contains(str(c["a"]["name"]))
	assert_str(ArenaRules.card_why(s, data, ARENA)).contains("уже")
	assert_str(ArenaRules.bet_why(s, data, 10)).contains("от")


func test_the_estimate_follows_strength_and_insight_shows_it() -> void:
	var s := _session()
	var weak := ArenaRules.hero_odds(s, data, ARENA, "bandit")
	var strong := ArenaRules.hero_odds(s, data, ARENA, "knight")
	assert_float(float(weak["p"])).is_greater(float(strong["p"]))
	assert_float(float(strong["mult"])).is_greater_equal(1.05)
	var wins := 0
	for i in 200:
		if str(ArenaRules.simulate(data, s.rng, "ogre", "bandit", "yield")["winner"]) == "a":
			wins += 1
	assert_int(wins).is_greater(180)
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
	CombatRules.start(s, data, d["foes"], d["source"])
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
