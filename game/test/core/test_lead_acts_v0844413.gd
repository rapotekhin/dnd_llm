extends GdUnitTestSuite
## v0.8.4.44.13, the author: «чего сложного просто заменять героя? мы же делали чтобы Игрок и NPC были одинаковыми
## классами». The follower the player leads acts out of a fight on the hero's own road: its spells (SpellRules.offers — a
## template's too), its uses and its things on the bar and the ✦ menu, spent from its own record by GameState._spend.

var data: Dictionary
var kept: GameSession


func before() -> void:
	data = TestUtils.data()


func before_test() -> void:
	kept = GameState.session
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-square"
	Being.follow(s, "npc_priestess")
	Being.follow(s, "npc_mercenary")
	GameState.session = s


func after_test() -> void:
	GameState.attached = {}
	GameState.session = kept


func _choice(id: String) -> Dictionary:
	for ch: Dictionary in GameState.attach_choices():
		if str(ch["id"]) == id:
			return ch
	return {}


func test_the_bar_offers_the_spells_of_the_one_led() -> void:
	var s := GameState.session
	assert_dict(_choice("cure_wounds")).is_empty()
	GameState.lead("npc_priestess")
	var cure := _choice("cure_wounds")
	assert_dict(cure).is_not_empty()
	assert_array(cure["slots"]).contains([1])
	assert_dict(_choice("sacred_flame")).is_not_empty()
	assert_array(SpellRules.offers(s, data, Sheet.HERO).map(func(o: Dictionary) -> String: return str(o["id"]))).not_contains(["cure_wounds"])


func test_a_follower_heals_the_hero_from_its_own_slot() -> void:
	var s := GameState.session
	GameState.lead("npc_priestess")
	s.character["hp"] = 3
	var spent := GameState._spend({"kind": "spell", "id": "cure_wounds", "slot": 1, "targets": [GameState.SELF_TARGET], "who": PartyLead.of(s)})
	assert_dict(spent).not_contains_keys(["reason"])
	assert_int(int(s.character["hp"])).is_greater(3)
	var me := Sheet.own(s, "npc_priestess")
	assert_int(SpellRules.slots_left(me, 1)).is_equal(2)
	assert_str(str(spent["facts"])).contains("Спутник героя")


