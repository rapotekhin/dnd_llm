extends GdUnitTestSuite
## v0.8.4.43.46: the last partial abilities done whole by 5e (abilities_reviewed.json). Natural Explorer in the favored terrain:
## the party not slowed by mud or snow, sneaking that keeps alert, food found twice, «mountains» of the master read as the
## SRD's «mountain»; Naturally Stealthy hides behind a larger ally too; a dwarf picks its tool; a tinker gnome winds its
## clockwork — no more than three, each for a day; Misty Visions casts a Silent Image that is a veil of the field.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func _weather(s: GameSession, loc: String, k: String) -> void:
	WeatherRules._state(s)["by_loc"][loc] = k
	WeatherRules._flags(s, data)


func _walker(preset_id: String, room: String) -> GameSession:
	var s := _hero(preset_id)
	s.settings["needs"] = false
	s.settings["weather"] = true
	s.room_id = room
	s.minute = 12 * 60
	s.day = 2
	WeatherRules.sync(s, data)
	return s


func _first(s: GameSession) -> void:
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules.economy(s)["action"] = 1
	CombatRules.economy(s)["bonus"] = 1


# --- Natural Explorer -----------------------------------------------------------------------------------------


func test_a_ranger_s_party_is_not_slowed_in_its_favored_terrain() -> void:
	var s := _walker("ranger_velena", "brod-gate")
	assert_bool(FeatureRules.has(s.character, "natural_explorer_forest")).is_true()
	_weather(s, "brod", "clear")
	_weather(s, "pushcha", "snow")
	assert_float(WeatherRules.travel_mult(s, data, "brod-gate", "pushcha-edge", true)).is_greater(1.0)
	assert_float(WeatherRules.travel_mult(s, data, "brod-gate", "pushcha-edge")).is_equal(1.0)  # the forest is the ranger's
	var lines := TimeRules.on_move(s, data, "brod-gate", "pushcha-edge")
	assert_str("\n".join(lines)).contains("знает эти места")
	var other := _walker("fighter_aira", "brod-gate")
	_weather(other, "brod", "clear")
	_weather(other, "pushcha", "snow")
	assert_float(WeatherRules.travel_mult(other, data, "brod-gate", "pushcha-edge")).is_greater(1.0)


func test_a_ranger_companion_leads_the_hero_too() -> void:
	var s := _walker("fighter_aira", "brod-gate")
	_weather(s, "brod", "clear")
	_weather(s, "pushcha", "snow")
	assert_float(WeatherRules.travel_mult(s, data, "brod-gate", "pushcha-edge")).is_greater(1.0)
	Being.of(s, "npc_merchant")["features"] = ["natural_explorer_forest"]
	Being.follow(s, "npc_merchant")
	assert_str(FeatureRules.party_explorer(s, data, "pushcha")).is_not_empty()
	assert_float(WeatherRules.travel_mult(s, data, "brod-gate", "pushcha-edge")).is_equal(1.0)


func test_sneaking_keeps_alert_in_the_favored_terrain_only() -> void:
	var s := _walker("ranger_velena", "pushcha-edge")
	s.sneaking = true
	var plain := TimeRules.passive_penalty(s, data)
	s.sneaking = false
	assert_int(plain).is_equal(TimeRules.passive_penalty(s, data))  # no −5 of sneaking in the forest
	s.room_id = "brod-square"
	var town := TimeRules.passive_penalty(s, data)
	s.sneaking = true
	assert_int(TimeRules.passive_penalty(s, data) - town).is_equal(ExplorationRules.SNEAK_PASSIVE_PENALTY)


func test_food_found_is_twice_in_the_favored_terrain() -> void:
	var s := _walker("ranger_velena", "pushcha-glade")
	s.character["skills"]["survival"] = 40
	assert_int(FeatureRules.forage_mult(s, data)).is_equal(2)
	var before := (s.character["inventory"] as Dictionary).duplicate()
	var lines := CraftRules.gather(s, data, "forage")
	assert_str("\n".join(lines)).contains("вдвое")
	var got := 0
	for id: String in s.character["inventory"]:
		if FoodRules.spoils_days(data, s.items, id) > 0:
			got += int(s.character["inventory"][id]) - int(before.get(id, 0))
	assert_int(got).is_greater(0)
	assert_int(got % 2).is_equal(0)
	var plain := _walker("fighter_aira", "pushcha-glade")
	assert_int(FeatureRules.forage_mult(plain, data)).is_equal(1)
	plain.room_id = "brod-square"
	s.room_id = "brod-square"
	assert_int(FeatureRules.forage_mult(s, data)).is_equal(1)


