extends GdUnitTestSuite
## One language of the class features (v0.8.4.9, ADR-0016): a class on any fighter, every feature action by one act, what a class adds
## to a blow on the one road of a blow, reactions and race traits of anybody, what the AI makes of them.

var data: Dictionary

## Who has each row of rules.feature_actions: a new row with no line here fails the first test.
const WHO := {"reckless": {"class": "barbarian", "level": 2}, "martial_strike": {"class": "monk", "level": 5, "subclass": "open_hand"},
	"flurry": {"class": "monk", "level": 5, "subclass": "open_hand"}, "flurry_topple": {"class": "monk", "level": 5, "subclass": "open_hand"},
	"flurry_push": {"class": "monk", "level": 5, "subclass": "open_hand"}, "flurry_stagger": {"class": "monk", "level": 5, "subclass": "open_hand"},
	"patient_defense": {"class": "monk", "level": 5, "subclass": "open_hand"}, "step_disengage": {"class": "monk", "level": 5, "subclass": "open_hand"},
	"step_dash": {"class": "monk", "level": 5, "subclass": "open_hand"}, "stunning": {"class": "monk", "level": 5, "subclass": "open_hand"},
	"turn_undead": {"class": "cleric", "level": 5, "subclass": "life"}, "preserve_life": {"class": "cleric", "level": 5, "subclass": "life"},
	"sacred_weapon": {"class": "paladin", "level": 5, "subclass": "devotion"}, "turn_unholy": {"class": "paladin", "level": 5, "subclass": "devotion"},
	"wild_shape": {"class": "druid", "level": 4, "subclass": "land"}, "font": {"class": "sorcerer", "level": 3, "subclass": "draconic"}, "breath": {},
	"one_with_shadows": {"class": "warlock", "level": 5}}


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String = "wizard_yalika") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["max_hp"] = 2000
	s.character["hp"] = 2000
	return s


## A fighter of `row`'s class of the template beside the hero, a goblin of its side.
func _foe(s: GameSession, row: Dictionary, monster: String = "commoner") -> Dictionary:
	var spec := row.duplicate()
	spec.merge({"monster": monster, "name": "Боец", "col": 2})
	TestUtils.fight(s, data, [spec, {"monster": "goblin", "name": "Гоблин", "col": 2}], {})
	s.mode = GameSession.MODE_COMBAT
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	f["points"] = CombatRules.fresh_points(s, data, f)
	TestUtils.beside(s, f)
	return f


func _text(lines: Array[String]) -> String:
	return "\n".join(lines)


func test_every_feature_action_goes_for_a_foe_of_its_class() -> void:
	var rows := FeatureRules.rows(data)
	for id: String in rows:
		if id.begins_with("_"):
			continue
		assert_bool(WHO.has(id)).override_failure_message("no owner for " + id).is_true()
		var s := _hero()
		var f := _foe(s, WHO[id])
		if id == "breath":
			f["traits"] = ["breath_weapon", "draconic_ancestry_red"]
			f["abilities"] = {"con": 14}
		if bool(rows[id].get("dark", false)):  # an invocation only in the dark: the tavern's cellar
			(f["features"] as Array).append("eldritch_invocation_one_with_shadows")
			s.room_id = "brod-tavern-cellar"
		CombatRules.points(s, data, f)["attacked"] = bool(rows[id].get("after_attack", false))
		var to := CombatRules.PLAYER if bool(rows[id].get("target", false)) else ""
		assert_str(Acts.one("feature").can(s, data, f, to, {"id": id})).override_failure_message(id).is_empty()
		var lines := Acts.one("feature").go(s, data, f, to, {"id": id})
		assert_bool(lines.is_empty() and id != "font").override_failure_message(id).is_false()


