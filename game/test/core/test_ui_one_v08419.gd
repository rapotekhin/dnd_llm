extends GdUnitTestSuite
## v0.8.4.19: the interface and the dead code — one limit of companions, one parley DC in and out of a fight, the rules a
## window reads made public, the members of a faction by Group.view, the windows' small parts in UiParts.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	return s


func test_three_people_go_with_the_hero_creatures_and_summons_without_a_limit() -> void:
	var s := _session()
	var most := int(FollowRules.cfg(data)["max"])
	for i in most - 1:
		Being.follow(s, "npc_follower_%d" % i)
	for i in 4:  # creatures on the hero's side do not count (the author, v0.8.4.19)
		CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "ally": true})
	assert_str(FollowRules.room_why(s, data)).is_empty()
	Being.follow(s, "npc_follower_last")
	assert_str(FollowRules.room_why(s, data)).is_equal("ALLY_TOO_MANY")
	assert_str(str(FollowRules.plan(s, data, "npc_innkeeper", true, false, true).get("reason", ""))).contains("больше никто")
	var goblin: Dictionary = CreatureRules.add(s, s.room_id, {"name": "Пленник", "monster": "goblin", "state": "surrendered"})
	assert_str(CreatureRules.can(s, str(goblin["id"]), "join", data)).is_not_equal("CREATURE_TOO_MANY")


func test_one_parley_dc_a_wounded_foe_listens_sooner() -> void:
	var foes: Array = [{"monster": "bandit"}]
	var whole := EncounterRules.parley_dc(data, foes, false)
	assert_int(whole).is_equal(CombatRules.parley_dc_of(data, foes, 0, false))
	var hurt: Array = [{"monster": "bandit", "hp": 2, "max_hp": 11}]
	assert_int(EncounterRules.parley_dc(data, hurt, false)).is_equal(maxi(int(CombatRules.cfg(data)["parley"]["min_dc"]),
		whole + int(CombatRules.cfg(data)["parley"]["per_bloodied"])))


func test_the_words_a_window_reads() -> void:
	assert_str(WorldView.location_name(data, "brod")).is_equal("Ольховый Брод")
	assert_str(WorldView.location_name(data, "nowhere")).is_equal("nowhere")
	assert_str(Scale.name_at(OfficeRules.cfg(data)["discontent_words"], 0)).is_equal("довольны")
	assert_str(CalendarRules.days_noun(1)).is_equal("день")
	assert_str(CalendarRules.days_noun(3)).is_equal("дня")
	assert_str(CalendarRules.days_noun(12)).is_equal("дней")


func test_a_faction_s_card_names_its_living_members() -> void:
	var s := _session()
	var known := ["npc_innkeeper", "npc_smith"]
	var names: Array = FactionRules.card(s, data, "brod_folk", known)["members"]
	assert_array(names).contains([WorldView.name_of(data, "npc_innkeeper"), WorldView.name_of(data, "npc_smith")])
	Being.of(s, "npc_smith")["dead"] = true
	assert_array(FactionRules.card(s, data, "brod_folk", known)["members"]).not_contains([WorldView.name_of(data, "npc_smith")])


func test_a_thing_s_ac_by_its_material() -> void:
	assert_int(ThingRules.ac_of({})).is_equal(15)
	assert_int(ThingRules.ac_of({"ac": 11})).is_equal(11)


func test_the_small_parts_of_a_window() -> void:
	var box := VBoxContainer.new()
	var l := UiParts.label(box, "строка")
	assert_int(box.get_child_count()).is_equal(1)
	assert_int(l.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	var lone := UiParts.label(null, "одна")
	assert_object(lone.get_parent()).is_null()
	lone.free()
	assert_str(UiParts.heading(box, "Заголовок").theme_type_variation).is_equal(UiTheme.ACCENT_LABEL)
	var b := UiParts.act_button(box, "Act", "Сделать", "PROPERTY_NOT_NOW", func() -> String: return "")
	assert_bool(b.disabled).is_true()
	var bar := UiParts.hp_bar(1, 10)
	assert_float(bar.max_value).is_equal(10.0)
	assert_object(UiTheme.hp_color(0.1)).is_equal(UiTheme.BAD)
	assert_object(UiTheme.hp_color(0.9)).is_equal(UiTheme.OK)
	box.free()
	bar.free()
