extends GdUnitTestSuite
## World packs: the start pack is valid, broken packs and mods are reported, rules filter and rename the SRD,
## the snapshot carries the world and the master settings.

const FRONTIER := "res://data/worlds/frontier"
const MODS := "user://test_mods/worlds"

var base: Dictionary


func before_test() -> void:
	base = TestUtils.base()
	_wipe(MODS)


func after_test() -> void:
	_wipe(MODS)


func _wipe(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		for f in DirAccess.get_files_at(dir.path_join(d)):
			DirAccess.remove_absolute(dir.path_join(d).path_join(f))
		DirAccess.remove_absolute(dir.path_join(d))


## Copies the start pack into the mods folder as `id`, changed by `edit` (func(bundle: Dictionary) -> void).
func _mod(id: String, edit: Callable) -> void:
	var b := WorldPack.load_bundle(FRONTIER, "builtin")
	b["pack"]["id"] = id
	edit.call(b)
	var dir := MODS.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	for key: String in ["pack", "world", "characters"]:
		var f := FileAccess.open(dir.path_join(key + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(b[key]))
		f.close()


func _errors(id: String) -> Array:
	for b: Dictionary in WorldPack.scan([WorldPack.BUILTIN_DIR, MODS], base):
		if b["id"] == id:
			return b["errors"]
	return ["not found"]


func test_the_start_pack_is_valid() -> void:
	var b := WorldPack.load_bundle(FRONTIER, "builtin")
	assert_array(WorldPack.validate(b, base)).is_empty()
	assert_str(b["pack"]["name"]).is_equal("Сумеречная Марка")


func test_one_ready_made_character_per_class() -> void:
	var d := TestUtils.data()
	var classes: Array = d["presets"].map(func(p: Dictionary) -> String: return p["choices"]["class"])
	classes.sort()
	var all: Array = d["classes"]["classes"].keys()
	all.sort()
	assert_array(classes).is_equal(all)
	for p: Dictionary in d["presets"]:
		var c := CharacterBuilder.build_preset(p, d)
		assert_str(c["story"]).override_failure_message(p["id"]).is_not_empty()
		assert_int(c["max_hp"]).is_greater(0)


func test_a_valid_mod_loads_next_to_the_builtin() -> void:
	_mod("my_world", func(b: Dictionary) -> void: b["pack"]["name"] = "Мой мир")
	var found := WorldPack.scan([WorldPack.BUILTIN_DIR, MODS], base)
	var mod: Dictionary = found.filter(func(x: Dictionary) -> bool: return x["id"] == "my_world")[0]
	assert_str(mod["source"]).is_equal("mod")
	assert_array(mod["errors"]).is_empty()


func test_broken_mods_are_reported() -> void:
	_mod("bad_rules", func(b: Dictionary) -> void: b["pack"]["rules"]["races"] = ["human", "ent"])
	_mod("bad_exit", func(b: Dictionary) -> void: b["world"]["rooms"]["brod-square"]["exits"].append("nowhere"))
	_mod("bad_preset", func(b: Dictionary) -> void: b["characters"]["presets"][0]["choices"]["skills"] = ["arcana"])
	_mod("bad_style", func(b: Dictionary) -> void: b["pack"]["dm_style"] = "epic")
	_mod("frontier", func(_b: Dictionary) -> void: pass)
	assert_str(" ".join(_errors("bad_rules"))).contains("ent")
	assert_str(" ".join(_errors("bad_exit"))).contains("nowhere")
	assert_str(" ".join(_errors("bad_preset"))).contains("CC_ERR_SKILLS")
	assert_str(" ".join(_errors("bad_style"))).contains("dm_style")
	var dup := WorldPack.scan([WorldPack.BUILTIN_DIR, MODS], base).filter(func(x: Dictionary) -> bool: return x["id"] == "frontier")
	assert_int(dup.size()).is_equal(2)
	assert_array(dup[0]["errors"]).is_empty()  # the built-in one wins
	assert_str(" ".join(dup[1]["errors"])).contains("уже есть")


func test_rules_filter_and_rename() -> void:
	var b := WorldPack.load_bundle(FRONTIER, "builtin")
	b["pack"]["rules"]["races"] = ["human", "elf"]
	b["pack"]["rules"]["classes"] = ["fighter"]
	b["pack"]["rules"]["items_exclude"] = ["crossbow_hand"]
	b["pack"]["rules"]["rename"]["items"] = {"longsword": {"name": "Меч пограничья"}}
	var d := WorldPack.apply_rules(base, b)
	assert_array(d["races"]["races"].keys()).contains_exactly_in_any_order(["human", "elf"])
	assert_array(d["classes"]["classes"].keys()).is_equal(["fighter"])
	assert_bool(d["items"]["catalog"].has("crossbow_hand")).is_false()
	assert_str(d["items"]["catalog"]["longsword"]["name"]).is_equal("Меч пограничья")
	assert_str(d["backgrounds"]["soldier"]["name"]).is_equal("Ветеран войны")
	assert_str(base["backgrounds"]["soldier"]["name"]).is_equal("Солдат")  # the base is untouched
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ch := CharacterBuilder.random_choices(d, rng)
	assert_str(ch["class"]).is_equal("fighter")
	assert_array(d["names"]["female"]).contains([ch["name"]] if ch["gender"] == "female" else [d["names"]["female"][0]])


func test_snapshot_carries_the_world_and_settings() -> void:
	var s := TestUtils.new_session()
	s.settings["dm_style"] = "dry"
	s.settings["veils"] = ["пауки"]
	s.settings["wishes"] = ["мрачный юмор"]
	var w: Dictionary = TurnSnapshot.build(s, TestUtils.data(), 4000)["world"]
	assert_str(w["name"]).is_equal("Сумеречная Марка")
	assert_str(w["lore"]).contains("Пепельн")
	assert_str(w["dm_style"]).is_equal("dry")
	assert_array(w["veils"]).is_equal(["пауки"])
	assert_array(w["wishes"]).is_equal(["мрачный юмор"])
	var c: Dictionary = TurnSnapshot.build(s, TestUtils.data(), 4000)["character"]
	assert_str(c["backstory"]).contains("Серой заставы")


func test_default_settings_come_from_the_pack() -> void:
	var st := WorldPack.default_settings(WorldPack.load_bundle(FRONTIER, "builtin")["pack"])
	assert_dict(st).contains_key_value("world", "frontier")
	assert_dict(st).contains_key_value("dm_style", "classic")
	assert_dict(st).contains_key_value("death_mode", "story")
	assert_array(st["veils"]).contains(["пытки"])
