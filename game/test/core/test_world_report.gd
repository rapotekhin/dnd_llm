extends GdUnitTestSuite
## WorldReport: the dev console's view of the pack and of what the session knows.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()


func test_the_room_shows_exits_npcs_secrets_and_their_state() -> void:
	var text := WorldReport.room(s, data, TestUtils.START_ROOM)
	assert_str(text).contains("Выходы:").contains("NPC:").contains("Бруно Хмель").contains("Секрет portrait [скрыт")
	s.revealed[TestUtils.START_ROOM] = ["portrait"]
	assert_str(WorldReport.room(s, data, TestUtils.START_ROOM)).contains("Секрет portrait [найден")
	assert_str(WorldReport.room(s, data, "no-such-room")).contains("нет комнаты")
	assert_str(WorldReport.room(s, data, "brod-temple")).contains("ночлег")


func test_quests_tell_taken_done_and_offered_here() -> void:
	s.room_id = "brod-tavern-hall"
	assert_str(WorldReport.quests(s, data)).contains("«Письмо для Илвы» [letter_to_ilva] — даёт здесь")
	QuestRules.accept(s, data, "letter_to_ilva")
	assert_str(WorldReport.quests(s, data)).contains("в работе, шаг 1")


func test_items_list_the_pockets_and_search_every_pool() -> void:
	assert_str(WorldReport.items(s, data)).contains("Монеты:")
	assert_str(WorldReport.items(s, data, "bruno_letter")).contains("(пакет)")
	assert_str(WorldReport.items(s, data, "zzzz")).contains("ничего не найдено")


func test_npc_rooms_and_state() -> void:
	assert_str(WorldReport.npc(s, data, "бруно")).contains("npc_innkeeper").contains("brod-tavern-hall")
	assert_str(WorldReport.rooms(s, data)).contains("● ")
	assert_str(WorldReport.state(s)).contains("флаги:")
