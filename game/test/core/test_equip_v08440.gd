extends GdUnitTestSuite
## v0.8.4.40, the author: one road of gear — a person, a monster and the hero strike only with what is in their hands,
## put things on by the same rules (Equip), a template's weapons are in its hands from the start, a Multiattack strikes
## with what the hand holds now, the master puts a thing on a person of the scene.

var data: Dictionary
var fx: EffectEngine
var turn := 0


func before() -> void:
	data = TestUtils.data()


func before_test() -> void:
	fx = EffectEngine.new()


func _foe(s: GameSession, monster: String) -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "col": 4}])
	return CombatRules.fighter(s, TestUtils.foe(s, 1))


func _acts(s: GameSession, f: Dictionary) -> Dictionary:
	var out := {}
	for a: Dictionary in Sheet.template(data, f)["actions"]:
		out[str(a.get("item", a.get("name_en", "")))] = a
	return out


func _turn(s: GameSession, e: Dictionary) -> Dictionary:
	turn += 1
	var t := "t-%d" % turn
	var r := fx.validate(s, data, t, e)
	if bool(r["accepted"]):
		fx.apply(s, t, [r["effect_id"]])
	return r


func test_a_template_holds_its_weapons_from_the_start() -> void:
	var kit := Gear.start(data, "goblin")
	assert_str(str(kit["equipped"]["main_hand"])).is_equal("scimitar")
	assert_str(str(kit["equipped"]["shield"])).is_equal("shield")
	assert_str(str(kit["stowed"]["main_hand"])).is_equal("shortbow")
	assert_str(str(Gear.start(data, "bandit_captain")["equipped"]["off_hand"])).is_equal("dagger")
	assert_str(str(Gear.start(data, "veteran")["equipped"]["off_hand"])).is_equal("shortsword")


func test_a_bow_put_away_is_struck_after_a_free_swap() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "goblin")
	var acts := _acts(s, f)
	assert_bool(bool(acts["scimitar"].get("stowed", false))).is_false()
	assert_bool(bool(acts["shortbow"].get("stowed", false))).is_true()
	Acts.one("swap").run(s, data, f, "", {})
	assert_str(str(f["equipped"]["main_hand"])).is_equal("shortbow")
	assert_bool(bool(_acts(s, f)["shortbow"].get("stowed", false))).is_false()


func test_a_weapon_in_the_pockets_is_no_blow_in_the_hands_it_is() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	f["inventory"]["longsword_plus_1"] = 1
	Gear.follow(s, data, f)
	assert_bool(_acts(s, f).has("longsword_plus_1")).is_false()
	Equip.put(s, data, str(f["id"]), "longsword_plus_1", "main_hand")
	var acts := _acts(s, f)
	assert_bool(acts.has("longsword_plus_1")).is_true()
	assert_bool(acts.has("scimitar")).is_false()  # it left the hand for the pack


func test_a_multiattack_strikes_with_what_the_hand_holds_now() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit_captain")
	var full := FightAI.blows(data, f, _acts(s, f)["scimitar"])  # two scimitars and the dagger
	f["inventory"]["longsword"] = 1
	Equip.put(s, data, str(f["id"]), "longsword", "main_hand")
	var sword: Dictionary = _acts(s, f)["longsword"]
	assert_str(str(sword["name_en"])).is_equal("Scimitar")  # the hand's name: its Multiattack finds it
	assert_int(FightAI.blows(data, f, sword)).is_equal(full)


func test_empty_hands_strike_with_fists() -> void:
	var s := TestUtils.new_session()
	var f := _foe(s, "bandit")
	Equip.off(s, data, str(f["id"]), "main_hand")
	CharacterRules.stowed(f)["main_hand"] = ""
	Gear.follow(s, data, f)
	var names: Array = (Sheet.template(data, f)["actions"] as Array).map(func(a: Dictionary) -> String: return str(a["name"]))
	assert_array(names).contains(["Безоружный удар"])


