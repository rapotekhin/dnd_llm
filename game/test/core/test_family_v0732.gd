extends GdUnitTestSuite
## Family (v0.7.32): a proposal at the top of a romance with a home, the wedding at an officiant for its fee, the
## spouse at home by night, a child at home with the spouse, birth and growth by days, a name, upkeep and the family's
## help, hunger and leaving, the adult heir taking the dead hero's place, no divorce by a button.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-herbalist") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gender"] = "male"
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


func _romance(s: GameSession, npc: String, pts: int) -> void:
	s.character["bonds"] = {npc: {"kind": "romance", "points": pts}}


func _home(s: GameSession) -> void:
	var room := s.room_id
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(s.character)["river_house"]["deed"] = true
	PropertyRules.upgrade(s, data, "river_house", "bed")
	TimeRules.advance(s, data, 1440)
	s.room_id = room
	s.minute = 12 * 60


## Married to Mira the herbalist at the temple, the hero at home at 21:00.
func _married() -> GameSession:
	var s := _hero()
	_romance(s, "npc_herbalist", 110)
	_home(s)
	FamilyRules.propose(s, data, "npc_herbalist")
	s.room_id = "brod-temple"
	FamilyRules.wedding(s, data, "npc_priestess")
	s.room_id = str(FamilyRules.view(s.character)["home_room"])
	s.minute = 21 * 60
	return s


func test_a_proposal_needs_the_romance_and_a_home() -> void:
	var s := _hero()
	_romance(s, "npc_herbalist", 100)
	assert_str(FamilyRules.propose_why(s, data, "npc_herbalist")).is_equal("FAMILY_NOT_YET")
	_romance(s, "npc_herbalist", 110)
	assert_str(FamilyRules.propose_why(s, data, "npc_herbalist")).is_equal("FAMILY_NO_HOME")
	_home(s)
	assert_str(FamilyRules.home(s, data)).is_equal("river_house")
	assert_str(FamilyRules.propose_why(s, data, "npc_herbalist")).is_empty()
	FamilyRules.propose(s, data, "npc_herbalist")
	assert_str(FamilyRules.engaged(s)).is_equal("npc_herbalist")
	assert_str(FamilyRules.propose_why(s, data, "npc_herbalist")).is_equal("FAMILY_ENGAGED")


func test_the_wedding_at_the_temple_or_the_town_hall() -> void:
	var s := _hero("brod-temple")
	assert_str(FamilyRules.officiant(s, data, "npc_priestess")).is_equal("clergy")
	assert_str(FamilyRules.officiant(s, data, "npc_clerk")).is_equal("registry")
	assert_str(FamilyRules.officiant(s, data, "npc_innkeeper")).is_empty()
	assert_str(FamilyRules.wedding_why(s, data, "npc_priestess")).is_equal("FAMILY_NOT_ENGAGED")
	var m := _married()
	assert_str(FamilyRules.spouse(m)).is_equal("npc_herbalist")
	assert_str(FamilyRules.engaged(m)).is_empty()
	assert_int(BondRules.points(m.character, "npc_herbalist")).is_equal(120)
	var r := _hero("brod-townhall")
	_romance(r, "npc_herbalist", 110)
	_home(r)
	FamilyRules.propose(r, data, "npc_herbalist")
	var gold := int(r.character["gold_cp"])
	r.room_id = "brod-townhall"
	assert_str(FamilyRules.wedding_why(r, data, "npc_clerk")).is_empty()
	FamilyRules.wedding(r, data, "npc_clerk")
	assert_int(int(r.character["gold_cp"])).is_equal(gold - 500)


func test_the_spouse_sleeps_at_home() -> void:
	var s := _married()
	var home := s.room_id
	assert_array(SceneRules.npcs(s, data["world"], home)).contains(["npc_herbalist"])
	assert_array(SceneRules.npcs(s, data["world"], "brod-herbalist")).not_contains(["npc_herbalist"])
	s.minute = 12 * 60
	assert_array(SceneRules.npcs(s, data["world"], home)).not_contains(["npc_herbalist"])
	assert_str(FamilyRules.text(s, data)).contains("дома с 20:00 до 7:00")


