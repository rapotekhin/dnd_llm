extends GdUnitTestSuite
## Pact of the Blade as in BG3 (v0.8.4.33): a form called into the hand or a weapon carried bound as it is; the pact weapon is
## the warlock's own (proficiency), magical and struck by the spellcasting ability; a called one is let go, never sold.

var data: Dictionary
var s: GameSession
var c: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	c = s.character
	c["class"] = "warlock"  # Charisma is its spellcasting ability
	(c["features"] as Array).append("pact_of_the_blade")
	c["abilities"]["cha"] = 18
	c["abilities"]["str"] = 10
	c["abilities"]["dex"] = 10
	c["weapon_profs"] = []
	ItemRules.add(c, "dagger", 1)
	CharacterRules.refresh(c, data, s.items)


func _profile(id: String) -> Dictionary:
	return CombatRules.weapon_profile(c, data, s.items, id)


func test_the_options_call_a_form_or_bind_a_weapon_carried() -> void:
	var ids: Array = FeatureRules.pact_options(c, data, s.items).map(func(o: Dictionary) -> String: return str(o["id"]))
	assert_array(ids).contains(["make:longsword", "make:greatsword", "bind:dagger"])
	assert_array(ids).not_contains(["drop"])


func test_a_called_form_is_in_the_hand_owned_magical_and_by_charisma() -> void:
	var bare := _profile("greatsword")
	var lines := FeatureRules.pact_weapon(s, data, Sheet.HERO, "make:greatsword")
	assert_str(" ".join(lines)).contains("призывает")
	var id := FeatureRules.pact_item(c)
	assert_str(id).is_equal("pact_greatsword")
	assert_str(str(c["equipped"]["main_hand"])).is_equal(id)
	assert_str(str(c["equipped"].get("off_hand", ""))).is_empty()  # two hands on it
	var p := _profile(id)
	assert_bool(bool(p["magical"])).is_true()
	var owned := CombatRules.weapon_proficient(c, data["items"]["catalog"]["greatsword"]["weapon"], "greatsword")
	assert_int(int(p["to_hit"])).is_equal(int(bare["to_hit"]) + (0 if owned else Sheet.prof(s, data, Sheet.HERO)) + 4)  # CHA +4 over STR +0
	assert_int(TradeRules.sellable(s, id, data)).is_equal(0)
	assert_int(ContainerRules.droppable(s, data, id)).is_equal(0)


func test_binding_makes_no_copy_the_thing_itself_is_the_pact_weapon() -> void:
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "make:longsword")
	var had := (c["inventory"] as Dictionary).size()
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "bind:dagger")
	assert_str(FeatureRules.pact_item(c)).is_equal("dagger")
	assert_bool((c["inventory"] as Dictionary).has("pact_longsword")).is_false()  # the called one vanished
	assert_int((c["inventory"] as Dictionary).size()).is_equal(had - 1)
	assert_bool(bool(_profile("dagger")["magical"])).is_true()
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "drop")
	assert_str(FeatureRules.pact_item(c)).is_empty()
	assert_bool(bool(_profile("dagger")["magical"])).is_false()
	assert_int(int(c["inventory"]["dagger"])).is_greater(0)  # a bound thing stays the hero's


func test_only_the_pact_weapon_is_owned_not_every_melee_weapon() -> void:
	ItemRules.add(c, "warhammer", 1)
	var plain := _profile("warhammer")
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "bind:warhammer")
	assert_int(int(_profile("warhammer")["to_hit"])).is_greater(int(plain["to_hit"]))
	assert_int(int(_profile("dagger")["to_hit"])).is_equal(int(CombatRules.weapon_profile(c, data, s.items, "dagger")["to_hit"]))


func test_a_called_weapon_let_go_from_the_hands_vanishes() -> void:
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "make:rapier")
	c["equipped"]["main_hand"] = ""
	CharacterRules.refresh(c, data, s.items)
	assert_bool((c["inventory"] as Dictionary).has("pact_rapier")).is_false()
	assert_str(FeatureRules.pact_item(c)).is_empty()


func test_in_a_fight_it_is_an_action_with_the_forms_to_pick() -> void:
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	var hero := CombatRules.player(s)
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)
	s.combat["current"] = CombatRules.PLAYER
	assert_array(FeatureRules.actions(s, data).map(func(a: Dictionary) -> String: return str(a["id"]))).contains(["pact_weapon"])
	Acts.one("feature").go(s, data, hero, "", {"id": "pact_weapon"})
	assert_str(str(s.combat.get("prompt", {}).get("kind", ""))).is_equal("pact_weapon")
	FeatureRules.answer_prompt(s, data, "make:battleaxe")
	assert_str(FeatureRules.pact_item(c)).is_equal("pact_battleaxe")


func test_thirsting_blade_strikes_twice_only_with_the_pact_weapon_in_hand() -> void:
	(c["features"] as Array).append("eldritch_invocation_thirsting_blade")
	c["equipped"]["main_hand"] = "dagger"
	assert_int(CharacterRules.extra_attacks(c, data)).is_equal(0)
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "bind:dagger")
	assert_int(CharacterRules.extra_attacks(c, data)).is_equal(1)
