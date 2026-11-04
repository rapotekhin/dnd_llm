extends GdUnitTestSuite
## v0.8.4.23: the stub animations of a fight. Every spell, blow and act has a kind of `data/anims.json` that the interface plays
## phase by phase; a kind is replaced by its row's `frames` or `scene`, not by code. A miss looks as the target's gear allows,
## picked by the seed and the event's number, never by the game's dice.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _fight(s: GameSession, monster: String = "goblin") -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "col": 0}])
	return CombatRules.fighter(s, TestUtils.foe(s, 1))


func test_every_srd_spell_has_a_delivery_as_in_the_catalog() -> void:
	var count := {}
	for id: String in data["spells"]:
		var k := AnimRules.of_spell(data, id)
		assert_str(str(data["anims"]["kinds"].get(k, {}).get("group", ""))).override_failure_message(id + " → " + k).is_equal("spell")
		count[k] = int(count.get(k, 0)) + 1
	# docs/design/systems/combat-animations.md, appendix
	var want := {"bolt": 7, "beam": 5, "burst": 8, "cone": 4, "line": 2, "nova": 6, "zone": 16, "touch": 37, "sigil": 25, "aura": 36,
		"summon": 11, "teleport": 2}
	for k: String in want:
		assert_int(int(count.get(k, 0))).override_failure_message("%s: %d" % [k, int(count.get(k, 0))]).is_equal(int(want[k]))


func test_the_rows_win_and_a_master_spell_gets_one_by_its_fields() -> void:
	assert_str(AnimRules.of_spell(data, "fireball")).is_equal("burst")
	assert_str(AnimRules.of_spell(data, "burning_hands")).is_equal("cone")
	assert_str(AnimRules.of_spell(data, "cure_wounds")).is_equal("touch")
	assert_str(AnimRules.of_spell(data, "remove_curse")).is_equal("touch")
	assert_str(AnimRules.of_spell(data, "eldritch_blast")).is_equal("beam")
	assert_str(AnimRules.of_spell(data, "magic_missile")).is_equal("bolt")
	assert_str(AnimRules.of_spell(data, "misty_step")).is_equal("teleport")
	data["spells"]["gen_ash_rain"] = {"range_ft": 90, "area": {"type": "sphere", "size": 15}, "duration": "Мгновенная", "damage_type": "fire",
		"damage_at_slot": {"3": "6d6"}, "save": {"ability": "dex", "success": "half"}}
	assert_str(AnimRules.of_spell(data, "gen_ash_rain")).is_equal("burst")
	assert_str(AnimRules.spell_colour(data, "gen_ash_rain")).is_equal("fire")


func test_every_kind_is_phases_of_stubs_and_can_be_replaced() -> void:
	var places := ["by", "to", "path", "cells", "beside"]
	var kinds: Dictionary = data["anims"]["kinds"]
	assert_int(kinds.size()).is_equal(51)
	for k: String in kinds:
		var row: Dictionary = kinds[k]
		if str(row["group"]) == "state":
			assert_bool(row.has("texture")).is_true()
			continue
		assert_bool(row.has("frames") and row.has("scene")).override_failure_message(k).is_true()
		assert_bool((row["phases"] as Array).is_empty()).override_failure_message(k).is_false()
		for p: Dictionary in row["phases"]:
			assert_bool(str(p["phase"]) in ["windup", "travel", "hit", "linger", "fade"]).override_failure_message(k).is_true()
			assert_bool(places.has(str(p["at"]))).override_failure_message(k).is_true()
			assert_float(float(p["time"])).is_greater(0.0)
			assert_str(str(p["stub"])).is_not_empty()


func test_every_srd_attack_has_a_look() -> void:
	var s := TestUtils.new_session()
	var hero := CombatRules.player(s)
	for tid: String in data["monsters"]:
		var f := {"id": "x", "monster": tid, "x": 0, "y": 0}
		for a: Dictionary in data["monsters"][tid].get("actions", []):
			var k := AnimRules.of_save(data, a) if str(a.get("kind")) == "save" else str(AnimRules.of_blow(s, data, f, hero, Attack.of_action(data, f, a))["anim"])
			assert_bool(data["anims"]["kinds"].has(k)).override_failure_message("%s %s → %s" % [tid, a.get("name_en"), k]).is_true()
	var wolf := {"id": "w", "monster": "wolf", "x": 0, "y": 0}
	var bite: Dictionary = data["monsters"]["wolf"]["actions"][0]
	assert_str(str(AnimRules.of_blow(s, data, wolf, hero, Attack.of_action(data, wolf, bite))["anim"])).is_equal("bite")
	var bear := {"id": "b", "monster": "brown_bear", "x": 0, "y": 0}
	for a: Dictionary in data["monsters"]["brown_bear"]["actions"]:
		if str(a.get("name_en")) == "Claws":
			assert_str(str(AnimRules.of_blow(s, data, bear, hero, Attack.of_action(data, bear, a))["anim"])).is_equal("claw")