func test_a_child_is_born_and_grows() -> void:
	var s := _married()
	assert_str(FamilyRules.child_why(s, data)).is_empty()
	assert_str(FamilyRules.bearer(s, data)).is_equal("npc_herbalist")
	for i in 30:
		FamilyRules.try_child(s, data)
		if FamilyRules.view(s.character).has("pregnant"):
			break
		assert_str(FamilyRules.child_why(s, data)).is_equal("FAMILY_TRIED_TODAY")
		s.day += 1
	assert_str(FamilyRules.child_why(s, data)).is_equal("FAMILY_EXPECTING")
	var due := int(FamilyRules.view(s.character)["pregnant"]["due"])
	var cash := int(s.character["property"]["river_house"].get("cash", 0))
	var lines := TimeRules.advance(s, data, 27 * 1440)
	assert_str(" ".join(lines)).contains("Родил")
	assert_str(" ".join(lines)).not_contains("налог")
	assert_int(int(s.character["property"]["river_house"]["cash"])).is_greater(cash)
	var kids := FamilyRules.children(s)
	assert_int(kids.size()).is_equal(1)
	var kid := kids[0]
	assert_int(int(BondRules.npc_def(s, data, kid)["child"]["born"])).is_equal(due)
	assert_array(data["world"]["rooms"][s.room_id]["npcs"]).contains([kid])
	assert_str(str(FamilyRules.stage(s, data, kid)["id"])).is_equal("infant")
	s.minute = 12 * 60
	TimeRules.advance(s, data, 30 * 1440)
	assert_int(FamilyRules.years(s, data, kid)).is_equal(3)
	assert_str(str(FamilyRules.stage(s, data, kid)["id"])).is_equal("child")
	assert_str(str(BondRules.npc_def(s, data, kid)["role"])).contains("ребёнок")
	FamilyRules.rename(s, data, kid, "  Велимир ")
	assert_str(BondRules.npc_name(s, data, kid)).is_equal("Велимир")
	assert_str(FamilyRules.text(s, data)).contains("Велимир")


func test_two_who_cannot_bear() -> void:
	var s := _married()
	s.character["gender"] = "female"
	assert_str(FamilyRules.child_why(s, data)).is_equal("FAMILY_NO_BEARER")
	s.minute = 12 * 60
	assert_str(FamilyRules.child_why(s, data)).is_equal("FAMILY_NOT_TOGETHER")


func test_upkeep_help_and_hunger() -> void:
	var s := _married()
	var till: Dictionary = s.character["property"]["river_house"]
	var cash := int(till.get("cash", 0))
	assert_int(FamilyRules.upkeep(s, data)).is_equal(15)
	assert_int(FamilyRules.help(s, data)).is_equal(25)
	s.day += 1
	FamilyRules.tick(s, data)
	assert_int(int(till["cash"])).is_equal(cash + 10)
	s.day += 3
	FamilyRules.tick(s, data)
	assert_int(int(till["cash"])).is_equal(cash + 40)
	FamilyRules.cfg(data)["help_cp"]["spouse"] = 0
	till["cash"] = 0
	s.character["gold_cp"] = 0
	s.day += 6
	FamilyRules.tick(s, data)
	assert_int(int(FamilyRules.view(s.character)["hungry"])).is_equal(6)
	assert_int(BondRules.points(s.character, "npc_herbalist")).is_equal(120 - 18)
	s.day += 1
	var lines := FamilyRules.tick(s, data)
	assert_str(" ".join(lines)).contains("уходит из дома")
	assert_str(FamilyRules.spouse(s)).is_empty()


func test_no_divorce_by_a_button() -> void:
	var s := _married()
	assert_str(BondRules.break_why(s, data, "npc_herbalist")).is_equal("FAMILY_NO_DIVORCE")


func test_the_adult_heir_takes_the_place() -> void:
	var s := _married()
	FamilyRules.view(s.character)["pregnant"] = {"bearer": "npc_herbalist", "due": s.day + 1}
	s.day += 1
	FamilyRules.tick(s, data)
	var kid := FamilyRules.children(s)[0]
	assert_str(FamilyRules.heir(s, data)).is_empty()
	s.day += 160
	assert_str(FamilyRules.heir(s, data)).is_equal(kid)
	var ch := FamilyRules.heir_choices(s, data)
	assert_str(str(ch["name"])).is_equal(BondRules.npc_name(s, data, kid))
	var heir_c := CharacterBuilder.build_preset(data["presets"][1], data)
	heir_c["gold_cp"] = 100
	var gold := int(s.character["gold_cp"])
	WorldGen.generated(s)["orgs"] = {"kin_band": {"name": "Банда", "kind": "criminal", "head": kid, "members": []}}
	FamilyRules.inherit(s, data, heir_c)
	assert_str(str(WorldGen.generated(s)["orgs"]["kin_band"]["head"])).is_equal(OwnerRules.HERO)
	assert_int(int(heir_c["gold_cp"])).is_equal(gold + 100)
	assert_bool((heir_c["property"] as Dictionary).has("river_house")).is_true()
	assert_array(heir_c["family"]["kin"]).contains([{"npc": "npc_herbalist", "rel": "мать"}])
	assert_bool(data["world"]["npcs"].has(kid)).is_false()
	s.character = heir_c
	s.minute = 22 * 60
	assert_array(SceneRules.npcs(s, data["world"], str(heir_c["family"]["home_room"]))).contains(["npc_herbalist"])
