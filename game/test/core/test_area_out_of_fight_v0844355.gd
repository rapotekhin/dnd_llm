extends GdUnitTestSuite
## An area out of a fight (v0.8.4.43.55, the author's roadmap «Область вне боя»: «огненный шар в клетку, а не в человека, —
## задетые начинают бой»). The pinned area spell is laid on a square of the room's map from the hero's square, as the fight
## lays it; those it catches — the people, the foes, the hero's own side — begin the fight on the squares they stood on,
## and the spell is the fight's first blow on its own road.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.attached = {}


## A wizard of level 5 in the tavern's hall with Fireball pinned on the hotbar, three slots of the 3rd circle.
func _wizard() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "wizard_yalika":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	while int(s.character["level"]) < 5:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
	var sp: Dictionary = s.character["spells"]
	sp["always"] = (sp.get("always", []) as Array) + ["fireball"]
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	CharacterRules.refresh(s.character, data, s.items)
	Stock.fill_slots(s.character)
	s.character["hp"] = int(s.character["max_hp"])
	s.room_id = TestUtils.START_ROOM
	s.mode = GameSession.MODE_EXPLORATION
	GameState.session = s
	GameState.attach("spell", "fireball", 3)
	return s


## The people of the room on their squares: {id: square}.
func _people(s: GameSession) -> Dictionary:
	var out := {}
	for t: Dictionary in MapSpots.standing(s, data):
		if str(t["kind"]) == "npc" and str(t["side"]) == "other":
			out[str(t["id"])] = Vector2i(int(t["x"]), int(t["y"]))
	return out


## The hero stands on a free square `far` squares from `at` (the hero's own walk), the followers round it.
func _stand_near(s: GameSession, at: Vector2i, far: int) -> Vector2i:
	var map := WalkRules.view(s, data)
	var taken := {}
	for t: Dictionary in MapSpots.standing(s, data):
		taken[Vector2i(int(t["x"]), int(t["y"]))] = true
	for y: int in range(at.y - far, at.y + far + 1):
		for x: int in range(at.x - far, at.x + far + 1):
			var c := Vector2i(x, y)
			if WalkRules.distance(c, at) == far and WalkRules.passable(map, data["layouts"], c) and not taken.has(c) \
					and WalkRules.room_of(map, c) == s.room_id:
				WalkRules.stand(s, map, s.room_id, c)
				return c
	return FightGrid.NONE


func _slots3(s: GameSession) -> int:
	return SpellRules.slots_left(s.character, 3)


## The fighter of a person, fallen too.
func _fighter_of(s: GameSession, npc_id: String) -> Dictionary:
	for id: String in s.combat.get("fighters", []):
		if str(CombatRules.fighter(s, id).get("npc_id", "")) == npc_id:
			return CombatRules.fighter(s, id)
	return {}


## The area cast at `at`, the lines of the fight's start.
func _cast(at: Vector2i) -> String:
	var got: Array[String] = []
	var grab := func(l: Array[String]) -> void: got.append_array(l)
	EventBus.combat_lines.connect(grab)
	var err := GameState._area_fight("fireball", 3, at, false)
	EventBus.combat_lines.disconnect(grab)
	var s := GameState.session
	for l: Variant in s.combat.get("start_lines", []):  # still there while the master would tell the start
		got.append(str(l))
	return err if not err.is_empty() else " · ".join(got)


func test_the_pinned_area_is_known_and_a_single_target_spell_is_not() -> void:
	var s := _wizard()
	assert_str(GameState.area_pinned()).is_equal("fireball")
	GameState.attach("spell", "fire_bolt", 0)
	assert_str(GameState.area_pinned()).is_empty()  # an attack roll: aimed at someone, not a square
	GameState.attach("spell", "fog_cloud", 1)
	assert_str(GameState.area_pinned()).is_empty()  # no harm: no fight to start
	assert_dict(GameState.area_aim(Vector2i(1, 1))).is_empty()
	GameState.attach("spell", "fireball", 3)
	s.mode = GameSession.MODE_COMBAT
	assert_dict(GameState.area_aim(Vector2i(1, 1))).is_empty()  # in a fight the fight aims it


