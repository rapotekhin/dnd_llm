extends GdUnitTestSuite
## v0.8.4.39, the author: a thing lays any status on its wearer while it works — an engine condition, a spell's own
## (`spell:<id>`), a made one — a Ring of Bless, a cursed Ring of Paralysis; a harm only on a cursed thing; a curse holds
## only on the body: one in the pockets is given or sold.

var data: Dictionary
var s: GameSession
var fx: EffectEngine
var turn := 0


func before_test() -> void:
	data = TestUtils.data()
	s = ChecklistProbe.session(data, ChecklistProbe.caster(data))
	s.character["level"] = 11
	CharacterRules.refresh(s.character, data, s.items)
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


func _ring(name: String, status: String, cursed := false, rarity := "rare") -> Dictionary:
	return {"name": name, "item_type": "wondrous", "rarity": rarity, "value_cp": 100000, "description": "Кольцо.",
		"properties": ["cursed"] if cursed else [], "wear": {"status": status}}


func _give(item: Dictionary) -> String:
	var r := _turn([{"kind": "move_item", "source": "world", "target": "hero", "item": item, "qty": 1, "reason": "находка"}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	for k: String in s.items:
		if str(s.items[k].get("name", "")) == str(item["name"]):
			return k
	return ""


func _put_on(id: String) -> void:
	s.character["equipped"][CharacterRules.slot_for(ItemRules.def_of(data["items"], s.items, id), data)] = id
	CharacterRules.refresh(s.character, data, s.items)


func _worn(c: Dictionary) -> Array:
	return ConditionRules.effects(c).filter(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("kind", "")) == ItemRules.WORN)


func test_a_ring_of_bless_lays_bless_while_worn() -> void:
	var id := _give(_ring("Кольцо Благословения", "spell:bless"))
	assert_str(str(ItemRules.def_of(data["items"], s.items, id)["rarity"])).is_equal("rare")
	_put_on(id)
	var e: Array = _worn(s.character).filter(func(x: Dictionary) -> bool: return str(x.get("die", "")) == "1d4")
	assert_int(e.size()).is_equal(1)
	assert_array(e[0]["on"]).contains_exactly(["attack", "save"])
	assert_bool(bool(e[0].get("concentration", false))).is_false()
	for slot: String in CharacterRules.SLOTS:
		if str(s.character["equipped"][slot]) == id:
			s.character["equipped"][slot] = ""
	CharacterRules.refresh(s.character, data, s.items)
	assert_bool(_worn(s.character).any(func(x: Dictionary) -> bool: return str(x.get("die", "")) == "1d4")).is_false()


func test_a_harm_only_on_a_cursed_thing() -> void:
	var r := _turn([{"kind": "move_item", "source": "world", "target": "hero", "item": _ring("Кольцо оцепенения", "paralyzed"), "qty": 1, "reason": "находка"}])
	assert_bool(bool(r[0]["accepted"])).is_false()
	assert_str(str(r[0]["reason"])).contains("проклятая")
	assert_bool(bool(_turn([{"kind": "move_item", "source": "world", "target": "hero", "item": _ring("Кольцо замедления", "spell:slow"), "qty": 1,
		"reason": "находка"}])[0]["accepted"])).is_false()
	assert_str(str(_turn([{"kind": "move_item", "source": "world", "target": "hero", "item": _ring("Кольцо огня", "spell:fireball"), "qty": 1,
		"reason": "находка"}])[0]["reason"])).contains("не кладёт статус")


func test_a_cursed_ring_of_paralysis_holds_on_the_body_and_remove_curse_frees() -> void:
	var id := _give(_ring("Кольцо паралича", "paralyzed", true, "uncommon"))
	assert_bool(ItemRules.held_by_curse(s.character, data, s.items, id)).is_false()  # in the pockets: given or sold like any thing
	_put_on(id)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_true()
	assert_bool(ItemRules.held_by_curse(s.character, data, s.items, id)).is_true()
	ItemRules.lift_curse(s.character, data, s.items)
	CharacterRules.refresh(s.character, data, s.items)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_false()


func test_an_attuned_cursed_thing_in_the_pockets_is_not_held() -> void:
	var id := _give(_ring("Кольцо паралича", "paralyzed", true, "uncommon"))
	s.character["attuned"] = [id]
	assert_bool(ItemRules.held_by_curse(s.character, data, s.items, id)).is_false()


func test_the_wearer_s_immunity_keeps_a_condition_off() -> void:
	assert_dict(ItemRules.status_fields(data, {"monster": "skeleton"}, "poisoned")).is_empty()
	assert_dict(ItemRules.status_fields(data, {"monster": "goblin"}, "poisoned")).contains_keys(["condition"])
	assert_dict(ItemRules.status_fields(data, {"monster": "goblin"}, "spell:haste")).contains_keys(["haste"])


func test_a_made_status_of_the_same_turn() -> void:
	var r := _turn([{"kind": "make", "what": "status", "key": "luck", "name": "Удача", "text": "Везёт в бою.", "parts": [{"part": "die", "value": "attack", "amount": 1}]},
		{"kind": "move_item", "source": "world", "target": "hero", "item": _ring("Кольцо удачи", "new:luck"), "qty": 1, "reason": "находка"}])
	assert_bool(bool(r[0]["accepted"])).override_failure_message(str(r[0])).is_true()
	assert_bool(bool(r[1]["accepted"])).override_failure_message(str(r[1])).is_true()
	var id := ""
	for k: String in s.items:
		if str(s.items[k].get("name", "")) == "Кольцо удачи":
			id = k
	_put_on(id)
	assert_bool(_worn(s.character).any(func(x: Dictionary) -> bool: return str(x.get("condition", "")).begins_with(MakeRules.PREFIX))).is_true()
