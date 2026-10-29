extends GdUnitTestSuite
## Property (v0.7.27): places on sale at the town hall, buying and the deed, tax and dispute, a worker's income,
## upgrades and building on land, animals (riding, feeding, produce, a dog in a fight), serfs while the world allows
## slavery, the master's place on sale.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _owner(room: String = "brod-townhall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	return s


func _bought(id: String) -> GameSession:
	var s := _owner()
	PropertyRules.buy(s, data, id)
	s.room_id = PropertyRules.main_room(s, data, id)
	return s


func _days(s: GameSession, n: int) -> Array[String]:
	return TimeRules.advance(s, data, n * 1440)


func test_the_clerk_sells_three_places() -> void:
	var s := _owner()
	assert_array(PropertyRules.of_seller(s, data, "npc_clerk")).contains_exactly_in_any_order(["river_house", "old_mill", "plot"])
	assert_str(PropertyRules.buy_why(s, data, "river_house")).is_empty()
	s.character["gold_cp"] = 10
	assert_str(PropertyRules.buy_why(s, data, "river_house")).is_equal("PROPERTY_NO_MONEY")


func test_bought_the_house_is_the_heros_and_open_to_him() -> void:
	var s := _owner()
	assert_str(SiteRules.unwelcome(s, data, "brod-river-house")).is_empty()  # nobody's empty house
	var lines := PropertyRules.buy(s, data, "river_house")
	assert_str(" ".join(lines)).contains("Куплено: Дом у реки")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 3000)
	assert_str(str(WorldView.new(data["world"]).site("brod-river-house")["owner"])).is_equal(OwnerRules.HERO)
	assert_str(SiteRules.unwelcome(s, data, "brod-river-house")).is_empty()
	assert_array(PropertyRules.of_seller(s, data, "npc_clerk")).not_contains(["river_house"])
	var w := WorldGen.merged(TestUtils.data()["world"], s.generated)  # a loaded game keeps it
	assert_str(str(w["sites"]["brod-river-house"]["owner"])).is_equal(OwnerRules.HERO)


func test_the_deed_at_the_town_hall() -> void:
	var s := _owner()
	PropertyRules.buy(s, data, "river_house")
	assert_str(PropertyRules.deed_why(s, data, "river_house")).is_empty()
	PropertyRules.deed(s, data, "river_house")
	assert_bool(bool(PropertyRules.state(s.character)["river_house"]["deed"])).is_true()
	var deeds := (s.character["inventory"] as Dictionary).keys().filter(func(i: String) -> bool: return str(s.items.get(i, {}).get("name", "")).begins_with("Купчая"))
	assert_array(deeds).has_size(1)
	assert_str(PropertyRules.deed_why(s, data, "river_house")).is_equal("PROPERTY_DEED_DONE")


func test_tax_debt_and_seizure() -> void:
	var s := _owner()
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.deed(s, data, "river_house")
	s.character["gold_cp"] = 0
	_days(s, 7)
	assert_int(int(PropertyRules.state(s.character)["river_house"]["debt"])).is_equal(30)
	var lines := _days(s, 21)
	assert_bool(PropertyRules.owned(s.character, "river_house")).is_false()
	assert_str(" ".join(lines)).contains("за долги")
	assert_str(str(WorldView.new(data["world"]).site("brod-river-house")["owner"])).is_equal("npc_clerk")


func test_without_a_deed_the_place_may_be_disputed() -> void:
	var s := _owner()
	data["rules"]["property"]["dispute"]["chance"] = 1.0
	PropertyRules.buy(s, data, "river_house")
	_days(s, 6)
	assert_bool(PropertyRules.owned(s.character, "river_house")).is_true()
	var lines := _days(s, 1)
	assert_bool(PropertyRules.owned(s.character, "river_house")).is_false()
	assert_str(" ".join(lines)).contains("оспорил")


func test_a_worker_brings_the_mills_income() -> void:
	var s := _bought("old_mill")
	assert_int(PropertyRules.income_day(s, data, "old_mill")).is_equal(20)  # worn: 50 × 40%
	assert_str(PropertyRules.worker_why(s, data, "old_mill")).is_empty()
	PropertyRules.hire_worker(s, data, "old_mill")
	var worker := str(PropertyRules.staff(s, "old_mill")[0]["npc"])
	assert_array(SceneRules.npcs(s, data["world"], s.room_id)).contains([worker])
	_days(s, 1)
	assert_int(int(PropertyRules.state(s.character)["old_mill"]["cash"])).is_equal(20 - 15)
	assert_str(PropertyRules.collect_why(s, data, "old_mill")).is_empty()
	PropertyRules.fire(s, data, "old_mill")
	assert_array(SceneRules.npcs(s, data["world"], s.room_id)).not_contains([worker])


