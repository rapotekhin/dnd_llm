extends GdUnitTestSuite
## The author's notes of 2026-11-13 on v0.8.4.43.48 (roadmap «Находки автора 2026-11-13»): the fight's bugs.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


## The author's game: the master's «Каменный стол» with a boulder's body stood on the lair, the four cultists on its squares
## — nobody could reach them and the Stinking Cloud, which does not fill a solid thing, did not touch them. The heads of an
## encounter stand only on free floor: not in a thing, not on a person.
func test_the_heads_of_a_lair_stand_beside_a_thing_not_in_it() -> void:
	var trail := "pushcha-trail"
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = trail
	s.minute = 992
	var enc := {"id": "t_cult", "enemies": [{"monster": "cultist", "count": 4, "name": "Сектант"}]}
	var world: Dictionary = data["world"].duplicate(true)
	(world["rooms"][trail] as Dictionary)["encounter"] = enc
	var d := data.duplicate()
	d["world"] = world
	EncounterRules.heads(s, d, trail, enc)
	s.lurking[trail] = {"encounter": "t_cult", "from": "pushcha-edge", "seen": true}
	var free := MapSpots.foes(s, d, WalkRules.view(s, d))
	assert_int(free.size()).is_equal(4)
	var lair := Vector2i(int(free[0]["x"]), int(free[0]["y"]))
	var map := LayoutRules.map_of(s, d, trail)
	s.props[trail] = [{"id": "stone_table", "name": "Каменный стол", "item_id": "", "owner": "", "text": "", "state": "", "body": "boulder",
		"at": [LayoutGen.on_grid(map, lair).x, LayoutGen.on_grid(map, lair).y]}]
	var stone := {}
	for t: Dictionary in MapSpots.of(s, d, map):
		if str(t["kind"]) == "prop":
			for c: Variant in t["cells"]:
				stone[c] = true
	assert_int(stone.size()).is_equal(4)
	for t: Dictionary in MapSpots.foes(s, d, WalkRules.view(s, d)):
		assert_bool(stone.has(Vector2i(int(t["x"]), int(t["y"])))).override_failure_message("%s stands in the stone table" % t["name"]).is_false()


## «Уйти» works on the way's own square too, not only on the square before it (the author stood right on the cave's exit).
func test_the_way_out_is_open_on_its_own_square() -> void:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = "pushcha-trail"
	CombatRules.start(s, data, [{"monster": "wolf", "x": 2, "y": 2}], {})
	var exits: Array = FightGrid.map(s, data)["exits"]
	assert_bool(exits.is_empty()).is_false()
	var e: Dictionary = exits[0]
	assert_bool(FightField.at_way_out(s, data, Vector2i(int(e["ax"]), int(e["ay"])))).is_true()
	assert_bool(FightField.at_way_out(s, data, Vector2i(int(e["x"]), int(e["y"])))).is_true()
	assert_str(FightField.way_out_shut(s, data, Vector2i(int(e["x"]), int(e["y"])))).is_not_equal("COMBAT_NOT_AT_EXIT")


## A foe caught by surprise skips its first turn, but the start of that turn is still its own: it saves against the
## Stinking Cloud it stands in (the author: «это относится к любым эффектам»).
func test_a_surprised_foe_still_saves_against_the_cloud_it_starts_in() -> void:
	var s := _hero("wizard_yalika", 5)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}, {"monster": "goblin", "col": 3}], {"sneak": true, "stealth_total": 99})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	var foes := CombatRules.enemies(s)
	assert_bool(bool(CombatRules.fighter(s, foes[0]).get("surprised", false))).is_true()
	s.character["spell_dc"] = 40
	var sp: Dictionary = s.character["spells"]
	sp["always"] = (sp.get("always", []) as Array) + ["stinking_cloud"]
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	Stock.fill_slots(s.character)
	CombatRules.economy(s)["action"] = 1
	var cast := Acts.one("cast").go(s, data, CombatRules.player(s), foes[0], {"spell": "stinking_cloud", "slot": 3})
	var lines: Array[String] = CombatRules.end_player_turn(s, data)
	for i in 4:
		if not str(s.combat.get("outcome", "")).is_empty() or CombatRules.is_player_turn(s):
			break
		lines.append_array(CombatRules.next_actor(s, data))
	var saved := lines.filter(func(l: String) -> bool: return l.begins_with("Зловонное облако: "))
	assert_int(saved.size()).override_failure_message(" · ".join(cast) + " || " + " · ".join(lines)).is_equal(2)


