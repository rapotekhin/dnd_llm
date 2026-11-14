extends GdUnitTestSuite
## What a character has (v0.8.4.10, ADR-0016): one form of things for anybody, a trader's one till, a foe's gear that its blows
## and AC follow, potions, flasks, scrolls and arrows on the one road of the hero's.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["max_hp"] = 2000
	s.character["hp"] = 2000
	return s


func _foe(s: GameSession, spec: Dictionary) -> Dictionary:
	var row := spec.duplicate()
	row.merge({"name": "Боец", "col": 2})
	TestUtils.fight(s, data, [row], {})
	s.mode = GameSession.MODE_COMBAT
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	f["points"] = CombatRules.fresh_points(s, data, f)
	TestUtils.beside(s, f)
	return f


func test_a_person_has_its_things_in_the_form_of_the_heros() -> void:
	var s := _hero()
	var c := Gear.of(s, data, "npc_veteran")
	for k: String in ["inventory", "gold_cp", "equipped"]:
		assert_bool(c.has(k)).override_failure_message(k).is_true()
	assert_str(str(c["equipped"]["armor"])).is_equal("chain_shirt")  # the guard template's
	assert_str(str(c["equipped"]["off_hand"])).is_equal("shield")
	assert_int(int(c["inventory"]["spear"])).is_equal(1)
	Gear.give(s, data, "npc_veteran", "healing_potion")
	assert_str(ItemRules.can_use(c, data, s.items, "healing_potion")).is_empty()  # the hero's rules read it as they are
	assert_bool(TheftRules.pockets(s, data, "npc_veteran").any(func(e: Dictionary) -> bool: return str(e["item_id"]) == "chain_shirt")).is_false()


func test_a_traders_purse_is_its_one_till() -> void:
	var s := _hero()
	TradeRules.merchant(s, data, "npc_innkeeper")
	var till := Gear.coins(s, data, "npc_innkeeper")
	assert_int(till).is_greater_equal(3000)
	assert_int(int(TradeRules.info(s, data, "npc_innkeeper")["purse_cp"])).is_equal(till)
	assert_int(ContestRules.purse(s, data, "npc_innkeeper")).is_equal(till)
	var before := Ledger.balance(s)
	TheftRules.steal(s, data, "npc_innkeeper", TheftRules.PURSE, true)
	var hand := Ledger.balance(s) - before
	assert_int(hand).is_equal(int(data["rules"]["theft"]["handful_cp"]))  # a hand takes a handful, not the till
	assert_int(Gear.coins(s, data, "npc_innkeeper")).is_equal(till - hand)
	assert_int(int(TradeRules.info(s, data, "npc_innkeeper")["purse_cp"])).is_equal(till - hand)


func test_a_hurt_foe_drinks_its_potion_and_it_is_not_on_its_body() -> void:
	var s := _hero()
	var f := _foe(s, {"monster": "veteran"})
	assert_int(int(f["inventory"].get("healing_potion", 0))).is_equal(1)
	f["hp"] = 5
	var lines: Array[String] = []
	FightAI.first(s, data, f, lines)
	assert_str("\n".join(lines)).contains("Боец —")
	assert_int(int(f["hp"])).is_greater(5)
	assert_int(int(f["inventory"].get("healing_potion", 0))).is_equal(0)
	f["status"] = "dead"
	assert_bool(CombatRules.spoils(data, f, RandomNumberGenerator.new()).has("healing_potion")).is_false()


func test_a_foe_spends_its_bolts_and_without_them_has_no_bow() -> void:
	var s := _hero()
	var f := _foe(s, {"monster": "bandit"})
	f["inventory"]["crossbow_bolt"] = 1
	var lines := Acts.one("attack").go(s, data, f, CombatRules.PLAYER, {"action": "Light Crossbow"})
	assert_bool(lines.is_empty()).is_false()
	assert_int(int(f["inventory"].get("crossbow_bolt", 0))).is_equal(0)
	assert_int(int(f["ammo_spent"]["crossbow_bolt"])).is_equal(1)
	assert_bool((Sheet.template(data, f)["actions"] as Array).any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "crossbow_light")).is_false()
	f["status"] = "dead"
	assert_int(int(CombatRules.spoils(data, f, RandomNumberGenerator.new()).get("crossbow_light", 0))).is_equal(1)  # the bow is still on it


