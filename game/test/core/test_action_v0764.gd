extends GdUnitTestSuite
## v0.7.64: one action. The master builds a spell, an ability with charges and a recipe neither the data nor 5e has; the
## engine sets the circle, the thing reaches the hero through a teacher, a book, a scroll or a quest's reward and works.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _hero(level: int = 5) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if str(p["id"]) == "wizard_yalika":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	s.character["slots_max"] = [4, 3, 3, 1, 1]
	Stock.fill_slots(s.character)
	MakeRules.install(data, s.generated)
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _fighter() -> GameSession:
	var s := TestUtils.new_session()
	MakeRules.install(data, s.generated)
	s.character["spell_ability"] = ""
	s.character.erase("spell_dc")
	s.character.erase("spell_attack")
	s.character["slots_max"] = [0, 0, 0, 0, 0]
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func _knows(s: GameSession, id: String) -> void:
	var always: Array = s.character["spells"].get("always", [])
	always.append(id)
	s.character["spells"]["always"] = always


func _bolt(extra: Array = []) -> Dictionary:
	var parts: Array = [{"part": "range", "value": "60"}, {"part": "roll", "value": "dex"}, {"part": "half"}, {"part": "damage", "value": "cold", "amount": 4}]
	parts.append_array(extra)
	return {"kind": "make", "what": "spell", "key": "frost", "name": "Иней Гнилой Топи", "text": "Иней рвёт кожу.", "parts": parts}


func _made(s: GameSession, e: Dictionary) -> Dictionary:
	var p := MakeRules.plan(s, data, e)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	return p["plan"]


func _teach(s: GameSession, kind: String, id: String) -> String:
	var made := StudyRules.make(s, data, {"npc_id": "npc_innkeeper", "name": "Наука", "teach_kind": kind, "teach_id": id, "lessons": 4, "fee_cp": 400})
	assert_bool(made.has("plan")).override_failure_message(str(made)).is_true()
	StudyRules.apply_make(s, data, made["plan"])
	return str(made["plan"]["id"])


func _circle(s: GameSession, parts: Array) -> int:
	var p := MakeRules.plan(s, data, {"kind": "make", "what": "spell", "key": "k", "name": "Проба %d" % parts.size(), "text": "Проба круга.", "parts": parts})
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	return int(p["plan"]["def"]["circle"])


func test_the_engine_sets_the_circle_and_it_is_not_asked() -> void:
	var s := _hero()
	var area := {"part": "target", "value": "area"}
	var save := {"part": "roll", "value": "dex"}
	assert_int(_circle(s, [{"part": "roll", "value": "attack"}, {"part": "damage", "value": "fire", "amount": 1}])).is_equal(0)
	assert_int(_circle(s, [area, save, {"part": "half"}, {"part": "damage", "value": "fire", "amount": 3}])).is_equal(1)
	assert_int(_circle(s, [area, save, {"part": "half"}, {"part": "damage", "value": "fire", "amount": 8}])).is_equal(3)
	assert_int(_circle(s, [area, save, {"part": "half"}, {"part": "damage", "value": "fire", "amount": 10}])).is_equal(5)
	assert_int(_circle(s, [save, {"part": "lay", "value": "paralyzed"}, {"part": "lasts", "value": "minute"}, {"part": "concentration"}, {"part": "repeat"}])).is_equal(2)


func test_a_circle_cannot_be_priced_down_nor_past_the_limit() -> void:
	var s := _hero()
	var e := _bolt()
	e["level"] = 0  # no such field: the sum decides
	e["circle"] = 0
	assert_int(int(MakeRules.plan(s, data, e)["plan"]["def"]["circle"])).is_equal(1)
	var huge := {"kind": "make", "what": "spell", "key": "h", "name": "Конец света", "text": "Всё горит.", "parts": [{"part": "target", "value": "area"},
		{"part": "roll", "value": "dex"}, {"part": "damage", "value": "fire", "amount": 20}]}
	assert_str(str(MakeRules.plan(s, data, huge).get("reason", ""))).contains("не собирает")


