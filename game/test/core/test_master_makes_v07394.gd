extends GdUnitTestSuite
## The master makes (v0.7.39.4, the author's acceptance of «Своя жизнь»): a recipe of any item by 5e, a recipe course
## by an item, the kind's goods under a trader's own and the master's `stock`, a settlement in one create_place with
## its sites, people and guard, the edges of a made place.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _smith() -> GameSession:
	var s := TestUtils.new_session()
	s.character["tools"] = ["smiths_tools"]
	s.room_id = "brod-smithy"
	s.minute = 12 * 60
	return s


func _recipe(out: String, mats: Dictionary, hours := 4) -> Dictionary:
	return {"tool": "smiths_tools", "station": "forge", "hours": hours, "dc_tier": "medium", "materials": mats, "output_id": out, "qty": 1}


func test_a_greataxe_is_paid_by_the_hours_of_work() -> void:
	var s := _smith()
	var made := CraftRules.make(s, data, _recipe("greataxe", {"iron_bar": 4, "timber": 1}))
	assert_bool(made.has("reason")).override_failure_message(str(made)).is_false()
	var mats := 4 * 20 + int(ItemRules.def_of(data["items"], s.items, "timber").get("value_cp", 0))
	assert_int(int(made["def"]["hours"])).is_equal(ceili((3000 - mats) / 62.0))
	assert_array(made["def"]["skills"]).contains(["craft:weaponsmith"])


func test_plate_armour_takes_months_and_a_cheap_thing_keeps_the_masters_hours() -> void:
	var s := _smith()
	var plate := CraftRules.make(s, data, _recipe("plate_armor", {"iron_bar": 4}))
	assert_int(int(plate["def"]["hours"])).is_greater(2000)
	assert_array(plate["def"]["skills"]).contains(["craft:armorsmith"])
	var dagger := CraftRules.make(s, data, _recipe("dagger", {"iron_bar": 1}, 6))
	assert_int(int(dagger["def"]["hours"])).is_equal(6)


func test_a_course_teaches_the_recipe_of_an_item() -> void:
	var s := _smith()
	var spec := {"npc_id": "npc_smith", "name": "Ковка меча", "teach_kind": "recipe", "teach_id": "longsword", "lessons": 4, "fee_cp": 400}
	var co := StudyRules.make(s, data, spec)
	assert_bool(co.has("reason")).override_failure_message(str(co)).is_false()
	assert_str(str(co["plan"]["def"]["teaches"]["id"])).is_equal("longsword")
	spec["teach_id"] = "greataxe"
	spec["name"] = "Ковка секиры"
	assert_str(str(StudyRules.make(s, data, spec).get("reason", ""))).contains("добавь курсу recipe")
	spec["recipe"] = {"tool": "smiths_tools", "station": "forge", "dc_tier": "medium", "materials": {"iron_bar": 4}}
	co = StudyRules.make(s, data, spec)
	assert_bool(co.has("reason")).override_failure_message(str(co)).is_false()
	StudyRules.apply_make(s, data, co["plan"])
	var rid := str(co["plan"]["def"]["teaches"]["id"])
	assert_str(str(CraftRules.recipe(s, data, rid).get("output", ""))).is_equal("greataxe")
	assert_array(CraftRules.learned(s.character)).not_contains([rid])  # learned only by the course


func test_the_herbalist_sells_the_kit_of_her_kind() -> void:
	var s := TestUtils.new_session()
	s.minute = 12 * 60
	assert_int(int(TradeRules.merchant(s, data, "npc_herbalist")["stock"].get("herbalism_kit", 0))).is_greater(0)
	assert_int(int(TradeRules.merchant(s, data, "npc_herbalist")["stock"].get("potion_of_climbing", 0))).is_greater(0)  # her own stay


func test_the_master_puts_a_missing_thing_on_the_shelf() -> void:
	var s := _smith()
	assert_int(int(TradeRules.merchant(s, data, "npc_smith")["stock"].get("greataxe", 0))).is_equal(0)
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "stock", "npc_id": "npc_smith", "item_id": "greataxe", "qty": 1})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_int(int(TradeRules.merchant(s, data, "npc_smith")["stock"].get("greataxe", 0))).is_equal(1)
	var again := fx.validate(s, data, "t-2", {"kind": "stock", "npc_id": "npc_smith", "item_id": "greataxe"})
	assert_bool(bool(again["accepted"])).is_false()
	var far := fx.validate(s, data, "t-3", {"kind": "stock", "npc_id": "npc_herbalist", "item_id": "herbs"})
	assert_bool(bool(far["accepted"])).is_false()


