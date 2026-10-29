extends GdUnitTestSuite
## Faith and the temple (v0.7.49): the gods of the pack and their shrines; favor by a service and donations, the
## blessing by favor (Bless's die until the long rest, not with the spell); vows broken by facts of the engine — a
## check of Deception, a theft, a murder, any crime — lose their gift until the atonement; a cleric's commandment
## broken weakens its spells; a desecration closes the god's priests; the master's `vow` and `god`.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = "brod-temple", preset: int = 0) -> GameSession:
	var s := TestUtils.new_session()
	if preset != 0:
		s.character = CharacterBuilder.build_preset(data["presets"][preset], data)
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	if not s.visited.has(room):
		s.visited.append(room)
	return s


func _preset(name: String) -> int:
	for i in (data["presets"] as Array).size():
		if str(data["presets"][i]["choices"]["name"]) == name:
			return i
	return -1


func test_the_pack_has_gods_shrines_and_a_cleric_needs_one() -> void:
	assert_bool(FaithRules.on(data)).is_true()
	var s := _session()
	assert_str(str(FaithRules.shrine(s, data, "brod-temple")["god"])).is_equal("chauntea")
	assert_str(str(FaithRules.shrine(s, data, "brod-den")["god"])).is_equal("mask")
	var branko := CharacterBuilder.build_preset(data["presets"][_preset("Бранко")], data)
	assert_str(FaithRules.hero_god(branko)).is_equal("chauntea")
	var ch := CharacterBuilder.preset_choices(data["presets"][_preset("Бранко")])
	ch["god"] = ""
	assert_array(CharacterBuilder.errors(ch, data, CharacterBuilder.STEP_DETAILS)).contains(["CC_ERR_GOD"])
	ch["god"] = "nobody"
	assert_array(CharacterBuilder.errors(ch, data, CharacterBuilder.STEP_DETAILS)).contains(["CC_ERR_GOD"])
	var aira := TestUtils.preset_choices()  # a fighter may have none
	assert_array(CharacterBuilder.errors(aira, data, CharacterBuilder.STEP_DETAILS)).not_contains(["CC_ERR_GOD"])


func test_service_donation_and_the_blessing_until_the_long_rest() -> void:
	var s := _session()
	assert_str(FaithRules.bless_why(s, data)).is_equal("FAITH_NOT_YOUR_GOD")
	assert_str(FaithRules.convert_why(s, data)).is_empty()
	FaithRules.convert(s, data)
	assert_str(FaithRules.hero_god(s.character)).is_equal("chauntea")
	assert_int(int(s.character["gold_cp"])).is_equal(100000)  # the first faith is free
	assert_str(FaithRules.bless_why(s, data)).is_equal("FAITH_LOW_FAVOR")
	FaithRules.service(s, data)
	assert_int(FaithRules.favor(s.character, "chauntea")).is_equal(10)
	assert_str(FaithRules.service_why(s, data)).is_equal("FAITH_SERVED")
	for i in 2:
		FaithRules.donate(s, data)
	assert_str(FaithRules.donate_why(s, data)).is_equal("FAITH_DONATED")
	assert_int(FaithRules.favor(s.character, "chauntea")).is_equal(20)
	assert_int(int(s.character["gold_cp"])).is_equal(99000)
	s.day += 1
	for i in 2:
		FaithRules.donate(s, data)
	assert_int(FaithRules.favor(s.character, "chauntea")).is_equal(30)
	assert_str(FaithRules.bless_why(s, data)).is_empty()
	FaithRules.bless(s, data)
	assert_str(FaithRules.bless_why(s, data)).is_equal("FAITH_BLESSED")
	var e: Dictionary = ConditionRules.effects(s.character).filter(func(x: Dictionary) -> bool: return str(x["source"]["id"]) == FaithRules.BLESS_ID)[0]
	assert_str(str(e["die"])).is_equal("1d4")
	assert_str(str(e["ends"]["rest"])).is_equal("long")
	var d := SpellEffects.hero_die(s, data, "save")
	assert_int(int(d["bonus"])).is_between(1, 4)
	assert_str(str(d["parts"][0]["label"])).contains("Благословение храма")
	SpellEffects.apply_self(s, data, "bless")  # the spell on top: one d4, not two
	var dice := 0
	for i in 20:
		dice = maxi(dice, int(SpellEffects.hero_die(s, data, "attack")["bonus"]))
	assert_int(dice).is_less_equal(4)
	ConditionRules.clear_on_rest(s.character, "long")
	assert_bool(ConditionRules.effects(s.character).any(func(x: Dictionary) -> bool: return str(x["source"]["id"]) == FaithRules.BLESS_ID)).is_false()


