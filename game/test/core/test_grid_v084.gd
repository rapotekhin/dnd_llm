extends GdUnitTestSuite
## v0.8.4: the fight on the grid: doors, things, fire and the ground, noise, Help and Jump.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	s.minute = 720
	return s


## A fight on an open field with the hero to move.
func _field(s: GameSession, foes: Array = [{"monster": "goblin", "col": 3}], source: Dictionary = {}) -> void:
	TestUtils.fight(s, data, foes, source)
	while not CombatRules.is_player_turn(s) and str(s.combat.get("outcome", "")).is_empty():
		CombatRules.next_actor(s, data)


## A fight on the place's own map; the hero by its first door.
func _at_door(s: GameSession) -> Dictionary:
	CombatRules.start(s, data, [{"monster": "goblin", "beside": true}], {})
	while not CombatRules.is_player_turn(s) and str(s.combat.get("outcome", "")).is_empty():
		CombatRules.next_actor(s, data)
	var d: Dictionary = FightGrid.map(s, data)["doors"][0]
	var door := Vector2i(int(d["x"]), int(d["y"]))
	var g := FightGrid.grid(s, data)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(foe, Vector2i(0, 0))
	for way: Vector2i in WalkRules.DIRS:
		if FightGrid.walkable(g, door + way) and FightGrid.flags_at(g, door + way) & FightGrid.DOOR == 0:
			FightGrid.put(CombatRules.player(s), door + way)
			break
	return d


# --- doors ----------------------------------------------------------------------------------------------------


func test_a_door_is_closed_and_barred_and_stops_the_walker() -> void:
	var s := _session()
	var d := _at_door(s)
	var door := Vector2i(int(d["x"]), int(d["y"]))
	s.combat["doors"][FightGrid.tag(door)] = {"open": true}
	assert_array(FightField.acts(s, data)).contains(["door_close"])
	CombatRules.field_act(s, data, "door_close")
	assert_bool(FightGrid.shut(s, FightGrid.grid(s, data), door)).is_true()
	CombatRules.economy(s)["action"] = 1
	CombatRules.field_act(s, data, "door_bar")
	assert_bool(FightGrid.fast(s, FightGrid.grid(s, data), door)).is_true()
	assert_bool(Move.routes(s, data, CombatRules.player(s)).has(door)).is_false()
	assert_array(FightField.acts(s, data)).contains(["door_force", "door_unbar"])


func test_a_foe_breaks_a_barred_door_and_it_stays_broken() -> void:
	var s := _session()
	var d := _at_door(s)
	var door := Vector2i(int(d["x"]), int(d["y"]))
	s.combat["doors"][FightGrid.tag(door)] = {"barred": true}
	FightGrid.changed(s)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(foe, door + (door - FightGrid.cell(CombatRules.player(s))))
	var lines: Array[String] = []
	for i: int in 200:
		FightField.force_way(s, data, foe, lines)
		if bool(FightGrid.door_state(s, door).get("gone", false)):
			break
	assert_bool(FightGrid.door_state(s, door).get("gone", false)).is_true()
	var m := FightGrid.map(s, data)
	assert_bool(s.ways[WayRules.key(str(m["ids"][int(d["a"])]), str(m["ids"][int(d["b"])]))].get("broken", false)).is_true()


func test_acts_cost_the_action() -> void:
	var s := _session()
	var d := _at_door(s)
	s.combat["doors"][FightGrid.tag(Vector2i(int(d["x"]), int(d["y"])))] = {"open": true}
	CombatRules.economy(s)["action"] = 0
	assert_str(CombatRules.can_field(s, data, "door_close")).is_equal("COMBAT_NO_ACTION")


# --- things ---------------------------------------------------------------------------------------------------


func test_a_block_is_pushed_and_smashed() -> void:
	var s := _session()
	_field(s)
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(1, 0)
	s.combat["blocks"][FightGrid.tag(at)] = FightField._block(data, "barrel", "бочка")
	FightGrid.changed(s)
	assert_bool(FightGrid.walkable(FightGrid.grid(s, data), at)).is_false()
	assert_str(CombatRules.can_field(s, data, "block_push")).is_empty()
	CombatRules.field_act(s, data, "block_push")
	assert_bool(s.combat["blocks"].has(FightGrid.tag(at))).is_false()
	assert_bool(s.combat["blocks"].has(FightGrid.tag(at + Vector2i(1, 0)))).is_true()
	assert_bool(FightGrid.walkable(FightGrid.grid(s, data), at)).is_true()
	s.combat["blocks"].clear()
	s.combat["blocks"][FightGrid.tag(at)] = FightField._block(data, "barrel", "бочка")
	s.combat["blocks"][FightGrid.tag(at)]["hp"] = 1
	FightGrid.changed(s)
	var lines: Array[String] = []
	for i: int in 60:
		FightField._smash_block(s, data, lines)
		if s.combat["blocks"].is_empty():
			break
	assert_bool(s.combat["blocks"].is_empty()).is_true()


