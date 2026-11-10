extends GdUnitTestSuite
## v0.8.4.43: one place an icon is chosen. A file by id, else a made thing's plain base with marks of its element and
## material and the frame of its rarity, else its group's file, else the blank of the kind, else _blank/default.png.

var data: Dictionary


func before_test() -> void:
	data = Catalog.load_all()
	IconRules.forget()


func after_test() -> void:
	IconRules.forget()


func test_no_file_gives_the_blank_of_the_kind() -> void:
	var ic := IconRules.of(data, {}, "features/rage")
	assert_str(ic["path"]).is_equal("res://assets/icons/_blank/features.png")
	assert_bool(ic["real"]).is_false()


func test_an_unknown_kind_gives_the_default_blank() -> void:
	assert_str(IconRules.of(data, {}, "nonsense/x")["path"]).is_equal("res://assets/icons/_blank/default.png")


func test_a_file_by_id_wins() -> void:
	data["icons"]["shared"]["items/longsword"] = "_blank/items"
	var ic := IconRules.of(data, {}, "items/longsword")
	assert_bool(ic["real"]).is_true()
	assert_str(ic["path"]).ends_with("_blank/items.png")


func test_a_made_thing_takes_its_base_with_marks_and_frame() -> void:
	data["icons"]["shared"]["items/longsword"] = "_blank/items"
	var made := {"gen_storm": {"name": "Грозовой длинный меч", "base": "longsword", "rarity": "rare",
		"properties": ["lightning_damage", "silvered"], "item_type": "weapon", "value_cp": 100}}
	var ic := IconRules.of(data, made, "items/gen_storm")
	assert_bool(ic["real"]).is_true()
	assert_str(ic["path"]).ends_with("_blank/items.png")
	assert_str(ic["frame"]).is_equal(str(data["icons"]["rarity"]["rare"]))
	var marks: Array = (ic["marks"] as Array).map(func(m: Dictionary) -> String: return m["id"])
	assert_array(marks).contains(["lightning", "silvered"])


func test_a_thing_with_no_base_file_is_not_real() -> void:
	var ic := IconRules.of(data, {}, "items/adamantine_chain_mail")
	assert_bool(ic["real"]).is_false()
	var marks: Array = (ic["marks"] as Array).map(func(m: Dictionary) -> String: return m["id"])
	assert_array(marks).contains(["adamantine"])


func test_a_spell_with_no_file_wears_its_school_and_its_marks() -> void:
	var ic := IconRules.of(data, {}, "spells/burning_hands")
	assert_str(ic["path"]).is_equal("res://assets/icons/_blank/spells.png")
	assert_str(ic["tint"]).is_equal(str(data["icons"]["schools"]["evocation"]))
	var marks: Array = (ic["marks"] as Array).map(func(m: Dictionary) -> String: return m["id"])
	assert_array(marks).contains(["fire", "cone"])
