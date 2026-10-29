extends GdUnitTestSuite
## Mounts and vehicles (v0.7.42): a pack by 5e capacity outside the hero's weight; a beast waits where it cannot go and
## comes along again; a cart only on roads and only with a beast that pulls it; a rent ends by itself; the hero's
## beast sold, stolen when left alone; the master's `stock` with `animal` derives a dealer's new beast.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-gate"
	s.minute = 10 * 60
	s.character["gold_cp"] = 100000
	return s


func _buy(s: GameSession, monster: String) -> Dictionary:
	PropertyRules.buy_animal(s, data, "npc_drover", monster)
	return CreatureRules.here(s, s.room_id).back()


func _move(s: GameSession, to: String) -> Array[String]:
	var lines := MountRules.on_move(s, data, s.room_id, to)
	CreatureRules.follow(s, s.room_id, to)
	s.room_id = to
	return lines


func test_the_pack_capacity_is_by_strength_and_size() -> void:
	var s := _session()
	assert_float(MountRules.capacity(data, _buy(s, "mule"))).is_equal(420.0)  # Str 14, burden — a size larger
	assert_float(MountRules.capacity(data, _buy(s, "riding_horse"))).is_equal(480.0)
	assert_float(MountRules.capacity(data, _buy(s, "draft_horse"))).is_equal(540.0)
	assert_float(MountRules.capacity(data, _buy(s, "mastiff"))).is_equal(0.0)


func test_things_in_the_pack_do_not_weigh_on_the_hero() -> void:
	var s := _session()
	var mule := _buy(s, "mule")
	s.character["inventory"]["iron_ore"] = 20
	CharacterRules.refresh(s.character, data, s.items)
	var before := CharacterRules.carried_weight(s.character, data, s.items)
	var id := MountRules.PACK + str(mule["id"])
	var r := ContainerRules.plan_put(s, data, id, "iron_ore", 20)
	assert_dict(r).override_failure_message(str(r)).contains_keys(["plan"])
	ContainerRules.apply_put(s, data, r["plan"])
	assert_int(int(mule["pack"]["iron_ore"])).is_equal(20)
	assert_float(CharacterRules.carried_weight(s.character, data, s.items)).is_less(before)
	assert_str(MountRules.load_text(s, data, mule)).contains("вьюк")
	r = ContainerRules.plan_take(s, data, id, "iron_ore", 1)
	ContainerRules.apply_take(s, data, r["plan"])
	assert_int(int(s.character["inventory"]["iron_ore"])).is_equal(1)


func test_the_pack_has_a_limit() -> void:
	var s := _session()
	var mule := _buy(s, "mule")
	s.character["inventory"]["iron_ore"] = 90  # 90 × 5 lb > 420
	assert_dict(ContainerRules.plan_put(s, data, MountRules.PACK + str(mule["id"]), "iron_ore", 90)).contains_keys(["reason"])


func test_a_horse_waits_at_the_mine_and_comes_along_again() -> void:
	var s := _session()
	var horse := _buy(s, "riding_horse")
	assert_array(_move(s, "mine-entrance")).is_empty()  # the entrance is tagged for mounts
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_equal("mine-entrance")
	var lines := _move(s, "mine-gallery")
	assert_str(" ".join(lines)).contains("ждёт у входа")
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_equal("mine-entrance")
	assert_bool(bool(horse["waiting"])).is_true()
	lines = _move(s, "mine-entrance")
	assert_str(" ".join(lines)).contains("снова с вами")
	assert_bool(bool(horse["led"])).is_true()
	_move(s, "brod-gate")
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_equal("brod-gate")


func test_no_beast_under_a_roof_but_a_dog_goes_anywhere() -> void:
	var s := _session()
	var horse := _buy(s, "riding_horse")
	var dog := _buy(s, "mastiff")
	assert_str(MountRules.blocked(s, data, "brod-tavern-hall", horse)).is_not_empty()
	assert_str(MountRules.blocked(s, data, "brod-tavern-hall", dog)).is_empty()
	assert_str(MountRules.blocked(s, data, "pushcha-glade", horse)).is_empty()


func test_a_cart_needs_a_beast_that_pulls_it() -> void:
	var s := _session()
	assert_str(MountRules.vehicle_why(s, data, "npc_drover", "cart")).is_equal("MOUNT_NO_PULLER")
	_buy(s, "mastiff")
	assert_str(MountRules.vehicle_why(s, data, "npc_drover", "cart")).is_equal("MOUNT_NO_PULLER")
	var mule := _buy(s, "mule")
	assert_str(MountRules.vehicle_why(s, data, "npc_drover", "wagon")).is_equal("MOUNT_NO_PULLER")  # a wagon needs pull 2
	assert_str(MountRules.vehicle_why(s, data, "npc_drover", "cart")).is_empty()
	MountRules.buy_vehicle(s, data, "npc_drover", "cart")
	assert_str(str(mule["cart"]["vehicle"])).is_equal("cart")
	var c := MountRules.container(s, data, MountRules.CART + str(mule["id"]))
	assert_float(float(c["capacity_lb"])).is_equal(800.0)
	assert_str(MountRules.vehicle_why(s, data, "npc_drover", "cart")).is_equal("MOUNT_NO_PULLER")  # one cart a beast


