extends GdUnitTestSuite
## v0.7.65: a thing. A copy carries what sets it apart wherever it goes; every thing has a body with HP and statuses, one
## rule with doors; the master builds a property of parts and the artificer lays it on a thing.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _hero(level: int = 5) -> GameSession:
	var s := TestUtils.new_session()
	MakeRules.install(data, s.generated)
	s.settings["needs"] = true
	s.character["level"] = level
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _chest(s: GameSession, extra: Dictionary = {}) -> Dictionary:
	var p := {"id": "p1", "name": "Сундук", "description": "", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest", "contents": {}, "body": "chest"}
	p.merge(extra, true)
	s.props[s.room_id] = [p]
	return p


func _wand(s: GameSession) -> String:
	s.items["gen_wand"] = {"name": "Палочка искр", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100, "properties": [], "generated": true,
		"charges": {"max": 3, "regain": "1d2"}, "use": {"spell": "fire_bolt", "level": 0}}
	s.character["inventory"]["gen_wand"] = 2
	return "gen_wand"


# --- copies ----------------------------------------------------------------------------------------------------------


func test_two_wands_of_a_stack_keep_their_own_charges() -> void:
	var s := _hero()
	var id := _wand(s)
	var d := ItemRules.def_of(data["items"], s.items, id)
	for i in 3:
		ItemRules.spend_charge(s.character, data, s.items, id, s.rng)
	assert_int(ItemRules.charges_left(s.character, d, id)).is_equal(3)
	ItemRules.spend_charge(s.character, data, s.items, id, s.rng)
	assert_array(Thing.states(s.character, id).map(func(x: Dictionary) -> int: return int(x["used"]))).is_equal([3, 1])


func test_a_spent_wand_stays_spent_in_a_chest() -> void:
	var s := _hero()
	var id := _wand(s)
	s.character["inventory"][id] = 1
	ItemRules.spend_charge(s.character, data, s.items, id, s.rng)
	_chest(s)
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": id, "qty": 1})
	assert_int(Thing.count(s.character, id)).is_equal(0)
	assert_int(int(Thing.states(s.props[s.room_id][0], id)[0]["used"])).is_equal(1)
	ContainerRules.apply_take(s, data, {"room": s.room_id, "from": "p1", "item_id": id, "qty": 1, "owner": ""})
	assert_int(ItemRules.charges_left(s.character, ItemRules.def_of(data["items"], s.items, id), id)).is_equal(2)


func test_water_goes_with_its_vessel() -> void:
	var s := _hero()
	s.character["inventory"]["waterskin"] = 1
	s.character["poured"] = true
	Thing.nth(s.character, "waterskin", 0)["pints"] = 3.0
	_chest(s)
	ContainerRules.apply_put(s, data, {"room": s.room_id, "into": "p1", "item_id": "waterskin", "qty": 1})
	ContainerRules.apply_take(s, data, {"room": s.room_id, "from": "p1", "item_id": "waterskin", "qty": 1, "owner": ""})
	assert_str(LiquidRules.summary(s.character, data, "waterskin")).is_equal("вода 3/4")


func test_a_new_heros_vessels_are_full_and_a_dropped_one_keeps_its_water() -> void:
	var s := _hero()
	s.character["inventory"]["waterskin"] = 1
	assert_float(LiquidRules.pints(s.character, data)).is_equal_approx(4.0, 0.01)
	ContainerRules.apply_drop(s, data, {"room": s.room_id, "item_id": "waterskin", "qty": 1})
	var p: Dictionary = s.props[s.room_id][-1]
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": str(p["id"]), "owner": ""})
	assert_float(LiquidRules.pints(s.character, data)).is_equal_approx(4.0, 0.01)


func test_food_ages_in_a_bag_as_in_the_pack() -> void:
	var s := _hero()
	s.character["inventory"]["backpack"] = 1
	ContainerRules.sync_bags(s.character, data)
	var bag: Dictionary = ContainerRules.bags(s.character).values()[0]
	Thing.add(bag, "raw_meat", 1)
	FoodRules.sync(s, data)
	TimeRules.advance(s, data, 8 * 1440)
	FoodRules.tick(s, data)
	assert_int(Thing.count(bag, "raw_meat")).is_equal(0)


func test_a_move_leaves_the_plain_copies_first() -> void:
	var h := {"contents": {"dagger": 3}}
	Thing.stamp(h, "dagger", 1, "owner", "npc_x")
	var to := {"contents": {}}
	Thing.move(h, to, "dagger", 2)
	assert_int(Thing.states(h, "dagger").size()).is_equal(1)
	Thing.move(h, to, "dagger", 1)
	assert_str(str(Thing.states(to, "dagger")[0]["owner"])).is_equal("npc_x")
	assert_bool(h.has("copies")).is_false()


func test_what_was_spent_takes_its_state() -> void:
	var c := {"inventory": {"bread": 2}}
	Thing.stamp(c, "bread", 2, "got", 5)
	c["inventory"]["bread"] = 1
	Thing.trim(c)
	assert_int(Thing.states(c, "bread").size()).is_equal(1)


# --- the body --------------------------------------------------------------------------------------------------------


func test_hp_come_from_size_and_frailty_and_ac_from_the_material() -> void:
	assert_int(ThingRules.max_hp(data, {"weight": 25, "made_of": "wood"})).is_equal(10)  # a chest
	assert_int(ThingRules.max_hp(data, {"weight": 1, "made_of": "glass"})).is_equal(2)  # a bottle
	assert_int(ThingRules.ac(data, {"made_of": "stone"})).is_equal(17)
	assert_int(ThingRules.ac(data, {"item_type": "weapon"})).is_equal(19)


func test_poison_does_nothing_to_a_thing_and_only_damage_is_kept() -> void:
	var st := {}
	var d := {"weight": 25, "made_of": "wood"}
	assert_int(int(ThingRules.hurt(data, st, d, 5, "poison")["took"])).is_equal(0)
	assert_bool(bool(ThingRules.hurt(data, st, d, 4, "fire")["broke"])).is_false()
	assert_int(int(st["dmg"])).is_equal(4)
	assert_int(ThingRules.hp(data, st, d)).is_equal(6)
	assert_bool(bool(ThingRules.hurt(data, st, d, 6, "fire")["broke"])).is_true()


func test_a_threshold_stops_a_small_blow() -> void:
	assert_int(int(ThingRules.hurt(data, {}, {"made_of": "stone"}, 4)["took"])).is_equal(0)


func test_a_broken_chest_lets_its_things_fall_and_they_stay_as_they_were() -> void:
	var s := _hero()
	var p := _chest(s, {"owner": ""})
	Thing.add(p, "dagger", 2)
	Thing.stamp(p, "dagger", 1, "owner", "npc_merchant")
	var plan := PropRules.plan_state(s, data, {"prop_id": "p1", "damage": 40, "damage_type": "bludgeoning", "cause": "разбил топором"})
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	var lines := PropRules.apply_state(s, data, plan["plan"])
	assert_str(" ".join(lines)).contains("выпадает")
	assert_str(str(p["state"])).is_equal("broken")
	var fell: Array = (s.props[s.room_id] as Array).filter(func(x: Dictionary) -> bool: return bool(x.get("dropped", false)))
	assert_int(fell.size()).is_equal(2)
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": str(fell[0]["id"]), "owner": ""})
	PropRules.apply_take(s, data, {"room": s.room_id, "prop": str(fell[1]["id"]), "owner": ""})
	assert_int(OwnerRules.held_of(s, "dagger", "npc_merchant")).is_equal(1)


func test_a_quest_thing_is_not_destroyed() -> void:
	var s := _hero()
	_chest(s, {"quest": true})
	assert_bool(PropRules.plan_state(s, data, {"prop_id": "p1", "damage": 10, "cause": "разбил топором"}).has("reason")).is_true()
	assert_bool(PropRules.plan_state(s, data, {"prop_id": "p1", "state": "broken"}).has("reason")).is_true()


func test_fire_takes_what_burns_and_spreads_and_ends_in_ash() -> void:
	var s := _hero()
	s.room_id = "brod-tavern-hall"
	var chest := _chest(s)
	var table := {"id": "p2", "name": "Стол", "description": "", "item_id": "", "owner": "", "text": "", "state": "", "body": "table"}
	var pillar := {"id": "p3", "name": "Колонна", "description": "", "item_id": "", "owner": "", "text": "", "state": "", "body": "pillar"}
	(s.props[s.room_id] as Array).append_array([table, pillar])
	Thing.add(chest, "dagger", 1)
	assert_str(ThingRules.ignite(s, data, chest, ThingRules.spec(data, s, chest), "факел")).is_empty()
	assert_str(ThingRules.ignite(s, data, pillar, ThingRules.spec(data, s, pillar), "факел")).contains("не горит")
	TimeRules.advance(s, data, int(ThingRules.cfg(data)["spread_minutes"]))
	assert_bool(ThingRules.has(s, table, "burning")).is_true()
	assert_bool(ThingRules.has(s, pillar, "burning")).is_false()
	TimeRules.advance(s, data, int(ThingRules.cfg(data)["burn_minutes"]))
	assert_str(str(chest["state"])).is_equal("burned")
	assert_int((s.props[s.room_id] as Array).filter(func(x: Dictionary) -> bool: return bool(x.get("dropped", false))).size()).is_equal(1)


func test_water_puts_a_fire_out_and_wet_will_not_burn() -> void:
	var s := _hero()
	var p := _chest(s)
	var d := ThingRules.spec(data, s, p)
	ThingRules.ignite(s, data, p, d, "факел")
	ThingRules.douse(s, data, p)
	assert_bool(ThingRules.has(s, p, "burning")).is_false()
	assert_str(ThingRules.ignite(s, data, p, d, "факел")).contains("мокрое")


func test_oil_makes_iron_burn() -> void:
	var s := _hero()
	var st := {}
	var d := {"made_of": "iron"}
	assert_bool(ThingRules.burns(s, data, st, d)).is_false()
	ThingRules.lay(s, st, "oiled", 60, "масло")
	assert_bool(ThingRules.burns(s, data, st, d)).is_true()


func test_the_master_lays_only_a_status_of_things_and_the_hero_cannot_burn_by_it() -> void:
	var s := _hero()
	_chest(s)
	assert_bool(PropRules.plan_state(s, data, {"prop_id": "p1", "status": "poisoned", "cause": "облил ядом"}).has("reason")).is_true()
	var plan := PropRules.plan_state(s, data, {"prop_id": "p1", "status": "glowing", "cause": "чары света"})
	PropRules.apply_state(s, data, plan["plan"])
	assert_str(str(PropRules.snapshot(s, data, s.room_id)[0]["state"])).is_equal("светится")
	var engine := EffectEngine.new()
	assert_bool(engine._plan(s, data, "t", {"kind": "condition", "condition": "burning", "cause": "player"}, [] as Array[Dictionary]).has("reason")).is_true()


func test_a_thing_harmed_before_its_owner_is_a_crime_seen() -> void:
	var s := _hero()
	s.room_id = "brod-tavern-hall"
	_chest(s, {"owner": "npc_innkeeper"})
	var plan := PropRules.plan_state(s, data, {"prop_id": "p1", "damage": 2, "cause": "пнул сундук"})
	var lines := PropRules.apply_state(s, data, plan["plan"])
	assert_bool(lines.is_empty()).is_false()


func test_a_body_says_what_it_does_on_the_map() -> void:
	var s := _hero()
	s.room_id = "brod-tavern-cellar"
	var plan := PropRules.plan_furnish(s, data, {"props": [{"name": "Длинный стол", "body": "table"}, {"name": "Занавесь", "body": "curtain"}]})
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	var table: Dictionary = plan["plan"]["props"][0]
	assert_str(str(ThingRules.body(data, table)["cover"])).is_equal("half")
	assert_array(ThingRules.body(data, plan["plan"]["props"][1])["blocks"]).is_equal(["sight"])
	assert_bool(PropRules.plan_furnish(s, data, {"props": [{"name": "Куб", "body": "cube"}]}).has("reason")).is_true()


func test_a_door_keeps_only_its_damage() -> void:
	var s := _hero()
	s.room_id = "brod-tavern-kitchen"
	var to := "brod-tavern-cellar"
	WayRules.hurt(s, data, s.room_id, to, 5)
	assert_int(int(s.ways[WayRules.key(s.room_id, to)]["dmg"])).is_equal(5)
	assert_bool(s.ways[WayRules.key(s.room_id, to)].has("hp")).is_false()


# --- a property of parts ---------------------------------------------------------------------------------------------


func _property(s: GameSession, parts: Array, extra: Dictionary = {}) -> Dictionary:
	var e := {"kind": "make", "what": "property", "key": "frost", "name": "Поцелуй инея", "text": "Лезвие покрыто инеем и морозит рану.", "parts": parts}
	e.merge(extra, true)
	var engine := EffectEngine.new()
	return engine._plan(s, data, "t", e, [] as Array[Dictionary])


func _smith(level: int = 5) -> GameSession:
	var s := _hero(level)
	s.settings["needs"] = false
	var c := s.character
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["inventory"]["dagger"] = 1
	c["inventory"]["arcane_dust"] = 20
	c["abilities"]["str"] = 20
	c["abilities"]["dex"] = 20
	c["abilities"]["int"] = 20
	CharacterRules.refresh(c, data, s.items)
	c["gold_cp"] = 5000
	s.room_id = "brod-smithy"
	return s


func test_a_property_is_priced_by_what_it_adds() -> void:
	var s := _hero()
	var plan := _property(s, [{"part": "plus", "amount": 1}, {"part": "element", "value": "cold"}])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	assert_int(int(plan["plan"]["def"]["points"])).is_equal(4)
	assert_array(plan["plan"]["def"]["tokens"]).is_equal(["magic_plus1", "cold_damage"])


func test_a_property_cannot_be_priced_down_or_made_of_what_is_not() -> void:
	var s := _hero(1)
	assert_str(str(_property(s, [{"part": "plus", "amount": 3}, {"part": "element", "value": "cold"}]).get("reason", ""))).contains("уровня")
	assert_bool(_property(s, [{"part": "wish", "amount": 1}]).has("reason")).is_true()
	assert_bool(_property(s, [{"part": "plus", "amount": 9}]).has("reason")).is_true()
	assert_bool(_property(s, [{"part": "plus", "amount": 1}, {"part": "armor", "amount": 1}]).has("reason")).is_true()


func test_the_artificer_lays_a_built_property_on_a_thing_and_it_works_in_a_fight_and_on_the_sheet() -> void:
	var s := _smith()
	var plan := _property(s, [{"part": "plus", "amount": 1}, {"part": "element", "value": "cold"}], {"book": "Трактат об инее"})
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	MakeRules.apply(s, data, plan["plan"])
	var prop := str(plan["plan"]["id"])
	var book := str(plan["plan"]["book"]["id"])
	var id := "tpl:imbue:dagger:%s" % prop
	assert_bool(CraftRules.known(s, data).has(id)).is_false()  # nothing yet without the book
	s.character["inventory"][book] = 1
	assert_bool(CraftRules.known(s, data).has(id)).is_true()
	var r := CraftRules.recipe(s, data, id)
	assert_str(str(r["output_def"]["rarity"])).is_equal("rare")
	assert_str(CraftRules.why_not(s, data, id)).is_empty()
	CraftRules.start(s, data, id)
	var shift := 0
	while not CraftRules.project(s.character).is_empty() and shift < 30:
		CraftRules.worked(s, data, CraftRules.shift_minutes(s, data, 8))
		shift += 1
	var made := ""
	for it: String in s.character["inventory"]:  # a fine make is a thing of its own, on the imbued one
		if str(ItemRules.def_of(data["items"], s.items, it).get("name", "")).contains("Поцелуй инея"):
			made = it
	assert_str(made).is_not_empty()
	assert_int(Thing.count(s.character, "dagger")).is_equal(0)
	var d := ItemRules.def_of(data["items"], s.items, made)
	assert_bool((d["properties"] as Array).has("cold_damage")).is_true()
	assert_str(ItemInfo.properties_line(d)).contains("Поцелуй инея")
	s.character["equipped"]["main_hand"] = made
	var w := CombatRules.weapon_profile(s.character, data, s.items, made)
	var plain := CombatRules.weapon_profile(s.character, data, s.items, "dagger")
	assert_int(int(w["to_hit"])).is_greater_equal(int(plain["to_hit"]) + 1)  # +1 of the property, and +1 more if the make came out fine


func test_a_built_property_on_armor_counts_in_the_ac() -> void:
	var s := _smith()
	var plan := _property(s, [{"part": "armor", "amount": 1}])
	MakeRules.apply(s, data, plan["plan"])
	var prop := str(plan["plan"]["id"])
	s.items["gen_coat"] = {"name": "Заиндевелая кольчуга", "base": "chain_mail", "item_type": "armor", "properties": [prop], "generated": true}
	s.character["abilities"]["str"] = 18
	s.character["inventory"]["chain_mail"] = 1
	s.character["inventory"]["gen_coat"] = 1
	s.character["equipped"]["armor"] = "chain_mail"
	CharacterRules.refresh(s.character, data, s.items)
	var plain := int(s.character["ac"])
	s.character["equipped"]["armor"] = "gen_coat"
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(int(s.character["ac"])).is_equal(plain + 1)


func test_a_built_property_goes_only_on_its_kind_of_thing() -> void:
	var s := _smith()
	var plan := _property(s, [{"part": "armor", "amount": 1}])
	MakeRules.apply(s, data, plan["plan"])
	assert_bool(CraftRules.template_recipe(s, data, "imbue", "dagger", str(plan["plan"]["id"])).is_empty()).is_true()


func test_a_course_teaches_a_built_property() -> void:
	var s := _smith()
	var plan := _property(s, [{"part": "element", "value": "cold"}])
	MakeRules.apply(s, data, plan["plan"])
	var engine := EffectEngine.new()
	var pending: Array[Dictionary] = [{"kind": "make", "plan": plan["plan"]}]
	var e := {"kind": "create", "what": "course", "npc_id": "npc_smith", "name": "Морозная ковка", "teach_kind": "recipe", "teach_id": "new:frost", "lessons": 4, "fee_cp": 400}
	var course := engine._plan(s, data, "t", e, pending)
	assert_bool(course.has("plan")).override_failure_message(str(course)).is_true()
	StudyRules.apply_make(s, data, course["plan"])
	StudyRules.grant(s, data, str(course["plan"]["id"]))
	assert_bool(CraftRules.known(s, data).has("tpl:imbue:dagger:%s" % plan["plan"]["id"])).is_true()


func test_the_masters_own_item_carries_a_built_property() -> void:
	var s := _hero()
	var plan := _property(s, [{"part": "element", "value": "cold"}])
	MakeRules.apply(s, data, plan["plan"])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": plan["plan"]}]
	var item := MakeRules.resolved_item({"name": "Ледяной стилет", "base": "dagger", "item_type": "weapon", "properties": ["new:frost"], "description": "х"}, pending)
	var chk := ItemRules.check_generated(data["items"], item, 5, data["spells"])
	assert_bool(bool(chk["ok"])).override_failure_message(str(chk)).is_true()
	assert_str(str(chk["def"]["rarity"])).is_equal("uncommon")


func test_what_another_game_built_leaves_the_rules() -> void:
	var s := _hero()
	var plan := _property(s, [{"part": "element", "value": "cold"}])
	var id := str(plan["plan"]["id"])
	assert_bool(data["items"]["properties"].has(id)).is_true()
	MakeRules.install(data, {})
	assert_bool(data["items"]["properties"].has(id)).is_false()
	assert_bool(data["items"]["built"].has(id)).is_false()