## The author, 2026-11-13: «в описании мобов и NPC лучше так же указывать какие у него заклинания, способности, устойчивости
## нашими иконками». The card gives each feature, spell, defense and status its icon; the panel draws them as icons.
func test_the_card_of_a_creature_shows_its_features_spells_and_defenses_as_icons() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "imp", "col": 1}, {"monster": "mage", "col": 2}])
	Knows.add(s, Knows.MONSTER, "imp")
	Knows.add(s, Knows.MONSTER, "mage")
	var imp := CreatureCard.of(s, data, CombatRules.fighter(s, TestUtils.foe(s, 1)))
	assert_bool(bool(imp["known"])).is_true()
	assert_array((imp["features"] as Array).map(func(f: Dictionary) -> String: return str(f["icon"]))).contains(["traits/devils_sight"])
	var icons: Array = []
	for d: Dictionary in imp["defenses"]:
		icons.append_array(d["icons"])
	assert_array(icons).contains(["conditions/resistant@cold", "conditions/poisoned"])
	var mage := CreatureCard.of(s, data, CombatRules.fighter(s, TestUtils.foe(s, 2)))
	assert_array(mage["spells"]["ids"]).contains(["fire_bolt"])
	var box := VBoxContainer.new()
	CreatureCardPanel.fill(box, mage)
	var spells: HFlowContainer = box.find_child("CardSpells", false, false)
	assert_object(spells).is_not_null()
	assert_bool(spells.find_children("*", "IconSlot", true, false).any(func(c: IconSlot) -> bool: return c.tip_title == "Огненный снаряд")).is_true()
	box.free()
	box = VBoxContainer.new()
	CreatureCardPanel.fill(box, imp)
	assert_object(box.find_child("CardDefenses", false, false)).is_not_null()
	assert_object(box.find_child("CardFeatures", false, false)).is_not_null()
	box.free()


## The author, 2026-11-13: «очень нелогичная генерация столов и скамей… скамьи не рядом со столами и стоят рандомно».
## A bench stands along its table: turned as it is, its long side against the table's long side.
func test_benches_stand_along_their_tables() -> void:
	var d := data.duplicate(true)
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	var benches := 0
	for seed: int in 20:
		s.game_seed = 300 + seed
		s.layout_cache.clear()
		var tokens := MapSpots.of(s, d, WalkRules.view(s, d))
		var tables := {}
		for t: Dictionary in tokens:
			if str(t.get("body", "")) == "table":
				for c: Vector2i in t["cells"]:
					tables[c] = true
		for t: Dictionary in tokens:
			if str(t.get("body", "")) != "bench":
				continue
			benches += 1
			var cells: Array = t["cells"]
			var across: bool = (cells[0] as Vector2i).y == (cells[1] as Vector2i).y  # the bench runs left to right
			var step := Vector2i(0, 1) if across else Vector2i(1, 0)
			var by := [step, -step].any(func(o: Vector2i) -> bool: return cells.all(func(c: Vector2i) -> bool: return tables.has(c + o)))
			assert_bool(by).override_failure_message("seed %d: a bench on %s not along a table" % [seed, cells]).is_true()
	assert_int(benches).is_greater(5)