func test_what_the_parts_do_not_cover_is_refused() -> void:
	var s := _hero()
	var e := _bolt([{"part": "time_stop"}])
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("части time_stop нет")
	var bad := {"kind": "make", "what": "spell", "key": "b", "name": "Ничто", "text": "Ничего не делает.", "parts": [{"part": "range", "value": "60"}]}
	assert_str(str(MakeRules.plan(s, data, bad).get("reason", ""))).contains("эффект")
	bad["parts"] = [{"part": "damage", "value": "fire", "amount": 2}]
	assert_str(str(MakeRules.plan(s, data, bad).get("reason", ""))).contains("roll")
	bad["parts"] = [{"part": "roll", "value": "dex"}, {"part": "lay", "value": "exhaustion"}]
	assert_str(str(MakeRules.plan(s, data, bad).get("reason", ""))).contains("так не положить")


func test_a_built_spell_reads_like_an_srd_one() -> void:
	var s := _hero()
	var id := str(_made(s, _bolt())["id"])
	var sp: Dictionary = data["spells"][id]
	assert_int(int(sp["level"])).is_equal(1)
	assert_dict(sp["save"]).is_equal({"ability": "dex", "success": "half"})
	assert_str(str(sp["damage_at_slot"]["1"])).is_equal("4d6")
	assert_str(str(sp["damage_at_slot"]["3"])).is_equal("6d6")
	assert_bool(CombatRules.is_engine_spell(data, id)).is_true()
	assert_array(SpellRules.prepare_pool(s.character, data)["pool"]).not_contains([id])
	assert_str(SpellRules.describe(data, id, 1)).contains("Иней Гнилой Топи")


func test_a_spell_by_a_teacher_is_cast_with_a_slot_and_hurts_a_foe() -> void:
	var s := _hero()
	var id := str(_made(s, _bolt())["id"])
	assert_bool(SpellRules.ready(s.character).has(id)).is_false()
	var course := _teach(s, "spell", id)
	assert_array(StudyRules.requirements(s, data, course).filter(func(r: Dictionary) -> bool: return not bool(r["ok"]))).is_empty()
	StudyRules.grant(s, data, course)
	assert_bool(SpellRules.ready(s.character).has(id)).is_true()
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	var t := foes[0]
	t["hp"] = 200
	t["max_hp"] = 200
	assert_str(CombatRules.can_cast(s, data, id, 1, str(t["id"]))).is_empty()
	var lines := CombatRules.player_cast(s, data, id, 1, str(t["id"]))
	assert_str(" ".join(lines)).contains("Иней Гнилой Топи")
	assert_int(int(t["hp"])).is_less(200)
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(3)


func test_a_spell_of_a_book_is_learned_by_reading() -> void:
	var s := _hero()
	var e := _bolt()
	e["book"] = "Записки о Гнилой Топи"
	var engine := EffectEngine.new()
	var plan := MakeRules.plan(s, data, e)
	MakeRules.apply(s, data, plan["plan"])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": plan["plan"]}]
	var given := engine._plan(s, data, "t", {"kind": "move_item", "source": "world", "target": "hero", "item_id": "new:book:frost", "qty": 1, "reason": "нашёл"}, pending)
	assert_bool(given.has("plan")).override_failure_message(str(given)).is_true()
	s.character["inventory"][str(plan["plan"]["book"]["id"])] = 1
	var course := StudyRules.books(s, data)[0]
	assert_str(StudyRules.teaches_text(s, data, course)).contains("Иней Гнилой Топи")
	StudyRules.grant(s, data, course)
	assert_bool(SpellRules.ready(s.character).has(str(plan["plan"]["id"]))).is_true()