func _village(kind: Variant = "village") -> Dictionary:
	var spec := {"room_id": "brod-gate", "edge": 0, "new_location": true, "name": "Ракитное", "description": "Деревня за полями.",
		"terrain": "grassland", "settlement": kind,
		"rooms": [
			{"key": "street", "name": "Улица Ракитного", "description": "Пыльная улица меж плетней.", "exits": ["inn", "house"],
				"open_edges": [{"text": "дорога дальше на север, к холмам", "terrain": ["hills"]}]},
			{"key": "inn", "name": "Корчма «Ракита»", "indoor": true, "site": "inn", "exits": ["street"]},
			{"key": "house", "name": "Изба старосты Ракитного", "indoor": true, "site": "home", "public": false, "exits": ["street"]}],
		"sites": [{"key": "inn", "name": "Корчма «Ракита»", "tags": ["tavern"], "owner_id": "new:host"},
			{"key": "home", "name": "Двор старосты", "tags": ["home"], "public": false, "owner_id": "new:head"}],
		"npcs": [{"key": "host", "name": "Явдоха Ракитная", "role": "корчмарка", "gender": "female", "room_id": "new:inn", "trader": true, "trade_kind": "food"},
			{"key": "head", "name": "Мирон Рябой", "role": "староста", "gender": "male", "room_id": "new:house"},
			{"key": "guard", "name": "Гаврила Кол", "role": "стражник", "gender": "male", "monster": "guard", "room_id": "street"}]}
	return spec


func test_a_village_in_one_create_place() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-gate"
	var p := WorldGen.plan_place(s, data, _village(), true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()
	var first := WorldGen.apply_place(s, data, p["plan"])
	var world := WorldView.new(data["world"])
	var loc := world.location_id(first)
	assert_bool(bool(world.location(loc).get("settlement", false))).is_true()
	assert_str(str(world.location(loc).get("settlement_kind", ""))).is_equal("village")
	var ids: Dictionary = p["plan"]["npc_ids"]
	assert_array(world.location(loc)["law"]["guards"]).contains([ids["guard"]])
	var inn := str(p["plan"]["ids"]["inn"])
	var inn_site := str(data["world"]["rooms"][inn]["site_id"])
	assert_str(str(data["world"]["sites"][inn_site]["owner"])).is_equal(ids["host"])
	assert_str(inn_site).is_not_equal(str(data["world"]["rooms"][first]["site_id"]))
	assert_bool(world.is_trader(ids["host"])).is_true()
	assert_array(data["world"]["rooms"][inn]["npcs"]).contains([ids["host"]])
	# the made street keeps its own edge, the gate's edge is not used up
	assert_int(WorldGen.open_edges(s, data, first).size()).is_equal(1)
	assert_int(WorldGen.open_edges(s, data, "brod-gate").size()).is_equal(1)


func test_the_world_grows_on_from_a_made_place() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-gate"
	var first := WorldGen.apply_place(s, data, WorldGen.plan_place(s, data, _village(), true)["plan"])
	s.room_id = first
	s.visited.append(first)
	var next := {"room_id": first, "edge": 0, "new_location": true, "name": "Перевал Кривой", "terrain": "hills",
		"rooms": [{"key": "pass", "name": "Кривой перевал", "description": "Седловина меж холмов."}]}
	var p := WorldGen.plan_place(s, data, next, true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()


func test_a_village_without_a_tavern_or_people_is_refused() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-gate"
	var spec := _village()
	spec["sites"][0]["tags"] = ["shop"]
	assert_str(str(WorldGen.plan_place(s, data, spec, true).get("reason", ""))).contains("tavern")
	spec = _village()
	spec["npcs"] = (spec["npcs"] as Array).slice(0, 1)
	spec["sites"][1].erase("owner_id")
	assert_str(str(WorldGen.plan_place(s, data, spec, true).get("reason", ""))).contains("нужны люди")
	spec = _village(null)  # the same place without a kind: free, no guard unless asked
	spec["npcs"] = (spec["npcs"] as Array).slice(0, 1)
	spec["sites"][1].erase("owner_id")
	var p := WorldGen.plan_place(s, data, spec, true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()
	assert_bool(bool(p["plan"]["place"]["law"])).is_false()


func test_a_bad_terrain_of_an_edge_is_refused() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-gate"
	var spec := _village()
	spec["rooms"][0]["open_edges"] = [{"text": "в облака", "terrain": ["sky"]}]
	assert_str(str(WorldGen.plan_place(s, data, spec, true).get("reason", ""))).contains("terrain")
