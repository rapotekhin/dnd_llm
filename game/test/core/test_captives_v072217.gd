extends GdUnitTestSuite
## The prisoner's branch (roadmap v0.7.22.17, the author's fixes check #7, #10, #11, #12, #15, #34): the table
## «Пленник» in docs/design/concepts.md — a truce is no captivity; a bound one is the hero's: handed to the law for a
## bounty, sold by the master's `owner`, executed before witnesses; the hero surrenders at once, the captors seize the
## hero's things into a chest of the room, the law's guard holds instead of binding; stolen things stay someone else's.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _creature(s: GameSession, monster: String, state: String, bound: bool = false) -> Dictionary:
	s.creature_counter += 1
	var c := {"id": "c%d" % s.creature_counter, "name": monster, "monster": monster, "state": state, "bound": bound, "led": false,
		"since": TimeRules.abs_minute(s), "hp": 3, "max_hp": 7, "xp_given": true}
	if bound:
		c["owner"] = OwnerRules.HERO
	var list: Array = s.creatures.get(s.room_id, [])
	list.append(c)
	s.creatures[s.room_id] = list
	return c


func test_a_truce_is_no_captivity() -> void:
	var s := _hero("pushcha-hollow")
	var c := _creature(s, "goblin", "truce")
	assert_bool(CreatureRules.captive(c)).is_false()
	assert_str(CreatureRules.can(s, str(c["id"]), "bind", data)).is_equal("CREATURE_CANNOT_BIND")
	assert_str(CreatureRules.text(c, data)).not_contains("пленник")
	var p := _creature(s, "goblin", "surrendered")
	assert_bool(CreatureRules.captive(p)).is_true()
	CreatureRules.act(s, data, str(p["id"]), "bind")
	assert_str(str(p["owner"])).is_equal(OwnerRules.HERO)
	assert_str(CreatureRules.text(p, data)).contains("ваш пленник")


func test_the_law_takes_a_prisoner_for_a_bounty() -> void:
	var wild := _hero("pushcha-hollow")
	var w := _creature(wild, "goblin", "surrendered", true)
	assert_str(CreatureRules.can(wild, str(w["id"]), "hand_over", data)).is_equal("CREATURE_NO_LAW")
	var s := _hero("brod-square")
	var c := _creature(s, "goblin", "surrendered", true)
	var loose := _creature(s, "goblin", "surrendered")
	assert_str(CreatureRules.can(s, str(loose["id"]), "hand_over", data)).is_equal("CREATURE_NOT_YOUR_PRISONER")
	assert_str(CreatureRules.can(s, str(c["id"]), "hand_over", data)).is_empty()
	var gold := int(s.character["gold_cp"])
	var rep := ReputationRules.points(s, "brod")
	CreatureRules.act(s, data, str(c["id"]), "hand_over")
	assert_dict(CreatureRules.find(s, s.room_id, str(c["id"]))).is_empty()
	assert_int(int(s.character["gold_cp"]) - gold).is_equal(int(data["rules"]["creatures"]["bounty_cp_per_xp"]) * 50)
	assert_int(ReputationRules.points(s, "brod")).is_equal(rep + int(data["rules"]["creatures"]["hand_over_reputation"]))


func test_an_execution_before_people_is_remembered() -> void:
	var s := _hero("brod-square")
	var c := _creature(s, "goblin", "surrendered", true)
	var before := s.attitude("npc_merchant")
	var lines := CreatureRules.act(s, data, str(c["id"]), "finish")
	assert_int(s.attitude("npc_merchant")).is_equal(before + int(data["rules"]["creatures"]["execute_attitude"]))
	assert_str(" ".join(s.memory_of("npc_merchant"))).contains("пленника")
	assert_str(" ".join(lines)).contains("казнь")


func test_surrender_ends_the_fight_at_once() -> void:
	var s := _hero("pushcha-hollow")
	CombatRules.start(s, data, [{"monster": "wolf", "col": 0}], {})
	s.combat["turn"] = s.combat["order"].find(CombatRules.PLAYER)
	assert_str(CombatRules.can_surrender(s, data)).is_equal("COMBAT_NO_SURRENDER")  # beasts take nobody alive
	var t := _hero("pushcha-hollow")
	CombatRules.start(t, data, [{"monster": "goblin", "col": 0}], {})
	t.combat["turn"] = t.combat["order"].find(CombatRules.PLAYER)
	assert_str(CombatRules.can_surrender(t, data)).is_empty()
	CombatRules.surrender(t)
	assert_str(str(t.combat["outcome"])).is_equal("captured")
	assert_bool(CombatRules.law_captors(t)).is_false()