func test_a_scroll_casts_it_without_a_slot_and_by_its_own_numbers() -> void:
	var s := _hero()
	var e := _bolt()
	e["scroll"] = "Свиток инея"
	var plan := _made(s, e)
	var scroll := str(plan["scroll"]["id"])
	var pending: Array[Dictionary] = [{"kind": "make", "plan": plan}]
	assert_str(MakeRules.resolve(pending, "new:scroll:frost")).is_equal(scroll)
	s.character["inventory"][scroll] = 1
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	var t := foes[0]
	t["hp"] = 200
	t["max_hp"] = 200
	assert_str(CombatRules.can_item_spell(s, data, scroll, str(t["id"]))).is_empty()
	var dc_before := int(s.character["spell_dc"])
	var lines: Array[String] = []
	for i in 30:  # no class has it: Arcana by the rule of scrolls, a failure burns the scroll
		s.character["inventory"][scroll] = 1
		CombatRules.economy(s)["action"] = 1
		lines = CombatRules.item_spell(s, data, scroll, str(t["id"]))
		if " ".join(lines).contains("Заклинание"):
			break
	assert_str(" ".join(lines)).contains("Иней Гнилой Топи")
	assert_int(int(s.character.get("inventory", {}).get(scroll, 0))).is_equal(0)
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(4)
	assert_int(int(s.character["spell_dc"])).is_equal(dc_before)
	assert_bool(SpellRules.ready(s.character).has(str(plan["id"]))).is_false()
	assert_bool(s.combat.has("by")).is_false()


func test_a_scroll_holds_up_to_the_third_circle() -> void:
	var s := _hero()
	var e := {"kind": "make", "what": "spell", "key": "s", "name": "Буря", "text": "Буря рвёт всё.", "scroll": "Свиток бури", "parts": [{"part": "target", "value": "area"},
		{"part": "roll", "value": "dex"}, {"part": "damage", "value": "lightning", "amount": 10}]}
	assert_str(str(MakeRules.plan(s, data, e).get("reason", ""))).contains("не выше 3 круга")


func test_a_quest_reward_can_be_its_scroll() -> void:
	var s := _hero()
	var e := _bolt()
	e["scroll"] = "Свиток инея"
	var plan := _made(s, e)
	var pending: Array[Dictionary] = [{"kind": "make", "plan": plan}]
	var engine := EffectEngine.new()
	assert_str(str(engine._made_ids({"reward_item_id": "new:scroll:frost"}, pending)["reward_item_id"])).is_equal(str(plan["scroll"]["id"]))
	var missing := engine._plan(s, data, "t", {"kind": "move_item", "source": "world", "target": "hero", "item_id": "new:scroll:nope", "qty": 1}, pending)
	assert_str(str(missing.get("reason", ""))).contains("сначала эффект make")


func test_a_status_of_this_turn_is_laid_by_the_spell_and_ends_with_the_concentration() -> void:
	var s := _hero()
	var rot := _made(s, {"kind": "make", "what": "status", "key": "rot", "name": "Чёрная вода", "text": "Слабость от проклятой воды.",
		"parts": [{"part": "attack", "value": "disadvantage"}]})
	var pending: Array[Dictionary] = [{"kind": "make", "plan": rot}]
	var p := MakeRules.plan(s, data, {"kind": "make", "what": "spell", "key": "curse", "name": "Сглаз", "text": "Взгляд чернит воду в жилах.", "parts": [{"part": "roll", "value": "con"},
		{"part": "lay", "value": "new:rot"}, {"part": "lasts", "value": "minute"}, {"part": "concentration"}, {"part": "repeat"}]}, pending)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	var id := str(p["plan"]["id"])
	assert_array(data["rules"]["combat"]["condition_spells"][id]["conditions"]).contains([str(rot["id"])])
	_knows(s, id)
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	var t := foes[0]
	t["monster"] = "goblin"
	for i in 30:  # until the save fails
		s.combat["by"] = {"dc": 40}
		CombatRules._cast_condition(s, data, id, 1, t, [] as Array[String])
		s.combat.erase("by")
		if ConditionRules.has(t, str(rot["id"])):
			break
	assert_bool(ConditionRules.has(t, str(rot["id"]))).is_true()


