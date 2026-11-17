extends GdUnitTestSuite
## v0.8.4.44.12, the author: «клик на портрет союзника должен как в BG3 давать управление союзником непосредственно как
## игроком (игрок становится спутником в этот момент и ходит за тем персонажем, которым я управляю)». PartyLead: the one
## led stands on the walk's square, the hero walks round it with the rest; a trap underfoot and a walk's passive
## Perception are the led one's; a fight hands the lead back to the hero.

var data: Dictionary
var kept: GameSession


func before() -> void:
	data = TestUtils.data()


func before_test() -> void:
	kept = GameState.session
	GameState.session = _party()


func after_test() -> void:
	GameState.session = kept


func _party() -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	return s


func test_the_hero_leads_until_a_follower_is_taken() -> void:
	var s := GameState.session
	assert_str(PartyLead.of(s)).is_equal(Being.HERO)
	assert_str(PartyLead.ref(s)).is_empty()
	var party := MapSpots.party(s, data)
	assert_str(str(party[0]["id"])).is_equal(Being.HERO)
	assert_array(MapSpots.walkers(s, data).map(func(t: Dictionary) -> String: return str(t["id"]))).is_equal(["npc_mercenary"])


func test_a_follower_led_stands_where_it_stood_and_the_hero_walks_with_the_rest() -> void:
	var s := GameState.session
	var map := WalkRules.view(s, data)
	var hero_was := WalkRules.settle(s, data, map)
	var merc_was := MapSpots.square_of(s, data, "npc_mercenary")
	assert_str(GameState.lead("npc_mercenary")).is_empty()
	assert_str(PartyLead.of(s)).is_equal("npc_mercenary")
	assert_str(PartyLead.ref(s)).is_equal("npc:npc_mercenary")
	assert_that(WalkRules.settle(s, data, map)).is_equal(merc_was)
	var walkers := MapSpots.walkers(s, data)
	assert_str(str(walkers[0]["kind"])).is_equal("hero")
	assert_that(MapSpots.square_of(s, data, Being.HERO)).is_not_equal(merc_was)
	assert_that(MapSpots.cell_of(s, data, map, "hero")).is_equal(MapSpots.square_of(s, data, Being.HERO))
	var standing := MapSpots.standing(s, data)
	assert_int(standing.filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "hero").size()).is_equal(1)
	assert_str(GameState.lead(Being.HERO)).is_empty()
	assert_str(PartyLead.of(s)).is_equal(Being.HERO)
	assert_bool(WalkRules.distance(WalkRules.settle(s, data, map), hero_was) <= 3).is_true()


func test_only_one_of_the_party_on_its_feet_is_led() -> void:
	var s := GameState.session
	assert_str(PartyLead.why(s, data, "npc_veteran")).is_equal("LEAD_NOT_PARTY")
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 6}], {})
	assert_str(PartyLead.why(s, data, "npc_mercenary")).is_equal("LEAD_NOT_IN_FIGHT")


func test_a_fight_hands_the_lead_back_to_the_hero() -> void:
	var s := GameState.session
	GameState.lead("npc_mercenary")
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 6}], {})
	assert_str(PartyLead.of(s)).is_equal(Being.HERO)
	assert_bool(s.layouts.has(PartyLead.KEY)).is_false()


func test_the_trap_underfoot_strikes_the_one_led() -> void:
	var s := GameState.session
	GameState.lead("npc_mercenary")
	var me := PartyLead.own(s)
	var hp := Sheet.hp(s, data, Sheet.who(s, data, "npc_mercenary"))
	var hero_hp := int(s.character["hp"])
	var sec := {"id": "t_test", "text": "Иглы в полу.", "dc": 10, "trap": {"damage": "6", "damage_type": "piercing"}}
	ExplorationRules.spring_trap(s, data, s.room_id, sec)
	assert_int(Sheet.hp(s, data, Sheet.who(s, data, "npc_mercenary"))).is_less(hp)
	assert_int(int(s.character["hp"])).is_equal(hero_hp)
	assert_dict(me).is_not_empty()
