extends GdUnitTestSuite
## The things of the checklist on the engine's roads (roadmap v0.8.4.27): heavy armour without its Strength, quivers and
## cases that hold what they are for, a chest and a barrel only on a beast or a cart, caltrops and ball bearings on a
## square, a crowbar and a ram on forcing, the hero's own lock, manacles for anybody, a magnifying glass by the sun.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := ChecklistProbe.session(data)
	s.character["inventory"].clear()
	CharacterRules.refresh(s.character, data, s.items)
	return s


func test_heavy_armour_slows_the_weak_but_not_a_dwarf() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "plate_armor", 1)
	c["equipped"]["armor"] = "plate_armor"
	c["abilities"]["str"] = 15
	CharacterRules.refresh(c, data, s.items)
	var strong := CharacterRules.speed(c, data)
	c["abilities"]["str"] = 10
	CharacterRules.refresh(c, data, s.items)
	assert_int(CharacterRules.speed(c, data)).is_equal(strong - 10)
	c["race"] = "dwarf"
	CharacterRules.refresh(c, data, s.items)
	var weak_dwarf := CharacterRules.speed(c, data)
	c["abilities"]["str"] = 15
	CharacterRules.refresh(c, data, s.items)
	assert_int(weak_dwarf).is_equal(CharacterRules.speed(c, data))


func test_heavy_armour_slows_a_foe_by_the_same_rule() -> void:
	var s := _hero()
	var f := ChecklistProbe.fight(s, data, "goblin")
	var free := Sheet.speed(s, data, f)
	f["inventory"] = {"plate_armor": 1}
	f["equipped"] = {"armor": "plate_armor"}
	assert_int(Sheet.speed(s, data, f)).is_equal(free - 10)


func _bag(s: GameSession, kind: String) -> String:
	Gear.give(s, data, Being.HERO, kind, 1)
	ContainerRules.sync_bags(s.character, data)
	return ContainerRules.bags_of(s.character, kind)[0]


func test_a_quiver_holds_twenty_arrows_and_a_shot_takes_them() -> void:
	var s := _hero()
	var c := s.character
	var q := _bag(s, "quiver")
	Gear.give(s, data, Being.HERO, "arrows", 30)
	Gear.give(s, data, Being.HERO, "rope", 1)
	assert_str(str(ContainerRules.plan_put(s, data, q, "rope", 1).get("reason", ""))).is_not_empty()
	assert_str(str(ContainerRules.plan_put(s, data, q, "arrows", 21).get("reason", ""))).is_not_empty()
	var plan := ContainerRules.plan_put(s, data, q, "arrows", 20)
	ContainerRules.apply_put(s, data, plan["plan"])
	assert_int(Gear.count(s, data, Being.HERO, "arrows")).is_equal(10)
	assert_int(Gear.ammo_left(data, c, "arrows")).is_equal(30)
	assert_float(float(ItemRules.def_of(data["items"], {}, "arrows")["weight"])).is_equal_approx(0.05, 0.001)


func test_a_shot_spends_the_loose_first_then_the_quiver() -> void:
	var s := _hero()
	var c := s.character
	var q := _bag(s, "quiver")
	Gear.give(s, data, Being.HERO, "arrows", 2)
	Thing.add(ContainerRules.bags(c)[q], "arrows", 3)
	var p := ChecklistProbe.fight(s, data, "goblin")
	var hero := CombatRules.player(s)
	for i in 3:
		Gear.spend_ammo(s, data, hero, "arrows")
	assert_int(Gear.count(s, data, Being.HERO, "arrows")).is_equal(0)
	assert_int(Gear.ammo_left(data, c, "arrows")).is_equal(2)
	assert_bool(p.is_empty()).is_false()


func test_a_scroll_case_takes_scrolls_and_sheets_only() -> void:
	var s := _hero()
	var b := ContainerRules.target(s, data, _bag(s, "case_map_or_scroll"))
	assert_int(ContainerRules.room_for(data, s.items, b, "spell_scroll_magic_missile")).is_equal(10)
	assert_int(ContainerRules.room_for(data, s.items, b, "parchment_one_sheet")).is_equal(10)
	assert_int(ContainerRules.room_for(data, s.items, b, "dagger")).is_equal(0)