func test_a_vow_gives_its_gift_and_a_lie_breaks_it_until_the_atonement() -> void:
	var s := _session()
	var before := int(s.character["skills"]["persuasion"])
	assert_str(FaithRules.vow_why(s, data, "truth")).is_empty()
	FaithRules.take_vow(s, data, "truth")
	assert_int(int(s.character["skills"]["persuasion"])).is_equal(before + 2)
	var parts := RollParts.cached(s.character, data, "skill", "persuasion", s.items)
	assert_bool(parts.any(func(p: Dictionary) -> bool: return str(p["label"]) == "обет «Слово правды»" and int(p["value"]) == 2)).is_true()
	assert_array(FaithRules.deed(s, data, "check:persuasion")).is_empty()
	var lines := FaithRules.deed(s, data, "check:deception")
	assert_str(" ".join(lines)).contains("Слово правды")
	assert_int(int(s.character["skills"]["persuasion"])).is_equal(before)
	assert_array(FaithRules.broken(s.character, data)).contains_exactly(["Слово правды"])
	assert_str(FaithRules.atone_why(s, data)).is_empty()  # without a god — any shrine
	FaithRules.atone(s, data)
	assert_int(int(s.character["skills"]["persuasion"])).is_equal(before + 2)
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 2500)


func test_vows_on_theft_murder_and_any_crime() -> void:
	var s := _session("brod-square")
	s.character["faith"] = {}
	FaithRules._rw(s.character)["vows"] = [{"id": "clean_hands", "since": 1, "broken": -1}, {"id": "law", "since": 1, "broken": -1}]
	CharacterRules.refresh(s.character, data, s.items)
	var saves := int(s.character["saves"]["wis"])
	TheftRules.steal(s, data, "npc_merchant", "nothing", true)  # no such pocket entry: nothing stolen, nothing broken
	assert_array(FaithRules.broken(s.character, data)).is_empty()
	var entry: Dictionary = TheftRules.pockets(s, data, "npc_merchant")[0]
	var lines := TheftRules.steal(s, data, "npc_merchant", str(entry["id"]), true)  # unseen
	assert_str(" ".join(lines)).contains("Чистые руки")
	assert_str(" ".join(lines)).contains("Под законом")
	var s2 := _session("brod-square")
	FaithRules._rw(s2.character)["vows"] = [{"id": "no_blood", "since": 1, "broken": -1}]
	CharacterRules.refresh(s2.character, data, s2.items)
	assert_int(int(s2.character["saves"]["wis"])).is_equal(saves + 1)
	CrimeRules.on_assault(s2, data, "npc_merchant", true, "brod-square")
	assert_array(FaithRules.broken(s2.character, data)).is_empty()  # an assault is no murder
	CrimeRules.on_death(s2, data, "npc_merchant", true, "brod-square")
	assert_array(FaithRules.broken(s2.character, data)).contains_exactly(["Без крови"])
	assert_int(int(s2.character["saves"]["wis"])).is_equal(saves)


func test_a_clerics_commandment_and_the_lapse() -> void:
	var s := _session("brod-square", _preset("Бранко"))
	var dc := int(s.character["spell_dc"])
	var atk := int(s.character["spell_attack"])
	FaithRules.add_favor(s.character, data, "chauntea", 40)
	assert_array(FaithRules.deed(s, data, "pickpocket")).is_empty()  # not Chauntea's commandment
	var lines := FaithRules.deed(s, data, "murder")
	assert_str(" ".join(lines)).contains("не отнимать жизнь")
	assert_int(FaithRules.favor(s.character, "chauntea")).is_equal(20)
	assert_bool(FaithRules.lapsed(s.character)).is_true()
	assert_int(int(s.character["spell_dc"])).is_equal(dc - 2)
	assert_int(int(s.character["spell_attack"])).is_equal(atk - 2)
	s.room_id = "brod-den"  # Mask's shrine: not Chauntea's
	assert_str(FaithRules.atone_why(s, data)).is_equal("FAITH_NOT_YOUR_GOD")
	s.room_id = "brod-temple"
	assert_str(FaithRules.bless_why(s, data)).is_equal("FAITH_LAPSED")
	FaithRules.atone(s, data)
	assert_int(int(s.character["spell_dc"])).is_equal(dc)


