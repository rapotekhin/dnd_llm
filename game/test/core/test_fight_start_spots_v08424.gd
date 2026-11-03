extends GdUnitTestSuite
## Playtest bug (v0.8.4.24): a wolf seen on the map and attacked from hiding started the fight on another square. The
## foes of the map keep their squares at the fight's start, whatever ways of the room are shut for now.

const TRAIL := "pushcha-trail"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data().duplicate(true)


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = TRAIL
	s.minute = 992
	s.character["inventory"] = {}
	s.character["traits"] = []
	CharacterRules.refresh(s.character, data, s.items)
	return s


## The foes of the room on the map as the hero sees them: {id: square}.
func _on_map(s: GameSession, enc: Dictionary) -> Dictionary:
	EncounterRules.heads(s, data, TRAIL, enc)
	s.lurking[TRAIL] = {"encounter": str(enc["id"]), "from": "pushcha-edge", "seen": true}
	var out := {}
	for t: Dictionary in MapSpots.foes(s, data, WalkRules.view(s, data)):
		out[str(t["id"])] = Vector2i(int(t["x"]), int(t["y"]))
	return out


## The fight as «Напасть врасплох» starts it (GameState.encounter_attack): the lurking gone, then the start from hiding.
func _attack_from_hiding(s: GameSession) -> void:
	var lk := EncounterRules.lurking(s, TRAIL)
	var enc := EncounterRules.lurking_encounter(s, data, TRAIL)
	s.lurking.erase(TRAIL)
	CombatRules.start(s, data, enc["enemies"], EncounterRules.source(enc, str(lk.get("from", "")), {"sneak": true, "stealth_total": 99, "from_hiding": true}))


func _in_fight(s: GameSession) -> Dictionary:
	var out := {}
	for id: String in CombatRules.enemies(s):
		out[id] = FightGrid.cell(CombatRules.fighter(s, id))
	return out


func _check(s: GameSession, enc: Dictionary) -> void:
	var seen := _on_map(s, enc)
	assert_int(seen.size()).is_equal(int(enc["enemies"][0].get("count", 1)))
	s.sneaking = true
	_attack_from_hiding(s)
	assert_dict(_in_fight(s)).is_equal(seen)


func test_the_wolf_keeps_its_square_when_attacked_from_hiding() -> void:
	var s := _session()
	_check(s, data["world"]["rooms"][TRAIL]["encounter"])


func test_a_ford_shut_by_the_downpour_moves_nobody() -> void:
	var s := _session()
	s.flags.append("weather_downpour_pushcha")  # the author's game: the ford to the glade shut, its way off the map
	_check(s, data["world"]["rooms"][TRAIL]["encounter"])


func test_a_pack_keeps_its_squares() -> void:
	var s := _session()
	s.flags.append("weather_downpour_pushcha")
	var enc := {"id": "t_pack", "enemies": [{"monster": "wolf", "count": 3, "name": "Волк"}]}
	(data["world"]["rooms"][TRAIL] as Dictionary)["encounter"] = enc
	_check(s, enc)


func test_captors_without_an_encounter_keep_their_squares() -> void:
	var s := _session()
	var ids: Array = []
	for i: int in 2:
		ids.append(str(Being.spawn(s, {"monster": "goblin", "name": "Гоблин %d" % (i + 1), "base": "Гоблин"})["id"]))
	s.lurking[TRAIL] = {"foes": ids, "from": "pushcha-edge"}
	var seen := {}
	for t: Dictionary in MapSpots.foes(s, data, WalkRules.view(s, data)):
		seen[str(t["id"])] = Vector2i(int(t["x"]), int(t["y"]))
	assert_int(seen.size()).is_equal(2)
	_attack_from_hiding(s)
	assert_dict(_in_fight(s)).is_equal(seen)
