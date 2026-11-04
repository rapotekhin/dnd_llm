extends GdUnitTestSuite
## The author's checklist checked row by row (ChecklistProbe): every item, monster, ability, spell, condition, defense and
## damage type run on the engine. The statuses are held in test/fixtures/checklist_probes.json: a row that changed — a
## mechanic broken, or one made — fails here until the file is written again (res://tools/checklist_probes.gd) and the
## sheet rebuilt (tools/checklist.py).

const KEPT := "res://test/fixtures/checklist_probes.json"

var kept: Dictionary


func before() -> void:
	kept = JSON.parse_string(FileAccess.get_file_as_string(KEPT))


func _sheet(sheet: String) -> void:
	var now := ChecklistProbe.sheet_rows(TestUtils.data(), sheet)
	var was: Dictionary = kept.get(sheet, {})
	var moved: Array[String] = []
	for id: String in now:
		var st := str(now[id]["status"])
		if not was.has(id):
			moved.append("%s: новая строка (%s)" % [id, st])
		elif str(was[id]["status"]) != st:
			moved.append("%s: %s → %s · %s" % [id, was[id]["status"], st, " · ".join(now[id]["steps"]).left(200)])
	for id: String in was:
		if not now.has(id):
			moved.append("%s: строки больше нет" % id)
	assert_array(moved).override_failure_message("%s — изменились строки (перепиши test/fixtures/checklist_probes.json): \n%s" % [sheet, "\n".join(moved)]).is_empty()
	var bugs := now.keys().filter(func(id: String) -> bool: return str(now[id]["status"]) == ChecklistProbe.BUG)
	assert_array(bugs).override_failure_message("%s — ошибки движка: %s" % [sheet, bugs]).is_empty()


func test_ordinary_items() -> void:
	_sheet("Обычные предметы")


func test_magic_items() -> void:
	_sheet("Магические предметы")


func test_monsters() -> void:
	_sheet("Монстры")


func test_abilities() -> void:
	_sheet("Способности")


func test_spells() -> void:
	_sheet("Заклинания")


func test_conditions() -> void:
	_sheet("Состояния")


func test_defenses() -> void:
	_sheet("Сопротивления и иммунитеты")


func test_damage_types() -> void:
	_sheet("Типы урона")


func test_a_row_is_its_worst_step() -> void:
	assert_str(str(ChecklistProbe.result(["✓ a", "○ b", "◇ c"])["status"])).is_equal(ChecklistProbe.GAP)
	assert_str(str(ChecklistProbe.result(["✓ a", "· b"])["status"])).is_equal(ChecklistProbe.OK)
	assert_str(str(ChecklistProbe.result(["◇ a", "✗ b"])["status"])).is_equal(ChecklistProbe.BUG)
	assert_str(str(ChecklistProbe.result([])["status"])).is_equal(ChecklistProbe.PLAIN)


func test_a_monster_immune_to_a_condition_never_gets_it() -> void:
	var data := TestUtils.data()
	var s := TestUtils.new_session()
	var m := ChecklistProbe.fight(s, data, "skeleton")
	ConditionRules.impose(s, data, {"condition": "poisoned", "ends": {}, "source": {"kind": "dev", "name": "проба"}}, m)
	assert_bool(ConditionRules.has(m, "poisoned")).is_false()
	var g := ChecklistProbe.fight(TestUtils.new_session(), data, "goblin")
	ConditionRules.impose(s, data, {"condition": "poisoned", "ends": {}, "source": {"kind": "dev", "name": "проба"}}, g)
	assert_bool(ConditionRules.has(g, "poisoned")).is_true()
