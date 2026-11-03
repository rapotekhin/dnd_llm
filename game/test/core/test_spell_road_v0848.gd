extends GdUnitTestSuite
## One road of a spell (v0.8.4.8, ADR-0016): every spell of the game goes by the same act for the hero, a foe and an ally;
## what it leaves ends with its caster's concentration; the AI picks from the act's own list; every file of core/acts/ answers for anyone.

var data: Dictionary

## What an act needs to be asked at all.
const HOW := {"cast": {"spell": "fire_bolt", "slot": 0}, "item_spell": {"item": "potion_of_healing"}, "sustain": {"spell": "moonbeam"},
	"throw": {"item": "dagger"}, "use_item": {"item": "potion_of_healing"}, "field": {"how": "door"}, "parley": {"skill": "persuasion"}}


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


## A priest beside the hero, a goblin of its side, the hero's ally.
func _fight(s: GameSession, monster: String = "priest") -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "name": "Жрец", "col": 2}, {"monster": "goblin", "name": "Гоблин", "col": 2}], {"allies": [{"monster": "guard", "name": "Влада"}]})
	s.mode = GameSession.MODE_COMBAT
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	_turn(s, f)
	return f


func _turn(s: GameSession, f: Dictionary) -> void:
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	f["points"] = CombatRules.fresh_points(s, data, f)


func _other(s: GameSession) -> Dictionary:
	return CombatRules.fighter(s, CombatRules.enemies(s)[1])


func _ally(s: GameSession) -> Dictionary:
	return CombatRules.fighter(s, CombatRules.allies(s)[0])


## The spell lands as a cast of `f`: `asked` — its cost is not this test's matter.
func _land(s: GameSession, f: Dictionary, spell: String, to: String) -> Array[String]:
	return Acts.one("cast").run(s, data, f, to, {"spell": spell, "slot": int(data["spells"][spell].get("level", 0)), "asked": true})


func _left_by(h: Dictionary, spell: String) -> Array:
	return ConditionRules.effects(h).filter(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == spell and str(e.get("condition", "")) != "prone")  # a fall is its own


func test_every_spell_a_foe_casts_at_the_hero_lands_and_ends_with_it() -> void:
	for id: String in data["spells"]:
		var s := _hero()
		var f := _fight(s)
		var lines := _land(s, f, id, CombatRules.PLAYER)
		assert_bool(lines.is_empty()).override_failure_message(id).is_false()
		assert_bool(s.combat.has("by")).override_failure_message(id).is_false()
		if f.has("concentration"):  # what took holds it; what did not has nothing to keep up (ActionRules._holds)
			MonsterRules.release(s, data, f, lines)
			assert_array(_left_by(s.character, id)).override_failure_message("left %s %s" % [id, _left_by(s.character, id)]).is_empty()


func test_every_spell_a_foe_casts_at_its_own_side_lands() -> void:
	for id: String in data["spells"]:
		var s := _hero()
		var f := _fight(s)
		assert_bool(_land(s, f, id, str(_other(s)["id"])).is_empty()).override_failure_message(id).is_false()


func test_every_spell_a_foe_casts_on_itself_lands() -> void:
	for id: String in data["spells"]:
		var s := _hero()
		var f := _fight(s)
		assert_bool(_land(s, f, id, "").is_empty()).override_failure_message(id).is_false()


func test_every_spell_an_ally_casts_at_a_foe_lands() -> void:
	for id: String in data["spells"]:
		var s := _hero()
		var f := _fight(s)
		var a := _ally(s)
		_turn(s, a)
		assert_bool(_land(s, a, id, str(f["id"])).is_empty()).override_failure_message(id).is_false()


func test_every_area_goes_on_a_square_for_anyone() -> void:
	for id: String in data["spells"]:
		if not data["spells"][id].has("area"):
			continue
		var s := _hero()
		var f := _fight(s)
		assert_bool(_land(s, f, id, FightGrid.aim_id(FightGrid.cell(CombatRules.player(s)))).is_empty()).override_failure_message(id).is_false()


