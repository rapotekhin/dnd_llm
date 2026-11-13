extends GdUnitTestSuite
## v0.8.4.43.33, the author: the card of a spell, a feature, a thing and an act as in BG3 — the name, what it is, the
## headline number with its dice, the description, how long it lasts, how it is laid, its range, concentration, what it
## takes; the icon in the corner. The card is data of `CardInfo`, drawn by `DetailsPanel`.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String) -> Dictionary:
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			var c := GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
			CharacterRules.refresh(c, data, {})
			return c
	return {}


func test_a_damage_spell_says_its_circle_damage_range_and_cost() -> void:
	var card := CardInfo.spell(data, "hellish_rebuke")
	assert_str(str(card["title"])).is_equal("Адский упрёк")
	assert_str(str(card["sub"])).is_equal("Заклинание 1 круга · Воплощение")
	assert_str(str(card["big"])).is_equal("2–20 урона")
	assert_str(str(card["dice"][0]["text"])).is_equal("2к10")
	assert_str(str(card["dice"][0]["type"])).is_equal("огонь")
	assert_str(str(card["dice"][0]["color"])).is_not_empty()
	assert_bool((card["props"] as Array).any(func(p: String) -> bool: return p.contains("60 футов"))).is_true()
	assert_bool((card["props"] as Array).any(func(p: String) -> bool: return p.contains("Спасбросок Ловкости") and p.contains("половина"))).is_true()
	assert_bool((card["props"] as Array).any(func(p: String) -> bool: return p.contains("Мгновенн"))).is_false()  # nothing lasts
	assert_array((card["cost"] as Array).map(func(c: Dictionary) -> String: return str(c["kind"]))).contains_exactly(["reaction", "slot"])
	assert_str(str(card["cost"][1]["text"])).is_equal("Ячейка 1 круга")
	assert_str(str(card["icon"])).is_equal("spells/hellish_rebuke")


func test_a_higher_slot_grows_the_card() -> void:
	var card := CardInfo.spell(data, "hellish_rebuke", 2)
	assert_str(str(card["big"])).is_equal("3–30 урона")
	assert_str(str(card["sub"])).starts_with("Заклинание 2 круга")
	assert_str(str(card["cost"][1]["text"])).is_equal("Ячейка 2 круга")
	var darts := CardInfo.spell(data, "magic_missile", 2)  # four darts at the second circle
	assert_str(str(darts["dice"][0]["text"])).is_equal("4 × 1к4+1")
	assert_str(str(darts["big"])).is_equal("8–20 урона")
	assert_str(CardInfo.plain(darts)).contains("Ячейкой 2 круга")


func test_a_cantrip_grows_by_the_caster_s_level_and_takes_no_slot() -> void:
	var c := _hero("wizard_yalika")
	c["level"] = 5
	var card := CardInfo.spell(data, "fire_bolt", 0, c)
	assert_str(str(card["sub"])).is_equal("Заговор · Воплощение")
	assert_str(str(card["big"])).is_equal("2–20 урона")
	assert_array((card["cost"] as Array).map(func(x: Dictionary) -> String: return str(x["kind"]))).contains_exactly(["action"])
	assert_bool((card["props"] as Array).any(func(p: String) -> bool: return p.contains("Дальнобойная атака"))).is_true()


func test_a_heal_counts_the_caster_s_ability_and_concentration_shows() -> void:
	var c := _hero("cleric_branko")
	var mod := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "wis"))))
	var card := CardInfo.spell(data, "cure_wounds", 0, c)
	assert_bool(bool(card["dice"][0].get("heal", false))).is_true()
	assert_str(str(card["dice"][0]["text"])).is_equal("1к8%+d" % mod)
	assert_str(str(card["big"])).contains("хитов")
	var alone := CardInfo.spell(data, "cure_wounds")  # by the spell alone: no number to promise
	assert_str(str(alone["dice"][0]["text"])).contains("мод.")
	var bless := CardInfo.spell(data, "bless")
	assert_bool((bless["props"] as Array).any(func(p: String) -> bool: return p.contains("Концентрация"))).is_true()
	assert_bool((bless["props"] as Array).any(func(p: String) -> bool: return p.contains("1 минуты"))).is_true()  # its while without the word twice


func test_a_spell_that_lays_a_condition_shows_it_with_its_icon() -> void:
	var card := CardInfo.spell(data, "hold_person")
	assert_array(card["status"]).is_not_empty()
	assert_str(str(card["status"][0]["icon"])).starts_with("conditions/")