func test_what_it_has_makes_its_blows_and_its_ac() -> void:
	var s := _hero()
	Gear.give(s, data, "npc_serving", "longsword")  # its club is in the hand: the sword stays in the pack (v0.8.4.40)
	Gear.give(s, data, "npc_serving", "leather_armor")  # light armour goes on by itself; a chain shirt is past a commoner
	Equip.put(s, data, "npc_serving", "longsword", "main_hand")
	var f := _foe(s, {"monster": "commoner", "npc_id": "npc_serving"})
	assert_int(int(f["ac"])).is_equal(11)  # a commoner of AC 10 in leather
	assert_bool((Sheet.template(data, f)["actions"] as Array).any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "longsword")).is_true()
	var t := _hero()
	var bare := _foe(t, {"monster": "bandit", "gear": {"scimitar": 1}})
	assert_int(int(bare["ac"])).is_equal(11)  # leather off: 10 + DEX
	assert_bool((Sheet.template(data, bare)["actions"] as Array).any(func(a: Dictionary) -> bool: return str(a.get("item", "")) == "crossbow_light")).is_false()


func test_a_foe_throws_its_flask_as_the_hero_would() -> void:
	var s := _hero()
	var f := _foe(s, {"monster": "spy"})
	var offers := Acts.one("throw").offers(s, data, f, [CombatRules.player(s)])
	assert_bool(offers.is_empty()).is_false()
	assert_str(Acts.one("throw").can(s, data, f, CombatRules.PLAYER, {"item": "acid_vial"})).is_empty()
	Acts.one("throw").go(s, data, f, CombatRules.PLAYER, {"item": "acid_vial"})
	assert_int(int(f["inventory"].get("acid_vial", 0))).is_equal(0)


func test_a_mage_reads_its_scroll_on_the_one_road_of_a_spell() -> void:
	var s := _hero()
	var f := _foe(s, {"monster": "mage"})
	var offers := Acts.one("item_spell").offers(s, data, f, [CombatRules.player(s)])
	assert_bool(offers.is_empty()).is_false()
	var o: Dictionary = offers[0]
	assert_str(str(o["how"]["item"])).is_equal("spell_scroll_burning_hands")
	assert_str(Acts.one("item_spell").can(s, data, f, str(o["to"]), o["how"])).is_empty()
	Acts.one("item_spell").go(s, data, f, str(o["to"]), o["how"])
	assert_int(int(f["inventory"].get("spell_scroll_burning_hands", 0))).is_equal(0)


func test_a_persons_things_go_back_to_it_after_the_fight() -> void:
	var s := _hero()
	Gear.of(s, data, "npc_veteran")
	var f := _foe(s, {"monster": "guard", "npc_id": "npc_veteran"})
	assert_bool(Being.view(s, "npc_veteran").has("inventory")).is_false()  # in the fight it is the fighter's
	assert_bool(Gear.of(s, data, "npc_veteran") == f).is_true()
	Gear.give(s, data, "npc_veteran", "torch")
	CombatRules.close(s)
	assert_int(Gear.count(s, data, "npc_veteran", "torch")).is_equal(1)
	assert_int(Gear.count(s, data, "npc_veteran", "spear")).is_equal(1)


func test_fire_burns_the_hero_as_it_burns_a_foe() -> void:
	var s := _hero()
	_foe(s, {"monster": "bandit"})
	var p := CombatRules.player(s)
	LiquidRules.coat(s, data, s.character, "alchemists_fire", "Алхимический огонь", p)
	var hp := int(s.character["hp"])
	var lines: Array[String] = []
	Harm.each_turn(s, data, p, "start", lines)
	assert_int(int(s.character["hp"])).is_less(hp)
