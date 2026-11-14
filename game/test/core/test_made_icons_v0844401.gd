extends GdUnitTestSuite
## The icons of the master's inventions (v0.8.4.44.1, the author: «один прогон FLUX для генерации картинки для создаваемого
## предмета или заклинания»): what the master made and has no picture is asked of `icon.request` on a chroma ground,
## green or magenta for a green subject; IconCut cuts the ground by the corners' box and the ground seen inside the thing;
## the profile's file is the thing's icon from then on.

var data: Dictionary
var s: GameSession
var dir := "user://gdunit_made_icons/"


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	IconRules.forget()
	IconRules.made_root = dir


func after_test() -> void:
	for kind: String in ["items", "spells"]:
		for f: String in DirAccess.get_files_at(dir + kind):
			DirAccess.remove_absolute(dir + kind + "/" + f)
	IconRules.made_root = MadeIcons.root(SaveManager.profile_dir)
	IconRules.forget()


func _item(name: String, text: String, extra: Dictionary = {}) -> String:
	var def := {"name": name, "item_type": "wondrous", "rarity": "uncommon", "value_cp": 500, "properties": [],
		"description": text, "generated": true}
	def.merge(extra, true)
	var id := ItemRules.generated_id(def)
	s.items[id] = def
	return id


func test_the_masters_things_and_spells_are_wanted_once() -> void:
	var dagger := _item("Пепельный кинжал", "Клинок из чёрного обсидиана с тлеющими трещинами.")
	_item("Тонкий длинный меч", "", {"base": "longsword", "quality": "fine"})  # a copy of a catalog thing: its base's picture
	s.items["gen_scroll_ab12cd34"] = {"name": "Свиток", "generated": true, "use": {"spell": "x", "scroll": true}}
	WorldGen.generated(s)["made"] = {"gen_sp_rot": {"what": "spell", "name": "Гнилостный шёпот", "text": "Облако зелёной гнили."},
		"gen_sk_x": {"what": "skill", "name": "Навык", "text": "Никакой картинки."}}
	var wants := MadeIcons.wanted(s, data)
	assert_array(wants.map(func(w: Dictionary) -> String: return w["ref"])).contains_exactly(["items/" + dagger, "spells/gen_sp_rot"])
	assert_str(str(wants[0]["ground"])).is_equal("green")
	assert_str(str(wants[1]["ground"])).is_equal("magenta")  # green rot on a green ground would be cut away
	var p := MadeIcons.params(data, wants[1])
	assert_str(str(p["kind"])).is_equal("spell")
	assert_int(int(p["seed"])).is_equal(int(MadeIcons.cfg(data)["seed"]))
	DirAccess.make_dir_recursive_absolute(dir + "items")
	Image.create_empty(4, 4, false, Image.FORMAT_RGBA8).save_png(MadeIcons.path_of(dir, "items/" + dagger))
	IconRules.forget()
	assert_array(MadeIcons.wanted(s, data).map(func(w: Dictionary) -> String: return w["ref"])).contains_exactly(["spells/gen_sp_rot"])
	var ic := IconRules.of(data, s.items, "items/" + dagger)
	assert_str(str(ic["path"])).is_equal(MadeIcons.path_of(dir, "items/" + dagger))
	assert_bool(bool(ic["real"])).is_true()
	assert_object(IconSlot.texture(str(ic["path"]))).is_not_null()


func test_the_folder_of_a_profile() -> void:
	assert_str(MadeIcons.root("user:/")).is_equal("user://made_icons/")
	assert_str(MadeIcons.root("user://profiles/author")).is_equal("user://profiles/author/made_icons/")


## A frame like FLUX's: a green ground with a little gradient, a grey thing with a hole of the ground inside it (glass,
## a gap of a chain mail) and a grey-green patch of its own (a cloak).
func _frame() -> Image:
	var img := Image.create_empty(512, 512, false, Image.FORMAT_RGB8)
	for y: int in 512:
		for x: int in 512:
			img.set_pixel(x, y, Color8(20 + x / 64, 220 - y / 64, 30))
	img.fill_rect(Rect2i(128, 128, 256, 256), Color8(120, 118, 115))
	img.fill_rect(Rect2i(176, 176, 48, 48), Color8(24, 214, 32))  # the ground seen through
	img.fill_rect(Rect2i(272, 272, 64, 64), Color8(77, 92, 71))  # the thing's own grey-green
	return img


func test_the_ground_is_cut_and_the_thing_kept() -> void:
	var cf: Dictionary = MadeIcons.cfg(data)["cut"]
	var icon := IconCut.cut(_frame(), cf)
	var side := int(cf["side"])
	assert_int(icon.get_width()).is_equal(side)
	assert_int(icon.get_format()).is_equal(Image.FORMAT_RGBA8)
	assert_float(icon.get_pixel(1, 1).a).is_less(0.05)  # the ground
	var at := func(fx: float, fy: float) -> Color:  # a point of the 256 square of the frame inside the cropped icon
		var pad := float(cf["pad"])
		return icon.get_pixel(int(side * (pad + fx) / (1.0 + 2.0 * pad)), int(side * (pad + fy) / (1.0 + 2.0 * pad)))
	assert_float(at.call(0.1, 0.9).a).is_greater(0.95)  # the thing
	var hole: Color = at.call(0.28, 0.28)
	assert_float(hole.a).is_less(0.2)  # the ground inside the thing is clear
	var own: Color = at.call(0.8, 0.8)
	assert_float(own.a).is_greater(0.95)  # its own grey-green stays
	assert_int(own.g8).is_greater(own.r8)


func test_a_magenta_ground_is_cut_too() -> void:
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	img.fill(Color8(250, 10, 245))
	img.fill_rect(Rect2i(64, 64, 128, 128), Color8(40, 160, 60))  # a green thing
	var icon := IconCut.cut(img, MadeIcons.cfg(data)["cut"])
	assert_float(icon.get_pixel(0, 0).a).is_less(0.05)
	var mid := icon.get_pixel(64, 64)
	assert_float(mid.a).is_greater(0.95)
	assert_int(mid.g8).is_greater(150)


func test_an_empty_frame_is_none() -> void:
	assert_object(IconCut.cut(Image.new(), MadeIcons.cfg(data)["cut"])).is_null()
