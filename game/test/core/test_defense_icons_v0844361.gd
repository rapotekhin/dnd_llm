extends GdUnitTestSuite
## Defense icons as in BG3 (v0.8.4.43.61, the author's note of 2026-11-14): an immunity, a resistance or a weakness to a damage
## type has a picture of its own for the pair — «Иммунитет к огню», «Устойчивость к огню», «Уязвимость к огню» — and only
## without one the shield of the kind wears the type's mark. The ref stays one (`conditions/immune@fire`): IconRules decides.

var data: Dictionary


func before_test() -> void:
	data = Catalog.load_all()
	IconRules.forget()


func after_test() -> void:
	IconRules.forget()


func _file(r: String, there: bool) -> void:
	IconRules._exists[IconRules.root(data) + r + ".png"] = there


func test_the_pair_has_its_own_picture() -> void:
	_file("conditions/immune_fire", true)
	var ic := IconRules.of(data, {}, "conditions/immune@fire")
	assert_str(str(ic["path"])).ends_with("conditions/immune_fire.png")
	assert_bool(bool(ic["real"])).is_true()
	assert_array(ic["marks"]).is_empty()  # no mark over its own picture


func test_without_the_pair_the_shield_wears_the_mark() -> void:
	_file("conditions/resistant_fire", false)
	_file("conditions/resistant", true)
	var ic := IconRules.of(data, {}, "conditions/resistant@fire")
	assert_str(str(ic["path"])).ends_with("conditions/resistant.png")
	assert_array((ic["marks"] as Array).map(func(m: Dictionary) -> String: return m["id"])).contains_exactly(["fire"])


func test_a_physical_type_has_its_pair_too() -> void:
	_file("conditions/vulnerable_slashing", true)  # no mark of its own: the pair's picture is all it has
	var ic := IconRules.of(data, {}, "conditions/vulnerable@slashing")
	assert_str(str(ic["path"])).ends_with("conditions/vulnerable_slashing.png")


func test_a_status_and_a_card_name_the_pair() -> void:
	var e := {"condition": "", "resist": ["cold"], "source": {"kind": "engine", "name": "тест"}}
	assert_str(ConditionRules.icon_of(data, e)).is_equal("conditions/resistant@cold")
	_file("conditions/resistant_cold", true)
	assert_str(str(IconRules.of(data, {}, ConditionRules.icon_of(data, e))["path"])).ends_with("conditions/resistant_cold.png")
