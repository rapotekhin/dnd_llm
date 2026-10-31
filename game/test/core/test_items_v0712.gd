extends GdUnitTestSuite
## «Правила 5e: предметы» (roadmap v0.7.12): ammunition and its recovery, elemental damage, heavy weapons and small
## races, silver, reach, curses; flasks and the net thrown in a fight; potions, scrolls, wands and the pearl;
## attunement, identification, charges at dawn; what the master may hand out; trader services.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func _fight(s: GameSession, monster: String, col: int = 0) -> Dictionary:
	CombatRules.start(s, data, [{"monster": monster, "col": col}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


# --- the catalog ---------------------------------------------------------------------------------------


func test_catalog_has_the_srd_magic_of_levels_1_to_5() -> void:
	var cat: Dictionary = data["items"]["catalog"]
	for id: String in ["wand_of_magic_missiles", "wand_of_web", "pearl_of_power", "gauntlets_of_ogre_power", "bag_of_holding",
			"potion_of_resistance_fire", "potion_of_climbing", "spell_scroll_cure_wounds", "spell_scroll_identify", "mithral_chain_mail",
			"adamantine_breastplate", "broom_of_flying"]:
		assert_bool(cat.has(id)).override_failure_message("нет " + id).is_true()
	assert_bool(bool(cat["broom_of_flying"].get("master", false))).is_true()
	assert_bool(bool(cat["cloak_of_protection"].get("attunement", false))).is_true()
	# Every property in the catalog is one the engine knows (the master pays only for working ones).
	for id: String in cat:
		for p: Variant in cat[id].get("properties", []):
			assert_bool((data["items"]["properties"] as Dictionary).has(str(p))).override_failure_message("%s: %s" % [id, p]).is_true()


# --- weapons --------------------------------------------------------------------------------------------


func test_arrows_are_spent_and_half_come_back() -> void:
	var s := _hero("ranger_velena")
	var c := s.character
	c["inventory"]["longbow"] = 1
	c["equipped"]["main_hand"] = "longbow"
	c["inventory"]["arrows"] = 2
	var f := _fight(s, "goblin", 2)
	var arrows := int(c["inventory"]["arrows"])
	assert_str(CombatRules.can_attack(s, data, str(f["id"]))).is_empty()
	CombatRules.player_attack(s, data, str(f["id"]))
	assert_int(int(c["inventory"].get("arrows", 0))).is_equal(arrows - 1)
	c["inventory"].erase("arrows")
	s.combat["economy"]["action"] = 1
	assert_str(CombatRules.can_attack(s, data, str(f["id"]))).is_equal("COMBAT_NO_AMMO")
	assert_int(int(s.combat["ammo_spent"]["arrows"])).is_equal(1)


func test_heavy_weapon_for_a_halfling_has_disadvantage() -> void:
	var s := _hero("druid_olha")
	s.character["inventory"]["greataxe"] = 1
	s.character["equipped"]["main_hand"] = "greataxe"
	var f := _fight(s, "goblin")
	var w := CombatRules.weapon_profile(s.character, data, s.items, "greataxe")
	assert_array(CombatRules._attack_mods(s, data, w, f)["dis"]).contains(["тяжёлое оружие не по росту"])


func test_common_weapons_are_not_magical_any_more() -> void:
	var s := _hero("fighter_aira")
	assert_bool(bool(CombatRules.weapon_profile(s.character, data, s.items, "longsword")["magical"])).is_false()
	assert_bool(bool(CombatRules.weapon_profile(s.character, data, s.items, "longsword_plus_1")["magical"])).is_true()


func test_a_flaming_sword_adds_fire() -> void:
	var s := _hero("fighter_aira")
	var def := {"name": "Огненный меч", "item_type": "weapon", "base": "longsword", "rarity": "uncommon", "properties": ["fire_damage"], "generated": true}
	var id := ItemRules.generated_id(def)
	s.items[id] = def
	s.character["inventory"][id] = 1
	s.character["equipped"]["main_hand"] = id
	var f := _fight(s, "ogre")
	f["ac"] = 1
	var lines: Array[String] = []
	for i in 6:
		s.combat["economy"]["action"] = 1
		lines.append_array(CombatRules.player_attack(s, data, str(f["id"])))
		if lines.any(func(l: String) -> bool: return l.contains("(огонь)")):
			break
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("Огненный меч: ещё"))).is_true()


