extends GdUnitTestSuite
## No class feature or race trait passes by its id alone (v0.8.4.33): Pact of the Blade, of the Chain and of the Tome were
## «работает» on the checklist only because their ids stood in the code or in rules.json. An ability with no act, no stock
## and no road the probe runs must be looked at by a person and written to test/fixtures/abilities_reviewed.json with what
## does it (or «частично: …» and what is missing); one with nothing at all goes to rules.off.features.

var data: Dictionary
var rows: Dictionary


func before() -> void:
	data = TestUtils.data()
	rows = ChecklistProbe.sheet_rows(data, "Способности")


func test_no_ability_is_read_by_its_mention_alone() -> void:
	var unseen: Array[String] = []
	for id: String in rows:
		for st: String in rows[id]["steps"]:
			if st.trim_prefix("○ ").begins_with(ChecklistProbe.UNSEEN):
				unseen.append("%s: %s" % [id, st.trim_prefix("○ " + ChecklistProbe.UNSEEN)])
	assert_array(unseen).override_failure_message("умения, которые движок только упоминает — проверь каждое руками и запиши в abilities_reviewed.json (или в rules.off.features):\n%s" % "\n".join(unseen)).is_empty()


func test_every_reviewed_ability_is_one_of_the_game_and_still_read_only_so() -> void:
	var stale: Array[String] = []
	for id: String in ChecklistProbe.reviewed():
		if not rows.has(id):
			stale.append("%s: нет такого умения (или оно вне игры)" % id)
		elif not (rows[id]["steps"] as Array).any(func(st: String) -> bool: return st.contains(str(ChecklistProbe.reviewed()[id]))):
			stale.append("%s: теперь проверяется действием или запасом — убери из списка" % id)
	assert_array(stale).override_failure_message("лишние строки abilities_reviewed.json:\n%s" % "\n".join(stale)).is_empty()


func test_a_cut_ability_is_not_on_the_list() -> void:
	for id: String in (data["rules"]["off"].get("features", []) as Array):
		assert_bool(rows.has(str(id))).override_failure_message("%s вне игры, но на листе" % id).is_false()
