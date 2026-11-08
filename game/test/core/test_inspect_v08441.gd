extends GdUnitTestSuite
## v0.8.4.41, the author: inspect any creature, as in BG3 and Pathfinder — one card (CreatureCard) for a person, a monster, a
## follower, in a fight and out of it: its numbers, blows, abilities and spells; every status on it with its source and time;
## what it wears; what is hidden until the one knowledge check (CombatRules.look_over, Knows) opens its kind.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _card(s: GameSession, d: Dictionary, id: String) -> Dictionary:
	return CreatureCard.of(s, d, Sheet.who(s, d, id))


## The knowledge check until it succeeds (a natural 1 fails whatever the bonus): the line of the success.
func _look(s: GameSession, who: Dictionary) -> String:
	for i in 10:
		var line := CombatRules.look_over(s, data, who)[0]
		if line.contains("теперь ясно"):
			return line
	fail("the knowledge check never succeeded")
	return ""


func _names(list: Array, key: String = "name") -> Array:
	return list.map(func(x: Dictionary) -> String: return str(x[key]))


func test_a_guard_out_of_a_fight_shows_its_worn_things_and_its_ac_once_known() -> void:
	var s := TestUtils.new_session()
	var c := _card(s, data, "npc_veteran")
	assert_str(str(c["name"])).is_equal("Старый Орвин")
	assert_bool(bool(c["known"])).is_false()
	assert_array(_names(c["worn"], "item")).contains(["chain_shirt", "shield", "spear"])  # what it wears is seen at once
	assert_bool(c.has("ac")).is_false()
	assert_str(str(c["lore"]["skill"])).is_equal("insight")  # a humanoid: Insight
	Knows.add(s, Knows.MONSTER, "guard")
	c = _card(s, data, "npc_veteran")
	assert_bool(bool(c["known"])).is_true()
	assert_int(int(c["ac"])).is_equal(16)  # a chain shirt and a shield, counted by what it wears
	assert_int(int(c["speed"])).is_equal(30)
	assert_array(_names(c["blows"])).contains(["Копьё"])
	assert_array(_names(c["skills"], "id")).contains(["perception"])
	assert_array(c["languages"]).is_not_empty()


func test_a_thing_given_to_a_person_is_worn_and_lays_its_status_with_its_source() -> void:
	var s := TestUtils.new_session()
	s.items["gen_ring_bless"] = {"name": "Кольцо Благословения", "item_type": "wondrous", "rarity": "rare", "value_cp": 100000,
		"description": "Кольцо.", "wear": {"status": "spell:bless"}}
	Gear.give(s, data, "npc_veteran", "gen_ring_bless")
	var c := _card(s, data, "npc_veteran")
	assert_array(_names(c["worn"])).contains(["Кольцо Благословения"])
	var by_ring: Array = (c["statuses"] as Array).filter(func(e: Dictionary) -> bool: return str(e["source"]) == "Кольцо Благословения")
	assert_int(by_ring.size()).is_equal(1)
	assert_str(str(by_ring[0]["kind"])).is_equal(ItemRules.WORN)
	assert_str(str(by_ring[0]["left"])).is_equal("пока надето")


func test_a_foe_in_a_fight_is_hidden_until_the_knowledge_check() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 1}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	var c := CreatureCard.of(s, data, f)
	assert_bool(bool(c["known"])).is_false()
	assert_str(str(c["health"])).is_equal("HEALTH_FULL")  # its health in a word, the numbers hidden
	assert_str(CreatureCard.text(s, data, f)).is_empty()
	var box := VBoxContainer.new()
	CreatureCardPanel.fill(box, c)
	var numbers: Label = box.find_child("CardNumbers", false, false)
	assert_str(numbers.text).contains(CreatureCard.HIDDEN)
	box.free()
	s.character["skills"]["nature"] = 40
	_look(s, f)
	c = CreatureCard.of(s, data, f)
	assert_bool(bool(c["known"])).is_true()
	assert_int(int(c["ac"])).is_equal(13)
	assert_int(int(c["hp"])).is_equal(int(f["hp"]))
	assert_int((c["abilities"] as Array).size()).is_equal(6)
	assert_array(_names(c["blows"])).contains(["Укус"])
	assert_bool((c["features"] as Array).any(func(x: Dictionary) -> bool: return str(x["kind"]) == "trait")).is_true()  # Pack Tactics
	box = VBoxContainer.new()
	CreatureCardPanel.fill(box, c)
	numbers = box.find_child("CardNumbers", false, false)
	assert_str(numbers.text).contains("13").not_contains(CreatureCard.HIDDEN)
	box.free()
	assert_str(CombatRules.monster_card(s, data, f)).contains("КД 13").contains("Укус")


