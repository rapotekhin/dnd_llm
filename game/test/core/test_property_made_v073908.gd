extends GdUnitTestSuite
## Property and the master's edits of the world (v0.7.39.8): a kind of place the master makes with its own upgrades
## (a school, a fishing pier), each upgrade working by the engine; an upgrade asked at the hero's place (a jeweler's
## bench) — priced by the engine, built, a ring made at it; more things in a furnished room with a cause; a thing given
## to a person or taken from a room's chest.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	s.character["gold_cp"] = 500000
	return s


func _days(s: GameSession, n: int) -> Array[String]:
	return TimeRules.advance(s, data, n * 1440)


## The master puts a place of its own kind on sale at the tavern; the hero buys it and stands in it. Its id.
func _made(s: GameSession, kind: Dictionary, price: int = 15000) -> String:
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "property", "site_id": "brod-tavern", "seller_id": "npc_innkeeper",
		"new_kind": kind, "price_cp": price})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var id: String = PropertyRules.of_seller(s, data, "npc_innkeeper")[0]
	PropertyRules.buy(s, data, id)
	PropertyRules.state(s.character)[id]["deed"] = true  # no dispute over the days of building
	s.room_id = PropertyRules.main_room(s, data, id)
	return id


func _up(s: GameSession, id: String, name: String) -> String:
	for up: String in PropertyRules.upgrades_for(s, data, id):
		if str(PropertyRules.ups(data)[up]["name"]) == name:
			return up
	return ""


func _build(s: GameSession, id: String, name: String) -> String:
	var up := _up(s, id, name)
	assert_str(PropertyRules.upgrade_why(s, data, id, up)).override_failure_message(name).is_empty()
	PropertyRules.upgrade(s, data, id, up)
	_days(s, int(PropertyRules.ups(data)[up]["days"]))
	assert_bool(PropertyRules.has_upgrade(s.character, id, up)).override_failure_message(name).is_true()
	return up


const SCHOOL := {"name": "школа", "income_cp_day": 40, "skill": "history", "hours": 6,
	"staff": [{"role": "учитель", "wage_cp_day": 20, "max": 1}],
	"upgrades": [
		{"name": "Второй класс", "text": "Ещё учитель и больше учеников", "gives": {"staff_max": 1, "income_pct": 25}},
		{"name": "Библиотека", "text": "Учиться здесь легче", "gives": {"lesson_bonus": 1}},
		{"name": "Общежитие", "text": "Кровать для своих", "gives": {"rest": true}, "indoor": true}]}

const PIER := {"name": "рыбацкий причал", "income_cp_day": 20, "skill": "survival", "hours": 8,
	"staff": [{"role": "рыбак", "wage_cp_day": 10, "max": 2}],
	"upgrades": [
		{"name": "Лодка", "text": "Улов каждый день", "gives": {"produce": {"fresh_fish": 4}}},
		{"name": "Коптильня", "text": "Коптить рыбу", "gives": {"station_new": {"name": "Коптильня", "tools": ["cooks_utensils"]}}},
		{"name": "Сети", "text": "Улов больше", "gives": {"produce_pct": 50}}]}


func test_a_school_of_the_masters_kind_with_its_upgrades() -> void:
	var s := _session()
	var id := _made(s, SCHOOL)
	assert_str(str(PropertyRules.kind(s, data, id)["name"])).is_equal("школа")
	var mine: Array = PropertyRules.upgrades_for(s, data, id).filter(func(u: String) -> bool: return u.begins_with("gen_u_"))
	assert_int(mine.size()).is_equal(3)
	assert_bool(PropertyRules.upgrades_for(s, data, id).has("bed")).is_true()  # the common ones work everywhere
	var base := PropertyRules.income_day(s, data, id)
	assert_int(base).is_equal(40)
	assert_int(PropertyRules.places(s, data, id)[0]["max"]).is_equal(1)
	var cls := _build(s, id, "Второй класс")
	assert_int(int(PropertyRules.ups(data)[cls]["price_cp"])).is_equal(400 + 600)  # staff 400 + 40 cp × 25% × 60 days
	assert_int(PropertyRules.places(s, data, id)[0]["max"]).is_equal(2)
	assert_int(PropertyRules.income_day(s, data, id)).is_equal(50)
	_build(s, id, "Библиотека")
	assert_int(PropertyRules.bonus(s, data, id, "lesson_bonus")).is_equal(1)
	_build(s, id, "Общежитие")
	assert_str(PropertyRules.bed_at(s, data, s.room_id)).is_equal(id)
	var w := WorldGen.merged(TestUtils.data()["world"], s.generated)  # a loaded game keeps the kind and its upgrades
	assert_bool(w["place_kinds"].has(PropertyRules.kind_id(s, data, id))).is_true()
	assert_bool(w["place_upgrades"].has(cls)).is_true()