func test_a_person_puts_on_a_gift_by_itself_and_a_beast_cannot() -> void:
	var s := TestUtils.new_session()
	Gear.give(s, data, "npc_veteran", "ring_of_warmth")
	var c := Gear.of(s, data, "npc_veteran")
	assert_str(str(c["equipped"].get("ring1", ""))).is_equal("ring_of_warmth")
	var w := _foe(s, "wolf")
	assert_str(Equip.why(s, data, str(w["id"]), "leather_armor", "armor")).is_equal("EQUIP_NO_HANDS")


func test_a_person_wears_what_its_template_may() -> void:
	var s := TestUtils.new_session()
	Gear.give(s, data, "npc_innkeeper", "plate_armor")
	assert_str(Equip.why(s, data, "npc_innkeeper", "plate_armor", "armor")).is_equal("EQUIP_NO_PROFICIENCY")  # a commoner: light only
	Gear.give(s, data, "npc_veteran", "plate_armor")  # a guard: its chain shirt's medium and light
	assert_str(Equip.why(s, data, "npc_veteran", "plate_armor", "armor")).is_equal("EQUIP_NO_PROFICIENCY")
	Gear.give(s, data, "npc_captain", "plate_armor")
	assert_str(str(Gear.of(s, data, "npc_captain")["equipped"]["armor"])).is_equal("splint_armor")  # its own stays on
	assert_str(Equip.why(s, data, "npc_captain", "plate_armor", "armor")).is_empty()  # a veteran: a fighter by its class


func test_a_worn_status_lies_on_a_person_out_of_a_fight() -> void:
	var s := TestUtils.new_session()
	var ring := {"name": "Кольцо Благословения", "item_type": "wondrous", "rarity": "rare", "value_cp": 100000, "description": "Кольцо.",
		"wear": {"status": "spell:bless"}}
	s.items["gen_ring_bless"] = ring
	Gear.give(s, data, "npc_veteran", "gen_ring_bless")
	var worn := ConditionRules.effects(Gear.of(s, data, "npc_veteran")).filter(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("kind", "")) == ItemRules.WORN)
	assert_int(worn.size()).is_equal(1)
	assert_str(str(worn[0].get("die", ""))).is_equal("1d4")


