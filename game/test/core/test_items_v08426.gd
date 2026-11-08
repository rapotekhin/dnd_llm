extends GdUnitTestSuite
## Magic items off the master's words (roadmap v0.8.4.26): a worn thing lays a status while it works (`wear`, read as a
## spell's), a thing's spell out of a fight goes the sheet's road, a thing calls a row of the summons, a hat casts at will,
## a decanter pours water anywhere.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(race := "") -> GameSession:
	var s := ChecklistProbe.session(data)
	if not race.is_empty():
		s.character["race"] = race
		CharacterRules.refresh(s.character, data, s.items)
	return s


func _wear(s: GameSession, id: String) -> void:
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 1)
	var d := ItemRules.def_of(data["items"], s.items, id)
	if ItemRules.needs_attunement(d):
		ItemRules.attune(c, data, s.items, id)
	var slot := CharacterRules.slot_for(d, data)
	if not slot.is_empty():
		c["equipped"][slot] = id
	CharacterRules.refresh(c, data, s.items)


func test_a_ring_gives_a_swim_only_while_worn() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "ring_of_swimming", 1)  # a free finger: it goes on by itself (v0.8.4.40)
	Equip.off(s, data, Being.HERO, "ring1")
	assert_bool(Move.speeds(s, data, Sheet.HERO).has("swim")).is_false()  # in the pack
	c["equipped"]["ring1"] = "ring_of_swimming"
	CharacterRules.refresh(c, data, s.items)
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("swim", 0))).is_equal(40)
	assert_str(" ".join(CharacterRules.item_boons(c, data, s.items))).contains("плавание 40 фт")
	c["equipped"]["ring1"] = ""
	CharacterRules.refresh(c, data, s.items)
	assert_bool(Move.speeds(s, data, Sheet.HERO).has("swim")).is_false()
	assert_bool(ConditionRules.effects(c).any(func(e: Dictionary) -> bool: return str(e["source"]["kind"]) == ItemRules.WORN)).is_false()


func test_winged_boots_fly_at_the_wearers_walk() -> void:
	var s := _hero("dwarf")
	_wear(s, "winged_boots")
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("fly", 0))).is_equal(25)
	assert_bool(SpellEffects.has(s.character, "flying")).is_true()


func test_a_foe_wears_the_same_ring() -> void:
	var s := _hero()
	var g := ChecklistProbe.fight(s, data, "goblin")
	g["inventory"]["ring_of_swimming"] = 1
	g["equipped"]["ring1"] = "ring_of_swimming"
	Gear.follow(s, data, g)
	assert_int(int(Move.speeds(s, data, g).get("swim", 0))).is_equal(40)


func test_the_lantern_reveals_only_lit_on_the_belt() -> void:
	var s := _hero()
	var c := s.character
	c["belt"] = ["", "", "", "", ""]  # a belt laid by the player: the lantern stays in the pack
	Gear.give(s, data, Being.HERO, "lantern_of_revealing", 1)
	CharacterRules.refresh(c, data, s.items)
	assert_bool(SpellEffects.has(c, "see_invisible")).is_false()
	ItemRules.belt_put(c, data, s.items, "lantern_of_revealing")
	CharacterRules.refresh(c, data, s.items)
	assert_bool(SpellEffects.has(c, "see_invisible")).is_true()


func test_a_hat_casts_at_will_where_it_is_worn() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "hat_of_disguise", 1)
	Equip.off(s, data, Being.HERO, "head")  # a free head: it went on by itself (v0.8.4.40)
	ItemRules.attune(c, data, s.items, "hat_of_disguise")
	CharacterRules.refresh(c, data, s.items)
	assert_str(ItemRules.can_use(c, data, s.items, "hat_of_disguise")).contains("не надета")
	c["equipped"]["head"] = "hat_of_disguise"
	CharacterRules.refresh(c, data, s.items)
	assert_str(ItemRules.can_use(c, data, s.items, "hat_of_disguise")).is_empty()
	for i in 2:
		var lines := ItemRules.use(c, data, s.items, "hat_of_disguise", s.rng, s)
		assert_str(" ".join(lines)).contains("чужой облик")
	assert_int(Gear.count(s, data, Being.HERO, "hat_of_disguise")).is_equal(1)


func test_a_wand_casts_its_world_spell_by_the_sheets_road() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "wand_of_magic_detection", 1)
	ItemRules.belt_put(c, data, s.items, "wand_of_magic_detection")
	var lines := ItemRules.use(c, data, s.items, "wand_of_magic_detection", s.rng, s)
	assert_str(" ".join(lines)).contains("магии")
	assert_str(str(c.get("concentration", ""))).is_equal("detect_magic")
	assert_int(Stock.spent(c, "slot_1")).is_equal(0)  # a thing pays for its spell


func test_a_bag_of_tricks_calls_one_of_its_beasts() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "bag_of_tricks", 1)
	ItemRules.belt_put(c, data, s.items, "bag_of_tricks")
	ItemRules.use(c, data, s.items, "bag_of_tricks", s.rng, s)
	var called := AllyRules.called(s)
	assert_int(called.size()).is_equal(1)
	assert_array(AllyRules.summon_spec(data, "bag_of_tricks")["pick"]).contains([str(called[0]["monster"])])
	assert_str(" ".join(AllyRules.summon_lines(s, data))).contains("Мешок фокусов")


func test_a_decanter_pours_water_anywhere() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"].clear()
	Gear.give(s, data, Being.HERO, "waterskin", 1)
	LiquidRules.drain(c)
	var dry := NeedRules.water_here(s, data)
	Gear.give(s, data, Being.HERO, "decanter_of_endless_water", 1)
	CharacterRules.refresh(c, data, s.items)
	assert_bool(NeedRules.water_here(s, data)).is_true()
	assert_str(NeedRules.can_fill(s, data)).is_empty()
	assert_bool(dry).is_false()