func test_a_weapon_strikes_by_its_damage_and_empty_hands_punch() -> void:
	var s := TestUtils.new_session()
	var hero := CombatRules.player(s)
	var foe := {"id": "g", "x": 1, "y": 0}
	hero["x"] = 0
	hero["y"] = 0
	var fist := Attack.of_weapon(CombatRules.weapon_profile(s.character, data, s.items, ""))
	assert_str(str(AnimRules.of_blow(s, data, hero, foe, fist)["anim"])).is_equal("punch")
	var sword := AnimRules.of_blow(s, data, hero, foe, Attack.of_weapon(CombatRules.weapon_profile(s.character, data, s.items, "longsword")))
	assert_str(str(sword["anim"])).is_equal("swing")
	assert_str(str(sword["sprite"])).is_equal("sword")
	var bow := AnimRules.of_blow(s, data, hero, foe, Attack.of_weapon(CombatRules.weapon_profile(s.character, data, s.items, "longbow")))
	assert_str(str(bow["anim"])).is_equal("shot")
	assert_str(str(bow["proj"])).is_equal("arrow")
	assert_str(str(AnimRules.of_blow(s, data, hero, foe, Attack.of_weapon(CombatRules.weapon_profile(s.character, data, s.items, "mace")))["anim"])).is_equal("smash")
	foe["x"] = 5  # a dagger at 25 ft leaves the hand
	assert_str(str(AnimRules.of_blow(s, data, hero, foe, Attack.of_weapon(CombatRules.weapon_profile(s.character, data, s.items, "dagger")))["anim"])).is_equal("throw")


func test_a_miss_looks_as_the_gear_allows() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s)
	var c := s.character
	c["equipped"]["shield"] = ""
	c["equipped"]["main_hand"] = ""
	var hero := CombatRules.player(s)
	assert_array(AnimRules.defences(s, data, hero, "swing")).is_equal(["dodge"])
	assert_array(AnimRules.defences(s, data, hero, "shot")).is_equal(["dodge", "overshoot", "undershoot"])
	c["equipped"]["shield"] = "shield"
	c["equipped"]["main_hand"] = "longsword"
	assert_array(AnimRules.defences(s, data, hero, "swing")).is_equal(["dodge", "block_shield", "parry"])
	assert_array(AnimRules.defences(s, data, hero, "shot")).is_equal(["dodge", "block_shield", "overshoot", "undershoot"])
	assert_array(AnimRules.defences(s, data, hero, "bolt")).is_equal(["dodge", "overshoot"])
	assert_bool(AnimRules.defences(s, data, g, "swing").has("block_shield")).is_equal(bool(AnimRules.gear(s, data, g)["shield"]))


func test_the_pick_of_a_miss_does_not_touch_the_dice() -> void:
	var s := TestUtils.new_session()
	var state := s.rng.state
	var seen := {}
	for n in 40:
		seen[AnimRules.pick(s, ["dodge", "block_shield", "parry"] as Array[String], n)] = true
	assert_int(s.rng.state).is_equal(state)
	assert_int(seen.size()).is_equal(3)
	assert_str(AnimRules.pick(s, ["a", "b", "c"] as Array[String], 7)).is_equal(AnimRules.pick(s, ["a", "b", "c"] as Array[String], 7))


func test_a_blow_leaves_an_event_with_its_result() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s)
	AnimRules.take(s)
	var lines: Array[String] = []
	Attack.swing(s, data, g, CombatRules.player(s), Attack.blade(s, data, g), lines)
	var evs := AnimRules.take(s)
	assert_int(evs.size()).is_greater_equal(1)
	var e: Dictionary = evs[0]
	assert_str(str(e["by"])).is_equal(str(g["id"]))
	assert_str(str(e["to"])).is_equal(CombatRules.PLAYER)
	assert_bool(str(e["result"]) in ["hit", "crit", "miss"]).is_true()
	assert_str(str(e["dtype"])).is_not_empty()
	assert_bool(e.has("by_at") and e.has("to_at")).is_true()
	if str(e["result"]) == "miss":
		assert_bool(AnimRules.defences(s, data, CombatRules.player(s), str(e["anim"])).has(str(e["miss"]))).is_true()


