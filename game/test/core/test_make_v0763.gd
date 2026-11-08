extends GdUnitTestSuite
## v0.7.63: the master builds a status, a skill and a passive trait out of parts: the engine prices them, a thing reaches
## the hero only through the world, what the parts do not cover is refused.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _hero(level: int = 5) -> GameSession:
	var s := TestUtils.new_session()
	s.character["level"] = level
	s.mode = GameSession.MODE_EXPLORATION
	MakeRules.install(data, s.generated)
	return s


func _rot() -> Dictionary:
	return {"kind": "make", "what": "status", "key": "rot", "name": "Чёрная вода", "text": "Слабость от проклятой воды.",
		"parts": [{"part": "check", "value": "all", "amount": -1}, {"part": "ac", "amount": -1}]}


func _made(s: GameSession, e: Dictionary) -> Dictionary:
	var p := MakeRules.plan(s, data, e)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	return p["plan"]


func test_the_price_is_the_sum_of_the_parts_and_the_tier_of_the_sum() -> void:
	var p := MakeRules.price(data, "x", [{"part": "attack", "value": "advantage"}, {"part": "ac", "amount": 2}])
	assert_int(int(p["points"])).is_equal(7)
	assert_str(str(MakeRules.tier(data, 7)["name"])).is_equal("сильное")
	assert_bool(bool(p["boon"])).is_true()
	assert_bool(bool(p["harm"])).is_false()
	assert_bool(bool(MakeRules.price(data, "x", [{"part": "attack", "value": "disadvantage"}])["harm"])).is_true()


func test_a_strong_thing_cannot_be_given_to_a_weak_hero_nor_priced_down() -> void:
	var strong := {"kind": "make", "what": "status", "key": "k", "name": "Сила", "text": "Очень сильно.",
		"parts": [{"part": "attack", "value": "advantage"}, {"part": "ac", "amount": 2}]}
	assert_str(str(MakeRules.plan(_hero(1), data, strong).get("reason", ""))).contains("уровня")
	assert_bool(MakeRules.plan(_hero(5), data, strong).has("plan")).is_true()
	var mighty: Dictionary = strong.duplicate(true)
	(mighty["parts"] as Array).append_array([{"part": "attacked", "value": "disadvantage"}, {"part": "damage", "value": "fire", "amount": 1},
		{"part": "damage", "value": "cold", "amount": 1}, {"part": "damage", "value": "acid", "amount": 1}])
	assert_str(str(MakeRules.plan(_hero(20), data, mighty).get("reason", ""))).contains("не собирает")


func test_what_the_parts_do_not_cover_is_refused() -> void:
	var s := _hero()
	var e := _rot()
	(e["parts"] as Array).append({"part": "fly"})
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("части fly нет")
	e = _rot()
	e["parts"] = [{"part": "ac", "amount": 9}]
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("amount")
	e = _rot()
	e["parts"] = []
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("parts")


func test_a_made_status_works_as_any_on_the_hero() -> void:
	var s := _hero()
	var ac := int(s.character["ac"])
	var id := str(_made(s, _rot())["id"])
	assert_bool(ConditionRules.known(data, id)).is_true()
	ConditionRules.impose(s, data, {"condition": id, "ends": {"rest": "long"}, "source": {"kind": "master", "name": "колодец"}})
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(int(s.character["ac"])).is_equal(ac - 1)
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, {"skill": "athletics"})["dis"]).contains(["колодец"])  # v0.8.4.40: the part `check`
	var chip: Dictionary = ConditionRules.shown(s, data).filter(func(e: Dictionary) -> bool: return e["condition"] == id)[0]
	assert_str(str(chip["name"])).is_equal("Чёрная вода")
	assert_str(str(chip["text"])).contains("проклятой воды")


func test_a_made_status_works_on_a_foe() -> void:
	var s := _hero()
	var id := str(_made(s, {"kind": "make", "what": "status", "key": "k", "name": "Морок", "text": "Промахивается.",
		"parts": [{"part": "attack", "value": "disadvantage"}, {"part": "speed", "amount": -10}]})["id"])
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	CombatRules._add_condition(s, data, f, id, {"rounds": 3})
	assert_array(ConditionRules.attack(data, f, {}, true)["dis"]).contains(["Морок"])
	assert_int(ConditionRules.sum(f, "speed")).is_equal(-10)


func test_the_condition_effect_lays_it_in_the_same_turn_harm_with_a_save() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var make := _plan_of(engine, s, _rot(), [])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": make["plan"]}]
	var e := {"kind": "condition", "condition": "new:rot", "reason": "выпил из колодца", "on": true}
	assert_str(str(engine._plan(s, data, "t", e, pending).get("reason", ""))).contains("спасброск")
	e["save"] = {"ability": "con", "dc_tier": "easy"}
	assert_bool(engine._plan(s, data, "t", e, pending).has("plan")).is_true()


