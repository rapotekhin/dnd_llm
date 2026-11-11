extends GdUnitTestSuite
## v0.8.4.43.5.2, the author: portraits drawn by Anima instead of a token's letter — a person by race, sex and age in five
## variants (a child in one), a monster by its template in five. One place chooses (PortraitRules.of), one reads a race's
## word (CharacterRules.race_id); a person keeps one face; no file — "" and the letter is drawn.

const ROOT := "res://assets/portraits/"

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func after_test() -> void:
	PortraitRules.forget()


## Pretends the files are drawn, as the generator will lay them.
func _drawn(paths: Array) -> void:
	for p: String in paths:
		PortraitRules._exists[p] = true


func _person(race: String, gender: String, age: String, n: int) -> String:
	return "%speople/%s/%s/%s__%d.webp" % [ROOT, race, gender, age, n]


func test_a_race_word_of_a_person_is_its_id_in_either_form() -> void:
	for pair: Array in [["полуэльфийка", "half_elf"], ["полуэльф", "half_elf"], ["гномка", "gnome"], ["Дварф", "dwarf"],
			["высшая эльфийка", "elf"], ["дроу", "elf"], ["Человек", "human"], ["полуорчиха", "half_orc"],
			["Драконорождённая", "dragonborn"], ["тифлингесса", "tiefling"], ["гнолл", ""], ["", ""]]:
		assert_str(CharacterRules.race_id(data, {"race": pair[0]})).override_failure_message(str(pair)).is_equal(str(pair[1]))
	assert_str(CharacterRules.race_id(data, {"race": "Человек", "race_id": "dwarf"})).is_equal("dwarf")  # a made person's id first
	assert_str(CharacterRules.race_id(data, {"race": "tiefling"})).is_equal("tiefling")  # the hero's id


func test_a_person_of_the_pack_keeps_one_face_of_its_race_sex_and_age() -> void:
	var s := TestUtils.new_session()
	assert_str(PortraitRules.of(s, data, {"npc_id": "npc_herbalist"})).is_empty()  # nothing drawn yet: the letter
	var age := str(BodyRules.npc(data, "npc_herbalist", data["world"]["npcs"]["npc_herbalist"])["age"])
	var all: Array = []
	for n in range(1, 6):
		all.append(_person("gnome", "female", age, n))
	_drawn(all)
	var face := PortraitRules.of(s, data, {"npc_id": "npc_herbalist"})
	assert_array(all).contains([face])  # «гномка» — a gnome woman of her age
	assert_str(PortraitRules.of(s, data, Sheet.who(s, data, "npc_herbalist"))).is_equal(face)  # by any road to her
	assert_str(PortraitRules.of_id(s, data, "npc_herbalist")).is_equal(face)


func test_a_variant_not_drawn_gives_way_to_another_of_the_same() -> void:
	var s := TestUtils.new_session()
	var age := str(BodyRules.npc(data, "npc_smith", data["world"]["npcs"]["npc_smith"])["age"])
	_drawn([_person("dwarf", "male", age, 4)])
	assert_str(PortraitRules.of(s, data, {"npc_id": "npc_smith"})).is_equal(_person("dwarf", "male", age, 4))


func test_a_child_has_one_variant_and_the_rest_five() -> void:
	assert_int(PortraitRules.count(data, "people", "child")).is_equal(1)
	assert_int(PortraitRules.count(data, "people", "teen")).is_equal(5)
	assert_int(PortraitRules.count(data, "monsters", "")).is_equal(5)
	assert_array(PortraitRules.variants(data, "human", "female", "child")).is_equal([_person("human", "female", "child", 1)])
	assert_int(PortraitRules.variants(data, "elf", "male", "old").size()).is_equal(5)
	assert_array(PortraitRules.variants(data, "", "male", "old")).is_empty()


func test_one_not_of_a_race_of_the_game_and_a_creature_take_their_template_s_face() -> void:
	var s := TestUtils.new_session()
	var paths: Array = []
	for n in range(1, 6):
		paths.append("%smonsters/wolf__%d.webp" % [ROOT, n])
	_drawn(paths)
	var face := PortraitRules.of(s, data, {"id": "cr_1", "monster": "wolf"})
	assert_array(paths).contains([face])
	assert_str(PortraitRules.of(s, data, {"id": "cr_1", "monster": "wolf"})).is_equal(face)  # the same creature, the same face
	assert_str(PortraitRules.of(s, data, {"id": "cr_2", "monster": "goblin"})).is_empty()


func test_a_body_not_its_own_shows_the_form() -> void:
	var s := TestUtils.new_session()
	_drawn(["%smonsters/brown_bear__1.webp" % ROOT])
	var f := {"id": "f1", "monster": "druid", "npc_id": "npc_hermit", "effects": [{"guise": {"monster": "brown_bear", "hp": 34, "max_hp": 34}}]}
	assert_str(PortraitRules.of(s, data, f)).is_equal("%smonsters/brown_bear__1.webp" % ROOT)


func test_the_hero_s_face_is_its_pick_else_one_by_its_name() -> void:
	var s := TestUtils.new_session()
	var c := s.character
	var age := str(c["body"]["age"])
	var all: Array = []
	for n in range(1, 6):
		all.append(_person(str(c["race"]), "female" if str(c["gender"]) == "female" else "male", age, n))
	_drawn(all)
	c.erase("portrait")
	assert_str(PortraitRules.of(s, data, Sheet.HERO)).is_equal(all[PortraitRules.hero_variant(data, c) - 1])
	c["portrait"] = 3
	assert_str(PortraitRules.of(s, data, Sheet.HERO)).is_equal(all[2])
	assert_str(PortraitRules.of(s, data, CombatRules.player(s) if CombatRules.active(s) else Sheet.HERO)).is_equal(all[2])


func test_the_pick_at_creation_is_kept_in_the_hero() -> void:
	var ch := TestUtils.preset_choices()
	ch["portrait"] = 2
	assert_int(int(CharacterBuilder.build(ch, data).get("portrait", 0))).is_equal(2)
	ch.erase("portrait")
	assert_bool(CharacterBuilder.build(ch, data).has("portrait")).is_false()


func test_an_npc_of_a_female_race_word_brings_its_race_traits_to_a_fight() -> void:
	var f := {"id": "f1", "monster": "commoner"}
	FeatureRules.give_class(data, f, {"npc_id": "npc_herbalist"})  # «гномка»: before, no gnome's traits at all
	assert_array(f.get("traits", [])).is_equal(CharacterBuilder.race_traits({"race": "gnome"}, data))


func test_the_tokens_of_the_map_carry_their_faces() -> void:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = "brod-tavern-hall"
	var map := WalkRules.view(s, data)
	var tokens := MapSpots.of(s, data, map)
	var people := tokens.filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "npc")
	assert_bool(people.is_empty()).is_false()
	for t: Dictionary in tokens:
		assert_bool(t.has("portrait")).is_true()
		assert_str(str(t["portrait"])).is_empty()  # nothing drawn: the letter
	var n: Dictionary = data["world"]["npcs"][str(people[0]["id"])]
	var age := str(BodyRules.npc(data, str(people[0]["id"]), n)["age"])
	var race := CharacterRules.race_id(data, n)
	var all: Array = []
	for k in range(1, 6):
		all.append(_person(race, "female" if str(n.get("gender", "")) == "female" else "male", age, k))
	_drawn(all)
	tokens = MapSpots.of(s, data, map)
	var again: Dictionary = tokens.filter(func(t: Dictionary) -> bool: return str(t["id"]) == str(people[0]["id"]))[0]
	assert_array(all).contains([str(again["portrait"])])