func test_reach_meets_a_foe_coming_in() -> void:
	var s := _hero("fighter_aira")
	s.character["inventory"]["glaive"] = 1
	s.character["equipped"]["main_hand"] = "glaive"
	s.character["equipped"]["shield"] = ""
	var f := _fight(s, "wolf", 1)
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, f, lines)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("досягаемость"))).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(bool(CombatRules.player(s).get("reacted", false))).is_true()


func test_adamantine_turns_a_crit_into_a_hit() -> void:
	var s := _hero("fighter_aira")
	s.character["inventory"]["adamantine_chain_mail"] = 1
	s.character["equipped"]["armor"] = "adamantine_chain_mail"
	CharacterRules.refresh(s.character, data, s.items)
	assert_bool(CharacterRules.item_prop(s.character, "no_crit")).is_true()


func test_mithral_drops_the_strength_need() -> void:
	var d := ItemRules.def_of(data["items"], {}, "mithral_plate_armor")
	assert_int(int(d["armor"]["str_min"])).is_equal(0)
	assert_bool(bool(d["armor"]["stealth_disadvantage"])).is_false()


# --- thrown things ------------------------------------------------------------------------------------


func test_alchemists_fire_burns_until_put_out() -> void:
	var s := _hero("rogue_damir")
	s.character["inventory"]["alchemists_fire_flask"] = 3
	var f := _fight(s, "ogre", 1)
	f["ac"] = 1
	var lines: Array[String] = []
	for i in 3:
		s.combat["economy"]["action"] = 1
		assert_str(CombatRules.can_throw(s, data, "alchemists_fire_flask", str(f["id"]))).is_empty()
		lines.append_array(CombatRules.throw_item(s, data, "alchemists_fire_flask", str(f["id"])))
		if f.has("burning"):
			break
	assert_bool(f.has("burning")).override_failure_message(" · ".join(lines)).is_true()
	var hp := int(f["hp"])
	var turn: Array[String] = []
	CombatRules._enemy_turn(s, data, f, turn)
	assert_bool(turn[0].contains("горит") or turn.any(func(l: String) -> bool: return l.contains("горит"))).is_true()
	assert_int(int(f["hp"])).is_less(hp)


func test_holy_water_hurts_only_undead_and_fiends() -> void:
	var s := _hero("cleric_branko")
	s.character["inventory"]["holy_water"] = 5
	var f := _fight(s, "wolf", 0)
	f["ac"] = 1
	var lines: Array[String] = []
	for i in 4:
		s.combat["economy"]["action"] = 1
		lines.append_array(CombatRules.throw_item(s, data, "holy_water", str(f["id"])))
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("не действует"))).is_true()


func test_a_net_holds_a_foe() -> void:
	var s := _hero("fighter_aira")
	s.character["inventory"]["net"] = 3
	var f := _fight(s, "goblin", 0)
	f["ac"] = 1
	for i in 3:
		s.combat["economy"]["action"] = 1
		CombatRules.throw_item(s, data, "net", str(f["id"]))
		if CombatRules._has(f, "restrained"):
			break
	assert_bool(CombatRules._has(f, "restrained")).is_true()


# --- potions, scrolls, wands ------------------------------------------------------------------------------


func test_potion_of_fire_resistance() -> void:
	var s := _hero("fighter_aira")
	s.character["inventory"]["potion_of_resistance_fire"] = 1
	assert_str(ItemRules.can_use(s.character, data, s.items, "potion_of_resistance_fire")).is_empty()
	ItemRules.use(s.character, data, s.items, "potion_of_resistance_fire", s.rng, s)
	assert_bool(HeroDefense.resistances(s, data).has("fire")).is_true()


func test_potion_of_climbing_gives_advantage_on_athletics() -> void:
	var s := _hero("fighter_aira")
	s.character["inventory"]["potion_of_climbing"] = 1
	ItemRules.use(s.character, data, s.items, "potion_of_climbing", s.rng, s)
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("check_adv", "")) == "athletics")).is_true()