func test_every_caster_of_the_base_plays_by_the_one_list() -> void:
	for id: String in data["monsters"]:
		if not data["monsters"][id].has("spellcasting"):
			continue
		var s := _hero()
		var f := _fight(s, id)
		var lines: Array[String] = []
		for i: int in 4:
			f["concentration"] = str(f.get("concentration", ""))
			TestUtils.enemy_turn(s, data, f, lines)
			if not CombatRules.active(s) or s.combat.has("pending"):
				break
		assert_bool(lines.is_empty()).override_failure_message(id).is_false()
		for k: String in f.get("slots", {}):
			assert_int(int(f["slots"][k])).override_failure_message(id).is_greater_equal(0)


func test_a_foe_shields_a_friend_as_the_hero_does() -> void:
	var s := _hero()
	var f := _fight(s)
	var g := _other(s)
	var ac := CombatRules.ac_of(g)
	_land(s, f, "shield_of_faith", str(g["id"]))
	assert_int(CombatRules.ac_of(g)).is_equal(ac + 2)


func test_a_foe_heals_a_friend_by_the_one_heal() -> void:
	var s := _hero()
	var f := _fight(s)
	var g := _other(s)
	g["hp"] = 1
	var lines := _land(s, f, "cure_wounds", str(g["id"]))
	assert_int(int(g["hp"])).is_greater(1)
	assert_str(" ".join(lines)).contains("Гоблин: +")


func test_the_hero_dispels_what_a_foe_laid_on_it() -> void:
	var s := _hero()
	var f := _fight(s, "cult_fanatic")
	s.character["abilities"]["wis"] = 1
	CharacterRules.refresh(s.character, data, s.items)
	var ok := false
	for i: int in 40:
		_land(s, f, "hold_person", CombatRules.PLAYER)
		if ConditionRules.has(s.character, "paralyzed"):
			ok = true
			break
	assert_bool(ok).is_true()
	assert_array(SpellEffects.dispellable(s, CombatRules.player(s))).is_not_empty()
	s.combat["by"] = {"dc": 13, "attack": 5, "ability": "int", "caster": CombatRules.PLAYER}
	var lines := SpellEffects.dispel(s, data, str(f["id"]))
	s.combat.erase("by")
	assert_bool(ConditionRules.has(s.character, "paralyzed")).override_failure_message(" · ".join(lines)).is_false()


func test_a_foes_zone_hits_the_other_side() -> void:
	var s := _hero()
	var f := _fight(s)
	var g := _other(s)
	TestUtils.beside(s, f)
	var hp := int(g["hp"])
	var was := int(s.character["hp"])
	_land(s, f, "spirit_guardians", "")
	FightGrid.put(g, FightGrid.cell(f) + Vector2i(0, 1))
	var lines: Array[String] = []
	for i: int in 12:
		lines.append_array(SpellEffects.zone_tick(s, data, CombatRules.player(s), "start"))
		lines.append_array(SpellEffects.zone_tick(s, data, g, "start"))
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_less(was)
	assert_int(int(g["hp"])).is_equal(hp)


func test_a_summoner_calls_its_own() -> void:
	var s := _hero()
	var f := _fight(s)
	var lines: Array[String] = []
	var n := CombatRules.enemies(s).size()
	var how := {"spell": "conjure_animals", "slot": 3, "asked": true}
	lines.append_array(Acts.one("cast").run(s, data, f, "", how))
	assert_int(CombatRules.enemies(s).size()).override_failure_message(" · ".join(lines)).is_greater(n)
	MonsterRules.release(s, data, f, lines)
	assert_int(CombatRules.enemies(s).size()).override_failure_message(" · ".join(lines)).is_equal(n)


func test_every_act_answers_for_the_hero_and_for_a_foe() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, "goblin")
	for a: Act in Acts.all():
		assert_str(a.title()).override_failure_message(a.id).is_not_empty()
		var how: Dictionary = HOW.get(a.id, {})
		for who: Dictionary in [CombatRules.player(s), f]:
			assert_str(a.cost(s, data, who, how)).override_failure_message(a.id).is_not_empty()
			a.shown(s, data, who)
			a.why(s, data, who, str(f["id"]) if who != f else CombatRules.PLAYER, how)
			a.can(s, data, who, str(f["id"]) if who != f else CombatRules.PLAYER, how)
			a.offers(s, data, who, [CombatRules.player(s)] as Array[Dictionary])