func test_every_fighter_with_a_template_class_has_it() -> void:
	var table: Dictionary = CombatRules.cfg(data)["classed"]
	for id: String in table:
		if id.begins_with("_"):
			continue
		assert_bool(data["monsters"].has(id)).override_failure_message(id).is_true()
		var s := _hero()
		var f := _foe(s, {}, id)
		assert_str(str(f["class"])).is_equal(str(table[id]["class"]))
		assert_int(int(f["level"])).is_equal(int(table[id]["level"]))
		assert_bool((f["features"] as Array).is_empty()).override_failure_message(id).is_false()
		assert_int(CharacterRules.prof_bonus(f, data)).is_greater_equal(2)


func test_every_classed_foe_and_every_class_plays() -> void:
	var rows: Array[Dictionary] = []
	for id: String in CombatRules.cfg(data)["classed"]:
		if not id.begins_with("_"):
			rows.append({"monster": id})
	for id: String in data["classes"]["classes"]:
		rows.append({"class": id, "level": 5, "subclass": str(data["classes"]["subclasses"].keys().filter(func(x: String) -> bool: return str(data["classes"]["subclasses"][x].get("class", "")) == id)[0])})
	for row: Dictionary in rows:
		var s := _hero()
		var f := _foe(s, row, str(row.get("monster", "guard")))
		var lines: Array[String] = []
		for i: int in 4:
			TestUtils.enemy_turn(s, data, f, lines)
			if not CombatRules.active(s) or s.combat.has("pending") or str(f.get("status")) != "active":
				break
		assert_bool(lines.is_empty()).override_failure_message(str(row)).is_false()


func test_a_rogue_foe_sneaks_by_its_class_once_a_turn() -> void:
	var s := _hero()
	var f := _foe(s, {"class": "rogue", "level": 3}, "scout")
	TestUtils.beside(s, CombatRules.fighter(s, CombatRules.enemies(s)[1]))
	var a: Dictionary = (Sheet.template(data, f)["actions"] as Array).filter(func(x: Dictionary) -> bool: return str(x["name_en"]) == "Shortsword")[0]
	var b := Attack.of_action(data, f, a)
	var p := CombatRules.player(s)
	assert_str(FeatureRules.sneak_dice(s, data, f, b, false, false, p)).is_equal("2d6")
	assert_str(FeatureRules.sneak_dice(s, data, f, b, false, true, p)).is_empty()
	CombatRules.points(s, data, f)["sneak"] = true
	assert_str(FeatureRules.sneak_dice(s, data, f, b, true, false, p)).is_empty()


func test_a_template_with_its_own_sneak_attack_does_not_roll_it_twice() -> void:
	var s := _hero()
	var f := _foe(s, {}, "spy")
	var a: Dictionary = (Sheet.template(data, f)["actions"] as Array).filter(func(x: Dictionary) -> bool: return str(x.get("kind")) == "melee")[0]
	assert_str(FeatureRules.sneak_dice(s, data, f, Attack.of_action(data, f, a), true, false, CombatRules.player(s))).is_empty()


func test_a_berserker_rages_by_the_ai_and_all_rage_gives_is_there() -> void:
	var s := _hero()
	var f := _foe(s, {}, "berserker")
	var lines: Array[String] = []
	FightAI.first(s, data, f, lines)
	assert_bool(bool(f["raging"])).is_true()
	assert_int(int(CombatRules.points(s, data, f)["bonus"])).is_equal(0)
	assert_int(Sheet.taken(s, data, f, "slashing", 10, false)).is_equal(5)
	assert_array(Sheet._advantages(s, data, f, "str", "")).contains(["ярость"])
	var b := Attack.blade(s, data, f)
	assert_int(FeatureRules.rage_bonus(s, data, f, b, CombatRules.player(s))).is_equal(2)
	assert_str(Acts.one("feature").can(s, data, f, "", {"stock": "rage"})).is_not_empty()
	FeatureRules.end_turn(s, f, lines)
	assert_bool(bool(f["raging"])).is_false()
	assert_str(_text(lines)).contains("Ярость угасает")