func test_a_scroll_of_the_own_class_reads_without_a_check() -> void:
	assert_bool(bool(ItemRules.read_scroll(_hero("cleric_branko"), data, "cure_wounds", 1)["ok"])).is_true()
	var line := str(ItemRules.read_scroll(_hero("fighter_aira"), data, "cure_wounds", 1)["line"])
	assert_str(line).contains("Сл 11")


func test_a_wand_of_magic_missiles_spends_charges_and_no_slot() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	c["inventory"]["wand_of_magic_missiles"] = 1
	var f := _fight(s, "ogre", 2)
	assert_str(CombatRules.can_item_spell(s, data, "wand_of_magic_missiles", str(f["id"]))).is_empty()
	var hp := int(f["hp"])
	var lines := CombatRules.item_spell(s, data, "wand_of_magic_missiles", str(f["id"]))
	assert_int(int(f["hp"])).override_failure_message(" · ".join(lines)).is_less(hp)
	var d := ItemRules.def_of(data["items"], s.items, "wand_of_magic_missiles")
	assert_int(ItemRules.charges_left(c, d, "wand_of_magic_missiles")).is_equal(6)
	assert_bool(c.has("spell_dc")).is_false()  # the fighter got no spellcasting out of it
	var gone := ItemRules.dawn(c, data, s.items, s.rng)
	assert_int(ItemRules.charges_left(c, d, "wand_of_magic_missiles")).is_equal(7)
	assert_int(gone.size()).is_equal(1)


func test_pearl_of_power_recovers_a_slot() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	c["inventory"]["pearl_of_power"] = 1
	c["slots_used"] = [1, 0, 0, 0, 0]
	assert_str(ItemRules.can_use(c, data, s.items, "pearl_of_power")).contains("настройки")
	assert_str(ItemRules.can_attune(c, data, s.items, "pearl_of_power")).is_empty()
	ItemRules.attune(c, data, s.items, "pearl_of_power")
	assert_str(ItemRules.can_use(c, data, s.items, "pearl_of_power")).is_empty()
	ItemRules.use(c, data, s.items, "pearl_of_power", s.rng, s)
	assert_int(int(c["slots_used"][0])).is_equal(0)
	assert_bool(ItemRules.can_attune(_hero("fighter_aira").character, data, {}, "pearl_of_power") == "EQUIP_NOT_OWNED").is_true()


# --- attunement, identification, curses ---------------------------------------------------------------


func test_gauntlets_need_attunement_and_set_strength_19() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	c["inventory"]["gauntlets_of_ogre_power"] = 1
	c["equipped"]["hands"] = "gauntlets_of_ogre_power"  # v0.7.22.9: worn on the hands
	CharacterRules.refresh(c, data, s.items)
	assert_int(CharacterRules.ability(c, "str")).is_less(19)
	ItemRules.attune(c, data, s.items, "gauntlets_of_ogre_power")
	CharacterRules.refresh(c, data, s.items)
	assert_int(CharacterRules.ability(c, "str")).is_equal(19)
	assert_int(CharacterRules.capacity(c, data)).is_equal(19 * 15)


func test_three_attunements_at_most() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	for id: String in ["cloak_of_protection", "ring_of_warmth", "gauntlets_of_ogre_power", "headband_of_intellect"]:
		c["inventory"][id] = 1
	for id: String in ["cloak_of_protection", "ring_of_warmth", "gauntlets_of_ogre_power"]:
		ItemRules.attune(c, data, s.items, id)
	assert_str(ItemRules.can_attune(c, data, s.items, "headband_of_intellect")).is_equal("ATTUNE_FULL")


func test_found_magic_is_unidentified_until_a_short_rest() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	var key := ItemRules.found(c, data, s.items, "boots_of_striding_and_springing")
	assert_str(key).is_equal("unk_boots_of_striding_and_springing")
	assert_str(ItemRules.display_name(data["items"], s.items, key)).is_equal("Сапоги, свойства неизвестны")
	assert_str(ItemRules.found(c, data, s.items, "healing_potion")).is_equal("healing_potion")
	c["hp"] = int(c["max_hp"])
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_bool(c["inventory"].has("boots_of_striding_and_springing")).is_true()
	assert_bool(c["inventory"].has(key)).is_false()