func test_a_chest_is_never_a_bag_and_goes_full_only_on_a_beast() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "chest", 1)
	ContainerRules.sync_bags(s.character, data)
	assert_bool(ContainerRules.bags(s.character).is_empty()).is_true()
	var p := ContainerRules.lay_down(s, data, s.room_id, "chest", {})
	p["container"] = "chest"
	p["contents"] = {"rope": 1}
	assert_str(str(PropRules.plan_take(s, data, {"prop_id": p["id"]}).get("reason", ""))).contains("вьючный зверь")
	p["contents"] = {}
	assert_bool(PropRules.plan_take(s, data, {"prop_id": p["id"]}).has("plan")).is_true()


func test_caltrops_bite_who_walks_in_until_it_is_healed() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "caltrops", 1)
	ItemRules.belt_put(s.character, data, s.items, "caltrops")
	var t := ChecklistProbe.fight(s, data, "goblin", true)
	var hero := CombatRules.player(s)
	ChecklistProbe.turn(s, data, hero)
	var at := Vector2i(41, 30)
	assert_str(Acts.one("throw").can(s, data, hero, str(t["id"]), {"item": "caltrops"})).is_equal("COMBAT_BAD_TARGET")
	assert_str(Acts.one("throw").can(s, data, hero, FightGrid.aim_id(at), {"item": "caltrops"})).is_empty()
	Acts.one("throw").go(s, data, hero, FightGrid.aim_id(at), {"item": "caltrops"})
	var lines: Array[String] = []
	for i in 20:
		ChecklistProbe.turn(s, data, t)
		t["zoned"] = []
		FightGrid.put(t, at)
		FightField.stepped(s, data, t, lines)
		if int(t["hp"]) < 999:
			break
	assert_int(int(t["hp"])).is_less(999)
	assert_int(ConditionRules.sum(t, "speed")).is_equal(-10)
	assert_int(int(t["points"]["move"])).is_equal(0)
	t["hp"] = 999
	assert_int(ConditionRules.sum(t, "speed")).is_equal(0)


func test_ball_bearings_cover_four_squares_and_lay_prone() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "ball_bearings_bag_of_1000", 1)
	ItemRules.belt_put(s.character, data, s.items, "ball_bearings_bag_of_1000")
	ChecklistProbe.fight(s, data, "goblin", true)
	var hero := CombatRules.player(s)
	ChecklistProbe.turn(s, data, hero)
	Acts.one("throw").go(s, data, hero, FightGrid.aim_id(Vector2i(41, 31)), {"item": "ball_bearings_bag_of_1000"})
	var z: Dictionary = SpellEffects.zones(s).back()
	assert_int((z["cells"] as Array).size()).is_equal(4)
	assert_str(str(z["cond"])).is_equal("prone")


func test_a_crowbar_and_a_ram_help_forcing() -> void:
	var s := _hero()
	var spec := {"what": "проба", "skill": "athletics", "dc": 10, "about": "force"}
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec, true)["adv"]).is_empty()
	Gear.give(s, data, Being.HERO, "crowbar", 1)
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec, true)["adv"]).is_not_empty()
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec.merged({"about": "stonework"}, true), true)["adv"]).is_empty()
	var r := _hero()
	Gear.give(r, data, Being.HERO, "ram_portable", 1)
	var parts: Array = CheckEngine.situation(r, data, Sheet.HERO, spec, true)["parts"]
	assert_bool(parts.any(func(p: Dictionary) -> bool: return int(p.get("value", 0)) == 4)).is_true()


func test_the_heros_own_lock_on_a_chest() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "lock", 1)
	var p := ContainerRules.lay_down(s, data, s.room_id, "chest", {})
	p["container"] = "chest"
	p["contents"] = {}
	assert_array(ContainerRules.lock_ways(s, data, p)).is_equal(["hang"])
	ContainerRules.lock_up(s, data, p, "hang")
	assert_bool(bool(p["locked"])).is_true()
	assert_int(int(p["lock_dc"])).is_equal(15)
	assert_str(str(p["owner"])).is_equal(OwnerRules.HERO)
	assert_int(Gear.count(s, data, Being.HERO, str(p["key"]))).is_equal(1)
	assert_array(ContainerRules.ways(s, data, p)).contains(["key"])
	ContainerRules.unlock(p, "key")
	assert_array(ContainerRules.lock_ways(s, data, p)).is_equal(["relock"])