func test_given_up_to_the_guard_the_hero_is_held() -> void:
	var s := _hero("brod-square")
	s.wanted["brod"] = 0
	s.arrest = s.room_id
	CrimeRules.answer(s, data, "resist")
	CombatRules.start(s, data, s.pending_fight, {})
	s.pending_fight = []
	assert_bool(CombatRules.law_captors(s)).is_true()
	CrimeRules.held_after_fight(s, data)
	assert_bool(CrimeRules.held(s)).is_true()
	assert_str(CrimeRules.can_answer(s, data, "resist")).is_equal("CRIME_TRIED")
	assert_str(CrimeRules.can_answer(s, data, "stocks")).is_empty()


func test_the_captors_seize_the_heros_things() -> void:
	var s := _hero("pushcha-hollow")
	s.props[s.room_id] = []  # furnished with nothing that holds things
	var had: Dictionary = (s.character["inventory"] as Dictionary).duplicate()
	assert_bool(had.is_empty()).is_false()
	EncounterRules.capture(s, [{"monster": "goblin", "name": "Гоблин", "count": 1}], "", "pushcha-trail")
	var lines := EncounterRules.seize(s, data)
	assert_str(" ".join(lines)).contains(str(data["rules"]["encounters"]["seized_name"]))
	assert_dict(s.character["inventory"]).is_empty()
	assert_str(str(s.character["equipped"]["main_hand"])).is_empty()
	var chest: Dictionary = PropRules.room_props(s, s.room_id)[0]
	assert_bool(bool(chest.get("seized", false))).is_true()
	for id: String in had:
		assert_int(int(chest["contents"].get(id, 0))).is_greater_equal(int(had[id]))
	assert_bool(PropRules.needs_furnish(s, s.room_id)).is_true()  # the chest is no furnishing of the master
	var some: String = had.keys()[0]
	assert_dict(ContainerRules.plan_take(s, data, str(chest["id"]), some, 1)).contains_keys(["reason"])  # bound
	s.captive = {}
	var r := ContainerRules.plan_take(s, data, str(chest["id"]), some, 1)
	assert_dict(r).contains_keys(["plan"])
	ContainerRules.apply_take(s, data, r["plan"])
	assert_int(int(s.character["inventory"].get(some, 0))).is_equal(1)
	assert_dict(OwnerRules.foreign(s)).is_empty()  # the hero's own things are not stolen back


func test_the_master_sells_a_beast_not_a_thinking_one() -> void:
	var s := _hero("brod-square")
	var wolf := _creature(s, "wolf", "unconscious", true)
	var gob := _creature(s, "goblin", "surrendered", true)
	var loose := _creature(s, "wolf", "unconscious")
	var engine := EffectEngine.new()
	var cap := OwnerRules.bounty_cap(data, gob)  # a thinking one: handed over for the law's bounty, never sold (v0.7.49.4)
	var no := engine.validate(s, data, "t-1", {"kind": "owner", "creature_id": str(gob["id"]), "owner_id": "npc_merchant", "price_cp": cap + 1})
	assert_bool(bool(no["accepted"])).is_false()
	assert_str(str(no["reason"])).contains("рабства нет")
	var handed := engine.validate(s, data, "t-0", {"kind": "owner", "creature_id": str(gob["id"]), "owner_id": "npc_merchant", "price_cp": cap})
	assert_bool(bool(handed["accepted"])).is_true()
	assert_str(str(handed["summary"])).contains("награда за поимку")
	engine.discard("t-0")  # one owner change a turn: this one is not taken
	no = engine.validate(s, data, "t-1", {"kind": "owner", "creature_id": str(loose["id"]), "owner_id": "npc_merchant", "price_cp": 100})
	assert_str(str(no["reason"])).contains("связывают")
	no = engine.validate(s, data, "t-1", {"kind": "owner", "creature_id": str(wolf["id"]), "owner_id": "npc_merchant", "price_cp": 999999})
	assert_str(str(no["reason"])).contains("не больше")
	var gold := int(s.character["gold_cp"])
	var purse := int(TradeRules.merchant(s, data, "npc_merchant")["purse_cp"])
	var ok := engine.validate(s, data, "t-1", {"kind": "owner", "creature_id": str(wolf["id"]), "owner_id": "npc_merchant", "price_cp": 500})
	assert_bool(bool(ok["accepted"])).is_true()
	engine.apply(s, "t-1", [ok["effect_id"]])
	assert_int(int(s.character["gold_cp"]) - gold).is_equal(500)
	assert_int(int(TradeRules.merchant(s, data, "npc_merchant")["purse_cp"])).is_equal(purse - 500)
	assert_str(str(wolf["owner"])).is_equal("npc_merchant")
	assert_bool(CreatureRules.foreign(wolf)).is_true()
	assert_str(CreatureRules.text(wolf, data)).contains("принадлежит")
	var taken := CreatureRules.act(s, data, str(wolf["id"]), "lead")  # led away before its owner — a theft
	assert_str(str(wolf["owner"])).is_equal(OwnerRules.HERO)
	assert_bool(taken.size() > 1).is_true()


