extends GdUnitTestSuite
## v0.8.4.15, ADR-0016: the things and the numbers of anybody — what works on a fighter, its AC and its blow by what it
## has, one «take a thing», a dish of whoever eats it; exhaustion, a spell on an ally read live, one HP step, the reaction
## spells by their rows, a hidden or invisible foe for both sides, a creature's short rest.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _foe(s: GameSession, monster: String) -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "col": 4}])
	return CombatRules.fighter(s, TestUtils.foe(s, 1))


func test_adamantine_on_a_foe_turns_a_critical_hit() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	f["inventory"]["adamantine_chain_mail"] = 1
	f["equipped"]["armor"] = "adamantine_chain_mail"
	assert_bool(Sheet.prop(s, data, f, "no_crit")).is_true()
	assert_bool(Sheet.prop(s, data, Sheet.HERO, "no_crit")).is_false()


func test_a_foe_s_brooch_works_only_attuned() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	f["inventory"]["brooch_of_shielding"] = 1
	var slot := CharacterRules.wear_slot(ItemRules.def_of(data["items"], {}, "brooch_of_shielding"), data)
	f["equipped"][slot if not slot.is_empty() else "neck"] = "brooch_of_shielding"
	assert_bool(HeroDefense.resistances(s, data, f).has("force")).is_false()
	f["attuned"] = ["brooch_of_shielding"]
	assert_bool(HeroDefense.resistances(s, data, f).has("force")).is_true()


func test_a_magic_sword_in_a_foe_s_hands_is_magic() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	f["inventory"]["longsword_plus_1"] = 1
	Equip.put(s, data, str(f["id"]), "longsword_plus_1", "main_hand")  # only what is in its hands strikes (v0.8.4.40)
	var blow: Dictionary = {}
	for a: Dictionary in Sheet.template(data, f)["actions"]:
		if str(a.get("item", "")) == "longsword_plus_1":
			blow = Attack.of_action(data, f, a)
	assert_bool(blow.is_empty()).is_false()
	assert_bool(bool(blow["magical"])).is_true()
	var plain := Gear._blow(s, data, f, data["monsters"]["bandit"], "longsword")
	assert_int(int(blow["to_hit"])).is_equal(int(plain["to_hit"]) + 1)


func test_a_foe_s_magic_shield_counts_in_its_ac() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	var was := CombatRules.ac_of(f)
	f["inventory"]["shield_plus_1"] = 1
	f["equipped"]["off_hand"] = "shield_plus_1"
	Gear.follow(s, data, f)
	assert_int(CombatRules.ac_of(f)).is_equal(was + 3)  # a shield's 2 and its +1


func test_a_thing_taken_is_off_its_slot_and_its_attunement() -> void:
	var s := TestUtils.new_session()
	var c := s.character
	c["inventory"]["ring_of_warmth"] = 1
	c["equipped"]["ring1"] = "ring_of_warmth"
	c["attuned"] = ["ring_of_warmth"]
	assert_int(ItemRules.remove(c, "ring_of_warmth")).is_equal(1)
	assert_str(str(c["equipped"].get("ring1", ""))).is_empty()
	assert_array(c["attuned"]).not_contains(["ring_of_warmth"])


func test_exhaustion_slows_a_foe_and_halves_its_maximum() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	var feet := Sheet.speed(s, data, f)
	var top := int(f["max_hp"])
	ConditionRules.add_exhaustion(s, data, 2, "тест", str(f["id"]))
	assert_int(Sheet.speed(s, data, f)).is_equal(feet / 2)
	ConditionRules.add_exhaustion(s, data, 2, "тест", str(f["id"]))
	assert_int(int(f["max_hp"])).is_equal(maxi(1, top / 2))
	ConditionRules.add_exhaustion(s, data, 1, "тест", str(f["id"]))
	assert_int(Sheet.speed(s, data, f)).is_equal(0)


func test_one_hp_step_with_dwarven_toughness() -> void:
	var c := {"traits": ["dwarven_toughness"]}
	assert_int(CharacterRules.hp_step(c, 8, 2)).is_equal(8 / 2 + 1 + 2 + 1)
	assert_int(CharacterRules.hp_step({}, 8, 2)).is_equal(8 / 2 + 1 + 2)


func test_longstrider_on_an_ally_adds_its_feet_once() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	var feet := Sheet.speed(s, data, f)
	ConditionRules.add_effect(f, {"condition": "", "speed_plus": 10, "source": {"kind": "spell", "id": "longstrider", "name": "Скороход"}})
	assert_int(Sheet.speed(s, data, f)).is_equal(feet + 10)


func test_mage_armor_on_a_fighter_is_read_live() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	var was := CombatRules.ac_of(f)
	ConditionRules.add_effect(f, {"condition": "", "ac_min": was + 2, "source": {"kind": "spell", "id": "mage_armor", "name": "Доспехи мага"}})
	assert_int(CombatRules.ac_of(f)).is_equal(was + 2)
	f["ac"] = was + 5  # a better armour put on beats it
	assert_int(CombatRules.ac_of(f)).is_equal(was + 5)


func test_the_hero_s_shield_takes_its_ac_from_the_row() -> void:
	var s := TestUtils.new_session()
	var plus := int(SpellEffects.spec(data, "shield")["ac_plus"])
	var ac := int(s.character["ac"])
	assert_int(SpellEffects.guard(s, data, Sheet.HERO, "shield")).is_equal(plus)
	assert_int(int(s.character["ac"])).is_equal(ac + plus)


func test_a_counter_of_anybody_stops_a_low_spell_at_once() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	var lines: Array[String] = []
	assert_bool(SpellEffects.countered(s, data, f, "counterspell", "int", 3, "fire_bolt", 0, lines)).is_true()
	assert_str(lines[0]).contains("срывается")


func test_an_ally_misses_where_an_invisible_foe_stood() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	FightGrid.keep_seen(f)
	f["conditions"] = (f["conditions"] as Array) + ["invisible"]
	f["x"] = int(f["x"]) + 2
	assert_bool(CombatRules._missed_unseen(s, f)).is_true()
	assert_array(FightAI._targets(s, CombatRules.player(s)).map(func(t: Dictionary) -> String: return str(t["id"]))).contains([str(f["id"])])


func test_a_creature_rests_its_own_wounds() -> void:
	var s := TestUtils.new_session()
	var b := Being.spawn(s, {"name": "Волк"})
	b["creature"] = {"monster": "wolf", "hp": 2, "max_hp": 11}
	assert_str(Sheet.template_id(data, Sheet.who(s, data, str(b["id"])))).is_equal("wolf")
	Rest.short(s, data, str(b["id"]), 2)
	assert_int(int(b["creature"]["hp"])).is_greater(2)
	assert_bool(b.has("monster")).is_false()