func test_a_follower_blesses_itself_by_default() -> void:
	var s := GameState.session
	GameState.lead("npc_priestess")
	var spent := GameState._spend({"kind": "spell", "id": "bless", "slot": 1, "who": PartyLead.of(s)})
	assert_dict(spent).not_contains_keys(["reason"])
	var on := ConditionRules.effects(Being.view(s, "npc_priestess"))
	assert_bool(on.any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless")).is_true()
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless")).is_false()


func test_the_led_drinks_its_own_potion_not_the_heros() -> void:
	var s := GameState.session
	var merc := Gear.of(s, data, "npc_mercenary")
	ItemRules.add(merc, "healing_potion", 1)
	if ItemRules.belt_why(merc, data, s.items, "healing_potion").is_empty() and not ItemRules.on_belt(merc, data, s.items, "healing_potion"):
		ItemRules.belt_put(merc, data, s.items, "healing_potion")
	ItemRules.add(s.character, "healing_potion", 1)
	var had := int(merc["inventory"]["healing_potion"])
	var hero_had := int(s.character["inventory"]["healing_potion"])
	Being.of(s, "npc_mercenary")["hp"] = 1
	GameState.lead("npc_mercenary")
	var spent := GameState._spend({"kind": "item", "id": "healing_potion", "who": PartyLead.of(s)})
	assert_dict(spent).not_contains_keys(["reason"])
	assert_int(int(merc.get("inventory", {}).get("healing_potion", 0))).is_equal(had - 1)
	assert_int(int(s.character["inventory"].get("healing_potion", 0))).is_equal(hero_had)
	assert_int(Sheet.hp(s, data, Sheet.who(s, data, "npc_mercenary"))).is_greater(1)


func test_a_whole_record_is_not_healed_from_nothing_and_a_wounded_one_up_to_its_template() -> void:
	var s := GameState.session
	var me := Sheet.own(s, "npc_mercenary")
	assert_int(Harm.mend(s, data, me, 50)).is_equal(0)
	assert_bool(Being.view(s, "npc_mercenary").has("hp")).is_false()
	Being.of(s, "npc_mercenary")["hp"] = 2
	var top := Sheet.max_hp(s, data, Sheet.who(s, data, "npc_mercenary"))
	assert_int(Harm.mend(s, data, me, 500)).is_equal(top - 2)
	assert_int(Sheet.hp(s, data, Sheet.who(s, data, "npc_mercenary"))).is_equal(top)


func test_a_pin_is_of_the_one_led_and_aims_at_it_by_default() -> void:
	var s := GameState.session
	GameState.lead("npc_priestess")
	GameState.attach("spell", "bless", 1)
	assert_str(str(GameState.attached["who"])).is_equal("npc_priestess")
	assert_bool(GameState.attach_aimed("npc_priestess")).is_true()
	assert_bool(GameState.attach_aimed(Being.HERO)).is_false()
	assert_str(GameState.aim_attached(Being.HERO)).is_empty()  # a portrait of the hero: on the hero, not on the caster
	assert_bool(GameState.attach_aimed(Being.HERO)).is_true()
	assert_bool(GameState.attach_aimed("npc_priestess")).is_false()
	GameState.lead(Being.HERO)
	GameState.attach("spell", "bless", 1)
	assert_str(str(GameState.attached["who"])).is_equal(Being.HERO)
	assert_dict(_choice("cure_wounds")).is_empty()
	assert_str(str(s.layouts.get(PartyLead.KEY, ""))).is_empty()


## «Ремесло» by the one led (the author: «Да, с ремесла»): its own tools, iron, coins, project and check.
func _smith(s: GameSession) -> Dictionary:
	var merc := Life.of(s, "npc_mercenary", data)
	merc["tools"] = ["smiths_tools"]
	ItemRules.add(merc, "smiths_tools", 1)
	ItemRules.add(merc, "iron_bar", 2)
	Ledger.purse(merc, 1000)
	s.room_id = "brod-smithy"
	s.minute = 9 * 60
	GameState.lead("npc_mercenary")
	return merc


func test_the_led_forges_with_its_own_hands() -> void:
	var s := GameState.session
	var merc := _smith(s)
	s.character["inventory"].erase("iron_bar")
	assert_array(CraftRules.known(s, data)).not_contains(["dagger"])  # the hero has no smith's tools
	assert_array(CraftRules.known(s, data, "npc_mercenary")).contains(["dagger"])
	assert_str(GameState.craft_act("start", "dagger")).is_empty()
	assert_dict(CraftRules.project(merc)).is_not_empty()
	assert_dict(CraftRules.project(s.character)).is_empty()
	assert_int(int(merc["inventory"]["iron_bar"])).is_equal(1)
	var hero_cp := Ledger.balance(s)
	var merc_cp := Ledger.balance(s, "npc_mercenary")
	assert_str(GameState.craft_act("work", "", 8)).is_empty()
	assert_dict(CraftRules.project(merc)).is_empty()
	assert_bool((merc["inventory"] as Dictionary).keys().any(func(id: String) -> bool: return ItemRules.plain_of(data["items"], s.items, id) == "dagger")).is_true()
	assert_int(Ledger.balance(s)).is_equal(hero_cp)
	assert_int(Ledger.balance(s, "npc_mercenary")).is_less(merc_cp)  # the forge's rent from its purse


func test_the_led_salvages_and_gathers_into_its_own_things() -> void:
	var s := GameState.session
	var merc := _smith(s)
	ItemRules.add(merc, "dagger", 1)
	assert_array(CraftRules.salvageable(s, data, "npc_mercenary")).contains(["dagger"])
	var iron := int(merc["inventory"].get("iron_bar", 0))
	var hero_iron := int(s.character["inventory"].get("iron_bar", 0))
	assert_str(GameState.craft_act("salvage", "dagger")).is_empty()
	assert_int(int(merc["inventory"].get("iron_bar", 0))).is_greater(iron)
	assert_int(int(s.character["inventory"].get("iron_bar", 0))).is_equal(hero_iron)
