extends GdUnitTestSuite
## v0.8.4.24: a fight's noise reaches a sensible distance: the rooms of its own map and a room just past a way out of one
## location, never along a road to another; a thunderous blow is heard farther. Captain Ratmir stays at the gate.

const CAPTAIN := "npc_captain"

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


## A fight in `room` at 10:00, when the captain stands at the North Gate.
func _fight(room: String, foes: Array, source: Dictionary = {}) -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	s.minute = 600
	CombatRules.start(s, data, foes, source)
	return s


## The hero on the square before the map's way out to `to`.
func _at_exit(s: GameSession, to: String) -> void:
	for e: Dictionary in FightGrid.map(s, data)["exits"]:
		if str(e["to"]) == to:
			FightGrid.put(CombatRules.player(s), Vector2i(int(e["ax"]), int(e["ay"])))
			FightGrid.changed(s)
			return
	fail("no way out to " + to)


func _came(s: GameSession) -> Array:
	var out: Array = []
	for inc: Dictionary in s.combat["incoming"]:
		for f: Dictionary in inc["foes"]:
			out.append(str(f.get("npc_id", "")))
	return out


func test_the_kobolds_fight_in_the_mine_does_not_bring_the_captain() -> void:
	var s := _fight("mine-gallery", [{"monster": "kobold", "beside": true}], {"encounter": "gallery_kobolds", "faction": "mine_kobolds"})
	assert_str(Where.npc_room(s, data, CAPTAIN)).is_equal("brod-gate")
	var lines: Array[String] = []
	for i: int in 3:
		FightField.hear(s, data, lines)
	assert_array(_came(s)).not_contains([CAPTAIN])
	assert_str(" ".join(lines)).not_contains("Ратмир")


func test_not_even_from_the_mines_mouth_along_the_road() -> void:
	var s := _fight("mine-entrance", [{"monster": "kobold", "beside": true}])
	_at_exit(s, "brod-gate")
	var lines: Array[String] = []
	FightField.hear(s, data, lines)
	assert_array(_came(s)).not_contains([CAPTAIN])
	assert_bool(FightField.carries(data, "mine-entrance", "brod-gate")).is_false()


func test_a_fight_by_the_gate_in_town_brings_him() -> void:
	var s := _fight("brod-square", [{"monster": "bandit", "beside": true}])
	_at_exit(s, "brod-gate")
	assert_bool(FightField.carries(data, "brod-square", "brod-gate")).is_true()
	var lines: Array[String] = []
	FightField.hear(s, data, lines)
	assert_array(_came(s)).contains([CAPTAIN])


func test_away_from_his_post_he_does_not_hear() -> void:
	var s := _fight("brod-square", [{"monster": "bandit", "beside": true}])
	s.minute = 20 * 60  # the evening hours: the captain is in the tavern
	_at_exit(s, "brod-gate")
	var lines: Array[String] = []
	FightField.hear(s, data, lines)
	assert_array(_came(s)).not_contains([CAPTAIN])


func test_a_thunderous_blow_carries_farther_for_a_round() -> void:
	var s := _fight("mine-gallery", [{"monster": "kobold", "beside": true}])
	var c: Dictionary = FightGrid.cfg(data)["noise"]
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	Harm.take(s, data, foe, 1, [] as Array[String], "thunder")
	assert_int(int(s.combat.get("loud", 0))).is_equal(int(c["loud"]["thunder"]))
	var g := FightGrid.grid(s, data)
	var a := Vector2i(1, 1)
	var b := Vector2i(5, 1)
	assert_int(FightField._loud(g, c, a, b, int(c["loud"]["thunder"])) - FightField._loud(g, c, a, b)).is_equal(int(c["loud"]["thunder"]))
	FightField.hear(s, data, [] as Array[String])
	assert_bool(s.combat.has("loud")).is_false()
