extends GdUnitTestSuite
## v0.8.4.36, the author's «добавляй возможность для создания всего»: what the master may build into a thing and into a
## spell — a thing's spells a long rest, spells kept in a thing (a Ring of Spell Storing), a bonus or advantage to initiative,
## an immunity to a condition, a blow that drains life, regeneration; the shape and size of a made spell's area.

var data: Dictionary
var s: GameSession
var fx: EffectEngine
var turn := 0


func before_test() -> void:
	data = TestUtils.data()
	s = ChecklistProbe.session(data, ChecklistProbe.caster(data))
	s.character["level"] = 11
	CharacterRules.refresh(s.character, data, s.items)
	Rest.long(s, data, Being.HERO)  # the slots of the level
	fx = EffectEngine.new()


func _turn(effects: Array) -> Array[Dictionary]:
	turn += 1
	var t := "t-%d" % turn
	fx.searched[t] = true
	fx._won[t] = ["perception"]
	var out: Array[Dictionary] = []
	var ids: Array = []
	for e: Dictionary in effects:
		var r := fx.validate(s, data, t, e)
		out.append(r)
		if bool(r["accepted"]):
			ids.append(r["effect_id"])
	fx.apply(s, t, ids)
	return out


## The master gives the thing and the hero puts it on where it goes. Its id ("" — refused, `why` says).
func _wear(item: Dictionary) -> String:
	var r := _turn([{"kind": "move_item", "source": "world", "target": "hero", "item": item, "qty": 1, "reason": "награда"}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	var id := ""
	for k: String in s.items:
		if str(s.items[k].get("name", "")) == str(item["name"]):
			id = k
	var slot := CharacterRules.slot_for(ItemRules.def_of(data["items"], s.items, id), data)
	s.character["equipped"][slot] = id
	CharacterRules.refresh(s.character, data, s.items)
	return id


func _off(id: String) -> void:
	for slot: String in CharacterRules.SLOTS:
		if str(s.character["equipped"][slot]) == id:
			s.character["equipped"][slot] = ""
	CharacterRules.refresh(s.character, data, s.items)


# --- a thing's spells -----------------------------------------------------------------------------------------------


func test_a_things_fireball_is_spent_and_comes_back_after_a_long_rest() -> void:
	var c := s.character
	_wear({"name": "Кинжал Пламенного Круга", "item_type": "weapon", "base": "dagger", "rarity": "very_rare", "value_cp": 500000,
		"description": "Рукоять тёплая.", "spells": [{"spell": "fireball", "uses": 1}, {"spell": "magic_missile", "uses": 4}]})
	var rid := SpellRules.stock_of(c, data, "fireball")
	assert_str(rid).starts_with("item:")
	assert_dict(SpellRules.check(c, data, "fireball", 0)).contains_keys(["spell_id"])
	assert_int(int(SpellRules.check(c, data, "fireball", 0)["slot"])).is_equal(0)  # no slot of the hero's
	var slots := SpellRules.slots_left(c, 3)
	SpellRules.cast(c, data, "fireball", 0, s)
	assert_int(SpellRules.slots_left(c, 3)).is_equal(slots)
	assert_int(Stock.left(c, data, rid)).is_equal(0)
	assert_bool(SpellRules.free_now(c, data, "fireball")).is_false()
	assert_int(Stock.left(c, data, SpellRules.stock_of(c, data, "magic_missile"))).is_equal(4)
	Rest.long(s, data, Being.HERO)
	assert_int(Stock.left(c, data, rid)).is_equal(1)


func test_a_things_spells_go_when_it_is_taken_off() -> void:
	var id := _wear({"name": "Кинжал Пламенного Круга", "item_type": "weapon", "base": "dagger", "rarity": "very_rare", "value_cp": 500000,
		"description": "Рукоять тёплая.", "spells": [{"spell": "fireball", "uses": 1}]})
	assert_bool(SpellRules.free_now(s.character, data, "fireball")).is_true()
	_off(id)
	assert_bool(SpellRules.free_now(s.character, data, "fireball")).is_false()


func test_a_things_spell_past_the_fifth_circle_is_refused() -> void:
	var r := _turn([{"kind": "move_item", "source": "world", "target": "hero", "qty": 1, "reason": "награда",
		"item": {"name": "Посох бездны", "item_type": "wondrous", "rarity": "legendary", "value_cp": 900000, "description": "Тёмный посох.",
			"spells": [{"spell": "disintegrate", "uses": 1}]}}])
	if data["spells"].has("disintegrate"):
		assert_bool(bool(r[0]["accepted"])).is_false()


# --- spells kept in a thing -----------------------------------------------------------------------------------------


## A 5th-level caster with its slots (the class tables end at the 5th).
func _caster5() -> void:
	s.character["level"] = 5
	CharacterRules.refresh(s.character, data, s.items)
	Rest.long(s, data, Being.HERO)


func test_a_spell_kept_in_a_ring_is_cast_once_and_never_comes_back() -> void:
	_caster5()
	var c := s.character
	var id := _wear({"name": "Кольцо хранения", "item_type": "wondrous", "rarity": "rare", "value_cp": 300000, "description": "Тяжёлое кольцо.",
		"store": 3})
	var can := ItemRules.storable(s, data, id)
	assert_array(can).is_not_empty()
	var sp := str(can[0]["spell"])
	var circle := int(can[0]["circle"])
	var slots := SpellRules.slots_left(c, circle)
	assert_str(ItemRules.store_why(s, data, id, sp, circle)).is_empty()
	ItemRules.store_spell(s, data, id, sp, circle)
	assert_int(SpellRules.slots_left(c, circle)).is_equal(slots - 1)  # the slot it was cast with
	assert_int(ItemRules.stored(c, id, ItemRules.def_of(data["items"], s.items, id)).size()).is_equal(1)
	var rid := SpellRules.stock_of(c, data, sp)
	assert_str(rid).starts_with("store:")
	SpellRules.cast(c, data, sp, 0, s)
	CharacterRules.refresh(c, data, s.items)
	assert_array(ItemRules.stored(c, id, ItemRules.def_of(data["items"], s.items, id))).is_empty()
	Rest.long(s, data, Being.HERO)
	CharacterRules.refresh(c, data, s.items)
	assert_array(ItemRules.stored(c, id, ItemRules.def_of(data["items"], s.items, id))).is_empty()


func test_two_kept_spells_leave_one_by_one() -> void:
	_caster5()
	var c := s.character
	var id := _wear({"name": "Кольцо хранения", "item_type": "wondrous", "rarity": "rare", "value_cp": 300000, "description": "Тяжёлое кольцо.",
		"store": 2, "stored": [{"spell": "magic_missile"}, {"spell": "shield"}]})
	var d := ItemRules.def_of(data["items"], s.items, id)
	assert_int(ItemRules.stored(c, id, d).size()).is_equal(2)
	SpellRules.cast(c, data, "magic_missile", 0, s)
	assert_array(ItemRules.stored(c, id, d).map(func(k: Dictionary) -> String: return str(k["spell"]))).is_equal(["shield"])
	SpellRules.cast(c, data, "shield", 0, s)  # a stale row of the first spell must not bring it back
	assert_array(ItemRules.stored(c, id, d)).is_empty()


func test_a_ring_holds_no_more_circles_than_it_keeps() -> void:
	_caster5()
	var id := _wear({"name": "Кольцо хранения", "item_type": "wondrous", "rarity": "rare", "value_cp": 300000, "description": "Тяжёлое кольцо.",
		"store": 1, "stored": [{"spell": "magic_missile"}]})
	var can := ItemRules.storable(s, data, id)
	assert_array(can).is_empty()
	assert_str(ItemRules.store_why(s, data, id, "magic_missile", 1)).is_not_empty()


# --- properties: initiative, immunity, drain, regeneration ----------------------------------------------------------


func test_initiative_plus_two_adds_two_to_the_roll() -> void:
	ChecklistProbe.fight(s, data, "goblin")
	s.rng.seed = 7
	var before := CombatRules.initiative_of(s, data, Being.HERO)
	_wear({"name": "Амулет быстрой руки", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 50000, "description": "Амулет.",
		"properties": ["initiative_plus2"]})
	s.rng.seed = 7
	assert_int(CombatRules.initiative_of(s, data, Being.HERO)).is_equal(before + 2)


func test_the_master_builds_initiative_and_immunity_of_parts() -> void:
	for parts: Array in [[{"part": "initiative", "amount": 2}], [{"part": "initiative_first"}], [{"part": "immune", "value": "frightened"}],
			[{"part": "drain"}], [{"part": "regen"}]]:
		var t := _turn([{"kind": "make", "what": "property", "key": "p%d" % turn, "name": "Свойство %d" % turn, "text": "Свойство.", "parts": parts}])
		assert_bool(bool(t[0]["accepted"])).override_failure_message("%s: %s" % [parts, t[0].get("reason", "")]).is_true()
	var bad := _turn([{"kind": "make", "what": "property", "key": "bad", "name": "Плохое", "text": "Свойство.", "parts": [{"part": "immune", "value": "exhaustion"}]}])
	assert_bool(bool(bad[0]["accepted"])).is_false()


func test_immune_to_fear_keeps_the_hero_unafraid() -> void:
	_wear({"name": "Амулет бесстрашия", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 50000, "description": "Амулет.",
		"properties": ["immune_frightened"]})
	ConditionRules.impose(s, data, {"condition": "frightened", "ends": {}, "source": {"kind": "spell", "id": "fear", "name": "Ужас"}})
	assert_bool(ConditionRules.has(s.character, "frightened")).is_false()
	ConditionRules.impose(s, data, {"condition": "charmed", "ends": {}, "source": {"kind": "spell", "id": "charm_person", "name": "Очарование"}})
	assert_bool(ConditionRules.has(s.character, "charmed")).is_true()  # only what it names


func test_a_draining_blade_heals_its_wielder() -> void:
	_wear({"name": "Кинжал-кровопийца", "item_type": "weapon", "base": "dagger", "rarity": "rare", "value_cp": 200000, "description": "Тёмный клинок.",
		"properties": ["life_drain"]})
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["ac"] = 1
	var hero := CombatRules.player(s)
	s.character["hp"] = 1
	var healed := false
	for i in 10:
		ChecklistProbe.turn(s, data, hero)
		Acts.one("attack").go(s, data, hero, str(goblin["id"]))
		if Sheet.hp(s, data, Sheet.HERO) > 1:
			healed = true
			break
	assert_bool(healed).is_true()


func test_regeneration_heals_at_the_start_of_a_turn_and_on_the_road() -> void:
	_wear({"name": "Кольцо регенерации", "item_type": "wondrous", "rarity": "very_rare", "value_cp": 500000, "description": "Кольцо.",
		"properties": ["regeneration"]})
	var c := s.character
	ChecklistProbe.fight(s, data, "goblin")
	var hero := CombatRules.player(s)
	c["hp"] = 1
	var lines: Array[String] = []
	ItemRules.regenerate(s, data, hero, lines)
	assert_int(Sheet.hp(s, data, Sheet.HERO)).is_greater(1)
	s.combat.clear()
	c["hp"] = 1
	ItemRules.regenerate_hero(s, data)  # the count starts
	TimeRules.advance(s, data, 60)
	assert_int(int(c["hp"])).is_greater(1)


func test_regeneration_does_not_raise_the_fallen() -> void:
	_wear({"name": "Кольцо регенерации", "item_type": "wondrous", "rarity": "very_rare", "value_cp": 500000, "description": "Кольцо.",
		"properties": ["regeneration"]})
	ChecklistProbe.fight(s, data, "goblin")
	s.character["hp"] = 0
	var lines: Array[String] = []
	ItemRules.regenerate(s, data, CombatRules.player(s), lines)
	assert_int(Sheet.hp(s, data, Sheet.HERO)).is_equal(0)


# --- the shape of a made spell's area -------------------------------------------------------------------------------


func _spell(key: String, extra: Array) -> Dictionary:
	var parts: Array = [{"part": "target", "value": "area"}, {"part": "roll", "value": "dex"}, {"part": "half"}, {"part": "damage", "value": "cold", "amount": 3}]
	return _turn([{"kind": "make", "what": "spell", "key": key, "name": "Стужа %s" % key, "text": "Холодный порыв.", "parts": parts + extra}])[0]


func _made(name: String) -> Dictionary:
	for id: String in s.generated.get("made", {}):
		if str(s.generated["made"][id]["name"]) == name:
			return data["spells"].get(id, {})
	return {}


func test_a_cone_starts_at_the_caster() -> void:
	var r := _spell("cone", [{"part": "shape", "value": "cone"}])
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var sp := _made("Стужа cone")
	assert_dict(sp["area"]).is_equal({"type": "cone", "size": 15})
	assert_str(str(sp["range"])).is_equal("На себя")
	assert_int(int(sp["range_ft"])).is_equal(0)


func test_a_cube_and_a_bigger_sphere() -> void:
	assert_bool(bool(_spell("cube", [{"part": "shape", "value": "cube"}, {"part": "size", "amount": 10}])["accepted"])).is_true()
	assert_dict(_made("Стужа cube")["area"]).is_equal({"type": "cube", "size": 10})
	assert_bool(bool(_spell("ball", [{"part": "shape", "value": "sphere"}, {"part": "size", "amount": 40}])["accepted"])).is_true()
	var big := _made("Стужа ball")
	assert_dict(big["area"]).is_equal({"type": "sphere", "size": 40})
	assert_bool(bool(_spell("small", [])["accepted"])).is_true()
	var small := _made("Стужа small")
	assert_dict(small["area"]).is_equal({"type": "sphere", "size": 20})  # no shape — the old default
	assert_int(int(big["level"])).is_greater_equal(int(small["level"]))  # a wider ball costs more


func test_a_shape_out_of_bounds_or_not_on_an_area_is_refused() -> void:
	assert_bool(bool(_spell("huge", [{"part": "shape", "value": "cone"}, {"part": "size", "amount": 90}])["accepted"])).is_false()
	assert_bool(bool(_spell("ring", [{"part": "shape", "value": "torus"}])["accepted"])).is_false()
	var one := _turn([{"kind": "make", "what": "spell", "key": "one", "name": "Укол", "text": "Холод.", "parts": [{"part": "target", "value": "one"},
		{"part": "roll", "value": "attack"}, {"part": "damage", "value": "cold", "amount": 2}, {"part": "shape", "value": "line"}]}])[0]
	assert_bool(bool(one["accepted"])).is_false()
