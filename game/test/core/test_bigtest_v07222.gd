extends GdUnitTestSuite
## The big test's blockers (roadmap v0.7.22.2): a thing dropped from the sheet, the patrol that came back at once,
## the guard's hold answered by words and a bribe, the guard leading the hero to the captain, magic things the
## master could never give.

var data: Dictionary
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	fx = EffectEngine.new()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _do(s: GameSession, e: Dictionary, turn := "t-1") -> Dictionary:
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


## A murder known in Brod, the hero held by the patrol in the tavern hall.
func _held() -> GameSession:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	TimeRules.advance(s, data, int(data["rules"]["crime"]["search_minutes"]))
	CrimeRules.check_arrest(s, data)
	return s


func test_a_held_weapon_drops_and_leaves_the_hand() -> void:
	var s := _hero("brod-square")
	var c := s.character
	var weapon := str(c["equipped"]["main_hand"])
	assert_str(weapon).is_not_empty()
	assert_int(ContainerRules.droppable(s, data, weapon)).is_greater(0)
	var r := ContainerRules.plan_drop(s, data, weapon, 1)
	assert_bool(r.has("plan")).override_failure_message(str(r)).is_true()
	ContainerRules.apply_drop(s, data, r["plan"])
	if not (c["inventory"] as Dictionary).has(weapon):
		assert_str(str(c["equipped"]["main_hand"])).is_empty()
	assert_bool((s.props["brod-square"] as Array).any(func(p: Dictionary) -> bool: return p["item_id"] == weapon)).is_true()
	var armor := str(c["equipped"].get("armor", ""))
	if not armor.is_empty() and int(c["inventory"].get(armor, 0)) == 1:
		assert_int(ContainerRules.droppable(s, data, armor)).is_equal(0)  # take the armour off first


func test_fought_free_no_patrol_at_once_then_by_chance() -> void:
	var s := _held()
	assert_bool(CrimeRules.held(s)).is_true()
	CrimeRules.answer(s, data, "resist")
	s.pending_fight = []
	assert_bool(CrimeRules.held(s)).is_false()
	assert_array(CrimeRules.check_arrest(s, data)).is_empty()  # big test #6: the same minute — no new patrol
	TimeRules.advance(s, data, 60)
	assert_array(CrimeRules.check_arrest(s, data)).is_empty()
	assert_bool(s.wanted.has("brod")).is_true()  # still wanted
	TimeRules.advance(s, data, int(data["rules"]["crime"]["let_go_minutes"]))
	var held := 0
	for i in 40:
		s.arrest = ""
		if not CrimeRules.check_arrest(s, data).is_empty():
			held += 1
	assert_int(held).is_greater(0).is_less(40)  # a patrol by chance, not every step


func test_talked_out_bribed_or_threatened() -> void:
	var s := _held()
	assert_str(CrimeRules.talk_tier(s, data, "brod")).is_equal("very_hard")  # Bruno is a mercenary — notable
	assert_array(CrimeRules.talked(s, data, "persuade", false)).contains(["Стража не верит ни слову"])
	assert_bool(CrimeRules.held(s)).is_true()
	assert_str(CrimeRules.can_answer(s, data, "persuade")).is_equal("CRIME_TRIED")
	var lines := CrimeRules.talked(s, data, "intimidate", false)
	assert_bool(s.pending_fight.is_empty()).is_false()  # a failed threat — a fight
	assert_str(" · ".join(lines)).contains("стража берётся за оружие")
	s = _held()
	s.character["gold_cp"] = 100000
	var bribe := CrimeRules.bribe(s, data, "brod")
	assert_int(bribe).is_equal(int(CrimeRules.fine(s, data, "brod") * float(data["rules"]["crime"]["bribe_share"])))
	CrimeRules.answer(s, data, "bribe")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - bribe)
	assert_bool(CrimeRules.held(s)).is_false()
	assert_bool(s.wanted.has("brod")).is_true()  # let go, not forgiven
	assert_array(CrimeRules.check_arrest(s, data)).is_empty()