## A table of a furnishing and the benches beside it stand whole, never a table of one furnishing with a crate of another
## where its bench was (v0.8.4.43.51: a room stands one furnishing whole).
func test_a_table_of_a_furnishing_stands_with_its_benches() -> void:
	var d := data.duplicate(true)
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	var map := WalkRules.view(s, d)
	var chunk_id := str(map["picks"][s.room_id]["chunk"])
	var chunk: Dictionary = (d["layouts"]["chunks"] as Array).filter(func(c: Dictionary) -> bool: return str(c["id"]) == chunk_id)[0]
	var rows: Array = chunk["rows"]
	var at := Vector2i(-1, -1)  # a block of plain floor two wide and three deep
	for y: int in range(2, rows.size() - 3):
		for x: int in range(2, str(rows[y]).length() - 3):
			var plain := true
			for dy: int in range(0, 3):
				for dx: int in range(0, 2):
					var ch := str(rows[y + dy])[x + dx]  # a spot gives way to a furnishing
					plain = plain and (ch == "." or str(chunk.get("marks", {}).get(ch, "")).begins_with(MapSpots.SPOT))
			if plain and at.x < 0:
				at = Vector2i(x, y)
	assert_int(at.x).is_greater(-1)
	chunk["furnish"] = [
		{"name": "стол", "things": [{"body": "table", "x": at.x, "y": at.y + 1}, {"body": "bench", "x": at.x, "y": at.y}, {"body": "bench", "x": at.x, "y": at.y + 2}]},
		{"name": "ящик", "things": [{"body": "crate", "x": at.x, "y": at.y}]},
	]
	var whole := 0
	for seed: int in 30:
		s.game_seed = 500 + seed
		s.layout_cache.clear()
		var mine := MapSpots.of(s, d, WalkRules.view(s, d)).filter(func(t: Dictionary) -> bool: return t.has("set"))
		var bodies := mine.map(func(t: Dictionary) -> String: return str(t["body"]))
		if bodies.has("table"):
			whole += 1
			assert_int(bodies.count("bench")).override_failure_message("seed %d: %s" % [seed, bodies]).is_equal(2)
			assert_bool(bodies.has("crate")).is_false()
		else:
			assert_bool(bodies.has("bench")).is_false()
	assert_int(whole).is_greater(0)


## The author: «скамья вдвое уже стола» — its picture takes half of its short side.
func test_a_bench_is_drawn_half_as_wide() -> void:
	assert_float(float(data["layouts"]["grounds"]["thin"]["bench"])).is_equal(0.5)


## The author, 2026-11-13: «огненный шар, выстрел или удар можно навести на цель и вне боя; кого задело — начинается бой».
## A blow readied by the hand on the hotbar lands first on the person it was aimed at, caught off guard; a shot does not
## walk up.
func test_a_blow_readied_out_of_a_fight_lands_first() -> void:
	var s := _hero("fighter_aira")
	GameState.session = s
	s.mode = GameSession.MODE_EXPLORATION
	GameState.poised = {}
	assert_str(GameState.poise_strike("main")).is_empty()
	assert_str(str(GameState.poised.get("hand", ""))).is_equal("main")
	assert_bool(GameState.poised_melee()).is_true()  # a longsword: the hero walks up first
	assert_str(GameState.poise_strike("main")).is_empty()  # pressed again — let go
	assert_bool(GameState.poised.is_empty()).is_true()
	var foes := [{"monster": "acolyte", "name": "Сестра Илва", "npc_id": "npc_priestess", "col": 1}]
	TestUtils.fight(s, data, foes, {"opening": {"npc_id": "npc_priestess"}})
	s.mode = GameSession.MODE_COMBAT
	var f := CombatRules.fighter(s, CombatRules.fighter_of_npc(s, "npc_priestess"))
	assert_bool(bool(f.get("surprised", false))).is_true()
	var lines := GameState._opening_strike({"attack": {}, "npc_id": "npc_priestess"})
	assert_bool(lines.is_empty()).is_false()
	GameState.session = null
