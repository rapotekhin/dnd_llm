extends GdUnitTestSuite
## The author's duty roster (v0.8.4.42.10): a quest's `find` step closes the moment its thing is the hero's — picked up from
## the floor, taken out of a chest, given — not only by the search; and a furnishing does not lay the quest's hidden thing
## in the open by a thing of the same name.

const ROOM := "brod-tavern-cellar"
const ROSTER := {"name": "Список нарядов", "description": "Лист с ночными сменами.", "item_type": "treasure", "rarity": "common", "value_cp": 0}

var kept: GameSession
var kept_world: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	kept = GameState.session
	kept_world = Catalog.data["world"].duplicate(true)
	s = TestUtils.new_session()
	GameState.session = s
	fx = EffectEngine.new()


func after_test() -> void:
	GameState.session = kept
	Catalog.data["world"] = kept_world


## A taken quest with its act: find the roster hidden in the cellar, then bring word to the innkeeper. Its id.
func _quest() -> String:
	var data := Catalog.data
	s.room_id = "brod-tavern-hall"
	fx.searched_quests["t-1"] = true
	var r := fx.validate(s, data, "t-1", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Наряды", "difficulty": "easy",
		"acts": [{"title": "Наряды", "goal": "Добыть список нарядов"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, id)
	var a := fx.validate(s, data, "t-2", {"kind": "quest_act", "quest_id": id, "act": 1,
		"items": [{"key": "roster", "item": ROSTER, "room": ROOM, "hint": "за бочкой", "dc_tier": "medium", "skill": "investigation"}],
		"steps": [{"text": "Добыть список нарядов", "kind": "find", "target": "roster"}, {"text": "Рассказать Бруно", "kind": "talk", "target": "npc_innkeeper"}]})
	assert_bool(bool(a["accepted"])).override_failure_message(str(a)).is_true()
	fx.apply(s, "t-2", [a["effect_id"]])
	s.room_id = ROOM
	assert_str(str(QuestRules.current(s, data["world"], id)["text"])).is_equal("Добыть список нарядов")
	return id


func _roster(qid: String) -> String:
	return str(s.generated["quests"][qid]["items"]["roster"])


func _step(qid: String) -> String:
	return str(QuestRules.current(s, Catalog.data["world"], qid).get("text", ""))


func test_a_quest_thing_picked_up_from_the_floor_closes_the_find_at_once() -> void:
	var qid := _quest()
	s.props[ROOM] = [{"id": "p1", "name": "Список нарядов", "item_id": _roster(qid), "owner": "", "state": ""}]
	assert_str(GameState.take_all()).is_empty()
	assert_int(int(s.character["inventory"].get(_roster(qid), 0))).is_equal(1)
	assert_str(_step(qid)).is_equal("Рассказать Бруно")
	assert_str(" · ".join(s.chat[-1]["lines"])).contains("Добыть список нарядов — сделано")


func test_a_quest_thing_taken_out_of_a_chest_closes_the_find_at_once() -> void:
	var qid := _quest()
	s.props[ROOM] = [{"id": "p1", "name": "Ящик", "item_id": "", "owner": "", "state": "", "container": "chest", "contents": {_roster(qid): 1}}]
	assert_str(GameState.container_take_all("p1")).is_empty()
	assert_str(_step(qid)).is_equal("Рассказать Бруно")


func test_a_quest_thing_got_any_other_way_closes_the_find_with_the_deed_s_line() -> void:
	var qid := _quest()
	ItemRules.found(s.character, Catalog.data, s.items, _roster(qid), 1)  # a gift, a body, a trader: any road that tells its deed
	GameState._effect_lines(["Получено: Список нарядов"])
	assert_str(_step(qid)).is_equal("Рассказать Бруно")
	assert_str(" · ".join(s.chat[-1]["lines"])).contains("Получено: Список нарядов")


func test_a_furnishing_does_not_lay_the_hidden_quest_thing_in_the_open() -> void:
	var qid := _quest()
	var e := {"kind": "furnish", "props": [{"name": "Стол", "body": "table"}, {"name": "Список нарядов", "item": ROSTER.duplicate()}]}
	var r := PropRules.plan_furnish(s, Catalog.data, e)
	assert_str(str(r.get("reason", ""))).contains("спрятан в тайнике")
	var chest := {"kind": "furnish", "props": [{"name": "Ящик", "container": "chest", "contents": [{"item_id": _roster(qid), "qty": 1}]}]}
	assert_str(str(PropRules.plan_furnish(s, Catalog.data, chest).get("reason", ""))).contains("спрятан в тайнике")
	Knows.add(s, Knows.SECRET, ROOM, "q_%s_roster" % qid)  # found: no longer held back
	assert_bool(PropRules.plan_furnish(s, Catalog.data, e).has("plan")).is_true()