func test_a_fishing_pier_brings_its_catch() -> void:
	var s := _session()
	var id := _made(s, PIER)
	var boat := _build(s, id, "Лодка")
	assert_int(int(PropertyRules.ups(data)[boat]["price_cp"])).is_equal(3 * 4 * 60)
	_build(s, id, "Сети")
	var smoke := _build(s, id, "Коптильня")
	var station := str(PropertyRules.ups(data)[smoke]["gives"]["station"])
	assert_str(CraftRules.station_name(data, station)).is_equal("Коптильня")
	assert_bool(CraftRules.station_here(s, data, station)).is_true()
	PropertyRules.state(s.character)[id]["stock"] = {}
	_days(s, 1)
	assert_int(int(PropertyRules.state(s.character)[id]["stock"].get("fresh_fish", 0))).is_equal(0)  # nobody fishes
	PropertyRules.hire_worker(s, data, id)
	_days(s, 1)
	assert_int(int(PropertyRules.state(s.character)[id]["stock"].get("fresh_fish", 0))).is_equal(6)  # 4 × (1 + 50%)
	assert_str(" ".join(PropertyRules.collect(s, data, id))).contains("Свежая рыба")


func test_the_master_kind_is_checked() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var spec := {"kind": "property", "site_id": "brod-tavern", "seller_id": "npc_innkeeper", "price_cp": 15000}
	var bad := [
		{"name": "школа", "income_cp_day": 40, "skill": "history"},  # income without hands
		{"name": "школа", "income_cp_day": 40, "skill": "магия", "staff": [{"role": "учитель", "wage_cp_day": 20}]},
		{"name": "школа", "staff": [{"role": "учитель", "wage_cp_day": 500}]},
		{"name": "таверна"},  # the kind is known
		{"name": "школа", "upgrades": [{"name": "Портал", "gives": {"teleport": true}}]},
		{"name": "причал", "upgrades": [{"name": "Лодка", "gives": {"produce": {"ring_of_warmth": 1}}}]},
		{"name": "причал", "income_cp_day": 200, "skill": "survival", "staff": [{"role": "рыбак", "wage_cp_day": 10}]}]  # > 1% of the price
	for k: Dictionary in bad:
		var e := spec.duplicate()
		e["new_kind"] = k
		var r := engine.validate(s, data, "t-1", e)
		assert_bool(bool(r["accepted"])).override_failure_message(str(k)).is_false()


func test_a_jewelers_bench_asked_at_home_and_a_ring_made() -> void:
	var s := _session()
	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	var c := s.character
	c["tools"] = ["jewelers_tools"]
	c["inventory"]["jewelers_tools"] = 1
	c["inventory"]["silver_bar"] = 2
	var engine := EffectEngine.new()
	var away := engine.validate(s, data, "t-1", {"kind": "upgrade", "name": "Станок ювелира",
		"gives": {"station_new": {"name": "Станок ювелира", "tools": ["jewelers_tools"]}}})
	assert_bool(bool(away["accepted"])).is_false()  # not at the hero's place
	s.room_id = PropertyRules.main_room(s, data, "river_house")
	var r := engine.validate(s, data, "t-1", {"kind": "upgrade", "name": "Станок ювелира", "text": "Кольца и подвески своими руками",
		"gives": {"station_new": {"name": "Станок ювелира", "tools": ["jewelers_tools"]}}, "indoor": true})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	assert_str(str(r["summary"])).contains("15 зм")
	engine.apply(s, "t-1", [r["effect_id"]])
	var up := _build(s, "river_house", "Станок ювелира")
	var station := str(PropertyRules.ups(data)[up]["gives"]["station"])
	assert_bool(CraftRules.station_here(s, data, station)).is_true()
	var other := _session()  # another place does not see it
	assert_bool(PropertyRules.ups(data)[up]["places"].has("river_house")).is_true()
	assert_bool(PropertyRules.upgrades_for(other, data, "old_mill").has(up)).is_false()
	var rec := engine.validate(s, data, "t-2", {"kind": "recipe", "tool": "jewelers_tools", "station": station, "hours": 2, "dc_tier": "easy",
		"materials": [{"item_id": "silver_bar", "qty": 1}], "output_id": "silver_ring"})
	assert_bool(bool(rec["accepted"])).override_failure_message(str(rec.get("reason", ""))).is_true()
	engine.apply(s, "t-2", [rec["effect_id"]])
	var ring: Array = CraftRules.known(s, data).filter(func(id: String) -> bool: return str(CraftRules.recipe(s, data, id).get("output", "")) == "silver_ring")
	assert_array(ring).has_size(1)
	assert_str(CraftRules.why_not(s, data, ring[0])).is_empty()
	CraftRules.start(s, data, ring[0])
	for i in 60:
		if CraftRules.project(s.character).is_empty():
			break
		CraftRules.worked(s, data, CraftRules.shift_minutes(s, data, 8))
	var rings := (c["inventory"] as Dictionary).keys().filter(func(id: String) -> bool:
		return id == "silver_ring" or str(ItemRules.def_of(data["items"], s.items, id).get("base", "")) == "silver_ring")
	assert_array(rings).has_size(1)


