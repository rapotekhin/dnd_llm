extends GdUnitTestSuite
## v0.8.4.24: the belt under the doll (as in Pathfinder): five cells of things at hand — only they are used, a light there
## lights the way; the set put away takes a javelin and says where a crossbow goes.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero(preset_id: String = "rogue_damir") -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


## In the dark gallery of the mine, no darkvision, nothing at hand.
func _dark(s: GameSession) -> void:
	s.room_id = "mine-gallery"
	(s.character["traits"] as Array).erase("darkvision")
	s.character["belt"] = ["", "", "", "", ""]


func test_the_belt_has_five_cells_and_takes_what_is_used() -> void:
	var s := _hero()
	var c := s.character
	c.erase("belt")
	c["inventory"] = {"healing_potion": 2, "candle": 10, "bread": 3, "longsword": 1}
	var belt := ItemRules.belt(c, data, s.items)
	assert_int(belt.size()).is_equal(int(data["rules"]["belt"]["size"]))
	assert_bool(belt.has("healing_potion")).is_true()
	assert_bool(belt.has("candle")).is_true()  # a light
	assert_bool(belt.has("longsword")).is_false()  # a weapon goes to the hands
	assert_bool(ItemRules.belt_fits(data, s.items, "berries")).is_false()  # food is eaten from the pack


func test_only_the_belts_things_are_used() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["healing_potion"] = 1
	c["inventory"]["berries"] = 1
	c["belt"] = ["", "", "", "", ""]
	assert_str(ItemRules.can_use(c, data, s.items, "healing_potion")).contains("не на поясе")
	assert_str(ItemRules.can_use(c, data, s.items, "berries")).is_empty()  # a meal is no act of the belt
	assert_str(ItemRules.belt_why(c, data, s.items, "healing_potion")).is_empty()
	ItemRules.belt_put(c, data, s.items, "healing_potion")
	assert_str(ItemRules.can_use(c, data, s.items, "healing_potion")).is_empty()
	assert_str(ItemRules.belt_why(c, data, s.items, "healing_potion")).is_equal("BELT_ALREADY")
	ItemRules.belt_take(c, data, s.items, ItemRules.belt(c, data, s.items).find("healing_potion"))
	assert_bool(ItemRules.on_belt(c, data, s.items, "healing_potion")).is_false()


func test_a_full_belt_takes_nothing_more() -> void:
	var s := _hero()
	var c := s.character
	c["belt"] = ["", "", "", "", ""]
	for id: String in ["healing_potion", "candle", "torch", "oil_flask", "acid_vial", "holy_water"]:
		c["inventory"][id] = 1
	for id: String in ["healing_potion", "candle", "torch", "oil_flask", "acid_vial"]:
		assert_str(ItemRules.belt_why(c, data, s.items, id)).is_empty()
		ItemRules.belt_put(c, data, s.items, id)
	assert_str(ItemRules.belt_why(c, data, s.items, "holy_water")).is_equal("BELT_FULL")


func test_a_flask_off_the_belt_is_not_thrown() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["alchemists_fire_flask"] = 1
	c["belt"] = ["", "", "", "", ""]
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 1}], {})
	var foe := CombatRules.enemies(s)[0]
	assert_str(Acts.one("throw").why(s, data, CombatRules.player(s), foe, {"item": "alchemists_fire_flask"})).is_equal("COMBAT_ITEM_CANT")


func test_candles_on_the_belt_light_the_way() -> void:
	var s := _hero()
	_dark(s)
	var c := s.character
	c["inventory"]["candle"] = 10
	var lights: Dictionary = SightRules.cfg(data)["lights"]
	assert_bool(TimeRules.unlit(s, data)).is_true()
	assert_int(SightRules.light(s, data)).is_equal(0)  # candles in the pack are not lit
	assert_str(SightRules.in_dark(s, data)).is_equal("темнота")
	ItemRules.belt_put(c, data, s.items, "candle")
	assert_int(SightRules.light(s, data)).is_equal(int(lights["candle"]))
	assert_int(SightRules.reach(s, data)).is_equal(int(lights["candle"]))
	assert_bool(SightRules.lit(s, data)).is_true()
	assert_str(SightRules.in_dark(s, data)).is_empty()
	c["inventory"]["torch"] = 1
	ItemRules.belt_put(c, data, s.items, "torch")
	assert_int(SightRules.reach(s, data)).is_equal(int(lights["torch"]))  # the best light on the belt


# --- the set put away ---------------------------------------------------------------------------------------------


func _melee(s: GameSession) -> void:
	var c := s.character
	for id: String in ["longsword", "crossbow_light", "javelin"]:
		c["inventory"][id] = 1
	c["equipped"]["main_hand"] = "longsword"
	c["equipped"]["off_hand"] = ""
	c["equipped"]["shield"] = ""
	c["stowed"] = {"main_hand": "", "off_hand": "", "shield": ""}
	CharacterRules.refresh(c, data, s.items)


func test_a_javelin_lies_in_either_set() -> void:
	var s := _hero("fighter_aira")
	_melee(s)
	var c := s.character
	assert_str(CharacterRules.can_equip(c, data, s.items, "javelin", "main_hand")).is_empty()  # the hands take it
	assert_str(CharacterRules.can_equip(c, data, s.items, "javelin", "main_hand", true)).is_empty()
	CharacterRules.put_stowed(c, data, s.items, "javelin", "main_hand")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("javelin")
	assert_str(str(c["equipped"]["main_hand"])).is_equal("longsword")
	CharacterRules.swap_hands(c)
	assert_str(str(c["equipped"]["main_hand"])).is_equal("javelin")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("longsword")


func test_one_javelin_moves_between_the_sets() -> void:
	var s := _hero("fighter_aira")
	_melee(s)
	var c := s.character
	c["equipped"]["main_hand"] = "javelin"
	CharacterRules.put_stowed(c, data, s.items, "javelin", "main_hand")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("javelin")
	assert_str(str(c["equipped"]["main_hand"])).is_empty()  # one copy, not two
	assert_int(CharacterRules.held_copies(c, "javelin")).is_equal(1)


func test_a_crossbow_goes_to_the_set_put_away() -> void:
	var s := _hero("fighter_aira")
	_melee(s)
	var c := s.character
	assert_str(CharacterRules.can_equip(c, data, s.items, "crossbow_light", "main_hand", true)).is_empty()
	CharacterRules.put_stowed(c, data, s.items, "crossbow_light", "main_hand")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("crossbow_light")
	assert_str(str(c["equipped"]["main_hand"])).is_equal("longsword")
	assert_str(Acts.one("swap").can(s, data, CombatRules.player(s))).is_empty()
	Acts.one("swap").go(s, data, CombatRules.player(s))
	assert_str(str(c["equipped"]["main_hand"])).is_equal("crossbow_light")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("longsword")