func test_repair_and_own_shift() -> void:
	var s := _bought("old_mill")
	var gold := int(s.character["gold_cp"])
	PropertyRules.repair(s, data, "old_mill", PropertyRules.repair_hours(s, data, "old_mill") * 60)
	assert_float(float(PropertyRules.state(s.character)["old_mill"]["cond"])).is_equal(100.0)
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 720)  # 6000 × 20% × 60%
	assert_int(PropertyRules.income_day(s, data, "old_mill")).is_equal(50)
	s.character["skills"]["athletics"] = 40
	gold = int(s.character["gold_cp"])
	PropertyRules.shift(s, data, "old_mill", 8 * 60)
	assert_int(int(s.character["gold_cp"])).is_greater_equal(gold + 50)
	assert_str(PropertyRules.shift_why(s, data, "old_mill")).is_equal("PROPERTY_SHIFT_DONE")


func test_a_bed_lets_the_hero_rest_at_home() -> void:
	var s := _bought("river_house")
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_equal("REST_NOT_SAFE")
	PropertyRules.upgrade(s, data, "river_house", "bed")
	assert_dict(PropertyRules.pending(s.character, "river_house", "bed")).is_not_empty()
	_days(s, 1)
	assert_bool(PropertyRules.has_upgrade(s.character, "river_house", "bed")).is_true()
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_empty()
	assert_int(int(ExplorationRules.rest_place(data["world"], s.room_id, s, data)["cost_cp"])).is_equal(0)


func test_a_forge_and_a_chest_at_home() -> void:
	var s := _bought("river_house")
	PropertyRules.upgrade(s, data, "river_house", "forge")
	PropertyRules.upgrade(s, data, "river_house", "chest")
	_days(s, 4)
	assert_array(WorldView.new(data["world"]).room(s.room_id).get("tags", [])).contains(["forge"])
	assert_bool((s.props.get(s.room_id, []) as Array).any(func(p: Dictionary) -> bool: return ContainerRules.is_container(p))).is_true()
	assert_str(PropertyRules.upgrade_why(s, data, "river_house", "sign")).is_equal("PROPERTY_NO_UPGRADE")  # a house earns nothing


func test_a_house_built_on_the_plot() -> void:
	var s := _bought("plot")
	assert_array(PropertyRules.upgrades_for(s, data, "plot")).is_empty()
	assert_str(PropertyRules.build_why(s, data, "plot", "house")).is_empty()
	PropertyRules.build(s, data, "plot", "house")
	_days(s, 5)
	var rooms := PropertyRules.rooms(s, data, "plot")
	assert_int(rooms.size()).is_equal(2)
	assert_str(PropertyRules.kind_id(s, data, "plot")).is_equal("house")
	var home := PropertyRules.main_room(s, data, "plot")
	assert_bool(bool(WorldView.new(data["world"]).room(home).get("indoor", false))).is_true()
	assert_array(WorldView.new(data["world"]).exits("brod-plot")).contains([home])
	var w := WorldGen.merged(TestUtils.data()["world"], s.generated)
	assert_array(w["rooms"]["brod-plot"]["exits"]).contains([home])


func test_a_horse_shortens_the_way_and_must_be_fed() -> void:
	var s := _owner("brod-gate")
	assert_str(PropertyRules.animal_why(s, data, "npc_drover", "riding_horse")).is_empty()
	PropertyRules.buy_animal(s, data, "npc_drover", "riding_horse")
	assert_array(PropertyRules.animals(s)).has_size(1)
	assert_float(PropertyRules.travel_mult(s, data, s.room_id)).is_equal(0.5)
	var before := TimeRules.abs_minute(s)
	CreatureRules.follow(s, "brod-gate", "pushcha-edge")
	TimeRules.on_move(s, data, "brod-gate", "pushcha-edge")
	assert_int(TimeRules.abs_minute(s) - before).is_equal(int(data["rules"]["time"]["travel_minutes"]) / 2)
	s.character["gold_cp"] = 0
	var lines := _days(s, 3)
	assert_array(PropertyRules.animals(s)).is_empty()
	assert_str(" ".join(lines)).contains("убежал")