func test_desecration_closes_the_priests_and_their_services() -> void:
	var s := _session()
	var cost := int(TradeRules.services(s, data, "npc_priestess")[0]["cost_cp"])
	FaithRules.start(s.character, "chauntea")
	FaithRules.add_favor(s.character, data, "chauntea", 60)
	assert_int(int(TradeRules.services(s, data, "npc_priestess")[0]["cost_cp"])).is_equal(int(cost * 0.6))  # the chosen: 40% off
	assert_bool(FaithRules.shelter(s, data, "brod-temple")).is_true()
	assert_bool(ExplorationRules.rest_place(data["world"], "brod-temple", s, data).get("free", false)).is_true()
	var lines := FaithRules.deed(s, data, "assault", "brod-temple")
	assert_str(" ".join(lines)).contains("Осквернение")
	assert_int(FaithRules.favor(s.character, "chauntea")).is_equal(-100)
	assert_str(FaithRules.refuses(s, data, "npc_priestess")).contains("осквернитель")
	assert_str(str(TradeRules.services(s, data, "npc_priestess")[0]["why"])).is_equal("FAITH_REFUSED")
	assert_str(FaithRules.service_why(s, data)).is_equal("FAITH_REFUSED")


func test_conversion_costs_and_waits() -> void:
	var s := _session()
	FaithRules.convert(s, data)
	s.room_id = "brod-townhall"
	assert_str(FaithRules.convert_why(s, data)).is_equal("FAITH_CONVERT_SOON")
	s.day += 30
	assert_str(FaithRules.convert_why(s, data)).is_empty()
	var lines := FaithRules.convert(s, data)
	assert_str(" ".join(lines)).contains("Тир")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 2500)


func test_the_master_vow_and_a_new_god() -> void:
	var s := _session("brod-square")
	var p := FaithRules.plan_vow(s, data, {"vow": "meek"})
	assert_bool(p.has("plan")).is_true()
	FaithRules.apply_vow(s, data, p["plan"])
	assert_bool(FaithRules.has_vow(s.character, "meek")).is_true()
	assert_str(str(FaithRules.plan_vow(s, data, {"vow": "meek"}).get("reason", ""))).contains("уже")
	assert_str(str(FaithRules.plan_vow(s, data, {"vow": "fasting"}).get("reason", ""))).contains("truth")
	var g := FaithRules.plan_god(s, data, {"shrine_name": "камень с вырезанным ликом", "new": {"name": "Хозяйка Брода", "title": "Речная Дева",
		"forbids": ["poaching"], "commandment": "не брать рыбы без спроса"}})
	assert_bool(g.has("plan")).override_failure_message(str(g)).is_true()
	FaithRules.apply_god(s, data, g["plan"])
	var sh := FaithRules.shrine(s, data, "brod-square")
	assert_str(FaithRules.god_name(s, data, str(sh["god"]))).is_equal("Хозяйка Брода")
	assert_str(str(FaithRules.plan_god(s, data, {"shrine_name": "ещё один", "god_id": "tyr"}).get("reason", ""))).contains("уже святилище")
	s.room_id = "brod-gate"
	assert_str(str(FaithRules.plan_god(s, data, {"shrine_name": "камень", "new": {"name": "Злой", "forbids": ["eat_meat"]}}).get("reason", ""))).contains("forbids")
	assert_str(FaithRules.scene_text(s, data)).is_empty()
	s.room_id = "brod-square"
	assert_str(FaithRules.scene_text(s, data)).contains("Хозяйка Брода")


func test_the_master_sees_the_faith() -> void:
	var s := _session()
	FaithRules.start(s.character, "chauntea")
	FaithRules.take_vow(s, data, "truth")
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"]["faith"])).contains("Чонтия")
	assert_str(str(snap["character"]["faith"])).contains("Слово правды")
	assert_str(str(snap["scene"]["shrine"])).contains("бог героя")
	var priestess: Dictionary = (snap["scene"]["npcs"] as Array).filter(func(n: Dictionary) -> bool: return str(n["npc_id"]) == "npc_priestess")[0]
	assert_str(str(priestess["god"])).contains("одной веры")
