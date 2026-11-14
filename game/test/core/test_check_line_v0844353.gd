extends GdUnitTestSuite
## v0.8.4.43.53, the author: «Строка проверки молчит о 1 и 20 на кубе: „Атлетика 41 против Сл 15 — провал“ без слова о
## естественной 1». Every line of a check against a DC says it by Roll.versus, and names the die when it decided against
## the total (ADR-0008 §2: a natural 20 / 1 always succeeds / fails).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_the_die_is_named_only_when_it_decided_against_the_total() -> void:
	assert_str(Roll.versus(41, 15, 1)).is_equal("41 против Сл 15, но на кубе 1")
	assert_str(Roll.versus(8, 15, 20)).is_equal("8 против Сл 15, но на кубе 20")
	assert_str(Roll.versus(15, 12, 7)).is_equal("15 против Сл 12")
	assert_str(Roll.versus(25, 15, 20)).is_equal("25 против Сл 15")  # it would pass anyway
	assert_str(Roll.versus(4, 15, 1)).is_equal("4 против Сл 15")  # it would fail anyway
	assert_str(Roll.versus(8, 15, 20, false)).is_equal("8 против Сл 15")  # an automatic failure is no die's doing
	assert_str(Roll.sum_versus(1, 41, 15)).is_equal("1 + 40 = 41 против Сл 15, но на кубе 1")
	assert_str(Roll.sum_versus(12, 9, 10)).is_equal("12 − 3 = 9 против Сл 10")
	assert_str(Roll.versus(16, 12, 1, false, "КД")).is_equal("16 против КД 12, но на кубе 1")  # a blow at a door or a thing


func test_a_check_failed_by_a_natural_1_says_so() -> void:
	var s := TestUtils.new_session()
	var seen := false
	for i: int in 400:
		s.rng.seed = i
		var r := EncounterRules.roll(s, data, "athletics", -10)  # passes whatever the total but on a natural 1
		if not bool(r["ok"]):
			assert_str(str(r["line"])).contains("но на кубе 1")
			seen = true
	assert_bool(seen).is_true()


func test_a_save_passed_by_a_natural_20_says_so() -> void:
	var s := TestUtils.new_session()
	var seen := false
	for i: int in 400:
		s.rng.seed = i
		var r := Sheet.save(s, data, Sheet.HERO, "con", 60, "", false, {"quiet": true})  # fails whatever the total but on a natural 20
		if bool(r["ok"]):
			assert_str(str(r["text"])).contains("но на кубе 20")
			seen = true
		else:
			assert_str(str(r["text"])).not_contains("на кубе")
	assert_bool(seen).is_true()


func test_an_occupations_line_and_the_check_card_say_it_too() -> void:
	var r := {"nat": 1, "total": 41, "dc": 15, "ok": false}
	assert_str(Activity.line("Смена", "Атлетика", r, "провал")).is_equal("Смена: Атлетика 1 + 40 = 41 против Сл 15, но на кубе 1 — провал")
	var e := {"skill": "athletics", "nat": 1, "rolls": [1], "bonus": 40, "total": 41, "dc": 15, "success": false}
	var card := CheckCard.new(e)
	var line := card.text_for(e)
	card.free()
	assert_str(line).contains("41 против Сл 15, но на кубе 1")
	assert_str(line).not_contains("DC")