func test_damage_with_a_status_rides_on_the_hit() -> void:
	var s := _hero()
	var id := str(_made(s, _bolt([{"part": "lay", "value": "poisoned"}, {"part": "lasts", "value": "minute"}]))["id"])
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	var t := foes[0]
	var lines: Array[String] = []
	ActionRules.riders(s, data, id, 1, t, true, lines)
	assert_bool(ConditionRules.has(t, "poisoned")).is_true()
	assert_str(" ".join(lines)).contains("отравлен")


func test_a_healing_spell_heals_an_ally_or_the_hero_out_of_a_fight() -> void:
	var s := _hero()
	var id := str(_made(s, {"kind": "make", "what": "spell", "key": "h", "name": "Роса", "text": "Роса закрывает раны.", "parts": [{"part": "heal", "amount": 2}]})["id"])
	assert_int(int(data["spells"][id]["level"])).is_equal(1)
	assert_str(str(data["spells"][id]["heal_at_slot"]["2"])).is_equal("3d6+MOD")
	_knows(s, id)
	s.character["hp"] = 1
	var lines := SpellRules.cast(s.character, data, id, 1, s, true)
	assert_int(int(s.character["hp"])).is_greater(1)
	assert_str(" ".join(lines)).contains("HP")


func test_a_boon_lands_on_the_hero_with_its_numbers() -> void:
	var s := _hero()
	var skin := _made(s, {"kind": "make", "what": "status", "key": "skin", "name": "Каменная кожа", "text": "Кожа твердеет.", "parts": [{"part": "ac", "amount": 2}]})
	var pending: Array[Dictionary] = [{"kind": "make", "plan": skin}]
	var p := MakeRules.plan(s, data, {"kind": "make", "what": "spell", "key": "sk", "name": "Отвердение", "text": "Кожа твердеет на минуту.",
		"parts": [{"part": "target", "value": "self"}, {"part": "lay", "value": "new:skin"}, {"part": "lasts", "value": "minute"}]}, pending)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	var id := str(p["plan"]["id"])
	assert_bool(SpellEffects.self_spell(data, id)).is_true()
	var ac := int(s.character["ac"])
	_knows(s, id)
	SpellRules.cast(s.character, data, id, 1, s, true)
	assert_bool(ConditionRules.has(s.character, str(skin["id"]))).is_true()
	assert_int(int(s.character["ac"])).is_equal(ac + 2)


func test_a_reaction_answers_a_hit() -> void:
	var s := _hero()
	var id := str(_made(s, {"kind": "make", "what": "spell", "key": "r", "name": "Шипы", "text": "Шипы бьют обидчика.", "parts": [{"part": "cast", "value": "reaction"},
		{"part": "roll", "value": "dex"}, {"part": "half"}, {"part": "damage", "value": "piercing", "amount": 2}]})["id"])
	_knows(s, id)
	assert_int(int(data["spells"][id]["level"])).is_equal(1)
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	assert_str(CombatRules.can_cast(s, data, id, 1, str(foes[0]["id"]))).is_equal("COMBAT_REACTION_SPELL")
	var options := SpellEffects.hit_reactions(s, data, {"dmg": 5, "total": 15, "ac": 12})
	assert_bool(options.any(func(o: Dictionary) -> bool: return str(o["id"]) == "spell_" + id)).is_true()
	var ctx := {"dmg": 5}
	var t := foes[0]
	t["hp"] = 200
	t["max_hp"] = 200
	var lines: Array[String] = []
	SpellEffects.apply_hit_reaction(s, data, t, "spell_" + id, ctx, lines)
	SpellEffects.rebuke(s, data, t, str(ctx["rebuke_spell"]), int(ctx["rebuke"]), lines)
	assert_str(" ".join(lines)).contains("Шипы")


func _ability(uses: int = 2) -> Dictionary:
	return {"kind": "make", "what": "ability", "key": "roar", "name": "Рёв кабана", "text": "Рёв рвёт строй.", "ability": "con", "parts": [{"part": "roll", "value": "wis"},
		{"part": "target", "value": "area"}, {"part": "damage", "value": "thunder", "amount": 1}, {"part": "uses", "amount": uses}, {"part": "recharge", "value": "short"}]}


