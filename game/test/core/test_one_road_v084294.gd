extends GdUnitTestSuite
## One road, review 2, group I (v0.8.4.29.4): the body of a character — one count of speed (CharacterRules.walk) and of the
## Unarmored Defense of anybody, the short rest of anybody with the hero (Rest.short, Rest.hit_die, a Song of Rest), one meal
## and one order of portions, one hunger by the day, one count of what a pint gives.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func test_one_count_of_walking() -> void:
	assert_int(CharacterRules.walk({}, {}, data, {}, 30, 10, [])).is_equal(30)
	assert_int(CharacterRules.walk({"features": ["fast_movement"]}, {}, data, {}, 30, 10, [])).is_equal(40)
	assert_int(CharacterRules.walk({"exhaustion": 2}, {}, data, {}, 30, 10, [])).is_equal(15)
	assert_int(CharacterRules.walk({}, {}, data, {}, 25, 10, ["speed_30"])).is_equal(30)


func test_a_person_with_a_class_walks_and_stands_as_the_hero() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var g := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var before := Sheet.speed(s, data, g)
	g["features"] = ["fast_movement"]
	assert_int(Sheet.speed(s, data, g)).is_equal(before + 10)  # the barbarian's Fast Movement, once the hero's alone


func test_unarmored_defense_of_anybody() -> void:
	var s := _hero("fighter_aira")
	var bear := {"features": ["barbarian_unarmored_defense"], "equipped": {}, "inventory": {}}
	assert_int(Gear.ac(s, data, "brown_bear", bear)).is_equal(13)  # 10 + DEX 0 + CON 3 over its natural 11
	assert_int(Gear.ac(s, data, "brown_bear", {"equipped": {}, "inventory": {}})).is_equal(11)


func test_the_heros_short_rest_is_anybodys() -> void:
	var s := _hero("fighter_aira")
	s.character["hp"] = 1
	var lines := Rest.short(s, data, Being.HERO, 1)
	assert_int(Stock.spent(s.character, "hit_dice")).is_equal(1)
	assert_str("\n".join(lines)).contains("кости хитов")
	assert_bool(s.character.has("hp")).is_true()  # the hero's sheet keeps its key


func test_hit_dice_of_a_person_with_a_class() -> void:
	var s := _hero("fighter_aira")
	var hd := Rest.hit_die(s, data, {"id": "x", "monster": "commoner", "class": "fighter", "level": 3})
	assert_int(int(hd["die"])).is_equal(10)
	assert_int(int(hd["count"])).is_equal(3)
	var plain := Rest.hit_die(s, data, {"id": "y", "monster": "brown_bear"})
	assert_int(int(plain["die"])).is_equal(10)
	assert_int(int(plain["count"])).is_equal(4)


func test_a_song_of_rest_heals_the_company_too() -> void:
	var s := _hero("bard_yas")
	s.character["xp"] = LevelUp.xp_for(data, 2)
	LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(Rest.song(s, data)).is_greater(0)  # the bard of level 2 sings
	s.character["hp"] = 1
	var lines := ExplorationRules.short_rest(s, data, 1, s.rng)
	assert_str(", ".join(lines)).contains("Песнь отдыха")


func test_one_hunger_by_the_day() -> void:
	var rec := {"at": 0}
	var missed := [0]
	var hungry := NeedRules.hunger(rec, "at", 3 * 1440, 1440, func() -> bool: return false, func() -> void: missed[0] += 1)
	assert_int(hungry).is_equal(3)
	assert_int(missed[0]).is_equal(3)
	assert_int(NeedRules.hunger(rec, "at", 4 * 1440, 1440, func() -> bool: return true)).is_equal(0)


func test_one_order_of_portions() -> void:
	var s := _hero("fighter_aira")
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	if foul.is_empty() or food.is_empty():
		return
	var bad := str(foul.keys()[0])
	var good := ""
	for id: String in food:
		if not foul.has(id):
			good = id
			break
	s.character["inventory"] = {bad: 1, good: 1}
	var ids := FoodRules.portions(s, data, s.character)
	if ids.has(bad) and ids.has(good):
		assert_str(str(ids[-1])).is_equal(bad)  # foul food last, for the hero and a follower alike


func test_one_count_of_a_pint() -> void:
	var s := _hero("fighter_aira")
	NeedRules.set_value(s, data, "water", 10.0)
	LiquidRules.nourish(s, data, Sheet.HERO, 2.0, {"water": 1})
	assert_float(NeedRules.value(s, data, "water")).is_equal_approx(10.0 + 2.0 * NeedRules.per_pint(data), 0.01)
