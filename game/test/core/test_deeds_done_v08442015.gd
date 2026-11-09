extends GdUnitTestSuite
## The world after the hero's deed (v0.8.4.42.@, the author's trace: after «Пепел над Маркой» Brod still talked of the
## fire on the tower and the missing as of now). What came of a finished quest goes to the master (`outcome`, the
## «Сделано» of the prompt) and the journal; the pack's records change by its facts through one road, Cond.overlay:
## a room's hooks, a person's character, the pack's lore; the pack's talk ends (`ends`) or begins (`when`) by them.

const QID := "ash_over_the_march"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	s.room_id = "brod-gate"
	s.minute = 12 * 60
	RumorRules.seed(s, data)
	return s


## The chain played to its end by the engine's own steps, the menhir decided by `choice`.
func _done(choice: String) -> GameSession:
	var s := _session()
	QuestRules.accept(s, data, QID)
	s.encounters_done.append_array(["crypt_commandant", "deep_ghoul"])
	QuestRules.advance(s, data)
	QuestRules.talk(s, data, QID)
	s.encounters_done.append("burrow_priest")
	QuestRules.advance(s, data)
	s.room_id = "pushcha-glade"
	Knows.add(s, Knows.SECRET, "pushcha-glade", "runes")
	QuestRules.choose(s, data, QID, choice)
	s.room_id = "brod-gate"
	QuestRules.talk(s, data, QID)
	s.room_id = "brod-tavern-hall"
	RumorRules.tick(s, data)  # the time's hook: the pack's talk of the deed begins
	return s


func _rumor_ids(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in RumorRules.known_at(s, data, "brod"):
		out.append(str(r["id"]))
	return out


func _quest(snap: Dictionary) -> Dictionary:
	for q: Dictionary in snap["quests"]:
		if str(q["id"]) == QID:
			return q
	return {}


func test_before_the_deed_brod_talks_of_the_cult_as_of_now() -> void:
	var s := _session()
	s.room_id = "brod-tavern-hall"
	assert_array(_rumor_ids(s)).contains(["tower_fire"])
	assert_array(_rumor_ids(s)).not_contains(["ash_lair_burned", "menhir_lit"])
	assert_str(" ".join(SceneRules.room(s, data["world"], "brod-tavern-hall")["hooks"])).contains("смотрит на восток")
	assert_str(str(SceneRules.npc(s, data["world"], "npc_captain")["personality"])).contains("пропавших много")
	assert_str(QuestRules.outcome(s, data["world"], QID)).is_empty()


func test_the_quest_done_carries_its_outcome_and_the_choice_made() -> void:
	var s := _done("restore")
	assert_bool(s.quests_done.has(QID)).is_true()
	var text := QuestRules.outcome(s, data["world"], QID)
	assert_str(text).contains("логово культа Пепла")
	assert_str(text).contains("Восстановить знаки на менгире")
	assert_str(text).not_contains("Забрать силу")
	var listed := XpRules.quest_list(s, data["world"]).filter(func(q: Dictionary) -> bool: return str(q["id"]) == QID)
	assert_str(str(listed[0]["outcome"])).is_equal(text)


func test_after_the_deed_the_talk_of_brod_is_of_the_past() -> void:
	var s := _done("restore")
	var ids := _rumor_ids(s)
	assert_array(ids).contains(["ash_lair_burned", "menhir_lit"])
	assert_array(ids).not_contains(["tower_fire", "menhir_broken"])
	var hooks := " ".join(SceneRules.room(s, data["world"], "brod-tavern-hall")["hooks"])
	assert_str(hooks).contains("спиной к востоку")
	assert_str(hooks).not_contains("смотрит на восток")
	assert_str(" ".join(SceneRules.room(s, data["world"], "brod-temple")["hooks"])).contains("новых имён не прибавляется")
	assert_str(" ".join(SceneRules.room(s, data["world"], "brod-gate")["hooks"])).contains("старые царапины")
	assert_str(str(SceneRules.npc(s, data["world"], "npc_captain")["personality"])).contains("больше не пропадают")
	assert_str(str(SceneRules.npc(s, data["world"], "npc_veteran")["personality"])).contains("культ Пепла разбит")


func test_the_taken_power_is_talked_of_its_own_way() -> void:
	var s := _done("power")
	assert_array(_rumor_ids(s)).contains(["ash_lair_burned", "menhir_broken"])
	assert_array(_rumor_ids(s)).not_contains(["menhir_lit"])
	assert_str(QuestRules.outcome(s, data["world"], QID)).contains("Забрать силу")


func test_the_master_sees_the_deed_done_in_the_snapshot() -> void:
	var s := _done("restore")
	s.room_id = "brod-tavern-hall"
	var snap := TurnSnapshot.build(s, data, 2000)
	var q := _quest(snap)
	assert_bool(bool(q["done"])).is_true()
	assert_str(str(q["outcome"])).contains("логово культа Пепла")
	assert_str(str(snap["world"]["lore"])).contains("логово разорено")
	assert_str(str(snap["world"]["lore"])).not_contains("Последний год в Пуще пропадают")
	assert_str(" ".join(snap["scene"]["rumors"])).contains("ash_lair_burned")
	assert_str(" ".join(snap["scene"]["rumors"])).not_contains("tower_fire")
	var orvin: Array = (snap["scene"]["npcs"] as Array).filter(func(n: Dictionary) -> bool: return str(n["npc_id"]) == "npc_veteran")
	assert_str(str(orvin[0]["personality"])).contains("культ Пепла разбит")


func test_a_bad_person_variant_is_refused_by_the_validator() -> void:
	var w: Dictionary = data["world"].duplicate(true)
	w["npcs"]["npc_captain"]["variants"] = [{"personality": "без условия"}, {"when": {"quest_done": QID}, "secrets": []}]
	var errors := WorldPack._validate_world(w, data)
	assert_int(errors.filter(func(e: String) -> bool: return e.contains("NPC npc_captain: вариант")).size()).is_equal(2)