func test_an_ordinary_victim_is_easier_to_talk_away() -> void:
	var s := _hero("brod-square")
	CrimeRules.on_death(s, data, "npc_merchant", true, s.room_id)
	assert_str(CrimeRules.talk_tier(s, data, "brod")).is_equal("hard")


func test_the_guard_leads_the_hero_to_the_captain() -> void:
	var s := _held()
	var r := _do(s, {"kind": "move", "room_id": "brod-gate"})  # not an exit of the hall — the guard leads
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_str(s.room_id).is_equal("brod-gate")
	assert_bool(CrimeRules.held(s)).is_true()  # the hold goes along
	assert_bool(bool(_do(s, {"kind": "move", "room_id": "pushcha-edge"}, "t-2")["accepted"])).is_false()  # not out of Brod
	var snap := CrimeRules.snapshot(s, data)
	assert_bool(snap.has("escort_to")).is_true()
	r = _do(s, {"kind": "crime_release"}, "t-3")
	assert_str(str(r["reason"])).contains("проверки")
	fx.note_check("t-4", "hard", true)
	assert_bool(bool(_do(s, {"kind": "crime_release"}, "t-4")["accepted"])).is_false()  # below the talk tier (very_hard)
	fx.note_check("t-5", "very_hard", true)
	assert_bool(bool(_do(s, {"kind": "crime_release"}, "t-5")["accepted"])).is_true()
	assert_bool(CrimeRules.held(s)).is_false()
	assert_bool(s.wanted.has("brod")).is_true()


func test_the_hold_survives_a_save() -> void:
	var s := _held()
	CrimeRules.talked(s, data, "deceive", false)
	var back := GameSession.from_dict(s.to_dict(5))
	assert_array(back.arrest_tried).contains_exactly(["deceive"])
	CrimeRules.answer(back, data, "resist")
	var again := GameSession.from_dict(back.to_dict(5))
	assert_bool(again.let_go.has("brod")).is_true()


func test_magic_without_mechanics_is_refused() -> void:
	var r := ItemRules.check_generated(data["items"], {"name": "Якорь Светлой Матери", "item_type": "wondrous", "rarity": "uncommon",
		"value_cp": 0, "properties": [], "description": "Свойства неизвестны."}, 4)
	assert_bool(bool(r["ok"])).is_false()
	assert_str(str(r["reason"])).contains("без механики")
	r = ItemRules.check_generated(data["items"], {"name": "Камешек", "item_type": "gear", "rarity": "common", "value_cp": 0, "properties": []}, 4)
	assert_bool(bool(r["ok"])).is_true()


func test_a_magic_find_needs_a_check_and_one_a_rest() -> void:
	var s := _hero("brod-temple")
	s.character["level"] = 4
	var r := _do(s, {"kind": "give_item", "item_id": "goggles_of_night"})
	assert_str(str(r["reason"])).contains("пройденной проверкой")
	fx.note_check("t-2", "medium", true)
	r = _do(s, {"kind": "give_item", "item_id": "goggles_of_night"}, "t-2")
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()  # big test #16: past the coin budget
	assert_int(s.reward_spent).is_equal(0)
	assert_int(s.magic_given).is_equal(1)
	fx.note_check("t-3", "medium", true)
	assert_str(str(_do(s, {"kind": "give_item", "item_id": "goggles_of_night"}, "t-3")["reason"])).contains("уже дана")
	ExplorationRules.long_rest(s, data)
	assert_int(s.magic_given).is_equal(0)


func test_carried_goggles_say_they_work() -> void:
	var s := _hero("brod-temple")
	s.character["inventory"]["goggles_of_night"] = 1
	CharacterRules.refresh(s.character, data, s.items)
	assert_array(ItemInfo.lines(s.character, data, s.items, "goggles_of_night")).contains([TranslationServer.translate("ITEM_WORKS_CARRIED")])