func test_an_ability_needs_a_level_by_its_price() -> void:
	assert_str(str(MakeRules.plan(_fighter(), data, _ability(5)).get("reason", ""))).contains("уровня")
	var s := _fighter()
	s.character["level"] = 5
	assert_bool(MakeRules.plan(s, data, _ability(5)).has("plan")).is_true()


func test_an_ability_by_a_course_works_for_a_fighter_with_its_charges_and_comes_back_after_a_rest() -> void:
	var s := _fighter()
	s.character["level"] = 3
	var id := str(_made(s, _ability(1))["id"])
	assert_bool(Stock.owned(s.character, data).has(id)).is_false()
	var course := _teach(s, "ability", id)
	assert_array(StudyRules.requirements(s, data, course).filter(func(r: Dictionary) -> bool: return not bool(r["ok"]))).is_empty()
	StudyRules.grant(s, data, course)
	assert_bool(Stock.owned(s.character, data).has(id)).is_true()
	assert_int(Stock.left(s.character, data, id)).is_equal(1)
	assert_str(Stock.display_name(s.character, data, id)).is_equal("Рёв кабана")
	var foes := _fight(s, [{"monster": "goblin", "col": 1}])
	var t := foes[0]
	t["hp"] = 100
	t["max_hp"] = 100
	var dc := 8 + CharacterRules.prof_bonus(s.character, data) + CharacterRules.mod(CharacterRules.ability(s.character, "con"))
	assert_int(int(ActionRules.numbers(s, data, id)["dc"])).is_equal(dc)
	assert_str(CombatRules.can_cast(s, data, id, 0, str(t["id"]))).is_empty()
	var lines := CombatRules.player_cast(s, data, id, 0, str(t["id"]))
	assert_str(" ".join(lines)).contains("Рёв кабана")
	assert_int(Stock.left(s.character, data, id)).is_equal(0)
	CombatRules.economy(s)["action"] = 1
	assert_str(CombatRules.can_cast(s, data, id, 0, str(t["id"]))).contains("заряды кончились")
	Stock.recharge_all(s.character, data, "short")
	assert_int(Stock.left(s.character, data, id)).is_equal(1)


func test_what_was_built_stays_in_the_save_and_leaves_with_another_game() -> void:
	var s := _hero()
	var id := str(_made(s, _bolt([{"part": "lay", "value": "poisoned"}]))["id"])
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	var other: Dictionary = TestUtils.data().duplicate(true)
	MakeRules.install(other, back.generated)
	assert_int(int(other["spells"][id]["level"])).is_equal(int(data["spells"][id]["level"]))
	assert_int(typeof(other["spells"][id]["level"])).is_equal(TYPE_INT)
	assert_bool(other["rules"]["combat"]["riders"].has(id)).is_true()
	assert_bool((other["rules"]["combat"]["engine_spells"] as Array).has(id)).is_true()
	MakeRules.install(other, {})
	assert_bool(other["spells"].has(id)).is_false()
	assert_bool(other["rules"]["combat"]["riders"].has(id)).is_false()
	assert_bool((other["rules"]["combat"]["engine_spells"] as Array).has(id)).is_false()


func _smith() -> GameSession:
	var s := TestUtils.new_session()
	MakeRules.install(data, s.generated)
	s.settings["needs"] = false
	var c := s.character
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["inventory"]["iron_bar"] = 2
	c["gold_cp"] = 5000
	s.room_id = "brod-smithy"
	s.minute = 12 * 60
	return s


func _recipe() -> Dictionary:
	return {"kind": "create", "what": "recipe", "key": "bell", "name": "Колокольчик от мавок", "tool": "smiths_tools", "station": "forge", "hours": 1, "dc_tier": "very_easy",
		"materials": [{"item_id": "iron_bar", "qty": 1}], "output": {"name": "Колокольчик от мавок", "item_type": "gear", "rarity": "common", "value_cp": 60,
			"weight": 0.5, "description": "Звенит, и мавки сторонятся."}}


