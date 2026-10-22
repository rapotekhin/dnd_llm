extends GdUnitTestSuite
## EffectEngine: validation against state and budgets, reserves, the turn transaction (ADR-0008 §3–4, ADR-0009 §5).

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	fx = EffectEngine.new()


func _ok(effect: Dictionary, turn := "t-1") -> String:
	var r := fx.validate(s, data, turn, effect)
	assert_bool(r["accepted"]).override_failure_message(str(r)).is_true()
	return r["effect_id"]


func _no(effect: Dictionary, turn := "t-1") -> String:
	var r := fx.validate(s, data, turn, effect)
	assert_bool(r["accepted"]).override_failure_message(str(r)).is_false()
	return r["reason"]


func test_nothing_changes_until_the_result_lists_the_id() -> void:
	var gold := int(s.character["gold_cp"])
	var id := _ok({"kind": "coins", "delta_cp": -500, "reason": "эль"})
	assert_int(s.character["gold_cp"]).is_equal(gold)
	var lines := fx.apply(s, "t-1", [id])
	assert_int(s.character["gold_cp"]).is_equal(gold - 500)
	assert_array(lines).is_equal(["−5 зм"])
	assert_dict(fx.reserves).is_empty()


func test_unlisted_and_foreign_reserves_burn() -> void:
	var a := _ok({"kind": "coins", "delta_cp": -100, "reason": "a"})
	_ok({"kind": "coins", "delta_cp": -100, "reason": "b"})
	var other := _ok({"kind": "coins", "delta_cp": -100, "reason": "c"}, "t-2")
	var gold := int(s.character["gold_cp"])
	fx.apply(s, "t-1", [a, other])  # other turn's id is ignored
	assert_int(s.character["gold_cp"]).is_equal(gold - 100)
	assert_int(fx.reserves.size()).is_equal(1)
	fx.discard("t-2")
	assert_dict(fx.reserves).is_empty()


func test_effect_limit_per_turn() -> void:
	for i in 3:
		_ok({"kind": "note", "text": "событие номер %d" % i})
	assert_str(_no({"kind": "note", "text": "событие номер 9"})).contains("лимит")


func test_move_only_to_an_exit_and_once() -> void:
	assert_str(_no({"kind": "move", "room_id": TestUtils.FAR_ROOM})).contains("нет выхода")
	var id := _ok({"kind": "move", "room_id": TestUtils.KITCHEN})
	assert_str(_no({"kind": "move", "room_id": "brod-square"})).contains("уже")
	fx.apply(s, "t-1", [id])
	assert_str(s.room_id).is_equal(TestUtils.KITCHEN)


func test_coins_respect_the_purse_including_pending_and_the_reward_cap() -> void:
	var gold := int(s.character["gold_cp"])
	_ok({"kind": "coins", "delta_cp": -(gold - 100), "reason": "a"})
	assert_str(_no({"kind": "coins", "delta_cp": -200, "reason": "b"})).contains("нет")
	assert_str(_no({"kind": "coins", "delta_cp": 50001, "reason": "клад"}, "t-2")).contains("бюджета")


func test_damage_rolls_dice_by_level_and_hp_never_below_zero() -> void:
	var id := _ok({"kind": "damage", "severity": "deadly", "damage_type": "огонь", "reason": "взрыв"})
	var amount := int(fx.reserves[id]["plan"]["amount"])
	assert_int(amount).is_between(4, 40)  # 4d10 at level 1
	fx.apply(s, "t-1", [id])
	assert_int(s.character["hp"]).is_equal(maxi(0, 12 - amount))
	assert_str(_no({"kind": "damage", "severity": "apocalyptic", "damage_type": "x", "reason": "y"}, "t-2")).is_not_empty()


func test_heal_only_when_hurt_and_capped() -> void:
	assert_str(_no({"kind": "heal", "tier": "minor", "reason": "x"})).contains("здоров")
	s.character["hp"] = 1
	fx.apply(s, "t-2", [_ok({"kind": "heal", "tier": "major", "reason": "зелье"}, "t-2")])
	assert_int(s.character["hp"]).is_equal(12)


func test_give_and_take_catalog_items() -> void:
	var give := _ok({"kind": "give_item", "item_id": "torch", "qty": 3})
	assert_str(_no({"kind": "give_item", "item_id": "longsword", "qty": 2})).contains("стопку")
	assert_str(_no({"kind": "give_item", "item_id": "excalibur"})).contains("нет")
	fx.apply(s, "t-1", [give])
	assert_int(s.character["inventory"]["torch"]).is_equal(13)  # 10 from the explorer's pack + 3
	var take := _ok({"kind": "take_item", "item_id": "handaxe", "qty": 2}, "t-2")
	assert_str(_no({"kind": "take_item", "item_id": "handaxe", "qty": 1}, "t-2")).contains("нет")
	fx.apply(s, "t-2", [take])
	assert_bool(s.character["inventory"].has("handaxe")).is_false()


