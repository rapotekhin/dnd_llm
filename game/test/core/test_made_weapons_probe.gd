extends GdUnitTestSuite
## A probe of the author's questions (2026-11-08): can the master make (1) a dagger that blinds the one it strikes, (2) a
## dagger that gives Fireball once a long rest and Magic Missile four times, (3) a wand of a spell the book lacks — an acid
## bolt, a lightning bolt of acid? All hold since v0.8.4.36: `hit`, `spells` of a made thing and `use.spell: new:<key>`.

var data: Dictionary
var s: GameSession
var fx: EffectEngine
var turn := 0


func before_test() -> void:
	data = TestUtils.data()
	s = ChecklistProbe.session(data)
	s.character["level"] = 11
	CharacterRules.refresh(s.character, data, s.items)
	fx = EffectEngine.new()


## The master's effects of one turn, in order (a `make` before what names it by new:<key>). The results.
func _turn(effects: Array) -> Array[Dictionary]:
	turn += 1
	var t := "t-%d" % turn
	fx.searched[t] = true
	fx._won[t] = ["perception"]  # a magic find needs a check that passed
	var out: Array[Dictionary] = []
	var ids: Array = []
	for e: Dictionary in effects:
		var r := fx.validate(s, data, t, e)
		out.append(r)
		if bool(r["accepted"]):
			ids.append(r["effect_id"])
	fx.apply(s, t, ids)
	return out


func _give(item: Dictionary) -> Dictionary:
	return {"kind": "move_item", "source": "world", "target": "hero", "item": item, "qty": 1, "reason": "награда"}


func _id_of(name: String) -> String:
	for id: String in s.items:
		if str(s.items[id].get("name", "")) == name:
			return id
	return ""


## Strikes the goblin with what is in the hero's main hand up to `n` times; whether it went blind.
func _strike_until_blind(n: int) -> bool:
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["ac"] = 1
	var hero := CombatRules.player(s)
	for i in n:
		ChecklistProbe.turn(s, data, hero)
		Acts.one("attack").go(s, data, hero, str(goblin["id"]))
		if ConditionRules.has(goblin, "blinded"):
			return true
	return false


# --- 1. a dagger that blinds on a hit -------------------------------------------------------------------------------


func test_1a_a_made_dagger_blinds_the_one_it_strikes() -> void:
	var r := _turn([_give({"name": "Кинжал Тёмной Вспышки", "item_type": "weapon", "base": "dagger", "rarity": "very_rare", "value_cp": 500000,
		"description": "Клинок вспыхивает при ударе.", "hit": {"cond": "blinded", "save": "con", "rounds": 1}})])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var id := _id_of("Кинжал Тёмной Вспышки")
	assert_bool((s.items[id] as Dictionary).has("hit")).override_failure_message("у вещи мастера нет поля «при попадании» — движок его отбросил").is_true()
	s.character["equipped"]["main_hand"] = id
	CharacterRules.refresh(s.character, data, s.items)
	assert_bool(_strike_until_blind(20)).override_failure_message("гоблин так и не ослеп от ударов кинжала").is_true()


