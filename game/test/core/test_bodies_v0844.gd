extends GdUnitTestSuite
## A fight gives only XP (v0.8.4.4): the dead lie where they fell, their things are looked through like a chest.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _won(foes: Array, treasure: Dictionary = {}) -> GameSession:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, foes)
	var ids: Array = CombatRules.enemies(s, false)
	for id: String in ids:
		CombatRules.fighter(s, id)["status"] = "dead"
		FightGrid.put(CombatRules.fighter(s, id), Vector2i(3, 4))
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id, treasure)
	return s


func test_a_dead_foe_stays_with_its_things_where_it_fell() -> void:
	var s := _won([{"monster": "bandit", "col": 0}])
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	assert_str(str(c["state"])).is_equal(CreatureRules.DEAD)
	assert_str(str(c["name"])).contains("Тело")
	assert_int(int(c["contents"]["scimitar"])).is_equal(1)
	assert_int(int(c["contents"]["leather_armor"])).is_equal(1)
	assert_int(int(c["x"])).is_equal(3)
	assert_array(Being.check(s)).is_empty()


func test_a_body_is_a_chest_and_its_coins_come_with_the_search() -> void:
	var s := _won([{"monster": "bandit", "col": 0}], {"coins_cp": 150, "items": {"torch": 2}})
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	var id := str(c["id"])
	var gold := int(s.character["gold_cp"])
	assert_str(CreatureRules.can(s, id, "search", data)).is_empty()
	CreatureRules.act(s, data, id, "search")
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 150)
	var box := CreatureRules.BOX + id
	assert_str(str(ContainerRules.target(s, data, box)["name"])).contains("Тело")
	var plan: Dictionary = ContainerRules.plan_take(s, data, box, "torch", 2)["plan"]
	var had := int(s.character["inventory"].get("torch", 0))
	ContainerRules.apply_take(s, data, plan)
	assert_int(int(s.character["inventory"]["torch"])).is_equal(had + 2)
	assert_bool((c["contents"] as Dictionary).has("torch")).is_false()


func test_the_treasure_of_beasts_is_a_heap_on_the_spot() -> void:
	var s := _won([{"monster": "wolf", "col": 0}], {"coins_cp": 30})
	var heap: Array = CreatureRules.here(s, s.room_id).filter(func(c: Dictionary) -> bool: return int(c.get("coins_cp", 0)) == 30)
	assert_int(heap.size()).is_equal(1)
	assert_str(str(heap[0]["monster"])).is_empty()


func test_a_body_does_nothing_but_lie_and_goes_in_time() -> void:
	var s := _won([{"monster": "goblin", "col": 0}])
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	var id := str(c["id"])
	for what: String in ["attack", "bind", "finish", "lead", "join"]:
		assert_str(CreatureRules.can(s, id, what, data)).is_equal("CREATURE_NOTHING")
	assert_str(CreatureRules.can(s, id, "hide", data)).is_empty()
	s.minute += int(data["rules"]["creatures"]["leave_minutes"]["dead"]) + 10
	s.day += 3
	assert_array(CreatureRules.tick(s, data)).is_empty()
	var left: Array = CreatureRules.here(s, s.room_id)  # the body is gone, its things are not
	assert_int(left.size()).is_equal(1)
	assert_str(str(left[0]["name"])).is_equal("Брошенные вещи")
	assert_int(int(left[0]["contents"]["scimitar"])).is_equal(1)
	s.minute += int(data["rules"]["creatures"]["leave_minutes"]["dead"]) * 10
	s.day += 30
	CreatureRules.tick(s, data)
	assert_int(CreatureRules.here(s, s.room_id).size()).is_equal(1)  # a heap stays until taken
	left[0]["contents"] = {}
	CreatureRules.tick(s, data)
	assert_int(CreatureRules.here(s, s.room_id).size()).is_equal(0)


