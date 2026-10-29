extends GdUnitTestSuite
## Pets (v0.7.43): what a pet gives is derived from its SRD template; a wild beast of the pack's room is tamed by
## Animal Handling (a treat — advantage), named and fed by hand; a dog beside the hero helps Perception; a raven
## scouts an exit — the room is known on the map with its danger; a cat keeps food longer; a hungry pet leaves; the
## master's `beast` and `bond` with a pet.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = "brod-gate") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 10 * 60
	return s


func _wild(s: GameSession, monster: String) -> Dictionary:
	return PetRules._wild(s, data, s.room_id, monster, "")


func _pet(s: GameSession, monster: String) -> Dictionary:
	var cr := _wild(s, monster)
	cr.merge({"state": PropertyRules.TAME, "owner": OwnerRules.HERO, "led": true, "pet": true, "close": 1, "fed_day": s.day}, true)
	return cr


func test_what_a_pet_gives_comes_from_its_template() -> void:
	var dog := PetRules.kind(data, "mastiff")
	assert_array(dog["help"] as Array).contains_exactly_in_any_order(["perception", "survival"])
	assert_bool(bool(dog["fights"])).is_true()
	assert_bool(bool(PetRules.kind(data, "raven")["scout"])).is_true()
	assert_bool(bool(PetRules.kind(data, "raven")["fights"])).is_false()
	assert_float(float(PetRules.kind(data, "cat")["spoil_mult"])).is_greater(1.0)
	assert_bool(PetRules.tameable(data, "brown_bear")).is_false()  # large
	assert_bool(PetRules.tameable(data, "goblin")).is_false()  # not a beast


func test_the_pack_puts_a_cat_in_the_tavern_hall_once() -> void:
	var s := _session("brod-tavern-hall")
	PetRules.seed(s, data, s.room_id)
	PetRules.seed(s, data, s.room_id)
	var cats := CreatureRules.here(s, s.room_id).filter(func(c: Dictionary) -> bool: return str(c["monster"]) == "cat")
	assert_int(cats.size()).is_equal(1)
	assert_str(str(cats[0]["state"])).is_equal(PetRules.WILD)
	assert_str(PetRules.tame_why(s, data, str(cats[0]["id"]))).is_empty()


func test_a_tamed_beast_with_a_treat_is_a_pet_named_by_the_player() -> void:
	var s := _session()
	s.character["skills"]["animal_handling"] = 30
	s.character["inventory"]["raw_meat"] = 2
	var dog := _wild(s, "mastiff")
	var cid := str(dog["id"])
	assert_array(PetRules.foods(s, data, "mastiff")).contains(["raw_meat"])
	var r := PetRules.tame(s, data, cid, "raw_meat")
	assert_bool(bool(r["ok"])).override_failure_message(str(r["lines"])).is_true()
	assert_int(int(s.character["inventory"]["raw_meat"])).is_equal(1)
	assert_bool(bool(dog["pet"])).is_true()
	assert_bool(bool(dog["led"])).is_true()
	assert_int(int(dog["close"])).is_equal(2)
	PetRules.rename(s, cid, "Буян")
	assert_str(str(dog["name"])).is_equal("Буян")
	assert_str(PetRules.text(data, dog)).contains("Мастиф")
	assert_str(PetRules.feed_why(s, data, cid, "raw_meat")).is_empty()
	PetRules.feed(s, data, cid, "raw_meat")
	assert_int(int(dog["close"])).is_equal(3)
	assert_str(PetRules.feed_why(s, data, cid, "raw_meat")).is_not_empty()


func test_a_failed_taming_waits_till_tomorrow_or_scares_it_away() -> void:
	var s := _session()
	s.character["skills"]["animal_handling"] = -30
	var cat := _wild(s, "cat")
	var r := PetRules.tame(s, data, str(cat["id"]), "")
	assert_bool(bool(r["ok"])).is_false()
	assert_bool(CreatureRules.find(s, s.room_id, str(cat["id"])).is_empty()).override_failure_message(str(r["lines"])).is_true()  # far below: it runs
	var raven := _wild(s, "raven")
	s.character["skills"]["animal_handling"] = 0
	raven["tame_day"] = s.day
	assert_str(PetRules.tame_why(s, data, str(raven["id"]))).is_equal("PET_TRIED_TODAY")


func test_a_dog_beside_helps_perception_and_not_from_afar() -> void:
	var s := _session()
	var dog := _pet(s, "mastiff")
	assert_str(PetRules.helper(s, data, "perception")).contains(str(dog["name"]))
	assert_str(PetRules.helper(s, data, "survival")).is_not_empty()
	assert_str(PetRules.helper(s, data, "athletics")).is_empty()
	dog["led"] = false
	s.room_id = "brod-square"
	assert_str(PetRules.helper(s, data, "perception")).is_empty()