func test_a_made_status_on_a_person_shows_with_its_source_and_what_it_does() -> void:
	var d := TestUtils.data().duplicate(true)
	var s := TestUtils.new_session()
	MakeRules.install(d, s.generated)
	s.character["level"] = 20
	var p := MakeRules.plan(s, d, {"kind": "make", "what": "status", "key": "cat", "name": "Кошачья поступь", "text": "Сделано мастером.",
		"parts": [{"part": "check", "value": "stealth", "amount": 1}, {"part": "damage", "value": "fire", "amount": 1}]})
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, d, p["plan"])
	var st := str(p["plan"]["id"])
	ConditionRules.impose(s, d, {"condition": st, "ends": {"rest": "long"}, "source": {"kind": "master", "name": "мастер"}}, Sheet.own(s, "npc_veteran"))
	var c := _card(s, d, "npc_veteran")
	var mine: Array = (c["statuses"] as Array).filter(func(e: Dictionary) -> bool: return str(e["condition"]) == st)
	assert_int(mine.size()).is_equal(1)
	assert_str(str(mine[0]["name"])).is_equal("Кошачья поступь")
	assert_str(str(mine[0]["source"])).is_equal("мастер")
	assert_str(str(mine[0]["left"])).is_equal("до долгого отдыха")
	assert_str(str(mine[0]["does"])).contains("преимущество на проверки").contains("сопротивление")
	Knows.add(s, Knows.MONSTER, "guard")
	c = _card(s, d, "npc_veteran")
	var fire: Array = (c["defenses"] as Array).filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "resist")
	assert_int(fire.size()).is_equal(1)
	assert_str(str(fire[0]["source"])).is_equal("мастер")  # by the one who laid it, as the damage line says
	assert_str(str(fire[0]["what"])).is_equal(str(d["misc"]["damage_types"]["fire"]))


func test_a_follower_is_seen_whole_without_a_check() -> void:
	var s := TestUtils.new_session()
	Being.of(s, "npc_merchant")["follows"] = 1
	var c := _card(s, data, "npc_merchant")
	assert_bool(bool(c["known"])).is_true()
	assert_bool(Knows.has(s, Knows.MONSTER, str(Sheet.template_id(data, Sheet.who(s, data, "npc_merchant"))))).is_false()
	assert_bool(c.has("ac") and c.has("abilities") and c.has("saves")).is_true()


func test_the_hero_looks_a_person_over_by_its_kind() -> void:
	var s := TestUtils.new_session()
	s.character["skills"]["insight"] = 40
	assert_str(_look(s, Sheet.who(s, data, "npc_veteran"))).contains("Старый Орвин")
	assert_bool(Knows.has(s, Knows.MONSTER, "guard")).is_true()
	assert_bool(bool(_card(s, data, "npc_veteran")["known"])).is_true()


func test_the_card_of_the_hero_is_whole() -> void:
	var s := TestUtils.new_session()
	var c := CreatureCard.of(s, data, Sheet.HERO)
	assert_bool(bool(c["known"])).is_true()
	assert_int(int(c["ac"])).is_equal(int(s.character["ac"]))
	assert_str(str(c["name"])).is_equal(str(s.character["name"]))