func test_a_spell_shows_its_delivery_and_its_attack_lands_on_it() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s)
	AnimRules.take(s)
	var lines: Array[String] = []
	ActionRules.cast(s, data, CombatRules.player(s), "fire_bolt", 0, str(g["id"]), {"ability": "int", "attack": 5, "dc": 13})
	var evs := AnimRules.take(s).filter(func(e: Dictionary) -> bool: return str(e["act"]) == "cast")
	assert_int(evs.size()).is_equal(1)  # one bolt, its roll on it
	assert_str(str(evs[0]["anim"])).is_equal("bolt")
	assert_str(str(evs[0]["dtype"])).is_equal("fire")
	assert_bool(str(evs[0]["result"]) in ["hit", "crit", "miss"]).is_true()
	ActionRules.cast(s, data, CombatRules.player(s), "burning_hands", 1, FightGrid.aim_id(FightGrid.cell(g)), {"ability": "int", "attack": 5, "dc": 13})
	var cone: Array = AnimRules.take(s).filter(func(e: Dictionary) -> bool: return str(e["act"]) == "cast")
	assert_str(str(cone[0]["anim"])).is_equal("cone")
	assert_bool((cone[0].get("cells", []) as Array).is_empty()).is_false()


## A foe casts on the player's road (ADR-0016): the act of the buttons and the AI leaves the same events as the hero's cast.
func test_a_foe_casts_by_the_same_events_as_the_hero() -> void:
	var s := TestUtils.new_session()
	var m := _fight(s, "mage")
	s.character["hp"] = 500
	AnimRules.take(s)
	var can := {}
	for o: Dictionary in MonsterRules.castable(data, m):  # what its AI is offered
		can[str(o["id"])] = o
	Acts.one("cast").go(s, data, m, CombatRules.PLAYER, {"spell": "fire_bolt"}.merged(can["fire_bolt"]))
	var bolt: Array = AnimRules.take(s).filter(func(e: Dictionary) -> bool: return str(e["act"]) == "cast")
	assert_int(bolt.size()).is_equal(1)
	assert_str(str(bolt[0]["by"])).is_equal(str(m["id"]))
	assert_str(str(bolt[0]["to"])).is_equal(CombatRules.PLAYER)
	assert_str(str(bolt[0]["anim"])).is_equal("bolt")
	assert_bool(str(bolt[0]["result"]) in ["hit", "crit", "miss"]).is_true()
	Acts.one("cast").go(s, data, m, CombatRules.PLAYER, {"spell": "magic_missile"}.merged(can["magic_missile"]))
	var darts: Array = AnimRules.take(s).filter(func(e: Dictionary) -> bool: return str(e["act"]) == "cast")
	assert_bool(darts.is_empty()).is_false()
	assert_str(str(darts[0]["anim"])).is_equal(AnimRules.of_spell(data, "magic_missile"))
	assert_str(str(darts[0]["by"])).is_equal(str(m["id"]))


func test_an_act_of_the_field_by_its_row() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s)
	AnimRules.take(s)
	var hero := CombatRules.player(s)
	ConditionRules.remove(s.character, "prone")
	CombatRules._hold(s.character, "prone")
	Acts.one("stand").go(s, data, hero)
	var evs := AnimRules.take(s)
	assert_str(str(evs[0]["anim"])).is_equal("rise")
	assert_str(str(evs[0]["by"])).is_equal(CombatRules.PLAYER)
	assert_dict(AnimRules.act(s, data, hero, "walk", "", {})).is_empty()  # a walk shows itself on the map


func test_the_token_shows_what_is_in_the_hands_of_anybody() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s, "bandit")
	s.character["equipped"]["main_hand"] = "longsword"
	s.character["equipped"]["shield"] = "shield"
	var mine := AnimRules.gear(s, data, CombatRules.player(s))
	assert_bool(bool(mine["shield"])).is_true()
	assert_str(str(mine["sprite"])).is_equal("sword")
	assert_str(str(AnimRules.gear(s, data, g)["sprite"])).is_not_empty()  # a bandit's scimitar or crossbow
	s.character["equipped"]["main_hand"] = ""
	assert_str(str(AnimRules.gear(s, data, CombatRules.player(s))["sprite"])).is_empty()
	var wolf := _fight(TestUtils.new_session(), "wolf")
	assert_str(str(AnimRules.gear(s, data, wolf)["sprite"])).is_empty()  # jaws only while it bites


func test_lasting_states_of_a_fighter() -> void:
	var s := TestUtils.new_session()
	var g := _fight(s)
	g["hidden"] = true
	g["dodging"] = true
	CombatRules._hold(Sheet.holder(s, g), "prone")
	var st := AnimRules.states(s, data, g)
	for k: String in ["hidden", "dodging", "prone"]:
		assert_bool(st.has(k)).override_failure_message(k).is_true()
	g["status"] = "dead"
	assert_array(AnimRules.states(s, data, g)).is_equal(["dead"])