func _door() -> Array[String]:
	for a: String in data["world"]["rooms"]:
		for b: String in data["world"]["rooms"][a].get("ways", {}):
			if not WayRules.def(data, a, b).is_empty() and not bool(WayRules.def(data, a, b).get("solid", false)):
				return [a, b]
	return []


func test_the_heros_own_lock_on_a_door_into_its_place() -> void:
	var s := _hero()
	var d := _door()
	assert_array(d).is_not_empty()
	Gear.give(s, data, Being.HERO, "lock", 1)
	assert_str(WayRules.lock_why(s, data, d[0], d[1])).is_equal("DOOR_NOT_YOURS")
	data["world"]["rooms"][d[1]]["owner"] = OwnerRules.HERO
	assert_str(WayRules.lock_why(s, data, d[0], d[1])).is_empty()
	WayRules.lock_with(s, data, d[0], d[1])
	assert_str(WayRules.blocked(s, data, d[0], d[1])).is_equal("DOOR_LOCKED")
	assert_int(int(WayRules.dcs(s, data, d[0], d[1])["pick"])).is_greater_equal(15)
	assert_bool(WayRules.ways(s, data, d[0], d[1]).has({"how": "key"})).is_true()


func test_manacles_bind_the_hero_and_the_prisoner_alike() -> void:
	assert_str(EncounterRules.bonds_for(data, [{"inventory": {"manacles": 1}}], "medium")).is_equal("manacles")
	assert_str(EncounterRules.bonds_for(data, [{"inventory": {"manacles": 1}}], "large")).is_equal("tied")
	assert_str(EncounterRules.bonds_for(data, [{"inventory": {}}], "medium")).is_equal("tied")
	assert_int(EncounterRules.escape_dc(data, "manacles", "escape_sleight")).is_equal(20)
	assert_int(EncounterRules.escape_dc(data, "", "escape_sleight")).is_equal(15)
	var s := _hero()
	Gear.give(s, data, Being.HERO, "manacles", 1)
	var cr := CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "surrendered", "bound": false, "led": false,
		"since": TimeRules.abs_minute(s)})
	CreatureRules.act(s, data, str(cr["id"]), "bind")
	assert_str(str(CreatureRules.find(s, s.room_id, str(cr["id"]))["bonds"])).is_equal("manacles")
	assert_int(Gear.count(s, data, Being.HERO, "manacles")).is_equal(0)
	CreatureRules.act(s, data, str(cr["id"]), "free")
	assert_int(Gear.count(s, data, Being.HERO, "manacles")).is_equal(1)


func test_a_prisoner_left_alone_tries_its_bonds() -> void:
	var s := _hero()
	var room := s.room_id
	var cr := CreatureRules.add(s, room, {"name": "Гоблин", "monster": "goblin", "state": "surrendered", "bound": false, "led": false,
		"since": TimeRules.abs_minute(s)})
	CreatureRules.act(s, data, str(cr["id"]), "bind")
	var left := false
	for i in 40:
		s.room_id = "_away"
		TimeRules.advance(s, data, 241)
		if CreatureRules.find(s, room, str(cr["id"])).is_empty():
			left = true
			break
	assert_bool(left).is_true()


func test_a_magnifying_glass_lights_a_fire_by_day_only() -> void:
	var s := _hero()
	assert_bool(WeatherRules.camp_fire(s, data)).is_false()
	Gear.give(s, data, Being.HERO, "magnifying_glass", 1)
	assert_bool(WeatherRules.camp_fire(s, data)).is_equal(not TimeRules.is_night(s, data))
	var spec := {"what": "проба", "skill": "investigation", "dc": 10, "about": "small_object"}
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec, true)["adv"]).is_not_empty()