func test_a_good_status_needs_no_save() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var make := _plan_of(engine, s, {"kind": "make", "what": "status", "key": "k", "name": "Милость родника", "text": "Вода придаёт сил.",
		"parts": [{"part": "skill_bonus", "value": "athletics", "amount": 2}]}, [])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": make["plan"]}]
	var p := engine._plan(s, data, "t", {"kind": "condition", "condition": "new:k", "reason": "напился из родника", "on": true}, pending)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()


func _plan_of(engine: EffectEngine, s: GameSession, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	return engine._plan(s, data, "t", e, pending)


func test_a_made_skill_is_on_every_sheet_and_learned_only_by_a_course() -> void:
	var s := _hero()
	var plan := _made(s, {"kind": "make", "what": "skill", "key": "foam", "name": "Чтение пены", "text": "Угадывать погоду по пиву.", "ability": "wis"})
	var id := str(plan["id"])
	assert_bool((s.character["skills"] as Dictionary).has(id)).is_true()
	assert_str(tr("SKILL_" + id.to_upper())).is_equal("Чтение пены")
	assert_bool((s.character.get("skill_profs", []) as Array).has(id)).is_false()
	var made := StudyRules.make(s, data, {"npc_id": "npc_innkeeper", "name": "Чтение пены", "teach_kind": "skill", "teach_id": id, "lessons": 4, "fee_cp": 400})
	assert_bool(made.has("plan")).override_failure_message(str(made)).is_true()
	StudyRules.apply_make(s, data, made["plan"])
	StudyRules.grant(s, data, str(made["plan"]["id"]))
	assert_bool((s.character["skill_profs"] as Array).has(id)).is_true()


func test_a_trait_is_a_status_with_no_end_taught_by_a_course_and_not_lifted_by_words() -> void:
	var s := _hero()
	var ac := int(s.character["ac"])
	var id := str(_made(s, {"kind": "make", "what": "trait", "key": "skin", "name": "Дублёная кожа", "text": "Удар скользит по коже.",
		"parts": [{"part": "ac", "amount": 1}]})["id"])
	var made := StudyRules.make(s, data, {"npc_id": "npc_innkeeper", "name": "Закалка", "teach_kind": "trait", "teach_id": id, "lessons": 4, "fee_cp": 400})
	assert_bool(made.has("plan")).override_failure_message(str(made)).is_true()
	StudyRules.apply_make(s, data, made["plan"])
	assert_bool(StudyRules.known_already(s, data, str(made["plan"]["id"]))).is_false()
	StudyRules.grant(s, data, str(made["plan"]["id"]))
	assert_int(int(s.character["ac"])).is_equal(ac + 1)
	assert_bool(StudyRules.known_already(s, data, str(made["plan"]["id"]))).is_true()
	ConditionRules.clear_on_rest(s.character, "long")
	assert_bool(ConditionRules.has(s.character, id)).is_true()
	var off := EffectEngine.new()._plan(s, data, "t", {"kind": "condition", "condition": id, "on": false}, [] as Array[Dictionary])
	assert_str(str(off.get("reason", ""))).contains("черта")


func test_a_trait_costs_double_and_must_help() -> void:
	var s := _hero(1)
	var e := {"kind": "make", "what": "trait", "key": "k", "name": "Кожа", "text": "Твёрже камня.", "parts": [{"part": "ac", "amount": 2}]}
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("уровня")  # 4 × 2 = 8 points
	e["parts"] = [{"part": "check", "value": "all", "amount": -1}]
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("без пользы")


func test_a_book_teaches_what_was_made_and_goes_by_give_item() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var make := _plan_of(engine, s, {"kind": "make", "what": "skill", "key": "foam", "name": "Чтение пены", "text": "Угадывать погоду по пиву.",
		"ability": "wis", "book": "Записки пивовара"}, [])
	MakeRules.apply(s, data, make["plan"])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": make["plan"]}]
	var book := MakeRules.resolve(pending, "new:book:foam")
	assert_str(book).starts_with("gen_book_")
	assert_str(ItemRules.def_of(data["items"], s.items, book).get("name", "")).is_equal("Записки пивовара")
	assert_array(StudyRules.books(s, data)).is_empty()
	s.character["inventory"][book] = 1
	assert_array(StudyRules.books(s, data)).has_size(1)
	var course := StudyRules.books(s, data)[0]
	assert_str(StudyRules.lesson_why(s, data, course)).is_empty()
	StudyRules.grant(s, data, course)
	assert_bool((s.character["skill_profs"] as Array).has(str(make["plan"]["id"]))).is_true()


func test_a_status_has_no_book() -> void:
	var e := _rot()
	e["book"] = "Трактат"
	assert_str(str(MakeRules.plan(_hero(), data, e).get("reason", ""))).contains("книга")


func test_a_guise_is_a_part_with_the_dc_of_its_tier() -> void:
	var s := _hero()
	var id := str(_made(s, {"kind": "make", "what": "status", "key": "k", "name": "Чужое лицо", "text": "Морок на лице.",
		"parts": [{"part": "guise", "value": "Старый нищий"}]})["id"])
	ConditionRules.impose(s, data, {"condition": id, "ends": {"rest": "long"}, "source": {"kind": "master", "name": "морок"}})
	assert_str(Guise.face(s.character)).is_equal("Старый нищий")
	assert_int(int(Guise.of(s.character)["dc"])).is_equal(int(data["rules"]["dc_tiers"]["easy"]))


func test_what_was_made_stays_in_the_save_and_leaves_with_another_game() -> void:
	var s := _hero()
	var id := str(_made(s, _rot())["id"])
	var skill := str(_made(s, {"kind": "make", "what": "skill", "key": "f", "name": "Чтение пены", "text": "Угадывать погоду.", "ability": "wis"})["id"])
	assert_str(MakeRules.text(s, data)).contains("Чёрная вода").contains(id)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	MakeRules.install(data, {})
	assert_bool(ConditionRules.known(data, id)).is_false()
	assert_bool((data["rules"]["skills"] as Dictionary).has(skill)).is_false()
	MakeRules.install(data, back.generated)
	assert_bool(ConditionRules.known(data, id)).is_true()
	assert_str(str(data["rules"]["skills"][skill])).is_equal("wis")


func test_the_master_sees_what_was_made() -> void:
	var s := _hero()
	_made(s, _rot())
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"]["made"])).contains("Чёрная вода")


func test_every_number_of_a_status_reaches_the_rules_of_the_hero() -> void:
	var s := _hero(9)
	var c := s.character
	var speed := CharacterRules.speed(c, data)
	var id := str(_made(s, {"kind": "make", "what": "status", "key": "k", "name": "Милость", "text": "Много всего.", "parts": [
		{"part": "speed", "amount": 10}, {"part": "damage", "value": "fire", "amount": 1}, {"part": "save", "value": "wis", "amount": 1},
		{"part": "skill_bonus", "value": "athletics", "amount": 3}, {"part": "die", "value": "check", "amount": 1}]})["id"])
	ConditionRules.impose(s, data, {"condition": id, "ends": {"rest": "long"}, "source": {"kind": "master", "name": "родник"}})
	assert_int(CharacterRules.speed(c, data)).is_equal(speed + 10)
	assert_bool(ConditionRules.resisted(c, "fire")).is_true()
	assert_str(SpellEffects.save_adv(c, "wis")).is_not_empty()
	assert_int(int(SpellEffects.hero_effects(c, "skill_bonus")[0]["skill_bonus"]["athletics"])).is_equal(3)
	assert_int(int(SpellEffects.die(s, c, "check")["bonus"])).is_greater(0)


func test_a_book_of_this_turn_goes_by_give_item_and_as_a_quest_reward() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var make := _plan_of(engine, s, {"kind": "make", "what": "trait", "key": "skin", "name": "Дублёная кожа", "text": "Удар скользит по коже.",
		"parts": [{"part": "ac", "amount": 1}], "book": "Трактат о коже"}, [])
	assert_bool(make.has("plan")).override_failure_message(str(make)).is_true()
	MakeRules.apply(s, data, make["plan"])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": make["plan"]}]
	var book := str(make["plan"]["book"]["id"])
	assert_str(str(engine._made_ids({"reward_item_id": "new:book:skin"}, pending)["reward_item_id"])).is_equal(book)
	var given := engine._plan(s, data, "t", {"kind": "move_item", "source": "world", "target": "hero", "item_id": "new:book:skin", "qty": 1, "reason": "награда"}, pending)
	assert_bool(given.has("plan")).override_failure_message(str(given)).is_true()


func test_a_new_key_without_its_make_is_refused_with_the_way_out() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var e := {"kind": "condition", "condition": "new:rot", "reason": "выпил из колодца", "on": true}
	assert_str(str(engine._plan(s, data, "t", e, [] as Array[Dictionary]).get("reason", ""))).contains("сначала эффект make")
	var c := {"kind": "create", "what": "course", "npc_id": "npc_innkeeper", "name": "Угли", "teach_kind": "skill", "teach_id": "new:coal", "lessons": 4, "fee_cp": 400}
	assert_str(str(engine._plan(s, data, "t", c, [] as Array[Dictionary]).get("reason", ""))).contains("сначала эффект make")
