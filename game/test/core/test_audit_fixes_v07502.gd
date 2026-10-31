extends GdUnitTestSuite
## The unification audit's findings (v0.7.50.2): followers, wounds, a fled creature, a faction's start, the shop's till
## and the tax, the marks of stolen things, a locked chest, food and water, charges of a stack, the study's misses.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-square") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


func _chest(s: GameSession, extra: Dictionary = {}) -> Dictionary:
	var p := {"id": "p1", "name": "Сундук", "description": "", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest", "contents": {}}
	p.merge(extra, true)
	s.props[s.room_id] = [p]
	return p


func _joins(s: GameSession, npc: String) -> bool:
	return AllyRules.joining(s, data, [{"monster": "wolf"}]).any(func(a: Dictionary) -> bool: return str(a.get("npc_id", "")) == npc)


func test_a_dead_follower_leaves() -> void:
	var s := _hero()
	s.followers = ["npc_mercenary"]
	assert_bool(_joins(s, "npc_mercenary")).is_true()
	CrimeRules.on_death(s, data, "npc_mercenary", false, s.room_id)
	assert_array(s.followers).is_empty()


func test_the_dead_and_the_knocked_out_do_not_fight() -> void:
	var s := _hero()
	s.followers = ["npc_mercenary"]
	s.creatures[s.room_id] = [{"id": "c1", "name": "Кейра", "monster": "guard", "state": "unconscious", "npc_id": "npc_mercenary"}]
	assert_bool(_joins(s, "npc_mercenary")).is_false()
	s.creatures[s.room_id] = []
	s.dead_npcs.append("npc_mercenary")
	assert_bool(_joins(s, "npc_mercenary")).is_false()


func test_a_wounded_npc_fights_with_its_wounds() -> void:
	var s := _hero()
	s.npc_hp["npc_mercenary"] = 3
	CombatRules.start(s, data, [{"monster": "guard", "name": "Кейра", "npc_id": "npc_mercenary", "col": 0}], {})
	assert_int(int(CombatRules.fighter(s, CombatRules.enemies(s)[0])["hp"])).is_equal(3)


func test_an_npc_foe_keeps_its_wounds_after_the_fight() -> void:
	var s := _hero()
	CombatRules.start(s, data, [{"monster": "guard", "name": "Кейра", "npc_id": "npc_mercenary", "col": 0}], {})
	CombatRules.fighter(s, CombatRules.enemies(s)[0])["hp"] = 4
	AllyRules.after_fight(s)
	assert_int(int(s.npc_hp["npc_mercenary"])).is_equal(4)


func test_captors_let_go_keep_wounds_and_given_xp() -> void:
	var s := _hero()
	EncounterRules.as_creatures(s, s.room_id, [{"monster": "goblin", "name": "Гоблин", "count": 1, "hp": 2, "max_hp": 7, "no_xp": true}], "truce")
	var c: Dictionary = s.creatures[s.room_id][0]
	assert_int(int(c["hp"])).is_equal(2)
	assert_int(int(c["max_hp"])).is_equal(7)
	assert_bool(bool(c["xp_given"])).is_true()


func test_a_creature_the_hero_ran_from_stays_with_its_wounds() -> void:
	var s := _hero()
	s.creatures[s.room_id] = [{"id": "c1", "name": "Гоблин", "monster": "goblin", "state": "truce", "bound": false, "led": false, "hp": 6, "max_hp": 7}]
	CreatureRules.act(s, data, "c1", "attack")
	assert_array(s.creatures[s.room_id]).is_empty()
	CombatRules.start(s, data, s.pending_fight, {})
	CombatRules.fighter(s, CombatRules.enemies(s)[0])["hp"] = 2
	CreatureRules.after_flight(s, s.room_id)
	var c: Dictionary = s.creatures[s.room_id][0]
	assert_str(str(c["id"])).is_equal("c1")
	assert_int(int(c["hp"])).is_equal(2)


func test_a_met_faction_counts_from_its_start() -> void:
	var s := _hero()
	data["world"]["factions"]["ash_cult"]["start"] = -20
	FactionRules.meet(s, data, "ash_cult")
	FactionRules.add(s, data, "ash_cult", 5, "тест")
	assert_int(FactionRules.points(s, data, "ash_cult")).is_equal(-15)


func test_the_tax_is_paid_from_the_shops_till() -> void:
	var s := _hero("brod-townhall")
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.deed(s, data, "river_house")
	s.character["gold_cp"] = 0
	ShopRules.venue(s.character, "river_house")["cash"] = 1000
	TimeRules.advance(s, data, 7 * 1440)
	assert_int(int(PropertyRules.state(s.character)["river_house"].get("debt", 0))).is_equal(0)
	assert_int(int(ShopRules.venue(s.character, "river_house")["cash"])).is_equal(970)


func test_a_stolen_thing_stays_stolen_through_a_chest() -> void:
	var s := _hero()
	s.character["inventory"]["dagger"] = 1
	OwnerRules.mark(s, "dagger", 1, "npc_merchant")
	_chest(s)
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": "dagger", "qty": 1})
	OwnerRules.tidy(s)
	assert_dict(OwnerRules.foreign(s)).is_empty()
	ContainerRules.apply_take(s, data, {"room": s.room_id, "from": "p1", "item_id": "dagger", "qty": 1, "owner": ""})
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_the_marks_leave_only_past_what_is_carried() -> void:
	var s := _hero()
	s.character["inventory"]["dagger"] = 2
	OwnerRules.mark(s, "dagger", 1, "npc_merchant")
	_chest(s)
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": "dagger", "qty": 1})
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_a_stolen_thing_stays_stolen_on_the_floor() -> void:
	var s := _hero()
	s.character["inventory"]["dagger"] = 1
	OwnerRules.mark(s, "dagger", 1, "npc_merchant")
	ContainerRules.apply_drop(s, data, {"room": s.room_id, "item_id": "dagger", "qty": 1})
	OwnerRules.tidy(s)
	var id := str(s.props[s.room_id][-1]["id"])
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": id, "owner": ""})
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_a_thing_back_in_its_owners_chest_is_returned() -> void:
	var s := _hero()
	s.character["inventory"]["dagger"] = 1
	OwnerRules.mark(s, "dagger", 1, "npc_merchant")
	var p := _chest(s, {"owner": "npc_merchant"})
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": "dagger", "qty": 1})
	assert_dict(p.get("marks", {})).is_empty()


func test_a_locked_chest_is_not_carried_off() -> void:
	var s := _hero()
	_chest(s, {"item_id": "backpack", "container": "backpack", "locked": true})
	assert_bool(PropRules.plan_take(s, data, {"prop_id": "p1"}).has("reason")).is_true()


func test_what_is_in_a_taken_bag_is_its_owners() -> void:
	var s := _hero()
	_chest(s, {"item_id": "backpack", "container": "backpack", "owner": "npc_merchant", "contents": {"dagger": 1}})
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": "p1", "owner": ""})
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_food_keeps_its_age_in_a_chest_and_on_the_floor() -> void:
	var s := _hero()
	s.character["inventory"]["raw_meat"] = 2
	FoodRules.sync(s, data)
	var got := int(s.character["fresh"]["raw_meat"][0][0])
	s.minute += 60
	_chest(s)
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": "raw_meat", "qty": 1})
	s.minute += 60
	ContainerRules.apply_take(s, data, {"room": s.room_id, "from": "p1", "item_id": "raw_meat", "qty": 1, "owner": ""})
	FoodRules.sync(s, data)
	assert_array(s.character["fresh"]["raw_meat"]).is_equal([[got, 1], [got, 1]])
	ContainerRules.apply_drop(s, data, {"room": s.room_id, "item_id": "raw_meat", "qty": 1})
	s.minute += 60
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": str(s.props[s.room_id][-1]["id"]), "owner": ""})
	FoodRules.sync(s, data)
	assert_int(int(s.character["fresh"]["raw_meat"][0][0])).is_equal(got)


func test_water_goes_with_its_vessel() -> void:
	var s := _hero()
	s.character["inventory"]["waterskin"] = 2
	s.character["vessels"] = {"waterskin": [{"pints": 4.0, "foul": false}, {"pints": 4.0, "foul": false}]}
	s.character["inventory"]["waterskin"] = 1
	CharacterRules.refresh(s.character, data, s.items)
	assert_array(s.character["vessels"]["waterskin"]).has_size(1)
	s.character["inventory"].erase("waterskin")
	CharacterRules.refresh(s.character, data, s.items)
	s.character["inventory"]["waterskin"] = 1
	assert_float(VesselRules.pints(s.character, data)).is_equal(0.0)


func test_identifying_keeps_the_mark_of_a_theft() -> void:
	var s := _hero()
	var key := ItemRules.UNKNOWN + "dagger"
	s.character["inventory"][key] = 1
	s.character["inventory"].erase("dagger")
	OwnerRules.mark(s, key, 1, "npc_merchant")
	ItemRules.identify(s.character, data, s.items)
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_each_copy_of_a_stack_has_its_own_charges() -> void:
	var s := _hero()
	var c := s.character
	var d: Dictionary = data["items"]["catalog"]["restorative_ointment"]
	c["inventory"]["restorative_ointment"] = 2
	assert_int(ItemRules.charges_left(c, d, "restorative_ointment")).is_equal(10)
	for i in 5:
		ItemRules.spend_charge(c, data, s.items, "restorative_ointment", s.rng)
	assert_int(int(c["inventory"]["restorative_ointment"])).is_equal(1)
	assert_int(ItemRules.charges_left(c, d, "restorative_ointment")).is_equal(5)


func test_one_copy_spends_as_before() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["restorative_ointment"] = 1
	for i in 5:
		ItemRules.spend_charge(c, data, s.items, "restorative_ointment", s.rng)
	assert_bool((c["inventory"] as Dictionary).has("restorative_ointment")).is_false()


func test_a_long_absence_from_a_course_is_many_misses() -> void:
	var s := _hero("brod-school-hall")
	s.character["skills"]["history"] = 30
	StudyRules.state(s.character)["schools"]["brod_school"] = {"since": s.day, "stipend": false}
	StudyRules.enroll(s, data, "letters")
	s.day += 8
	StudyRules.tick(s, data)
	assert_int(int(StudyRules.view(s.character)["courses"]["letters"]["misses"])).is_equal(2)
	s.day += 8
	StudyRules.tick(s, data)
	assert_bool(StudyRules.enrolled(s.character, "letters")).is_false()


func test_the_hooks_of_time_run_alone_after_a_night() -> void:
	var s := _hero("brod-school-hall")
	s.character["skills"]["history"] = 30
	StudyRules.state(s.character)["schools"]["brod_school"] = {"since": s.day, "stipend": false}
	StudyRules.enroll(s, data, "letters")
	s.day += 4
	assert_str(" ".join(TimeRules.hooks(s, data))).contains("Пропуск занятий")