func test_new_item_needs_a_search_and_a_level_fitting_rarity() -> void:
	var item := {"name": "Кинжал инея", "item_type": "weapon", "base": "dagger", "rarity": "common", "value_cp": 2000,
		"properties": ["finesse", "cold_damage"]}
	assert_str(_no({"kind": "give_item", "item": item})).contains("find_items")
	fx.mark_searched("t-1")
	var r := fx.validate(s, data, "t-1", {"kind": "give_item", "item": item})
	assert_bool(r["accepted"]).is_true()
	assert_str(r["item_id"]).starts_with("gen_")
	fx.apply(s, "t-1", [r["effect_id"]])
	var def: Dictionary = s.items[r["item_id"]]
	assert_str(def["rarity"]).is_equal("uncommon")  # the engine sets rarity from the properties, not the model
	assert_int(s.character["inventory"][r["item_id"]]).is_equal(1)
	fx.mark_searched("t-2")
	var too_strong := item.duplicate()
	too_strong["properties"] = ["magic_plus3"]
	assert_str(_no({"kind": "give_item", "item": too_strong}, "t-2")).contains("недоступен")
	var unknown := item.duplicate()
	unknown["properties"] = ["vorpal"]
	assert_str(_no({"kind": "give_item", "item": unknown}, "t-2")).contains("неизвестно")


func test_npc_attitude_only_for_npcs_here_and_clamped() -> void:
	assert_str(_no({"kind": "npc_attitude", "npc_id": TestUtils.COOK, "delta": 1, "reason": "x"})).contains("нет")
	for t in ["t-1", "t-2"]:
		fx.apply(s, t, [_ok({"kind": "npc_attitude", "npc_id": TestUtils.INNKEEPER, "delta": 2, "reason": "помог"}, t)])
	assert_int(s.attitude(TestUtils.INNKEEPER)).is_equal(3)


func test_flags() -> void:
	fx.apply(s, "t-1", [_ok({"kind": "flag", "flag": "burrow_known"})])
	assert_array(s.flags).is_equal(["burrow_known"])
	fx.apply(s, "t-2", [_ok({"kind": "flag", "flag": "burrow_known", "value": false}, "t-2")])
	assert_array(s.flags).is_empty()


## Playtest-3: the master set made-up flags («ayra_swore_to_hooded») the player saw as ids — only the pack's
## flags are flags, the master's own memory is a note in Russian (v0.7.4).
func test_a_made_up_flag_is_refused_and_a_note_is_kept() -> void:
	assert_str(_no({"kind": "flag", "flag": "ayra_swore_to_hooded"})).contains("note")
	var lines := fx.apply(s, "t-1", [_ok({"kind": "note", "text": "Айра поклялась служить человеку в капюшоне"})])
	assert_str(lines[0]).is_equal("Запомнено: Айра поклялась служить человеку в капюшоне")
	assert_str(str(s.notes[0]["text"])).contains("поклялась")
	assert_int(int(s.notes[0]["day"])).is_equal(s.day)


func test_gear_by_words_strips_and_dresses() -> void:
	var eq: Dictionary = s.character["equipped"]
	var armor := str(eq.get("armor", ""))
	var shield := str(eq.get("shield", ""))
	var ac := int(s.character["ac"])
	var lines := fx.apply(s, "t-1", [_ok({"kind": "equip", "slot": "all"})])
	assert_str(lines[0]).starts_with("Снято:")
	for sl: String in CharacterRules.SLOTS:
		assert_str(str(s.character["equipped"][sl])).is_empty()
	assert_int(int(s.character["ac"])).is_less_equal(ac)
	assert_str(_no({"kind": "equip", "slot": "all"}, "t-2")).contains("ничего не надето")
	if not armor.is_empty():
		fx.apply(s, "t-3", [_ok({"kind": "equip", "slot": "armor", "item_id": armor}, "t-3")])
		assert_str(str(s.character["equipped"]["armor"])).is_equal(armor)
		assert_int(int(s.character["ac"])).is_equal(ac - (2 if not shield.is_empty() else 0))  # the armour back, the shield still off
	assert_str(_no({"kind": "equip", "slot": "armor", "item_id": "no_such_item"}, "t-4")).contains("нельзя надеть")


func test_unknown_kind() -> void:
	assert_str(_no({"kind": "summon_dragon"})).contains("не знает")


## Playtest-2: the master handed over the letter by give_item and took it by take_item — the quest never started.
## A quest thing by words now takes the quest at its giver and closes the step at its addressee (v0.7.2).
func test_a_quest_thing_by_words_takes_and_closes_the_quest() -> void:
	s.room_id = "brod-tavern-hall"
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = "npc_innkeeper"
	var given := fx.apply(s, "t-1", [_ok({"kind": "give_item", "item_id": "bruno_letter"})])
	assert_bool(s.quests_active.has("letter_to_ilva")).is_true()
	assert_int(int(s.character["inventory"]["bruno_letter"])).is_equal(1)
	assert_str(given[0]).contains("Письмо для Илвы")
	assert_str(_no({"kind": "give_item", "item_id": "bruno_letter"}, "t-2")).contains("уже выдана")
	s.room_id = "brod-temple"
	s.npc_id = "npc_priestess"
	var xp := int(s.character["xp"])
	var handed := fx.apply(s, "t-3", [_ok({"kind": "take_item", "item_id": "bruno_letter"}, "t-3")])
	assert_bool(s.quests_done.has("letter_to_ilva")).is_true()
	assert_bool(s.character["inventory"].has("bruno_letter")).is_false()
	assert_int(int(s.character["xp"])).is_equal(xp)  # v0.7.19: a delivery gives no class experience
	assert_str("\n".join(handed)).contains("сделано")


func test_a_quest_thing_elsewhere_is_refused() -> void:
	s.room_id = "brod-square"
	assert_str(_no({"kind": "give_item", "item_id": "bruno_letter"})).contains("Взять задание")
	s.room_id = "brod-tavern-hall"
	QuestRules.accept(s, data, "letter_to_ilva")
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = "npc_innkeeper"
	assert_str(_no({"kind": "take_item", "item_id": "bruno_letter"}, "t-2")).contains("Сестра Илва")