func test_a_goat_gives_milk_at_home() -> void:
	var s := _bought("river_house")
	s.room_id = "brod-gate"
	PropertyRules.buy_animal(s, data, "npc_drover", "goat")
	CreatureRules.follow(s, "brod-gate", "brod-river-house")
	s.room_id = "brod-river-house"
	_days(s, 2)
	assert_int(int(PropertyRules.state(s.character)["river_house"]["stock"].get("goat_milk", 0))).is_equal(2)
	PropertyRules.collect(s, data, "river_house")
	assert_int(int(s.character["inventory"].get("goat_milk", 0))).is_equal(2)


func test_a_dog_fights_beside_the_hero() -> void:
	var s := _owner("brod-gate")
	PropertyRules.buy_animal(s, data, "npc_drover", "mastiff")
	var specs := AllyRules.joining(s, data, [{"monster": "wolf"}])
	assert_bool(specs.any(func(x: Dictionary) -> bool: return str(x.get("monster", "")) == "mastiff" and str(x.get("ally", "")) == "animal")).is_true()


func test_serfs_only_where_slavery_is() -> void:
	var s := _bought("old_mill")
	s.creature_counter += 1
	s.creatures[s.room_id] = [{"id": "c9", "name": "Разбойник", "monster": "bandit", "state": "surrendered", "bound": true, "led": false,
		"owner": OwnerRules.HERO, "since": 0, "hp": 11, "max_hp": 11}]
	assert_str(PropertyRules.serf_why(s, data, "old_mill", "c9")).is_equal("PROPERTY_NO_SLAVERY")
	s.settings["slavery"] = true
	assert_str(PropertyRules.serf_why(s, data, "old_mill", "c9")).is_empty()
	PropertyRules.set_serf(s, data, "old_mill", "c9")
	s.character["gold_cp"] = 0
	data["rules"]["property"]["serfs"]["escape_chance_day"] = 0.0
	_days(s, 1)
	assert_int(int(PropertyRules.state(s.character)["old_mill"]["cash"])).is_equal(20 - 5)


func test_the_master_puts_a_place_on_sale() -> void:
	var s := _owner("brod-square")
	s.room_id = "brod-tavern-hall"
	var engine := EffectEngine.new()
	var dear := engine.validate(s, data, "t-1", {"kind": "property", "site_id": "brod-mill", "seller_id": "npc_innkeeper", "place_kind": "mill",
		"price_cp": 5000, "income_cp_day": 400})
	assert_bool(bool(dear["accepted"])).is_false()
	var theirs := engine.validate(s, data, "t-1", {"kind": "property", "site_id": "brod-smithy", "seller_id": "npc_innkeeper", "place_kind": "workshop", "price_cp": 5000})
	assert_bool(bool(theirs["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "property", "site_id": "brod-tavern", "seller_id": "npc_innkeeper", "place_kind": "tavern",
		"price_cp": 15000, "income_cp_day": 100})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	assert_int(PropertyRules.of_seller(s, data, "npc_innkeeper").size()).is_equal(1)
	assert_str(str(TurnSnapshot.build(s, data, 1000)["character"]["property"])).contains("Таверна «Хромой олень»")


func test_the_master_sees_the_property() -> void:
	var s := _bought("river_house")
	var text := str(TurnSnapshot.build(s, data, 1000)["character"]["property"])
	assert_str(text).contains("Имущество")
	assert_str(text).contains("Дом у реки (дом) — без купчей")
	assert_str(str(TurnSnapshot.build(s, data, 1000)["scene"]["site_owner"])).contains("герой")


func test_things_left_at_home_stay() -> void:
	var s := _bought("river_house")
	var home := s.room_id
	s.props[home] = [{"id": "p1", "name": "Котелок", "dropped": true, "dropped_at": TimeRules.abs_minute(s) - 3 * 1440}]
	assert_array(PropRules.abandon(s, data, home)).is_empty()
	s.props["brod-square"] = [{"id": "p2", "name": "Котелок", "dropped": true, "dropped_at": TimeRules.abs_minute(s) - 3 * 1440}]
	assert_array(PropRules.abandon(s, data, "brod-square")).has_size(1)
