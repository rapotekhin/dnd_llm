extends GdUnitTestSuite
## 18+ (v0.7.38.7): off by default, on by the player's toggle.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.character["body"] = {"age": "young", "build": "athletic", "height": "tall"}


func test_off_by_default_and_on_by_the_setting() -> void:
	assert_bool(bool(WorldPack.default_settings(data["pack"])["adult"])).is_false()
	s.settings = WorldPack.default_settings(data["pack"])
	assert_bool(bool(TurnSnapshot.world_info(s, data)["adult"])).is_false()
	s.settings["adult"] = true
	assert_bool(bool(TurnSnapshot.world_info(s, data)["adult"])).is_true()


func test_a_teen_hero_is_a_minor_for_the_master() -> void:
	s.character["body"]["age"] = "teen"


func test_a_child_npc_here_is_a_minor_for_the_master_and_the_brush() -> void:
	var world := WorldView.new(data["world"])
	var id: String = s.npcs_here(world.world, s.room_id)[0]
	data["world"]["npcs"][id]["age"] = "child"
	var name := str(data["world"]["npcs"][id]["name"])
	s.settings["adult"] = true
	s.append(GameSession.dm_entry("%s машет рукой." % name.get_slice(" ", 0), "t-1"))
	var p := ImageFrame.params(s, data, ImageFrame.event_index(s))
	assert_bool(bool(p["adult"])).is_true()
