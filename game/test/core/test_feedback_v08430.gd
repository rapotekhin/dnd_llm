extends GdUnitTestSuite
## The author's feedback (v0.8.4.30): a person's quest goes on from what happened between it and the hero; the foes of
## a lair own its things — taken, they are the hero's spoil, no theft.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func test_a_persons_quest_frame_carries_what_it_remembers_and_its_quests() -> void:
	s.remember("npc_serving", "герой спас её из землянки ловчего")
	fx.searched_quests["t-q"] = true
	var r := fx.validate(s, data, "t-q", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Пленница",
		"difficulty": "easy", "description": "Мира пропала.", "offer_text": "Найди Миру.", "acts": [{"title": "Землянка", "goal": "Освободить Миру"}]})
	fx.apply(s, "t-q", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, id)
	var a := fx.validate(s, data, "t-a", {"kind": "quest_act", "quest_id": id, "act": 1, "steps": [{"text": "Поговорить с Мирой", "kind": "talk", "target": "npc_serving"}]})
	assert_bool(bool(a["accepted"])).override_failure_message(str(a)).is_true()
	fx.apply(s, "t-a", [a["effect_id"]])
	var past := "\n".join(QuestGen.person_past(s, data, "npc_serving"))
	assert_str(past).contains("Помнит о герое").contains("спас её")
	assert_str(past).contains("Был в задании «Пленница» (взято)")
	var frame := PrepareRules.frame(s, data, {"kind": "quest", "npc": "npc_serving", "room": s.room_id})
	assert_str(frame).contains("Был в задании «Пленница»").contains("Помнит о герое")
	assert_str("\n".join(QuestGen.person_past(s, data, "npc_innkeeper"))).contains("Его задание «Пленница»")