## The hover shows the squares of the area from the hero's square and who stands on them, before any fight.
func test_the_area_shows_whom_it_catches_before_the_fight() -> void:
	var s := _wizard()
	var people := _people(s)
	assert_bool(people.is_empty()).override_failure_message("nobody in the hall").is_false()
	var id: String = people.keys()[0]
	var at: Vector2i = people[id]
	assert_that(_stand_near(s, at, 6)).is_not_equal(FightGrid.NONE)
	var a := GameState.area_aim(at)
	assert_str(str(a["why"])).is_empty()
	assert_bool((a["cells"] as Array).has(at)).is_true()
	var ids: Array = (a["caught"] as Array).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_bool(ids.has(id)).override_failure_message(str(ids)).is_true()
	assert_bool(ids.has(Being.HERO)).is_false()  # 6 squares off: out of a sphere of 20 ft
	assert_int(CombatRules.on_map(s, data)["x"]).is_equal(WalkRules.settle(s, data, WalkRules.view(s, data)).x)


## A click on the square: all it catches fight, each caught off guard when it did not expect it; the hero goes first and
## the Fireball is the first blow on the fight's road — one slot of the 3rd circle, the saves of each caught, an assault.
func test_the_area_opens_the_fight_with_all_it_catches() -> void:
	var s := _wizard()
	var people := _people(s)
	var id: String = people.keys()[0]
	var at: Vector2i = people[id]
	_stand_near(s, at, 6)
	var caught: Array = (GameState.area_aim(at)["caught"] as Array).filter(func(t: Dictionary) -> bool: return str(t["side"]) == "other")
	var before := _slots3(s)
	var lines := _cast(at)
	assert_bool(CombatRules.active(s)).override_failure_message(lines).is_true()
	assert_str(str(s.combat["order"][0])).is_equal(CombatRules.PLAYER)
	assert_int(_slots3(s)).is_equal(before - 1)
	assert_bool(lines.contains("Удар без предупреждения")).override_failure_message(lines).is_true()
	for t: Dictionary in caught:
		var f := _fighter_of(s, str(t["id"]))
		assert_bool(f.is_empty()).override_failure_message("%s not in the fight: %s" % [t["name"], lines]).is_false()
		assert_bool(bool(f.get("by_hero", false))).is_true()  # the fight's end tells the assault
		assert_bool(lines.contains("Огненный шар: %s" % f["name"])).override_failure_message(lines).is_true()
	assert_bool(GameState.attached.is_empty()).is_true()


## The followers stand in the fight where they stood by the hero; caught in the hero's area they take it as anybody
## (friendly fire, no «Точно?»).
func test_a_follower_in_the_area_takes_the_friendly_fire() -> void:
	var s := _wizard()
	var people := _people(s)
	var friend := ""
	for id: String in people:
		if friend.is_empty() and data["monsters"].has(str(data["world"]["npcs"][id].get("monster", CombatRules.cfg(data)["default_npc_monster"]))):
			friend = id
	people.erase(friend)
	(s.character["features"] as Array).erase(str(CombatRules.cfg(data)["friendly_fire"]["sculpt"]["feature"]))  # no Sculpt Spells
	FollowRules.apply(s, {"follow_npc": friend, "on": true})
	s.shift_attitude(friend, 6, data)
	var id: String = people.keys()[0]
	var at: Vector2i = people[id]
	_stand_near(s, at, 2)
	var walker: Dictionary = MapSpots.walkers(s, data)[0]
	var stood := Vector2i(int(walker["x"]), int(walker["y"]))
	var a := GameState.area_aim(at)
	var ids: Array = (a["caught"] as Array).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_bool(ids.has(friend) and ids.has(Being.HERO)).override_failure_message(str(ids)).is_true()
	var lines := _cast(at)
	var f := _fighter_of(s, friend)
	assert_str(str(f.get("side", ""))).override_failure_message(lines).is_equal("ally")
	assert_that(FightGrid.cell(f)).is_equal(stood)
	assert_bool(lines.contains("Огненный шар: %s" % f["name"])).override_failure_message(lines).is_true()