func test_a_mage_shields_itself_from_a_hit() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, "mage")
	TestUtils.beside(s, f)
	var left := int(MonsterRules.castable(data, f).filter(func(o: Dictionary) -> bool: return str(o["id"]) == "shield")[0]["slot"])
	var was := int(f["slots"][str(left)])
	var ac := CombatRules.ac_of(f)
	var lines: Array[String] = []
	assert_bool(Acts.react(s, data, f, "hit", {"foe": CombatRules.PLAYER, "total": ac + 2, "melee": true}, lines)).is_true()
	assert_int(CombatRules.ac_of(f)).is_equal(ac + 5)
	assert_int(int(f["slots"][str(left)])).is_equal(was - 1)
	assert_bool(bool(f["reacted"])).is_true()
	ConditionRules.turn_comes(f, str(f["id"]))  # its own turn comes
	assert_int(CombatRules.ac_of(f)).is_equal(ac)


func test_a_mage_counters_the_heros_spell_and_the_slot_is_gone() -> void:
	var s := _hero()
	var f := _fight(s, "mage")
	var hero := CombatRules.player(s)
	_turn(s, hero)
	var slots := SpellRules.slots_left(s.character, 1)
	var hp := int(f["hp"])
	var lines := Acts.one("cast").go(s, data, hero, str(f["id"]), {"spell": "magic_missile", "slot": 1})
	assert_str(" ".join(lines)).contains("срывается")
	assert_int(int(f["hp"])).is_equal(hp)
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(slots - 1)
	assert_bool(bool(f["reacted"])).is_true()


func test_a_cantrip_is_not_worth_a_foes_counterspell() -> void:
	var s := _hero()
	var f := _fight(s, "mage")
	var lines: Array[String] = []
	assert_bool(ActionRules.countered(s, data, CombatRules.player(s), "fire_bolt", 0, lines)).is_false()
	assert_bool(bool(f.get("reacted", false))).is_false()


func test_the_ai_lays_a_boon_on_a_friend() -> void:
	var s := _hero("fighter_aira")
	var f := _fight(s, "cult_fanatic")
	var g := _other(s)
	var offers := Acts.one("cast").offers(s, data, f, FightAI._targets(s, f))
	assert_bool(offers.any(func(o: Dictionary) -> bool: return str(o["how"]["spell"]) == "shield_of_faith" and str(o["to"]) == str(g["id"]))).is_true()
	_land(s, f, "shield_of_faith", str(g["id"]))
	var more := Acts.one("cast").offers(s, data, f, FightAI._targets(s, f))
	assert_bool(more.any(func(o: Dictionary) -> bool: return str(o["how"]["spell"]) == "shield_of_faith" and str(o["to"]) == str(g["id"]))).is_false()


## A call of an autoload is not checked by the parser: a function taken away would fall only in play.
func test_every_call_of_the_game_state_has_its_function() -> void:
	var known := {}
	for m: Dictionary in GameState.get_script().get_script_method_list():
		known[str(m["name"])] = true
	for p: Dictionary in GameState.get_script().get_script_property_list():
		known[str(p["name"])] = true
	for m: Dictionary in GameState.get_method_list():
		known[str(m["name"])] = true
	for p: Dictionary in GameState.get_property_list():
		known[str(p["name"])] = true
	var call := RegEx.create_from_string("[^a-z_](?:GameState|gs)[.]([a-z_]+)[(]")
	for dir: String in ["res://ui", "res://autoload", "res://tools/playtest"]:
		for path: String in _scripts(dir):
			for m: RegExMatch in call.search_all(FileAccess.get_file_as_string(path)):
				assert_bool(known.has(m.get_string(1))).override_failure_message("%s: %s" % [path, m.get_string(1)]).is_true()


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in ResourceLoader.list_directory(dir):
		if f.ends_with("/"):
			out.append_array(_scripts(dir + "/" + f.trim_suffix("/")))
		elif f.ends_with(".gd"):
			out.append(dir + "/" + f)
	return out
