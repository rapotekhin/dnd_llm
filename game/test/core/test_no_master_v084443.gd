extends GdUnitTestSuite
## v0.8.4.44.3, the author: «поправить этот недочёт в принципе для наших механик. Наполнять сундуки, ставить трупы хотелось
## бы и без мастера». A chest of the pack holds what its author wrote or what the engine lays by its kind and place; a pack
## room's dead are bodies to search, its bound are prisoners; «Развязать» someone else's prisoner is a rescue; a place keeps
## its dead by a table. No master in any of it.

const CELLAR := "brod-tavern-cellar"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _at(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	return s


func _props(room: String, props: Array) -> void:
	data["world"]["rooms"][room]["props"] = props


func _creatures(room: String, rows: Array) -> void:
	data["world"]["rooms"][room]["creatures"] = rows


func test_a_pack_chest_holds_what_its_author_wrote() -> void:
	_props(CELLAR, [{"id": "chest", "name": "Окованный сундук", "container": "chest", "contents": {"rope": 1, "healing_potion": 2},
		"coins_cp": 500, "lock": "simple", "key": "key_iron", "body": "chest"}])
	var s := _at(CELLAR)
	PropRules.ensure(s, data, CELLAR)
	var p := PropRules.find(s, CELLAR, "f_chest")
	assert_str(str(p["container"])).is_equal("chest")
	assert_dict(p["contents"]).is_equal({"rope": 1, "healing_potion": 2})
	assert_int(int(p["coins_cp"])).is_equal(500)
	assert_bool(bool(p["locked"])).is_true()
	assert_int(int(p["lock_dc"])).is_equal(int(data["rules"]["containers"]["lock_dc"]["simple"]))
	assert_str(str(p["key"])).is_equal("key_iron")
	assert_bool(PropRules.needs_furnish(s, CELLAR)).is_true()  # the master still furnishes the room beside it
	assert_bool(MapSpots.of(s, data, WalkRules.view(s, data)).any(func(t: Dictionary) -> bool: return str(t["ref"]) == "prop:f_chest" and str(t.get("body", "")) == "chest")).is_true()


func test_an_empty_pack_chest_is_filled_by_its_kind_the_same_in_one_game() -> void:
	_props(CELLAR, [{"id": "box", "name": "Сундук", "container": "chest"}])
	var a := _at(CELLAR)
	var b := _at(CELLAR)
	PropRules.ensure(a, data, CELLAR)
	PropRules.ensure(b, data, CELLAR)
	var pa := PropRules.find(a, CELLAR, "f_box")
	assert_dict(pa["contents"]).is_equal(PropRules.find(b, CELLAR, "f_box")["contents"])
	var row: Dictionary = data["rules"]["containers"]["fill"]["chest"]
	var filled := 0
	var coined := 0
	for sd: int in 30:
		var s := TestUtils.new_session(sd)
		var got := ContainerRules.fill(s, data, CELLAR, "chest", "f_box")
		var n := 0
		for id: String in got["contents"]:
			assert_bool(data["items"]["catalog"].has(id)).is_true()
			n += int(got["contents"][id])
		assert_int(n).is_less_equal(int(row["n"][1]))
		filled += 1 if n > 0 else 0
		coined += 1 if int(got["coins_cp"]) > 0 else 0
		assert_int(int(got["coins_cp"])).is_less_equal(int(row["coins_cp"][1]))
	assert_int(filled).is_greater(20)
	assert_int(coined).is_between(5, 28)  # by its chance


func test_a_chest_s_coins_come_into_the_purse_and_a_locked_one_gives_none() -> void:
	var s := _at(CELLAR)
	var p := {"id": "x", "name": "Сундук", "container": "chest", "contents": {}, "coins_cp": 500, "locked": true, "owner": ""}
	assert_array(ContainerRules.take_coins(s, data, p, "container:coins")["lines"]).is_empty()
	p["locked"] = false
	var gold := Ledger.balance(s)
	var got := ContainerRules.take_coins(s, data, p, "container:coins")
	assert_int(Ledger.balance(s) - gold).is_equal(500)
	assert_bool(p.has("coins_cp")).is_false()
	assert_str(str(got["caught"])).is_empty()


func test_a_body_of_the_pack_is_searched_like_one_after_a_fight_and_stays() -> void:
	_creatures(CELLAR, [{"id": "guard", "monster": "guard", "state": "dead", "coins_cp": 120}])
	var s := _at(CELLAR)
	CreatureRules.seed(s, data, CELLAR)
	var here := CreatureRules.here(s, CELLAR)
	assert_int(here.size()).is_equal(1)
	var c: Dictionary = here[0]
	assert_str(str(c["state"])).is_equal(CreatureRules.DEAD)
	assert_str(str(c["name"])).starts_with("Тело: ")
	assert_dict(c["contents"]).is_equal(Gear.start(data, "guard")["inventory"])
	assert_str(CreatureRules.can(s, str(c["id"]), "search", data)).is_empty()
	var gold := Ledger.balance(s)
	CreatureRules.act(s, data, str(c["id"]), "search")
	assert_int(Ledger.balance(s) - gold).is_equal(120)
	(c["contents"] as Dictionary).clear()
	TimeRules.advance(s, data, 10000)
	CreatureRules.tick(s, data)
	assert_int(CreatureRules.here(s, CELLAR).size()).is_equal(1)  # the pack's body neither rots nor goes when emptied
	CreatureRules.seed(s, data, CELLAR)
	assert_int(CreatureRules.here(s, CELLAR).size()).is_equal(1)  # once


func test_a_bound_captive_of_foes_is_untied_as_a_rescue() -> void:
	_creatures(CELLAR, [{"id": "victim", "monster": "commoner", "name": "Пленный дровосек", "state": "bound", "owner": "enc:x"}])
	var s := _at(CELLAR)
	CreatureRules.seed(s, data, CELLAR)
	var c: Dictionary = CreatureRules.here(s, CELLAR)[0]
	var id := str(c["id"])
	assert_bool(CreatureRules.held(c)).is_true()
	assert_bool(CreatureRules.captive(c)).is_true()
	assert_str(CreatureRules.can(s, id, "free", data)).is_equal("CREATURE_UNTIE_IT")
	assert_str(CreatureRules.can(s, id, "hand_over", data)).is_equal("CREATURE_NOT_YOUR_PRISONER")
	var whats := CreatureRules.acts(s, data, c).map(func(a: Array) -> String: return str(a[0]))
	assert_array(whats).contains(["untie"]).not_contains(["free"])
	var crimes := s.crimes.size()
	CreatureRules.act(s, data, id, "untie")
	assert_bool(bool(c["bound"])).is_false()
	assert_str(str(c["state"])).is_equal("truce")
	assert_bool(CreatureRules.joinable(c)).is_true()
	assert_int(s.crimes.size()).is_equal(crimes)  # no assault


func test_a_pack_npc_set_free_thinks_better_and_goes_along_when_it_joins() -> void:
	_creatures(CELLAR, [{"id": "hermit", "npc": "npc_hermit", "state": "bound", "joins": true}])
	var s := _at(CELLAR)
	CreatureRules.seed(s, data, CELLAR)
	assert_bool(s.held_as_creature("npc_hermit")).is_true()
	assert_array(s.npcs_here(data["world"], CELLAR)).not_contains(["npc_hermit"])
	var before := s.attitude("npc_hermit")
	CreatureRules.act(s, data, "npc_hermit", "untie")
	assert_bool(s.held_as_creature("npc_hermit")).is_false()
	assert_bool(Being.follows(s, "npc_hermit")).is_true()
	assert_int(s.attitude("npc_hermit")).is_equal(before + int(data["rules"]["creatures"]["rescued_attitude"]))


func test_a_guarded_captive_is_not_untied_and_does_not_slip_away_alone() -> void:
	_creatures("pushcha-burrow", [{"id": "victim", "monster": "commoner", "state": "bound"}])
	var s := _at("pushcha-burrow")
	CreatureRules.seed(s, data, "pushcha-burrow")
	var c: Dictionary = CreatureRules.here(s, "pushcha-burrow").filter(func(x: Dictionary) -> bool: return str(x.get("pack_row", "")) == "victim")[0]
	assert_str(CreatureRules.can(s, str(c["id"]), "untie", data)).is_equal("CREATURE_GUARDED")
	s.room_id = CELLAR
	TimeRules.advance(s, data, 2000)
	CreatureRules.tick(s, data)
	assert_bool(bool(CreatureRules.find(s, "pushcha-burrow", str(c["id"])).get("bound", false))).is_true()


func test_a_place_keeps_its_dead_by_its_table_and_a_dream_none() -> void:
	data["rules"]["creatures"]["remains"]["by"]["crypt"]["chance"] = 1.0
	data["world"]["rooms"][CELLAR]["tags"] = ["crypt"]
	var s := _at(CELLAR)
	CreatureRules.seed(s, data, CELLAR)
	var dead := CreatureRules.here(s, CELLAR)
	assert_int(dead.size()).is_between(1, 3)
	for c: Dictionary in dead:
		assert_str(str(c["name"])).starts_with("Останки: ")
		assert_bool(bool(c["remains"])).is_true()
	var again := _at(CELLAR)
	CreatureRules.remains(again, data, CELLAR)
	assert_int(CreatureRules.here(again, CELLAR).size()).is_equal(dead.size())  # by the seed of the game and the room
	data["world"]["locations"]["brod"]["remains"] = false
	var dream := _at(CELLAR)
	assert_array(CreatureRules.remains(dream, data, CELLAR)).is_empty()


func test_a_key_by_its_weight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert_str(Roll.weighted(rng, {})).is_empty()
	assert_str(Roll.weighted(rng, {"a": 0})).is_empty()
	var seen := {}
	for i: int in 200:
		seen[Roll.weighted(rng, {"a": 1, "b": 3, "c": 0})] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(["a", "b"])
