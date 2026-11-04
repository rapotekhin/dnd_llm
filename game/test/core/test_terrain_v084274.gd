extends GdUnitTestSuite
## Terrain traits on the engine's roads (roadmap v0.8.4.27.4): Stone and Snow Camouflage — advantage on Stealth where the
## `when` of the trait holds (Cond: the location's terrain, today's weather under the sky), for a head at a meeting too;
## Sure-Footed — advantage on a save against being knocked down. A save against a status carries that status's tag by one
## table (rules.hero_effects.cond_tags) for monsters' blows, spells and zones alike.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _stealth_adv(s: GameSession, who: Dictionary) -> Array:
	return Roll.check(s, data, who, {"skill": "stealth", "quiet": true})["adv"]


func test_a_grimlock_hides_better_among_stones() -> void:
	data["monsters"]["grimlock"] = TestUtils.uncut("monsters", "grimlock")  # out of the game (v0.8.4.28.4); its road stays
	var s := ChecklistProbe.session(data)
	var head := {"monster": "grimlock", "name": "Гримлок"}  # a head at a meeting: no statuses yet
	s.room_id = "mine-gallery"
	assert_array(_stealth_adv(s, head)).contains(["Маскировка в камне"])
	s.room_id = "brod-tavern-hall"
	assert_array(_stealth_adv(s, head)).not_contains(["Маскировка в камне"])


func test_a_winter_wolf_hides_in_falling_snow() -> void:
	var s := ChecklistProbe.session(data)
	s.settings["weather"] = true  # the probe's session keeps it off
	s.room_id = "pushcha-trail"
	var wolf := {"monster": "winter_wolf", "name": "Зимний волк"}
	WeatherRules._state(s)["by_loc"]["pushcha"] = "snow"
	assert_array(_stealth_adv(s, wolf)).contains(["Маскировка в снегу"])
	WeatherRules._state(s)["by_loc"]["pushcha"] = "fog"
	assert_array(_stealth_adv(s, wolf)).not_contains(["Маскировка в снегу"])


func test_a_goat_keeps_its_feet() -> void:
	var s := ChecklistProbe.session(data)
	var goat := ChecklistProbe.fight(s, data, "goat")
	assert_array(Sheet.save(s, data, goat, "dex", 15, HeroDefense.cond_tags(data, ["prone"]))["adv"]).contains(["Уверенная поступь"])
	assert_array(Sheet.save(s, data, goat, "dex", 15, "magic")["adv"]).not_contains(["Уверенная поступь"])


func test_a_save_against_a_status_carries_its_tag() -> void:
	assert_str(HeroDefense.cond_tags(data, ["prone"], ["magic"])).is_equal("prone,magic")
	assert_str(HeroDefense.cond_tags(data, ["frightened"], ["fear"])).is_equal("fear")
	assert_str(MonsterRules.tag_of(data, {"condition": "charmed", "magic": true}, {})).is_equal("charm,magic")
	assert_str(MonsterRules.tag_of(data, {"save": {}}, {"damage": [{"type": "poison"}]})).is_equal("poison")
	assert_str(CombatRules._spell_tag(data, "hold_person", ["paralyzed"])).is_equal("paralysis,magic")


func test_grease_asks_a_save_against_the_fall() -> void:
	var s := ChecklistProbe.session(data)
	var goat := ChecklistProbe.fight(s, data, "goat")
	SpellEffects.zones(s).clear()
	var row := {"name": "Жир", "save": "dex", "dc": 99, "cond": "prone", "on": ["start"]}
	SpellEffects.add_zone(s, FightField.zone_of("grease", row, FightGrid.pack_cells([FightGrid.cell(goat)] as Array[Vector2i])))
	var lines := SpellEffects.zone_tick(s, data, goat, "start")
	assert_bool(" ".join(lines).contains("Жир")).override_failure_message(" · ".join(lines)).is_true()
	assert_str(HeroDefense.cond_tags(data, [str(SpellEffects.zones(s)[0]["cond"])], [str(SpellEffects.zones(s)[0].get("tag", "magic"))])).contains("prone")