func _finish(s: GameSession, id: String) -> void:
	assert_str(CraftRules.why_not(s, data, id)).is_empty()
	CraftRules.start(s, data, id)
	CraftRules.worked(s, data, CraftRules.shift_minutes(s, data, 8))
	assert_bool(CraftRules.project(s.character).is_empty()).is_true()


func test_a_recipe_of_a_thing_no_data_has_is_taught_and_made() -> void:
	var s := _smith()
	var engine := EffectEngine.new()
	var plan := engine._plan(s, data, "t", _recipe(), [] as Array[Dictionary])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	CraftRules.apply_make(s, data, plan["plan"])
	var id := str(plan["plan"]["id"])
	assert_bool(CraftRules.known(s, data).has(id)).is_true()
	var out := str(CraftRules.recipe(s, data, id)["output"])
	assert_bool(data["items"]["catalog"].has(out)).is_false()
	_finish(s, id)
	assert_int(int(s.character["inventory"].get(out, 0)) + (s.character["inventory"] as Dictionary).keys().filter(func(k: String) -> bool:
		return str(ItemRules.def_of(data["items"], s.items, k).get("name", "")).contains("Колокольчик")).size()).is_greater(0)


func test_a_recipe_of_a_book_is_known_while_carried_and_goes_as_a_reward() -> void:
	var s := _smith()
	var engine := EffectEngine.new()
	var e := _recipe()
	e["book"] = "Записки кузнеца"
	var plan := engine._plan(s, data, "t", e, [] as Array[Dictionary])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	CraftRules.apply_make(s, data, plan["plan"])
	var id := str(plan["plan"]["id"])
	assert_bool(CraftRules.known(s, data).has(id)).is_false()
	var pending: Array[Dictionary] = [{"kind": "create:recipe", "plan": plan["plan"]}]
	var book := MakeRules.resolve(pending, "new:book:bell")
	assert_str(book).starts_with("gen_book_")
	var given := engine._plan(s, data, "t", {"kind": "move_item", "source": "world", "target": "hero", "item_id": "new:book:bell", "qty": 1, "reason": "награда"}, pending)
	assert_bool(given.has("plan")).override_failure_message(str(given)).is_true()
	assert_str(str(engine._made_ids({"reward_item_id": "new:book:bell"}, pending)["reward_item_id"])).is_equal(book)
	s.character["inventory"][book] = 1
	assert_bool(CraftRules.known(s, data).has(id)).is_true()
	_finish(s, id)


func test_a_recipe_course_teaches_a_thing_no_data_has() -> void:
	var s := _smith()
	var engine := EffectEngine.new()
	var e := {"kind": "create", "what": "course", "npc_id": "npc_smith", "name": "Колокола", "teach_kind": "recipe", "teach_id": "", "lessons": 4, "fee_cp": 400, "recipe": _recipe()}
	var plan := engine._plan(s, data, "t", e, [] as Array[Dictionary])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	StudyRules.apply_make(s, data, plan["plan"])
	var course := str(plan["plan"]["id"])
	StudyRules.grant(s, data, course)
	var id := str(StudyRules.course(s, data, course)["teaches"]["id"])
	assert_bool(CraftRules.known(s, data).has(id)).is_true()
	_finish(s, id)


func _first_circle() -> Dictionary:
	var e := {"kind": "make", "what": "spell", "key": "spark", "name": "Искра Ялики", "text": "Огонь лижет врагов вокруг.", "learn": true,
		"parts": [{"part": "target", "value": "area"}, {"part": "roll", "value": "dex"}, {"part": "half"}, {"part": "damage", "value": "fire", "amount": 3}]}
	return e


func _second_circle() -> Dictionary:
	var e := _first_circle()
	e["name"] = "Пламя Ялики"
	(e["parts"] as Array)[3]["amount"] = 5
	return e


func test_a_wizard_of_five_works_out_a_first_circle_spell_alone_at_once() -> void:
	var s := _hero()
	s.character["slots_max"] = [4, 3, 2, 0, 0]
	var plan := _made(s, _first_circle())
	assert_int(int(plan["def"]["circle"])).is_equal(1)
	assert_bool(s.character["spells"]["always"].has(str(plan["id"]))).is_true()
	assert_str(MakeRules.apply(s, data, plan)[0]).contains("Искра Ялики")