func test_a_thing_too_heavy_stays() -> void:
	var s := _session()
	_field(s)
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(1, 0)
	s.combat["blocks"][FightGrid.tag(at)] = FightField._block(data, "boulder", "валун")
	assert_str(CombatRules.can_field(s, data, "block_push")).is_equal("COMBAT_TOO_HEAVY")


func test_a_block_gives_cover() -> void:
	var s := _session()
	_field(s, [{"monster": "goblin", "col": 2}])
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var open := FightGrid.cover(s, data, CombatRules.player(s), foe)
	var at := FightGrid.cell(foe) - Vector2i(1, 0)
	s.combat["blocks"][FightGrid.tag(at)] = FightField._block(data, "barrel", "бочка")
	FightGrid.changed(s)
	assert_int(FightGrid.cover(s, data, CombatRules.player(s), foe)).is_greater(open)


# --- fire and the ground --------------------------------------------------------------------------------------


func test_oil_catches_and_burns_who_stands_there_then_goes_out() -> void:
	var s := _session()
	_field(s)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var at := FightGrid.cell(foe)
	FightField.splash(s, data, at, {"oiled": 5}, "Масло", [] as Array[String])
	assert_bool(s.combat["oil"].has(FightGrid.tag(at))).is_true()
	var lines: Array[String] = []
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	assert_array(lines).contains(["Огонь занимается"])
	assert_array(TestUtils.zones_on(s, foe)).contains(["Огонь"])
	var hp := int(foe["hp"])
	lines.append_array(SpellEffects.zone_tick(s, data, foe, "start"))
	assert_int(int(foe["hp"])).is_less(hp)
	s.combat["round"] = int(s.combat["round"]) + 2
	FightField.fire_round(s, data, lines)
	assert_array(SpellEffects.zones(s)).is_empty()


func test_bare_ground_does_not_catch_and_fire_goes_over_oil() -> void:
	var s := _session()
	_field(s)
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(3, 3)
	var lines: Array[String] = []
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	assert_array(lines).is_empty()
	FightField.splash(s, data, at, {"oiled": 5}, "Масло", lines)
	FightField.splash(s, data, at + Vector2i(1, 0), {"oiled": 5}, "Масло", lines)
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	assert_bool(s.combat["fires"].has(FightGrid.tag(at + Vector2i(1, 0)))).is_false()
	FightField.fire_round(s, data, lines)
	assert_bool(s.combat["fires"].has(FightGrid.tag(at + Vector2i(1, 0)))).is_true()


func test_a_fire_bolt_lights_the_oil_under_a_foe() -> void:
	var s := _session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "wizard_yalika":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	s.character["spells"]["cantrips"].append("fire_bolt")
	_field(s)
	var id: String = CombatRules.enemies(s)[0]
	var foe := CombatRules.fighter(s, id)
	FightField.splash(s, data, FightGrid.cell(foe), {"oiled": 5}, "Масло", [] as Array[String])
	CombatRules.player_cast(s, data, "fire_bolt", 0, id)
	assert_bool(s.combat["fires"].has(FightGrid.tag(FightGrid.cell(foe)))).is_true()


func test_a_flask_goes_on_a_square() -> void:
	var s := _session()
	s.character["inventory"]["oil_flask"] = 1
	_field(s)
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(2, 0)
	var aim := FightGrid.aim_id(at)
	assert_str(CombatRules.can_throw(s, data, "oil_flask", aim)).is_empty()
	CombatRules.throw_item(s, data, "oil_flask", aim)
	assert_bool(s.combat["oil"].has(FightGrid.tag(at))).is_true()
	assert_int(int(s.character["inventory"].get("oil_flask", 0))).is_equal(0)


