extends GdUnitTestSuite
## The brush (v0.7.35): the frame of the last event — the master's whole turn with the player's words, the place, the
## hour, the hero's looks and only the people the event names; one file per event.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.chat.clear()


func test_nothing_to_draw_before_the_master_speaks() -> void:
	assert_int(ImageFrame.event_index(s)).is_equal(-1)
	s.append(GameSession.player_entry("осматриваюсь"))
	assert_int(ImageFrame.event_index(s)).is_equal(-1)


func test_the_event_is_the_last_turn_with_the_players_words() -> void:
	s.append(GameSession.player_entry("иду к стойке"))
	s.append(GameSession.dm_entry("Старый ход.", "t-1"))
	s.append(GameSession.player_entry("бью кружкой по стойке"))
	s.append(GameSession.dm_entry("Кружка трескается.", "t-2"))
	s.append({"kind": GameSession.KIND_EFFECT, "lines": ["−1 HP"]})
	s.append(GameSession.npc_entry("bruno", "Бруно", "«Эй!»", "t-2"))
	var i := ImageFrame.event_index(s)
	assert_int(i).is_equal(5)
	var text := ImageFrame.event_text(s, i)
	assert_str(text).is_equal("Герой: бью кружкой по стойке\nКружка трескается.\nБруно: «Эй!»")


func test_the_params_carry_the_place_the_hour_the_hero_and_the_named_people() -> void:
	var world := WorldView.new(data["world"])
	var here := s.npcs_here(world.world, s.room_id)
	assert_bool(here.is_empty()).override_failure_message("the start room has people").is_false()
	var npc_name := str(world.npc(here[0]).get("name", ""))
	s.append(GameSession.dm_entry("%s кивает герою." % npc_name.get_slice(" ", 0), "t-1"))
	var p := ImageFrame.params(s, data, ImageFrame.event_index(s))
	assert_str(str(p["place"])).contains(str(world.room(s.room_id).get("name", "")))
	assert_str(str(p["time"])).contains(TimeRules.clock(s))
	assert_str(str(p["hero"])).starts_with(str(s.character["name"]))
	assert_int((p["people"] as Array).size()).is_equal(1)
	assert_str(str(p["people"][0])).starts_with(npc_name)
	var sex := str(ImageFrame.GENDER.get(str(world.npc(here[0]).get("gender", "")), "мужчина"))  # v0.7.38.7: the sex in words
	assert_str(str(p["people"][0])).contains(", %s," % sex)
	assert_str(str(p["style"])).contains("book illustration")


func test_one_file_per_event_and_the_image_stays_on_its_entry() -> void:
	s.append(GameSession.dm_entry("Волк прыгает.", "t-7"))
	var path := ImageFrame.file_path("user://profiles/test", s, 0)
	assert_str(path).starts_with("user://profiles/test/images/")
	assert_str(path).ends_with("/t-7.webp")
	assert_str(ImageFrame.image_of(s.chat[0])).is_empty()
	s.chat[0]["image"] = path
	var back := GameSession.from_dict(s.to_dict(50))
	assert_str(ImageFrame.image_of(back.chat[0])).is_equal(path)


func test_an_answer_is_decoded_and_kept_no_wider_than_the_limit() -> void:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(0.4, 0.3, 0.2))
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var out := ImageFrame.decode("image/png", b64, 32)
	assert_int(out.get_width()).is_equal(32)
	assert_int(out.get_height()).is_equal(18)
	assert_object(ImageFrame.decode("image/webp", "bm90IGFuIGltYWdl", 32)).is_null()