func test_identify_service_and_scroll() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	ItemRules.found(c, data, s.items, "ring_of_warmth")
	c["inventory"]["spell_scroll_identify"] = 1
	c["class"] = "wizard"  # reads its own class's scroll without a check
	CharacterRules.refresh(c, data, s.items)
	var lines := ItemRules.use(c, data, s.items, "spell_scroll_identify", s.rng, s)
	assert_bool(c["inventory"].has("ring_of_warmth")).override_failure_message(" · ".join(lines)).is_true()


func test_a_cursed_thing_does_not_come_off() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	var def := {"name": "Чёрный меч", "item_type": "weapon", "base": "longsword", "rarity": "common", "properties": ["cursed"], "generated": true}
	var id := ItemRules.generated_id(def)
	s.items[id] = def
	c["inventory"][id] = 1
	c["equipped"]["main_hand"] = id
	assert_bool(ItemRules.held_by_curse(c, data, s.items, id)).is_true()
	assert_int(TradeRules.sellable(s, id, data)).is_equal(0)
	s.npc_id = "npc_priestess"
	var lines := TradeRules.buy_service(s, data, "npc_priestess", "remove_curse")
	assert_str(str(c["equipped"]["main_hand"])).is_empty()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("проклятие отпустило"))).is_true()


func test_silvering_at_the_smith() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	var main := str(c["equipped"]["main_hand"])
	c["gold_cp"] = 100000
	var sv := TradeRules.services(s, data, "npc_smith")
	assert_str(str(sv[0]["id"])).is_equal("silver")
	assert_str(str(sv[0]["why"])).is_empty()
	TradeRules.buy_service(s, data, "npc_smith", "silver", main)
	var now := str(c["equipped"]["main_hand"])
	assert_str(now).is_not_equal(main)
	assert_bool(bool(CombatRules.weapon_profile(c, data, s.items, now)["silvered"])).is_true()


func test_the_master_hands_out_nothing_rarer_than_uncommon() -> void:
	var rare := {"name": "Доспех +1", "rarity": "rare"}
	assert_str(ItemRules.rarity_ok(data, rare, 3)).is_not_empty()
	assert_str(ItemRules.rarity_ok(data, {"rarity": "uncommon"}, 3)).is_empty()
	assert_str(ItemRules.rarity_ok(data, rare, 6)).is_empty()


func test_old_saves_keep_the_cloak_working() -> void:
	var v19 := {"save_version": 19, "session": {"character": {"inventory": {"cloak_of_protection": 1}}}}
	SaveFormat._v19_to_v20(v19, {})
	assert_array(v19["session"]["character"]["attuned"]).contains_exactly(["cloak_of_protection"])


func test_the_sheet_says_what_worn_goggles_give() -> void:  # the author's finding (v0.7.49.4)
	var s := _hero("bard_yas")
	s.character["inventory"]["goggles_of_night"] = 1
	assert_array(CharacterRules.item_boons(s.character, data, s.items)).is_empty()  # in the pack, not worn
	s.character["equipped"]["eyes"] = "goggles_of_night"
	CharacterRules.refresh(s.character, data, s.items)
	assert_array(CharacterRules.item_boons(s.character, data, s.items)).contains(["Очки ночного видения: тёмное зрение 60 фт"])


func test_an_attack_line_of_the_fight_has_its_breakdown() -> void:  # the author's finding (v0.7.49.4)
	var s := _hero("bard_yas")
	var f := _fight(s, "goblin")
	var w := CombatRules.weapon_profile(s.character, data, s.items, "rapier")
	var lines: Array[String] = []
	CombatRules._attack(s, data, "Ясь", "Рапира", int(w["to_hit"]), false, false, f, "1d8", 2, "piercing", lines, "", false, w)
	var tip := CombatRules.tip_for(s, lines[0])
	assert_str(tip).contains("к20")
	assert_str(tip).contains("против КД")
	assert_str(tip).contains("Ловкость")
	assert_str(tip).not_contains("прочие бонусы")