func test_a_cart_goes_only_by_the_roads() -> void:
	var s := _session()
	var mule := _buy(s, "mule")
	MountRules.buy_vehicle(s, data, "npc_drover", "cart")
	assert_str(MountRules.blocked(s, data, "pushcha-edge", mule)).is_empty()  # a road into the forest
	_move(s, "pushcha-edge")
	_move(s, "pushcha-trail")
	var lines := _move(s, "pushcha-glade")
	assert_str(" ".join(lines)).contains("нет дороги")
	assert_str(PropertyRules.room_of(s, str(mule["id"]))).is_equal("pushcha-trail")


func test_a_rent_ends_and_the_beast_goes_home_with_the_load_left() -> void:
	var s := _session()
	assert_str(MountRules.rent_why(s, data, "npc_drover", "riding_horse", 30)).is_equal("MOUNT_RENT_DAYS")
	var gold := int(s.character["gold_cp"])
	MountRules.rent(s, data, "npc_drover", "riding_horse", 2)
	assert_int(gold - int(s.character["gold_cp"])).is_equal(MountRules.rent_price(data, "riding_horse", 2))
	var horse: Dictionary = CreatureRules.here(s, s.room_id).back()
	horse["pack"] = {"rations": 3}
	assert_array(MountRules.sellable(s, data, "npc_drover")).is_empty()  # not one's own
	s.day += 1
	PropertyRules.tick(s, data)
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_equal("brod-gate")
	s.day += 1
	var lines := PropertyRules.tick(s, data)
	assert_str(" ".join(lines)).contains("аренды")
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_empty()
	assert_int(int(s.character["inventory"].get("rations", 0))).is_greater_equal(3)


func test_the_hero_sells_his_own_beast_empty() -> void:
	var s := _session()
	var mule := _buy(s, "mule")
	mule["pack"] = {"rations": 1}
	assert_str(MountRules.sell_why(s, data, "npc_drover", str(mule["id"]))).is_equal("MOUNT_LOADED")
	mule["pack"] = {}
	assert_str(MountRules.sell_why(s, data, "npc_drover", str(mule["id"]))).is_empty()
	var gold := int(s.character["gold_cp"])
	MountRules.sell(s, data, "npc_drover", str(mule["id"]))
	assert_int(int(s.character["gold_cp"]) - gold).is_equal(MountRules.sell_price(data, mule))
	assert_str(PropertyRules.room_of(s, str(mule["id"]))).is_empty()


func test_a_beast_left_alone_is_not_fed_and_may_be_stolen() -> void:
	var s := _session()
	data["rules"]["mounts"]["steal_pct_day"] = 100
	var horse := _buy(s, "riding_horse")
	horse["pack"] = {"rations": 2}
	_move(s, "mine-entrance")
	_move(s, "mine-gallery")
	assert_bool(MountRules.unattended(s, data, horse)).is_true()
	assert_bool(MountRules.fed_by_purse(s, data, horse)).is_false()
	s.day += 1
	var lines := PropertyRules.tick(s, data)
	assert_str(" ".join(lines)).contains("увели")
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_empty()
	var stolen: Array = s.character["stolen_animals"]
	assert_str(str(stolen[0]["room"])).is_equal("mine-entrance")
	assert_str(str(stolen[0]["load"])).is_not_empty()
	assert_str(PropertyRules.text(s, data)).contains("Украдены")


func test_a_led_beast_is_safe_and_fed() -> void:
	var s := _session()
	data["rules"]["mounts"]["steal_pct_day"] = 100
	var horse := _buy(s, "riding_horse")
	var gold := int(s.character["gold_cp"])
	s.day += 1
	PropertyRules.tick(s, data)
	assert_str(PropertyRules.room_of(s, str(horse["id"]))).is_equal("brod-gate")
	assert_int(int(s.character["gold_cp"])).is_less(gold)


func test_the_master_gives_the_dealer_a_camel() -> void:
	var s := _session()
	var r := MountRules.plan_stock(s, data, {"npc_id": "npc_drover", "animal": "camel"})
	assert_dict(r).override_failure_message(str(r)).contains_keys(["plan"])
	MountRules.apply_stock(s, data, r["plan"])
	assert_array(PropertyRules.animals_of(data, "npc_drover")).contains(["camel"])
	var camel := _buy(s, "camel")
	assert_float(MountRules.capacity(data, camel)).is_greater(0.0)
	assert_float(float(PropertyRules.animal_cfg(data, "camel")["travel_mult"])).is_less(1.0)
	assert_dict(MountRules.plan_stock(s, data, {"npc_id": "npc_drover", "animal": "camel"})).contains_keys(["reason"])
	assert_dict(MountRules.plan_stock(s, data, {"npc_id": "npc_drover", "animal": "goblin"})).contains_keys(["reason"])
	# the dealer's new beast survives a reload: the world is merged from the generated buckets
	var w := WorldGen.merged(TestUtils.data()["world"], WorldGen.generated(s))
	assert_array(w["npcs"]["npc_drover"]["animals"] as Array).contains(["camel"])
	assert_dict(w["animal_kinds"] as Dictionary).contains_keys(["camel"])


func test_the_effect_stock_with_an_animal_goes_through_the_engine() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t1", {"kind": "stock", "npc_id": "npc_drover", "animal": "camel", "reason": "караван из степи"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t1", [r["effect_id"]])
	assert_array(PropertyRules.animals_of(data, "npc_drover")).contains(["camel"])
	assert_bool(bool(fx.validate(s, data, "t2", {"kind": "stock", "npc_id": "npc_drover", "animal": "goblin", "reason": "x"})["accepted"])).is_false()