func test_a_sold_creature_goes_to_its_buyers_home() -> void:
	var s := _hero("brod-tavern-hall")
	s.followers.append("npc_merchant")  # the merchant is here, his home is the square
	var wolf := _creature(s, "wolf", "unconscious", true)
	wolf["led"] = true
	var engine := EffectEngine.new()
	var ok := engine.validate(s, data, "t-1", {"kind": "owner", "creature_id": str(wolf["id"]), "owner_id": "npc_merchant"})
	assert_bool(bool(ok["accepted"])).is_true()
	engine.apply(s, "t-1", [ok["effect_id"]])
	assert_dict(CreatureRules.find(s, s.room_id, str(wolf["id"]))).is_empty()
	var there := CreatureRules.find(s, "brod-square", str(wolf["id"]))
	assert_bool(bool(there["led"])).is_false()


func test_a_stolen_thing_stays_its_owners() -> void:
	var s := _hero("brod-square")
	var entry: Dictionary = {}
	for e: Dictionary in TheftRules.pockets(s, data, "npc_merchant"):
		if not str(e.get("item_id", "")).is_empty() and not bool(e.get("worn", false)):
			entry = e
	if entry.is_empty():
		return
	var id := str(entry["item_id"])
	TheftRules.steal(s, data, "npc_merchant", str(entry["id"]), true)
	var key: String = OwnerRules.foreign(s).keys()[0]
	assert_int(OwnerRules.held_of(s, key, "npc_merchant")).is_greater(0)
	var all := TradeRules.sellable(s, key, data)
	assert_str(str(TradeRules.quote(s, data, "npc_merchant", {"sell": {key: all - 1}})["error"])).is_empty()  # the hero's own
	assert_str(str(TradeRules.quote(s, data, "npc_merchant", {"sell": {key: all}})["error"])).is_equal("TRADE_ERR_THEIR_OWN")
	var sheet := TurnSnapshot.character_sheet(s, data)
	assert_str(str(sheet["inventory"].filter(func(e: Dictionary) -> bool: return str(e["item_id"]) == key)[0]["name"])).contains("чужое")
	var engine := EffectEngine.new()
	var ok := engine.validate(s, data, "t-1", {"kind": "owner", "item_id": key, "owner_id": "hero"})
	assert_bool(bool(ok["accepted"])).is_true()
	engine.apply(s, "t-1", [ok["effect_id"]])
	assert_int(OwnerRules.held_of(s, key, "npc_merchant")).is_equal(0)
	assert_str(key).is_equal(id)


func test_ownership_survives_the_save_and_old_prisoners_are_the_heros() -> void:
	var s := _hero("brod-square")
	OwnerRules.mark(s, "dagger", 1, "npc_merchant")
	s.character["inventory"]["dagger"] = 1
	s.talk_creature = "c3"
	var back := GameSession.from_dict(s.to_dict(5))
	assert_int(OwnerRules.held_of(back, "dagger", "npc_merchant")).is_equal(1)
	assert_str(back.talk_creature).is_equal("c3")
	var old := {"save_version": 38, "session": {"creatures": {"r": [{"id": "c1", "bound": true}, {"id": "c2", "bound": false}]}}}
	SaveFormat.migrate(old)
	assert_str(str(old["session"]["creatures"]["r"][0].get("owner", ""))).is_equal(OwnerRules.HERO)
	assert_bool(old["session"]["creatures"]["r"][1].has("owner")).is_false()