func test_only_a_body_is_hidden() -> void:
	var s := _won([{"monster": "goblin", "col": 0}])
	var id := str(CreatureRules.here(s, s.room_id)[0]["id"])
	CreatureRules.act(s, data, id, "hide")
	var heap: Array = CreatureRules.here(s, s.room_id)
	assert_int(heap.size()).is_equal(1)  # its things stay
	assert_int(int(heap[0]["contents"]["scimitar"])).is_equal(1)
	assert_str(CreatureRules.can(s, str(heap[0]["id"]), "hide", data)).is_equal("CREATURE_NOTHING")
	var live := TestUtils.new_session()
	var c := CreatureRules.add(live, live.room_id, {"name": "Гоблин", "monster": "goblin", "state": "surrendered", "bound": false, "led": false, "since": 0})
	assert_str(CreatureRules.can(live, str(c["id"]), "hide", data)).is_equal("CREATURE_NOTHING")


func test_the_beaten_alive_keep_their_gear_to_be_searched() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "bandit", "col": 0}])
	CombatRules.fighter(s, CombatRules.enemies(s, false)[0])["status"] = "surrendered"
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	assert_bool(CreatureRules.lootable(c)).is_true()
	assert_str(CreatureRules.can(s, str(c["id"]), "search", data)).is_empty()


func test_a_floating_disk_is_a_horse_for_an_hour() -> void:
	var s := TestUtils.new_session()
	var lines := AllyRules.summon(s, data, "floating_disk")
	assert_array(lines).has_size(1)
	var disk: Dictionary = MountRules.beasts(s, s.room_id)[0]
	assert_float(MountRules.capacity(data, disk)).is_equal(500.0)
	assert_str(MountRules.blocked(s, data, "brod-tavern-upstairs", disk)).is_empty()
	assert_bool(ContainerRules.target(s, data, MountRules.PACK + str(disk["id"])).is_empty()).is_false()
	assert_array(Being.check(s)).is_empty()
	AllyRules.summon(s, data, "floating_disk")
	assert_int(MountRules.beasts(s, s.room_id).size()).is_equal(1)  # a new casting replaces the old


func test_the_disk_ends_and_its_load_falls_to_the_hero() -> void:
	var s := TestUtils.new_session()
	AllyRules.summon(s, data, "floating_disk")
	var disk: Dictionary = MountRules.beasts(s, s.room_id)[0]
	disk["pack"] = {"torch": 3}
	var had := int(s.character["inventory"].get("torch", 0))
	var lines := TimeRules.advance(s, data, 61)
	assert_str(" ".join(lines)).contains("исчезает")
	assert_int(MountRules.beasts(s, s.room_id).size()).is_equal(0)
	assert_int(int(s.character["inventory"]["torch"])).is_equal(had + 3)


func test_a_healer_cures_by_its_art() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-herbalist"
	var plan := DiseaseRules.plan_cure(s, data, {"npc_id": "npc_herbalist", "patient_id": "npc_sick_pilgrim"})
	if plan.has("reason"):
		assert_str(str(plan["reason"])).is_equal("")
		return
	assert_array(DiseaseRules.apply_cure(s, data, plan["plan"])).is_not_empty()
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_empty()
	assert_str(str(DiseaseRules.plan_cure(s, data, {"npc_id": "npc_herbalist", "patient_id": "npc_sick_pilgrim"}).get("reason", ""))).contains("не болен")


func test_no_cure_without_an_art_or_past_it() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-herbalist"
	Being.of(s, "npc_sick_pilgrim")["sick"] = {"id": "rot_fever", "until": s.clock + 100000}
	assert_str(str(DiseaseRules.plan_cure(s, data, {"npc_id": "npc_herbalist", "patient_id": "npc_sick_pilgrim"}).get("reason", ""))).contains("магия")
	assert_str(str(DiseaseRules.plan_cure(s, data, {"npc_id": "npc_innkeeper", "patient_id": "npc_sick_pilgrim"}).get("reason", ""))).contains("не в сцене")


func test_a_door_broken_from_inside_is_someone_elses_all_the_same() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-smithy"
	assert_str(WayRules.victim(s, data, "brod-smithy", "brod-square")).is_equal("npc_smith")
	s.room_id = "brod-square"
	assert_str(WayRules.victim(s, data, "brod-square", "brod-smithy")).is_equal("npc_smith")