func test_1b_today_a_made_liquid_on_the_blade_blinds_for_one_hit() -> void:
	var r := _turn([{"kind": "make", "what": "liquid", "key": "flash", "name": "Слепящая пыльца", "text": "Пыльца жжёт глаза.",
		"parts": [{"part": "blade"}, {"part": "lay", "value": "blinded"}, {"part": "save", "value": "con", "amount": 14}]}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var lid := ""
	for id: String in s.generated.get("made", {}):
		if str(s.generated["made"][id]["name"]) == "Слепящая пыльца":
			lid = id
	var c := s.character
	c["inventory"]["dagger"] = 1
	c["equipped"]["main_hand"] = "dagger"
	CharacterRules.refresh(c, data, s.items)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["ac"] = 1
	var hero := CombatRules.player(s)
	var blind := false
	for i in 20:
		c["inventory"][lid] = 1
		ItemRules.belt_put(c, data, s.items, lid)
		ItemRules.use(c, data, s.items, lid, s.rng, s)
		ChecklistProbe.turn(s, data, hero)
		Acts.one("attack").go(s, data, hero, str(goblin["id"]))
		if ConditionRules.has(goblin, "blinded"):
			blind = true
			break
	assert_bool(blind).override_failure_message("пыльца на клинке не ослепила").is_true()


# --- 2. a dagger with spells a long rest ----------------------------------------------------------------------------


func test_2a_a_made_dagger_gives_fireball_once_and_magic_missile_four_times_a_long_rest() -> void:
	var r := _turn([_give({"name": "Кинжал Пламенного Круга", "item_type": "weapon", "base": "dagger", "rarity": "very_rare", "value_cp": 500000,
		"description": "Рукоять тёплая.", "spells": [{"spell": "fireball", "uses": 1}, {"spell": "magic_missile", "uses": 4}]})])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var id := _id_of("Кинжал Пламенного Круга")
	assert_bool((s.items[id] as Dictionary).has("spells")).override_failure_message("у вещи мастера нет поля «заклинания вещи» — движок его отбросил").is_true()
	var c := s.character
	c["equipped"]["main_hand"] = id
	CharacterRules.refresh(c, data, s.items)
	assert_bool(SpellRules.free_now(c, data, "fireball")).override_failure_message("огненный шар от кинжала не доступен").is_true()
	assert_int(Stock.left(c, data, SpellRules.stock_of(c, data, "fireball"))).is_equal(1)
	assert_int(Stock.left(c, data, SpellRules.stock_of(c, data, "magic_missile"))).is_equal(4)


func test_2b_today_a_dagger_holds_one_spell_as_a_wand() -> void:
	var r := _turn([_give({"name": "Кинжал-жезл", "item_type": "weapon", "base": "dagger", "rarity": "rare", "value_cp": 200000,
		"description": "Руны на клинке.", "use": {"spell": "fireball", "charges": 1}})])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var d: Dictionary = s.items[_id_of("Кинжал-жезл")]
	assert_str(str(d["use"]["spell"])).is_equal("fireball")
	assert_int(int(d["charges"]["max"])).is_equal(1)
	assert_str(str(d["charges"]["regain"])).is_equal("1d1")  # a wand's dawn, not «once a long rest»
	assert_bool(bool(d["charges"]["crumble"])).is_true()  # and it may crumble on its last charge


# --- 3. a wand of a spell the book lacks ----------------------------------------------------------------------------


func _acid_bolt() -> Dictionary:
	return {"kind": "make", "what": "spell", "key": "acid_bolt", "name": "Кислотная молния", "text": "Струя кислоты бьёт по всем на пути.",
		"parts": [{"part": "range", "value": "120"}, {"part": "target", "value": "area"}, {"part": "roll", "value": "dex"}, {"part": "half"},
			{"part": "damage", "value": "acid", "amount": 8}, {"part": "shape", "value": "line"}, {"part": "size", "amount": 100}]}


func test_3a_a_wand_of_a_spell_made_in_the_same_turn() -> void:
	var r := _turn([_acid_bolt(), _give({"name": "Жезл кислотной молнии", "item_type": "wondrous", "rarity": "rare", "value_cp": 300000,
		"description": "Зеленоватый жезл.", "use": {"spell": "new:acid_bolt", "charges": 7}})])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	assert_bool(bool(r[1]["accepted"])).override_failure_message("жезл заклинания этого же хода: %s" % r[1].get("reason", "")).is_true()
	var d: Dictionary = s.items[_id_of("Жезл кислотной молнии")]
	var sp := str(d["use"]["spell"])
	assert_str(sp).starts_with(MakeRules.PREFIX)
	assert_int(int(d["charges"]["max"])).is_equal(7)


func test_3b_a_wand_of_a_spell_made_a_turn_before() -> void:
	var r := _turn([_acid_bolt()])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var sp := str(r[0]["plan"]["id"]) if r[0].has("plan") else ""
	if sp.is_empty():
		for id: String in s.generated.get("made", {}):
			if str(s.generated["made"][id]["name"]) == "Кислотная молния":
				sp = id
	assert_int(SpellRules.level_of(data, sp)).is_equal(3)
	assert_dict(data["spells"][sp]["area"]).is_equal({"type": "line", "size": 100})  # a line as Lightning Bolt's, from the caster
	assert_int(int(data["spells"][sp]["range_ft"])).is_equal(0)
	assert_str(str(data["spells"][sp].get("damage", {}).get("type", data["spells"][sp].get("damage_type", "")))).is_not_empty()
	var w := _turn([_give({"name": "Жезл кислотной молнии", "item_type": "wondrous", "rarity": "rare", "value_cp": 300000,
		"description": "Зеленоватый жезл.", "use": {"spell": sp, "charges": 7}})])
	assert_bool(bool(w[0]["accepted"])).override_failure_message(str(w[0])).is_true()
	assert_str(str(s.items[_id_of("Жезл кислотной молнии")]["use"]["spell"])).is_equal(sp)