## The foes of the room before a fight: the area at one of them brings their whole encounter, each on its square of the
## map, the hero first; the struck one takes the Fireball.
func test_the_area_at_a_foe_of_the_room_starts_its_encounter() -> void:
	var s := _wizard()
	s.room_id = "pushcha-trail"
	s.game_seed = 42
	s.minute = 992
	var enc: Dictionary = data["world"]["rooms"]["pushcha-trail"]["encounter"]
	EncounterRules.heads(s, data, s.room_id, enc)
	s.lurking[s.room_id] = {"encounter": str(enc["id"]), "from": "pushcha-edge", "seen": true}
	var foes := MapSpots.foes(s, data, WalkRules.view(s, data))
	assert_bool(foes.is_empty()).is_false()
	var at := Vector2i(int(foes[0]["x"]), int(foes[0]["y"]))
	_stand_near(s, at, 7)
	var seen := {}
	for t: Dictionary in foes:
		seen[str(t["id"])] = Vector2i(int(t["x"]), int(t["y"]))
	var lines := _cast(at)
	assert_bool(CombatRules.active(s)).override_failure_message(lines).is_true()
	assert_bool(s.lurking.has(s.room_id)).is_false()
	assert_str(str(s.combat["order"][0])).is_equal(CombatRules.PLAYER)
	for id: String in seen:
		assert_that(FightGrid.cell(CombatRules.fighter(s, id))).is_equal(seen[id])
	assert_bool(lines.contains("Огненный шар: %s" % foes[0]["name"])).override_failure_message(lines).is_true()


## Only the hero and its own in the area: no fight out of it, nothing spent. Nobody at all: a cast without a fight.
func test_only_the_heros_own_in_the_area_is_refused() -> void:
	var s := _wizard()
	s.room_id = "pushcha-trail"  # nobody lives there and no foe lurks now
	var friend := "npc_veteran"
	FollowRules.apply(s, {"follow_npc": friend, "on": true})
	var hero := WalkRules.settle(s, data, WalkRules.view(s, data))
	var a := GameState.area_aim(hero)
	var ids: Array = (a["caught"] as Array).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_bool(ids.has(Being.HERO) and ids.has(friend)).override_failure_message(str(ids)).is_true()
	var before := _slots3(s)
	assert_str(GameState._area_fight("fireball", 3, hero, false)).is_equal("AREA_ONLY_FRIENDS")
	assert_bool(CombatRules.active(s)).is_false()
	assert_int(_slots3(s)).is_equal(before)
	assert_str(GameState.area_pinned()).is_equal("fireball")  # still pinned: moved off or let go by the right button
	var empty := FightGrid.NONE
	var map := WalkRules.view(s, data)
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var c := Vector2i(x, y)
			if empty == FightGrid.NONE and WalkRules.distance(c, hero) in range(9, 20) and WalkRules.passable(map, data["layouts"], c) 					and GameState.area_aim(c)["caught"].is_empty() and str(GameState.area_aim(c)["why"]).is_empty():
				empty = c
	assert_that(empty).is_not_equal(FightGrid.NONE)
	GameState._area_fight("fireball", 3, empty, false)  # no master in a test: a cast as from the sheet, refused for it
	assert_bool(CombatRules.active(s)).is_false()


## Out of a fight the grid is the hero's room with its things as the fight lays them: a table bars an area as it would.
func test_the_grid_out_of_a_fight_has_the_rooms_things() -> void:
	var s := _wizard()
	var map := LayoutRules.map_of(s, data, s.room_id)
	var blocks := FightField.blocks_of(s, data, map)
	var g := FightGrid.grid(s, data)
	for key: String in blocks:
		assert_int(FightGrid.flags_at(g, FightGrid.y_x(key)) & int(blocks[key]["flags"])).is_equal(int(blocks[key]["flags"]))
	s.room_id = TestUtils.KITCHEN
	assert_str(str(FightGrid.map(s, data)["ids"])).contains(TestUtils.KITCHEN)


## The fight's opening of an area: each caught off guard by its own, the hero first.
func test_the_opening_of_an_area_catches_several_off_guard() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "acolyte", "name": "А", "npc_id": "a"}, {"monster": "acolyte", "name": "Б", "npc_id": "b"},
		{"monster": "acolyte", "name": "В", "npc_id": "c"}])
	s.combat["order"] = (s.combat["order"] as Array).filter(func(x: String) -> bool: return x != CombatRules.PLAYER) + [CombatRules.PLAYER]
	var lines := CombatRules._opening(s, {"opening": {"caught": {"a": true, "b": true, "c": false}}})
	assert_str(str(s.combat["order"][0])).is_equal(CombatRules.PLAYER)
	assert_bool(bool(CombatRules.fighter(s, CombatRules.fighter_of_npc(s, "a")).get("surprised", false))).is_true()
	assert_bool(bool(CombatRules.fighter(s, CombatRules.fighter_of_npc(s, "c")).get("surprised", false))).is_false()
	assert_str(" ".join(lines)).contains("А, Б не ждут нападения")