func test_the_master_s_mountains_are_the_srd_s_mountain() -> void:
	var s := _hero("ranger_velena")
	(s.character["features"] as Array).append("natural_explorer_mountain")
	var w := WorldView.new(data["world"])
	var loc := w.location_id(s.room_id)
	data["world"]["locations"][loc]["terrain"] = "mountains"
	assert_str(FeatureRules.terrain_of(s, data)).is_equal("mountain")
	assert_bool(FeatureRules.explorer(s, data, Sheet.HERO)).is_true()
	data["world"]["locations"][loc]["terrain"] = "swamp"
	assert_bool(FeatureRules.explorer(s, data, Sheet.HERO)).is_false()


# --- Naturally Stealthy ---------------------------------------------------------------------------------------


func test_a_halfling_hides_behind_a_larger_ally() -> void:
	var s := _hero("druid_olha")
	assert_bool(CharacterRules.has_trait(s.character, "naturally_stealthy")).is_true()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}], {"allies": [{"monster": "guard", "name": "Влада"}]})
	_first(s)
	var p := CombatRules.player(s)
	var gob := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var guard := CombatRules.fighter(s, CombatRules.allies(s)[0])
	FightGrid.put(p, Vector2i(10, 10))
	FightGrid.put(gob, Vector2i(11, 10))  # a small goblin beside: no cover of its bulk
	FightGrid.put(guard, Vector2i(20, 20))
	assert_str(Acts.one("hide").why(s, data, p, "", {})).is_equal("COMBAT_HIDE_SEEN")
	FightGrid.put(guard, Vector2i(9, 10))  # a medium guard at its back
	assert_str(Acts.one("hide").why(s, data, p, "", {})).is_empty()
	guard["hp"] = 0
	guard["status"] = "down"
	assert_str(Acts.one("hide").why(s, data, p, "", {})).is_equal("COMBAT_HIDE_SEEN")


# --- a dwarf's tool ------------------------------------------------------------------------------------------


func test_a_dwarf_picks_its_tool() -> void:
	var ch := {"race": "dwarf", "subrace": "hill_dwarf", "class": "cleric", "background": "acolyte"}
	var picks := CharacterBuilder.feature_choices(ch, data).filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "tool")
	assert_int(picks.size()).is_equal(1)
	assert_array(picks[0]["from"]).contains(["smiths_tools", "brewers_supplies", "masons_tools"])
	ch["options"] = {str(picks[0]["id"]): ["masons_tools"]}
	assert_array(CharacterBuilder.tools_of(ch, data)).contains(["masons_tools"])
	assert_array(CharacterBuilder.tools_of(ch, data)).not_contains(["smiths_tools"])
	var branko := _hero("cleric_branko")
	assert_array(branko.character["tools"]).contains(["smiths_tools"])


# --- a tinker gnome's clockwork -----------------------------------------------------------------------------


func _tinker() -> GameSession:
	var s := _hero("warlock_fiber")
	s.room_id = "brod-square"
	s.minute = 10 * 60
	s.character["inventory"]["tinkers_tools"] = 1
	s.character["inventory"]["clockwork_parts"] = 3
	return s


func test_only_a_tinker_knows_its_clockwork() -> void:
	var s := _tinker()
	assert_bool(CharacterRules.has_trait(s.character, "tinker")).is_true()
	for id: String in ["clockwork_toy", "clockwork_fire_starter", "clockwork_music_box"]:
		assert_array(CraftRules.known(s, data)).contains([id])
	assert_str(CraftRules.why_not(s, data, "clockwork_toy")).is_empty()
	var aira := _hero("fighter_aira")
	aira.character["tools"] = (aira.character["tools"] as Array) + ["tinkers_tools"]
	aira.character["inventory"]["tinkers_tools"] = 1
	assert_array(CraftRules.known(aira, data)).not_contains(["clockwork_toy"])
	assert_array(CraftRules.known(aira, data)).contains(["tinderbox"])