func test_a_weapon_card_says_the_blow_of_who_holds_it() -> void:
	var c := _hero("fighter_aira")
	var card := CardInfo.item(c, data, {}, "longsword")
	assert_str(str(card["sub"])).is_equal("Воинское оружие ближнего боя")
	var p := CombatRules.weapon_profile(c, data, {}, "longsword")
	var r := CombatRules.dice_range(str(p["dice"]))
	assert_str(str(card["big"])).is_equal("%d–%d урона" % [r[0] + int(p["bonus"]), r[1] + int(p["bonus"])])
	assert_str(str(card["dice"][0]["type"])).is_equal("рубящий")
	assert_bool((card["props"] as Array).any(func(x: String) -> bool: return x.contains("двумя руками 1к10"))).is_true()
	assert_bool((card["foot"] as Array).any(func(x: String) -> bool: return x.contains("фнт"))).is_true()
	assert_bool((card["foot"] as Array).any(func(x: String) -> bool: return x.contains("зм"))).is_true()


func test_armor_and_a_shield_say_their_class() -> void:
	assert_str(str(CardInfo.item({}, data, {}, "chain_mail")["big"])).is_equal("КД 16")
	assert_str(str(CardInfo.item({}, data, {}, "shield")["big"])).is_equal("+2 КД")
	assert_str(str(CardInfo.item({}, data, {}, "shield")["sub"])).is_equal("Щит")


func test_a_magic_thing_wears_its_rarity_on_the_name() -> void:
	var rare := ""
	for id: String in data["items"]["catalog"]:
		if str(data["items"]["catalog"][id].get("rarity", "")) == "rare" and not CardInfo.item({}, data, {}, id).is_empty():
			rare = id
			break
	assert_str(rare).is_not_empty()
	var card := CardInfo.item({}, data, {}, rare)
	assert_str(str(card.get("title_color", ""))).is_equal(str(data["icons"]["rarity"]["rare"]))
	assert_str(str(card["sub"])).starts_with("Редкий")


func test_a_feature_says_its_class_its_uses_and_its_cost() -> void:
	var c := _hero("fighter_aira")
	var card := CardInfo.feature(data, "second_wind", c)
	assert_str(str(card["title"])).is_equal("Второе дыхание")
	assert_str(str(card["sub"])).contains("Воин")
	assert_bool((card["props"] as Array).any(func(x: String) -> bool: return x.contains("1/1") and x.contains("короткого"))).is_true()
	assert_str(str(card["cost"][0]["kind"])).is_equal("bonus")
	assert_str(str(CardInfo.feature(data, "second_wind")["icon"])).is_equal("features/second_wind")  # by its resource too


func test_an_act_says_what_it_costs() -> void:
	var s := TestUtils.new_session()
	s.character = _hero("fighter_aira")
	var card := CardInfo.act(s, data, Sheet.HERO, Acts.one("dash"))
	assert_str(str(card["title"])).is_equal(Acts.one("dash").title())
	assert_str(str(card["cost"][0]["kind"])).is_equal("action")


func test_the_drawn_card_has_its_icon_its_body_and_its_band() -> void:
	var card := CardInfo.spell(data, "hellish_rebuke")
	var tip := DetailsPanel.tip_card(str(card["title"]), "", CardInfo.plain(card), card)
	auto_free(tip)
	assert_object(tip.find_child("TipIcon", true, false)).is_not_null()
	assert_str((tip.find_child("TipSub", true, false) as Label).text).is_equal("Заклинание 1 круга · Воплощение")
	assert_str((tip.find_child("TipText", true, false) as RichTextLabel).text).contains("2–20 урона")
	var band := tip.find_child("CardCost", true, false) as RichTextLabel
	assert_str(band.text).contains("Реакция")
	assert_str(band.text).contains("Ячейка 1 круга")


func test_a_cell_with_a_card_keeps_its_plain_words() -> void:
	var cell := IconSlot.make("spells/hellish_rebuke", "Адский упрёк")
	auto_free(cell)
	cell.set_card(CardInfo.spell(data, "hellish_rebuke"))
	assert_str(cell.tip_title).is_equal("Адский упрёк")
	assert_str(cell.tip_body).contains("2к10 огонь")
	assert_str(cell.tip_body).contains("Реакция")


func test_a_framed_icon_is_laid_edge_to_edge() -> void:
	var look := IconRules.of(data, {}, "spells/fire_bolt")
	assert_bool(bool(look.get("framed", false))).is_equal(bool(look["real"]))
	assert_bool(bool(IconRules.of(data, {}, "items/longsword").get("framed", false))).is_false()