func test_more_things_in_a_furnished_room_need_a_cause() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "furnish", "props": [{"name": "Длинный стол"}, {"name": "Бочка эля", "item_id": "barrel", "owner": "npc_innkeeper"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var plain := engine.validate(s, data, "t-2", {"kind": "furnish", "props": [{"name": "Арфа"}]})
	assert_bool(bool(plain["accepted"])).is_false()
	var more := engine.validate(s, data, "t-2", {"kind": "furnish", "cause": "Бруно купил у бродячего музыканта арфу", "props": [{"name": "Арфа", "description": "Старая арфа у камина"}]})
	assert_bool(bool(more["accepted"])).override_failure_message(str(more.get("reason", ""))).is_true()
	engine.apply(s, "t-2", [more["effect_id"]])
	var names: Array = PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return p["name"])
	assert_array(names).contains(["Длинный стол", "Бочка эля", "Арфа"])
	var ids: Array = PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return p["id"])
	assert_array(ids).contains_exactly_in_any_order(["p1", "p2", "p3"])


func test_the_master_gives_and_takes_things_of_the_world() -> void:
	var s := _session()
	var engine := EffectEngine.new()
	var nocause := engine.validate(s, data, "t-1", {"kind": "world_item", "op": "give", "npc_id": "npc_innkeeper", "item_id": "dagger"})
	assert_bool(bool(nocause["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "world_item", "op": "give", "npc_id": "npc_innkeeper", "item_id": "dagger", "cause": "купил у кузнеца нож для кухни"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	assert_bool(TheftRules.pockets(s, data, "npc_innkeeper").any(func(k: Dictionary) -> bool: return str(k["item_id"]) == "dagger")).is_true()
	var take := engine.validate(s, data, "t-2", {"kind": "world_item", "op": "take", "npc_id": "npc_innkeeper", "item_id": "dagger", "cause": "отдал нож поварёнку"})
	engine.apply(s, "t-2", [take["effect_id"]])
	assert_bool(TheftRules.pockets(s, data, "npc_innkeeper").any(func(k: Dictionary) -> bool: return str(k["item_id"]) == "dagger")).is_false()
	s.props[s.room_id] = [{"id": "p1", "name": "Сундук Бруно", "item_id": "", "owner": "npc_innkeeper", "container": "chest", "contents": {"torch": 2}, "state": ""}]
	var put := engine.validate(s, data, "t-3", {"kind": "world_item", "op": "give", "prop_id": "p1", "item_id": "rope", "cause": "Бруно убрал верёвку на место"})
	assert_bool(bool(put["accepted"])).override_failure_message(str(put.get("reason", ""))).is_true()
	engine.apply(s, "t-3", [put["effect_id"]])
	var torches := int(s.character["inventory"].get("torch", 0))
	var out := engine.validate(s, data, "t-4", {"kind": "world_item", "op": "take", "prop_id": "p1", "item_id": "torch", "qty": 2, "cause": "Бруно унёс факелы в погреб"})
	engine.apply(s, "t-4", [out["effect_id"]])
	assert_dict(PropRules.find(s, s.room_id, "p1")["contents"]).is_equal({"rope": 1})
	assert_int(int(s.character["inventory"].get("torch", 0))).is_equal(torches)  # not the hero's