func test_frenzy_is_a_blow_for_the_bonus_action_of_anyone_in_it() -> void:
	var s := _hero()
	var f := _foe(s, {}, "berserker")
	f["raging"] = true
	var lines: Array[String] = []
	FightAI.first(s, data, f, lines)
	assert_bool(bool(f["frenzy"])).is_true()
	FightAI.last(s, data, f, lines)
	assert_int(int(CombatRules.points(s, data, f)["bonus"])).is_equal(0)
	assert_str(_text(lines)).contains("против КД")


func test_second_wind_only_when_it_is_hurt() -> void:
	var s := _hero()
	var f := _foe(s, {"class": "fighter", "level": 3}, "guard")
	var lines: Array[String] = []
	FightAI.first(s, data, f, lines)
	assert_int(Stock.left(f, data, "second_wind")).is_equal(1)
	f["hp"] = 1
	FightAI.first(s, data, f, lines)
	assert_int(int(f["hp"])).is_greater(1)
	assert_int(Stock.left(f, data, "second_wind")).is_equal(0)


func test_action_surge_gives_a_veteran_its_whole_action_twice() -> void:
	var s := _hero("fighter_aira")
	var f := _foe(s, {}, "veteran")
	var blows := (Sheet.template(data, f)["multiattack"] as Array).reduce(func(n: int, x: Dictionary) -> int: return n + int(x["count"]), 0) as int
	var lines: Array[String] = []
	FightAI.act(s, data, f, lines)
	assert_int(Stock.left(f, data, "action_surge")).is_equal(0)
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("против КД")).size()).override_failure_message(_text(lines)).is_greater_equal(blows * 2)


func test_extra_attack_of_a_class_on_a_template_without_multiattack() -> void:
	var s := _hero()
	var f := _foe(s, {"class": "fighter", "level": 5})
	var a: Dictionary = Sheet.template(data, f)["actions"][0]
	assert_int(Attack._plan(s, data, f, CombatRules.player(s), a).size()).is_equal(2)


func test_a_rogue_foe_halves_a_blow_with_its_reaction() -> void:
	var s := _hero("fighter_aira")
	var f := _foe(s, {"class": "rogue", "level": 5})
	f["ac"] = 1
	f["hp"] = 5000
	f["max_hp"] = 5000
	var said := ""
	for i: int in 30:
		f["reacted"] = false
		var lines: Array[String] = []
		Attack.swing(s, data, CombatRules.player(s), f, Attack.blade(s, data, CombatRules.player(s)), lines)
		said += _text(lines)
	assert_str(said).contains("Невероятное уклонение")


func test_a_paladin_foe_smites_with_its_own_slots() -> void:
	var s := _hero()
	var f := _foe(s, {"class": "paladin", "level": 3}, "guard")
	assert_int(SpellRules.slots_left(f, 1)).is_greater(0)
	var lines: Array[String] = []
	var hp := int(s.character["hp"])
	FeatureRules.after_hit(s, data, f, Attack.blade(s, data, f), CombatRules.player(s), false, {}, lines)
	assert_int(int(s.character["hp"])).is_less(hp)
	assert_int(Stock.spent(f, "slot_1")).is_equal(1)


func test_a_druid_foe_turns_into_a_beast_and_back() -> void:
	var s := _hero()
	var f := _foe(s, {}, "druid")
	var hp := int(f["hp"])
	var lines := Acts.one("feature").go(s, data, f, "", {"id": "wild_shape"})
	assert_str(str(Sheet.template(data, f)["type"])).is_equal("beast")
	assert_bool(Attack.way(s, data, f, {"action": "Quarterstaff"}).is_empty()).is_true()  # the beast's blows, not its staff
	assert_array(MonsterRules.castable(data, f)).is_empty()
	assert_int(CombatRules.ac_of(f)).is_equal(int(Guise.body(f)["ac"]))
	assert_int(int(CombatRules.points(s, data, f)["action"])).is_equal(0)
	var body := int(Guise.body(f)["hp"])
	Harm.take(s, data, f, body + 3, lines, "slashing", false, true)
	assert_bool(Guise.has_body(f)).is_false()
	assert_str(str(Sheet.template(data, f)["type"])).is_equal("humanoid")
	assert_bool(Attack.way(s, data, f, {"action": "Quarterstaff"}).is_empty()).is_false()
	assert_int(int(f["hp"])).is_equal(hp - 3)