func test_the_maps_bad_ground_is_a_zone() -> void:
	var s := _session()
	_field(s)
	var z := FightField._ground("hazard", FightGrid.cfg(data)["hazard"], [FightGrid.tag(FightGrid.cell(CombatRules.player(s)))])
	(s.combat["zones"] as Array).append(z)
	var hp := int(s.character["hp"])
	SpellEffects.zone_tick(s, data, CombatRules.player(s), "start")
	assert_int(int(s.character["hp"])).is_less(hp)
	assert_bool(FightField.hurts(s, data, CombatRules.player(s))).is_true()


# --- noise ----------------------------------------------------------------------------------------------------


func test_a_wall_dampens_the_noise() -> void:
	var flags := PackedByteArray()
	flags.resize(40)
	var g := {"w": 40, "h": 1, "flags": flags}
	var c: Dictionary = FightGrid.cfg(data)["noise"]
	var open := FightField._loud(g, c, Vector2i(0, 0), Vector2i(20, 0))
	flags[10] = FightGrid.OPAQUE
	g["flags"] = flags
	assert_int(FightField._loud(g, c, Vector2i(0, 0), Vector2i(20, 0))).is_equal(open - int(c["wall"]))


func test_the_peaceful_hide_from_a_fight_in_their_room() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "goblin", "beside": true}], {})
	var lines: Array[String] = []
	FightField.hear(s, data, lines)
	assert_array(s.combat.get("scared", [])).is_not_empty()
	assert_str(" ".join(lines)).contains("прячется от боя")


func test_an_open_field_hears_nothing() -> void:
	var s := _session()
	_field(s)
	var lines: Array[String] = []
	FightField.hear(s, data, lines)
	assert_array(lines).is_empty()


# --- Help and Jump --------------------------------------------------------------------------------------------


func test_help_gives_the_ally_advantage_once() -> void:
	var s := _session()
	_field(s, [{"monster": "goblin", "col": 0}], {"allies": [{"monster": "guard", "name": "Влада"}]})
	var id: String = CombatRules.enemies(s)[0]
	var foe := CombatRules.fighter(s, id)
	TestUtils.beside(s, foe)
	assert_str(CombatRules.can_help(s, data, id)).is_empty()
	CombatRules.help(s, data, id)
	assert_bool(foe.get("helped", false)).is_true()
	CombatRules._creature_attack(s, data, CombatRules.fighter(s, CombatRules.allies(s)[0]), data["monsters"]["guard"]["actions"][0], foe, [] as Array[String])
	assert_bool(foe.has("helped")).is_false()


func test_no_help_without_an_ally() -> void:
	var s := _session()
	_field(s, [{"monster": "goblin", "col": 0}])
	assert_str(CombatRules.can_help(s, data, CombatRules.enemies(s)[0])).is_equal("COMBAT_NO_ALLY")


func test_a_jump_goes_by_strength_and_a_run_doubles_it() -> void:
	var s := _session()
	_field(s)
	var stand := CombatRules.jump_reach(s, data)
	assert_int(stand).is_equal(mini(CharacterRules.ability(s.character, "str") / 2 / 5, int(CombatRules.economy(s)["move"])))
	CombatRules.economy(s)["walked"] = 2
	assert_int(CombatRules.jump_reach(s, data)).is_greater_equal(stand)


func test_a_jump_clears_a_pit_a_step_would_fall_in() -> void:
	var s := _session()
	_field(s)
	s.character["abilities"]["str"] = 20
	CharacterRules.refresh(s.character, data, s.items)
	CombatRules.economy(s)["walked"] = 2
	var from := FightGrid.cell(CombatRules.player(s))
	var to := from + Vector2i(2, 0)
	assert_str(CombatRules.can_jump(s, data, to)).is_empty()
	var move := int(CombatRules.economy(s)["move"])
	CombatRules.player_jump(s, data, to)
	assert_bool(FightGrid.cell(CombatRules.player(s)) == to).is_true()
	assert_int(int(CombatRules.economy(s)["move"])).is_equal(move - 2)


func test_no_jump_through_a_wall_or_a_foe() -> void:
	var s := _session()
	_field(s, [{"monster": "goblin", "col": 0}])
	s.character["abilities"]["str"] = 20
	CharacterRules.refresh(s.character, data, s.items)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var from := FightGrid.cell(CombatRules.player(s))
	FightGrid.put(foe, from + Vector2i(1, 0))
	FightGrid.changed(s)
	assert_str(CombatRules.can_jump(s, data, from + Vector2i(2, 0))).is_equal("COMBAT_BAD_MOVE")