func test_the_foes_of_a_lair_own_its_things_and_taking_them_is_no_theft() -> void:
	var room := ""
	for rid: String in data["world"]["rooms"]:
		if not EncounterRules.live(s, data, rid).is_empty():
			room = rid
			break
	assert_str(room).is_not_empty()
	var foes := OwnerRules.FOES + str(EncounterRules.live(s, data, room)["id"])
	assert_array(PropRules.owners(s, data, room)).contains([foes])
	assert_str(OwnerRules.name_of(s, data, foes)).is_not_empty()
	assert_bool(OwnerRules.claims(foes)).is_false()
	assert_bool(OwnerRules.claims("npc_innkeeper")).is_true()
	s.room_id = room
	var r := fx.validate(s, data, "t-f", {"kind": "furnish", "props": [{"name": "Сундук ловчего", "container": "chest", "owner": foes,
		"contents": [{"item_id": "candle", "qty": 2}]}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-f", [r["effect_id"]])
	var chest: Dictionary = PropRules.room_props(s, room).filter(func(p: Dictionary) -> bool: return str(p["name"]) == "Сундук ловчего")[0]
	assert_str(str(chest["owner"])).is_equal(foes)
	ContainerRules.apply_take(s, data, ContainerRules.plan_take(s, data, str(chest["id"]), "candle", 2)["plan"])
	assert_dict(OwnerRules.foreign(s)).is_empty()


func test_a_foe_is_looked_over_by_the_same_check_as_in_a_fight() -> void:
	var t := {"id": "c1", "name": "Волк", "monster": "wolf"}
	var lines := CombatRules.look_over(s, data, t)
	assert_str(lines[0]).contains("присматривается").contains("Волк")
	assert_bool(Knows.has(s, Knows.MONSTER, "wolf") == lines[0].contains("теперь ясно")).is_true()


func test_a_quest_follows_an_offered_one_and_ahead_stops_when_it_ends() -> void:
	fx.searched_quests["t-q"] = true
	var r := fx.validate(s, data, "t-q", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Мыши",
		"difficulty": "easy", "description": "Мыши.", "offer_text": "Мыши!", "acts": [{"title": "Подвал", "goal": "Выгнать мышей"}]})
	fx.apply(s, "t-q", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, id)
	assert_bool(QuestRules.ahead(s, data["world"], id, 0)).is_true()  # waits for its act
	s.quests_active.erase(id)
	s.quests_done.append(id)
	assert_bool(QuestRules.ahead(s, data["world"], id)).is_false()


func test_a_weapon_tells_the_fire_its_properties_add() -> void:
	var def: Dictionary = (data["items"]["catalog"]["dagger"] as Dictionary).merged({"properties": ["fire_damage"]}, true)
	assert_array(ItemRules.elements(data, def)).is_equal([{"dice": "1d6", "type": "fire"}])
	assert_str(ItemInfo.kind_line(data, def)).contains("1к4").contains("+ 1к6 огонь")


func test_a_made_thing_or_spell_must_deal_the_damage_its_words_promise() -> void:
	assert_str(MakeRules.told_damage(data, "Клинок наносит урон огнём.", ["slashing"])).contains("огонь")
	assert_str(MakeRules.told_damage(data, "Клинок наносит урон огнём.", ["fire"])).is_empty()
	assert_str(MakeRules.told_damage(data, "Выкован в огне дракона. Рубит врагов.", ["slashing"])).is_empty()
	var item := {"name": "Огненный удар", "base": "dagger", "item_type": "weapon", "rarity": "uncommon", "description": "Кинжал; при ударе наносит урон огнём."}
	var bad := ItemRules.check_generated(data, item, 20)
	assert_bool(bool(bad["ok"])).is_false()
	assert_str(str(bad["reason"])).contains("fire_damage")
	var good := ItemRules.check_generated(data, item.merged({"properties": ["fire_damage"]}), 20)
	assert_bool(bool(good["ok"])).override_failure_message(str(good)).is_true()
	var spell := MakeRules.plan(s, data, {"kind": "make", "what": "spell", "key": "fs", "name": "Огненный удар", "text": "Удар наносит урон огнём.",
		"parts": [{"part": "damage", "value": "cold", "amount": 2}, {"part": "roll", "value": "attack"}]})
	assert_str(str(spell.get("reason", ""))).override_failure_message(str(spell)).contains("огонь")


func test_fire_and_the_other_surfaces_have_a_look_of_their_own() -> void:
	var fire := AnimRules.surface(data, {"spell": "fire", "type": "fire"})
	assert_str(str(fire["kind"])).is_equal("flames")
	assert_bool(bool(fire["moves"])).is_true()
	assert_str(str(AnimRules.surface(data, {"spell": "puddle:oil", "tile": "o"})["kind"])).is_equal("gloss")
	assert_str(str(AnimRules.surface(data, {"spell": "gen_sp_x", "type": "cold"})["kind"])).is_equal("frost")
	assert_dict(AnimRules.surface(data, {"spell": "bless"})).is_empty()


func test_a_stack_of_buckets_weighs_by_each_one_filled() -> void:
	var c := s.character
	c["poured"] = true  # no starting vessel filled by its catalog row
	var before := CharacterRules.carried_weight(c, data, s.items)
	ItemRules.add(c, "bucket", 3)
	assert_float(CharacterRules.carried_weight(c, data, s.items) - before).is_equal_approx(6.0, 0.01)
	LiquidRules.fill(c, data, false, "bucket")
	assert_float(CharacterRules.carried_weight(c, data, s.items) - before).is_equal_approx(78.0, 0.01)  # 3 × (2 + 24)
	ItemRules.remove(c, "bucket")
	assert_float(CharacterRules.carried_weight(c, data, s.items) - before).is_equal_approx(52.0, 0.01)


func test_a_quest_giver_lets_the_hero_into_its_own_place_for_the_quest() -> void:
	var world := WorldView.new(data["world"])
	var room := ""
	var owner := ""
	for rid: String in data["world"]["rooms"]:
		var o := SiteRules.unwelcome(s, data, rid)
		if not o.is_empty() and not world.npc(o).is_empty():
			room = rid
			owner = o
			break
	assert_str(room).is_not_empty()
	fx.searched_quests["t-g"] = true
	var r := fx.validate(s, data, "t-g", {"kind": "create", "what": "quest", "giver": owner, "title": "За дверью",
		"difficulty": "easy", "description": "Забрать вещь у хозяина.", "offer_text": "Зайди ко мне.", "acts": [{"title": "Комната", "goal": "Зайти"}]})
	fx.apply(s, "t-g", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, id)
	var a := fx.validate(s, data, "t-a", {"kind": "quest_act", "quest_id": id, "act": 1, "steps": [{"text": "Зайти к хозяину", "kind": "visit", "target": room}]})
	assert_bool(bool(a["accepted"])).override_failure_message(str(a)).is_true()
	fx.apply(s, "t-a", [a["effect_id"]])
	QuestRules.advance(s, data)
	assert_str(SiteRules.unwelcome(s, data, room)).is_empty()
	assert_str(str(s.permits.get(world.site_id(room), ""))).is_equal(owner)


func test_crafting_stops_when_the_crafter_is_worn_out() -> void:
	ConditionRules.add_exhaustion(s, data, 3, "без сна")
	assert_bool(CraftRules.tired(s, data)).is_true()
	assert_str(CraftRules.can_work(s, data)).is_equal("CRAFT_NO_PROJECT")
	s.character["craft"] = Progress.of_work(60).merged({"recipe": "x"})
	assert_str(CraftRules.can_work(s, data)).is_equal("CRAFT_TOO_TIRED")


func test_a_thing_that_bars_the_way_never_cuts_one_door_from_another() -> void:
	var cells: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			cells.append(Vector2i(x, y))
	var ways: Array[Vector2i] = [Vector2i(0, 0), Vector2i(4, 0)]
	var walls := {Vector2i(2, 1): true}
	var at := MapSpots._off_the_way(cells, cells, ways, walls, {}, Vector2i(2, 0))
	assert_bool(at == Vector2i(2, 0)).is_false()
	assert_bool(MapSpots._joined(cells, ways, walls, at)).is_true()
	assert_bool(MapSpots._off_the_way(cells, cells, ways, {}, {}, Vector2i(2, 0)) == Vector2i(2, 0)).is_true()


func test_each_spent_arrow_is_found_by_its_own_chance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var back := Gear.shot_back(data, {"ammo_spent": {"arrows": 100}}, rng)
	assert_int(int(back.get("arrows", 0))).is_between(35, 65)
	assert_dict(Gear.shot_back(data, {"ammo_spent": {}}, rng)).is_empty()


func test_the_arena_picks_an_opponent_by_the_heros_level() -> void:
	s.character["level"] = 1
	for id: String in ArenaRules.pool(s, data, 0):
		assert_float(float(data["monsters"][id]["cr"])).is_less_equal(0.125)
	s.character["level"] = 5
	var top := ArenaRules.pool(s, data, 3)
	assert_array(top).is_not_empty()
	for id: String in top:
		assert_float(float(data["monsters"][id]["cr"])).is_between(1.5, 3.0)
	var lad := ArenaRules.ladder(s, data, "x")
	assert_int(lad.size()).is_equal((data["rules"]["arena"]["ranks"] as Array).size())
	assert_int(int(lad[-1]["wins"])).is_equal(0)
	assert_int(int(lad[0]["prize_cp"])).is_greater(0)