func test_a_trait_of_a_template_works_for_the_hero_who_has_it() -> void:
	var s := _hero()
	var f := _foe(s, {}, "goblin")
	var p := CombatRules.player(s)
	var other := CombatRules.fighter(s, CombatRules.enemies(s)[1])
	CombatRules.add_allies(s, data, [{"monster": "guard", "name": "Страж"}], true)
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	FightGrid.put(ally, FightGrid.free_near(s, data, FightGrid.cell(f), 1))
	assert_bool(FightGrid.touching(ally, f)).is_true()
	var b := Attack.blade(s, data, p)
	assert_bool(Attack.mods(s, data, p, f, b)["adv"].has("стайная тактика")).is_false()
	s.character["traits"].append("pack_tactics")
	assert_bool(Attack.mods(s, data, p, f, b)["adv"].has("стайная тактика")).is_true()
	assert_bool(other.is_empty()).is_false()


func test_a_race_trait_of_a_person_works_in_a_fight() -> void:
	var s := _hero()
	var f := _foe(s, {})
	assert_bool(Sheet._advantages(s, data, f, "dex", "fear").is_empty()).is_true()
	f["traits"] = ["brave"]
	assert_bool(Sheet._advantages(s, data, f, "dex", "fear").is_empty()).is_false()
	f["traits"] = ["relentless_endurance"]
	var lines: Array[String] = []
	Harm.take(s, data, f, 500, lines, "slashing", false, true)
	assert_int(int(f["hp"])).is_equal(1)
	Harm.take(s, data, f, 500, lines, "slashing", false, true)
	assert_str(str(f["status"])).is_not_equal("active")


func test_a_person_of_the_pack_brings_the_traits_of_its_race() -> void:
	var dwarf := ""
	var word := str(data["races"]["races"]["dwarf"]["name"]).to_lower()
	for id: String in data["world"]["npcs"]:
		if str(data["world"]["npcs"][id].get("race", "")).to_lower() == word:
			dwarf = id
	assert_str(dwarf).is_not_empty()
	var f := {"monster": "commoner"}
	FeatureRules.give_class(data, f, {"npc_id": dwarf})
	assert_bool((f["traits"] as Array).is_empty()).is_false()
	assert_int(int(f["abilities"]["str"])).is_equal(int(data["monsters"]["commoner"]["abilities"]["str"]))


func test_a_sorcerer_foe_pays_the_cheapest_metamagic_it_knows() -> void:
	var s := _hero()
	var f := _foe(s, {"class": "sorcerer", "level": 3})
	(f["features"] as Array).append("metamagic_quickened_spell")
	var left := Stock.left(f, data, "sorcery_points")
	assert_str(FeatureRules.pay_metamagic(s, data, f)).is_equal("quickened_spell")
	assert_int(Stock.left(f, data, "sorcery_points")).is_less(left)
	assert_bool(f.has("metamagic")).is_false()


func test_turn_undead_by_a_priest_is_an_option_only_with_undead_near() -> void:
	var s := _hero()
	var f := _foe(s, {}, "priest")
	var is_turn := func(o: Dictionary) -> bool: return str(o["how"].get("id", "")) == "turn_undead"
	var targets: Array[Dictionary] = [CombatRules.player(s)]
	assert_bool(Acts.one("feature").offers(s, data, f, targets).any(is_turn)).is_false()
	CombatRules.add_allies(s, data, [{"monster": "skeleton", "name": "Скелет"}], true, "ally", FightGrid.cell(f))
	assert_bool(Acts.one("feature").offers(s, data, f, targets).any(is_turn)).is_true()