func test_no_more_than_three_clockworks_at_once() -> void:
	var s := _tinker()
	s.character["inventory"]["clockwork_toy"] = 2
	s.character["inventory"]["clockwork_music_box"] = 1
	assert_int(CraftRules.held_of(s, data, "clockwork")).is_equal(3)
	assert_str(CraftRules.why_not(s, data, "clockwork_fire_starter")).is_equal("CRAFT_LIMIT")
	s.character["inventory"].erase("clockwork_toy")
	assert_str(CraftRules.why_not(s, data, "clockwork_fire_starter")).is_empty()


func test_a_clockwork_winds_down_into_its_parts_even_with_the_needs_off() -> void:
	var s := _tinker()
	s.settings["needs"] = false
	s.character["inventory"].erase("clockwork_parts")
	s.character["inventory"]["clockwork_toy"] = 1
	FoodRules.tick(s, data)
	var lines := TimeRules.advance(s, data, 1440 + 60)
	assert_str(" ".join(lines)).contains("Кончился завод")
	assert_int(int(s.character["inventory"].get("clockwork_toy", 0))).is_equal(0)
	assert_int(int(s.character["inventory"].get("clockwork_parts", 0))).is_equal(1)
	assert_int(int(s.character["inventory"].get("spoiled_food", 0))).is_equal(0)


func test_a_clockwork_fire_starter_lights_the_camp() -> void:
	var s := _tinker()
	s.character["inventory"].erase("tinderbox")
	s.room_id = "pushcha-edge"
	var had := WeatherRules.camp_fire(s, data)
	s.character["inventory"]["clockwork_fire_starter"] = 1
	assert_bool(had).is_false()
	assert_bool(WeatherRules.camp_fire(s, data)).is_true()
	assert_str("\n".join(ItemInfo.lines(s.character, data, s.items, "clockwork_toy"))).contains("Шестерёнки")


# --- Misty Visions: Silent Image on the field ----------------------------------------------------------------


func test_a_silent_image_veils_the_field_until_one_walks_into_it() -> void:
	var s := _hero("warlock_fiber", 2)
	var c := s.character
	(c["features"] as Array).append("eldritch_invocation_misty_visions")
	CharacterRules.refresh(c, data, s.items)
	assert_array(data["rules"]["spellcasting"]["by_master"]).not_contains(["silent_image"])
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}], {})
	_first(s)
	var p := CombatRules.player(s)
	var gob := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(p, Vector2i(10, 10))
	FightGrid.put(gob, Vector2i(22, 10))
	assert_bool(FightGrid.sees(s, data, gob, p)).is_true()
	var at := FightGrid.aim_id(Vector2i(16, 10))
	assert_str(Acts.one("cast").why(s, data, p, at, {"spell": "silent_image", "slot": 0})).is_empty()
	Acts.one("cast").run(s, data, p, at, {"spell": "silent_image", "slot": 0})
	var zones: Array = (s.combat.get("zones", []) as Array).filter(func(z: Dictionary) -> bool: return str(z.get("spell", "")) == "silent_image")
	assert_int(zones.size()).is_equal(1)
	var z: Dictionary = zones[0]
	assert_bool(bool(z.get("obscure", false))).is_true()
	assert_bool(FightGrid.sees(s, data, gob, p)).is_false()
	var said := SpellEffects._zone_hit(s, data, z, gob)
	assert_str("\n".join(said)).contains("иллюзия")
	assert_bool(FightGrid.sees(s, data, gob, p)).is_true()  # the goblin knows it for an illusion
	assert_array(SpellEffects._zone_hit(s, data, z, gob)).is_empty()  # told once
	assert_int(SpellRules.slots_left(c, 1)).is_equal(int(c["slots_max"][0]))  # at will: no slot spent