func test_the_master_puts_a_thing_on_a_person_of_the_scene() -> void:
	var s := TestUtils.new_session()
	ItemRules.add(Gear.of(s, data, "npc_mercenary"), "cloak_of_protection", 1)
	var r := _turn(s, {"kind": "equip", "npc_id": "npc_mercenary", "slot": "cloak", "item_id": "cloak_of_protection"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_str(str(Gear.of(s, data, "npc_mercenary")["equipped"]["cloak"])).is_equal("cloak_of_protection")
	r = _turn(s, {"kind": "equip", "npc_id": "npc_hermit", "slot": "cloak", "item_id": "cloak_of_protection"})
	assert_bool(bool(r["accepted"])).is_false()  # not in the scene
	r = _turn(s, {"kind": "equip", "npc_id": "npc_mercenary", "slot": "armor", "item_id": "plate_armor"})
	assert_bool(bool(r["accepted"])).is_false()  # not its own thing


# --- the parts of a made status: advantage, disadvantage, vulnerability and immunity to anything ---------------------


func _status(s: GameSession, d: Dictionary, key: String, parts: Array) -> String:
	s.character["level"] = 20
	var p := MakeRules.plan(s, d, {"kind": "make", "what": "status", "key": key, "name": key, "text": "Сделано мастером.", "parts": parts})
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, d, p["plan"])
	return str(p["plan"]["id"])


func _lay(s: GameSession, d: Dictionary, id: String) -> void:
	ConditionRules.impose(s, d, {"condition": id, "ends": {"rest": "long"}, "source": {"kind": "master", "name": "мастер"}})


func test_a_cursed_ring_of_friendship_makes_persuasion_against_its_wearer_easy() -> void:
	var d := TestUtils.data().duplicate(true)
	var s := TestUtils.new_session()
	MakeRules.install(d, s.generated)
	var st := _status(s, d, "friend", [{"part": "against", "value": "persuasion", "amount": 1}])
	assert_bool(bool(MakeRules.def_of(d, st).get("harm", false))).is_true()  # a boon to the others is a harm to it
	s.items["gen_ring_friend"] = {"name": "Кольцо дружбы", "item_type": "wondrous", "rarity": "rare", "value_cp": 50000, "description": "Кольцо.",
		"properties": ["cursed"], "wear": {"status": st}}
	var spec := {"skill": "persuasion", "target_id": "npc_mercenary"}
	assert_array(CheckEngine.situation(s, d, Sheet.HERO, spec)["adv"]).is_empty()
	Gear.give(s, d, "npc_mercenary", "gen_ring_friend")
	assert_str(str(Gear.of(s, d, "npc_mercenary")["equipped"].get("ring1", ""))).is_equal("gen_ring_friend")
	assert_array(CheckEngine.situation(s, d, Sheet.HERO, spec)["adv"]).contains(["Кольцо дружбы"])
	assert_array(CheckEngine.situation(s, d, Sheet.HERO, {"skill": "intimidation", "target_id": "npc_mercenary"})["adv"]).is_empty()
	assert_str(Equip.off_why(s, d, "npc_mercenary", "ring1")).is_equal("ITEM_CURSED")


func test_damage_immunity_and_vulnerability_of_a_made_status() -> void:
	var d := TestUtils.data().duplicate(true)
	var s := TestUtils.new_session()
	MakeRules.install(d, s.generated)
	_lay(s, d, _status(s, d, "salamander", [{"part": "damage", "value": "fire", "amount": 2}, {"part": "damage", "value": "cold", "amount": -1}]))
	assert_int(Sheet.taken(s, d, Sheet.HERO, "fire", 10)).is_equal(0)
	assert_int(Sheet.taken(s, d, Sheet.HERO, "cold", 10)).is_equal(20)


func test_a_condition_part_guards_or_weakens_the_saves() -> void:
	var d := TestUtils.data().duplicate(true)
	var s := TestUtils.new_session()
	MakeRules.install(d, s.generated)
	_lay(s, d, _status(s, d, "calm", [{"part": "condition", "value": "charmed", "amount": 2}, {"part": "condition", "value": "frightened", "amount": -1}]))
	assert_str(HeroDefense.immune(s, d, Sheet.HERO, "charmed", "")).is_not_empty()
	var tag := HeroDefense.cond_tags(d, ["frightened"])
	assert_bool(bool(Sheet.save_odds(s, d, Sheet.HERO, "wis", tag)["dis"])).is_true()
	assert_bool(bool(Sheet.save_odds(s, d, Sheet.HERO, "wis", "")["dis"])).is_false()


func test_a_check_part_gives_advantage_or_disadvantage() -> void:
	var d := TestUtils.data().duplicate(true)
	var s := TestUtils.new_session()
	MakeRules.install(d, s.generated)
	_lay(s, d, _status(s, d, "cat", [{"part": "check", "value": "stealth", "amount": 1}, {"part": "save", "value": "all", "amount": -1}]))
	assert_array(CheckEngine.situation(s, d, Sheet.HERO, {"skill": "stealth"})["adv"]).contains(["мастер"])  # by the one who laid it
	assert_array(CheckEngine.situation(s, d, Sheet.HERO, {"skill": "athletics"})["adv"]).is_empty()
	assert_bool(bool(Sheet.save_odds(s, d, Sheet.HERO, "con")["dis"])).is_true()


## The master sees what a person of the scene wears and holds, by the slots its `equip` names.
func test_the_snapshot_shows_a_persons_gear() -> void:
	var s := TestUtils.new_session()
	var lines: Array = TurnSnapshot._wears(s, data, "npc_captain")
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("armor: ") and l.ends_with("[splint_armor]"))).is_true()
	Equip.off(s, data, "npc_captain", "armor")
	lines = TurnSnapshot._wears(s, data, "npc_captain")
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("armor: "))).is_false()