func test_a_raven_scouts_an_exit_onto_the_map_with_its_danger() -> void:
	var s := _session()
	s.visited = ["brod-gate"]
	var raven := _pet(s, "raven")
	var cid := str(raven["id"])
	assert_array(PetRules.scout_targets(s, data)).contains(["outpost-road"])
	assert_str(PetRules.scout_why(s, data, cid, "outpost-road")).is_empty()
	var lines := PetRules.scout(s, data, cid, "outpost-road")
	assert_str(" ".join(lines)).contains("опасность")
	var known := WorldMap.known(s, data["world"])
	assert_array(known["rooms"] as Array).contains(["outpost-road"])
	assert_array(known["frontier"] as Array).not_contains(["outpost-yard"])  # its own exits stay unknown
	assert_array(PetRules.scout_targets(s, data)).not_contains(["outpost-road"])
	PetRules.scout(s, data, cid, "pushcha-edge")
	assert_str(PetRules.scout_why(s, data, cid, "mine-entrance")).is_equal("PET_SCOUT_TIRED")
	assert_str(PetRules.scout_why(s, data, str(_pet(s, "mastiff")["id"]), "mine-entrance")).is_equal("PET_NO_SCOUT")


func test_a_cat_beside_keeps_meat_longer() -> void:
	var s := _session()
	s.settings["needs"] = true
	s.character["inventory"]["raw_meat"] = 1
	FoodRules.sync(s, data)
	var cat := _pet(s, "cat")
	s.minute += 3 * 1440  # past the 2 days of raw meat, within the cat's 4
	FoodRules.tick(s, data)
	assert_int(int(s.character["inventory"].get("raw_meat", 0))).is_equal(1)
	cat["led"] = false
	PropertyRules._remove_creature(s, str(cat["id"]))
	FoodRules.tick(s, data)
	assert_int(int(s.character["inventory"].get("raw_meat", 0))).is_equal(0)


func test_a_pet_eats_of_the_heros_things_and_leaves_when_hungry() -> void:
	var s := _session()
	s.character["gold_cp"] = 0
	s.character["inventory"].erase("rations")
	s.character["inventory"]["raw_meat"] = 1
	var dog := _pet(s, "mastiff")
	s.day += 1
	PropertyRules.tick(s, data)
	assert_int(int(s.character["inventory"].get("raw_meat", 0))).is_equal(0)
	assert_int(int(dog.get("hungry", 0))).is_equal(0)
	var lines: Array[String] = []
	for i in PetRules.starve_days(data, dog) + 1:
		s.day += 1
		lines.append_array(PropertyRules.tick(s, data))
	assert_str(" ".join(lines)).contains("убежал")
	assert_str(PropertyRules.room_of(s, str(dog["id"]))).is_empty()


func test_a_tamed_wolf_fights_beside_and_a_bought_dog_is_a_pet() -> void:
	var s := _session()
	_pet(s, "wolf")
	assert_array(PropertyRules.fighting(s, data).map(func(f: Dictionary) -> String: return str(f["monster"]))).contains(["wolf"])
	s.character["gold_cp"] = 100000
	PropertyRules.buy_animal(s, data, "npc_drover", "mastiff")
	assert_bool(bool((CreatureRules.here(s, s.room_id).back() as Dictionary).get("pet", false))).is_true()
	PropertyRules.buy_animal(s, data, "npc_drover", "mule")
	assert_bool(bool((CreatureRules.here(s, s.room_id).back() as Dictionary).get("pet", false))).is_false()
	assert_str(CreatureRules.snapshot(s, data, s.room_id)[0]).contains("питомец героя")


func test_the_master_brings_a_stray_and_a_scene_moves_a_pets_closeness() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t1", {"kind": "beast", "monster": "mastiff", "cause": "бездомный пёс прибился к воротам"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t1", [r["effect_id"]])
	var dog: Dictionary = CreatureRules.here(s, s.room_id).back()
	assert_str(str(dog["state"])).is_equal(PetRules.WILD)
	assert_str(CreatureRules.snapshot(s, data, s.room_id).back()).contains("приручить")
	assert_bool(bool(fx.validate(s, data, "t2", {"kind": "beast", "monster": "brown_bear", "cause": "медведь вышел из леса"})["accepted"])).is_false()
	var pet := _pet(s, "cat")
	r = fx.validate(s, data, "t3", {"kind": "bond", "creature_id": str(pet["id"]), "delta": 2, "reason": "кот спал у героя на груди в холодную ночь"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t3", [r["effect_id"]])
	assert_int(int(pet["close"])).is_equal(3)
	assert_bool(bool(fx.validate(s, data, "t4", {"kind": "bond", "creature_id": str(pet["id"]), "delta": 1, "reason": "ещё раз"})["accepted"])).is_false()