func test_every_monster_carries_what_it_strikes_with() -> void:
	var catalog: Dictionary = data["items"]["catalog"]
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		for item: Variant in m["equipment"]:
			assert_bool(catalog.has(str(item))).override_failure_message("%s: %s" % [id, item]).is_true()
		for a: Dictionary in m["actions"]:
			if a.has("item"):
				assert_array(m["equipment"]).override_failure_message("%s: %s" % [id, a["item"]]).contains([str(a["item"])])


func test_a_dead_monster_leaves_all_its_gear_and_without_it_has_fists() -> void:
	var ammo: Dictionary = ItemRules.cfg(data)["ammo"]
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		var left := CombatRules.spoils(data, {"monster": id, "status": "dead"})
		for item: Variant in m["equipment"]:
			assert_int(int(left.get(str(item), 0))).override_failure_message("%s: %s" % [id, item]).is_greater(0)
			if ammo.has(str(item)):
				assert_bool(left.has(str(ammo[str(item)]))).override_failure_message("%s: ammo of %s" % [id, item]).is_true()
		var bare := Gear.actions(TestUtils.new_session(), data, id, {"inventory": {}})
		assert_bool(bare.all(func(a: Dictionary) -> bool: return not a.has("item"))).override_failure_message(id).is_true()
		assert_bool(bare.any(func(a: Dictionary) -> bool: return str(a.get("kind", "")) == "melee")).override_failure_message(id).is_true()


func test_the_bandit_leaves_its_crossbow_and_bolts() -> void:
	var c: Dictionary = CreatureRules.here(_won([{"monster": "bandit", "col": 0}]), "brod-tavern-hall")[0]
	assert_int(int(c["contents"]["crossbow_light"])).is_equal(1)
	assert_int(int(c["contents"]["crossbow_bolt"])).is_equal(int(data["rules"]["creatures"]["foe_ammo"]))


func test_a_searched_foe_fights_with_what_is_left() -> void:
	var s := TestUtils.new_session()
	var c := CreatureRules.add(s, s.room_id, {"name": "Разбойник", "monster": "bandit", "state": "surrendered", "bound": false, "led": false,
		"since": 0, "contents": {"leather_armor": 1}, "searched": true})
	CreatureRules.act(s, data, str(c["id"]), "attack")
	TestUtils.fight(s, data, s.pending_fight)
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var names: Array = (f["actions"] as Array).map(func(a: Dictionary) -> String: return str(a["name"]))
	assert_int(names.size()).is_equal(1)
	assert_str(str(f["actions"][0]["damage"][0]["dice"])).is_equal("1")
	f["status"] = "dead"
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	assert_dict(CreatureRules.here(s, s.room_id)[0]["contents"]).is_equal({"leather_armor": 1})  # no blade out of nowhere


func test_a_helpless_foe_finished_off_leaves_a_body() -> void:
	var s := TestUtils.new_session()
	var c := CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "unconscious", "bound": false, "led": false,
		"since": 0, "contents": {"scimitar": 1}})
	CreatureRules.act(s, data, str(c["id"]), "finish")
	assert_str(str(c["state"])).is_equal(CreatureRules.DEAD)
	assert_int(int(c["contents"]["scimitar"])).is_equal(1)


func test_the_dead_of_a_fled_fight_stay_and_the_living_do_not() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "bandit", "count": 2, "col": 0}])
	var ids: Array = CombatRules.enemies(s, false)
	CombatRules.fighter(s, ids[0])["status"] = "dead"
	CreatureRules.after_fight(s, data, s.room_id, {}, true)
	assert_int(CreatureRules.here(s, s.room_id).size()).is_equal(1)
	assert_str(str(CreatureRules.here(s, s.room_id)[0]["state"])).is_equal(CreatureRules.DEAD)


func test_a_dead_person_gets_no_second_blade() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "commoner", "col": 0, "npc_id": TestUtils.INNKEEPER, "name": "Бруно"}])
	CombatRules.fighter(s, CombatRules.enemies(s, false)[0])["status"] = "dead"
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	var clubs: Array = (TheftRules.pockets(s, data, TestUtils.INNKEEPER) as Array).filter(func(e: Dictionary) -> bool: return str(e["item_id"]) == "club")
	assert_int(clubs.size()).is_equal(1)