func test_past_two_circles_under_the_highest_a_spell_goes_through_the_world() -> void:
	var s := _hero()
	s.character["slots_max"] = [4, 3, 2, 0, 0]
	var p := MakeRules.plan(s, data, _second_circle())
	assert_str(str(p.get("reason", ""))).contains("сам не выведет")
	var taught := _second_circle()
	taught.erase("learn")
	assert_bool(MakeRules.plan(s, data, taught).has("plan")).is_true()


func test_a_young_caster_and_a_fighter_do_not_work_a_spell_out_alone() -> void:
	var young := _hero()
	young.character["slots_max"] = [2, 0, 0, 0, 0]
	assert_str(str(MakeRules.plan(young, data, _first_circle()).get("reason", ""))).contains("сам не выведет")
	assert_str(str(MakeRules.plan(_fighter(), data, _first_circle()).get("reason", ""))).contains("не заклинатель")


func test_only_a_spell_is_worked_out_alone() -> void:
	var e := _first_circle()
	e["what"] = "ability"
	e["ability"] = "str"
	(e["parts"] as Array).append({"part": "uses", "amount": 1})
	(e["parts"] as Array).append({"part": "recharge", "value": "long"})
	assert_str(str(MakeRules.plan(_hero(), data, e).get("reason", ""))).contains("только заклинание")


func _forge(out: Dictionary) -> Dictionary:
	return {"kind": "create", "what": "recipe", "tool": "smiths_tools", "station": "forge", "hours": 8, "dc_tier": "medium",
		"materials": [{"item_id": "iron_bar", "qty": 2}], "qty": 1}.merged(out)


func test_an_experienced_smith_gets_a_recipe_of_a_new_saber_at_once() -> void:
	var s := _smith()
	DevelopmentRules.state(s.character, "craft")["xp"] = 1200
	(DevelopmentRules.state(s.character, "craft")["skills"] as Array).append("craft:weaponsmith")
	var plan := EffectEngine.new()._plan(s, data, "t", _forge({"output": {"name": "Сабля", "item_type": "weapon", "base": "scimitar", "rarity": "common", "value_cp": 2500,
		"weight": 3.0, "description": "Лёгкий изогнутый клинок."}}), [] as Array[Dictionary])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	CraftRules.apply_make(s, data, plan["plan"])
	var id := str(plan["plan"]["id"])
	assert_bool(CraftRules.known(s, data).has(id)).is_true()
	assert_array(CraftRules.skills_missing(s.character, data, CraftRules.recipe(s, data, id))).is_empty()


func test_an_experienced_smith_gets_a_recipe_of_a_halberd_of_the_catalog_at_once() -> void:
	var s := _smith()
	(DevelopmentRules.state(s.character, "craft")["skills"] as Array).append("craft:weaponsmith")
	var plan := EffectEngine.new()._plan(s, data, "t", _forge({"output_id": "halberd"}), [] as Array[Dictionary])
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	assert_array(plan["plan"]["def"]["skills"]).contains(["craft:weaponsmith"])


func test_a_smith_without_the_skill_knows_the_recipe_but_cannot_forge_it_yet() -> void:
	var s := _smith()
	var plan := EffectEngine.new()._plan(s, data, "t", _forge({"output_id": "halberd"}), [] as Array[Dictionary])
	CraftRules.apply_make(s, data, plan["plan"])
	assert_str(CraftRules.why_not(s, data, str(plan["plan"]["id"]))).is_equal("CRAFT_NO_SKILL")


func test_who_has_no_tool_gets_no_recipe() -> void:
	var s := _smith()
	s.character["tools"] = []
	var plan := EffectEngine.new()._plan(s, data, "t", _forge({"output_id": "halberd"}), [] as Array[Dictionary])
	assert_str(str(plan.get("reason", ""))).contains("не владеет")
