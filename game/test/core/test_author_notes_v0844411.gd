extends GdUnitTestSuite
## v0.8.4.44.11, the author's 11 notes of 2026-11-16: nothing put on by itself; worn and belt things handed in the party
## window; universal armour of the property `any_wearer`; a flyer under a roof within a blade's reach; guards who keep
## their post; no results window over the dream's wake.

var data: Dictionary
var kept: GameSession


func before() -> void:
	data = TestUtils.data()


func before_test() -> void:
	kept = GameState.session
	GameState.session = _party()


func after_test() -> void:
	GameState.session = kept


func _party() -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	return s


func _inv(s: GameSession, who: String, item: String) -> int:
	return int(Gear.of(s, data, who).get("inventory", {}).get(item, 0))


## «первая же броня попавшая в инвентарь надевается … пусть её наденет игрок»: the hero and a follower given a thing keep it in the pack.
func test_a_thing_given_is_not_put_on_by_itself() -> void:
	var s := GameState.session
	s.character["equipped"]["armor"] = ""
	Gear.give(s, data, Being.HERO, "chain_mail")
	assert_str(str(s.character["equipped"]["armor"])).is_empty()
	var mate := Gear.of(s, data, "npc_mercenary")
	(mate.get("equipped", {}) as Dictionary)["armor"] = ""
	Gear.give(s, data, "npc_mercenary", "leather_armor")
	assert_str(str(Gear.of(s, data, "npc_mercenary").get("equipped", {}).get("armor", ""))).is_empty()


## «обмениваться всеми предметами — и надетыми и на поясе»: a worn thing goes off its slot into the other's pack.
func test_a_worn_thing_is_handed_off_its_slot() -> void:
	var s := GameState.session
	var armor := str(s.character["equipped"]["armor"])
	assert_str(armor).is_not_empty()
	var had := _inv(s, "npc_mercenary", armor)
	assert_str(Equip.hand_why(s, data, Being.HERO, "npc_mercenary", armor)).is_empty()
	assert_str(GameState.item_act({"act": "give", "item": armor, "to": "npc_mercenary", "qty": 1}, Being.HERO)).is_empty()
	assert_str(str(s.character["equipped"]["armor"])).is_empty()
	assert_int(_inv(s, "npc_mercenary", armor)).is_equal(had + 1)
	assert_str(str(Gear.of(s, data, "npc_mercenary").get("equipped", {}).get("armor", ""))).is_not_equal(armor)


func test_a_worn_thing_is_not_handed_in_a_fight() -> void:
	var s := GameState.session
	var armor := str(s.character["equipped"]["armor"])
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 6}], {})
	assert_str(Equip.hand_why(s, data, Being.HERO, "npc_mercenary", armor)).is_not_empty()


func test_a_belt_thing_is_handed_and_its_cell_marked() -> void:
	var s := GameState.session
	ItemRules.add(s.character, "healing_potion", 2)
	if ItemRules.belt_why(s.character, data, s.items, "healing_potion").is_empty():
		ItemRules.belt_put(s.character, data, s.items, "healing_potion")
	assert_str(PartyPanel.place_of(s, data, Being.HERO, "healing_potion")).is_equal("slots/belt")
	assert_str(PartyPanel.place_of(s, data, Being.HERO, str(s.character["equipped"]["armor"]))).is_equal("slots/armor")
	assert_str(GameState.item_act({"act": "give", "item": "healing_potion", "to": "npc_mercenary", "qty": 2}, Being.HERO)).is_empty()
	assert_int(_inv(s, Being.HERO, "healing_potion")).is_equal(0)
	assert_bool(ItemRules.on_belt(s.character, data, s.items, "healing_potion")).is_false()


## «универсальный доспех, который бы мог носить каждый»: heavy armour of `any_wearer` on a wizard, no Strength it asks.
func test_armour_anybody_wears() -> void:
	var s := GameState.session
	var c := s.character
	c["armor_profs"] = []
	ItemRules.add(c, "plate_armor", 1)
	assert_str(CharacterRules.can_equip(c, data, s.items, "plate_armor", "armor")).is_equal("EQUIP_NO_PROFICIENCY")
	var def: Dictionary = (data["items"]["catalog"]["plate_armor"] as Dictionary).duplicate(true)
	def["name"] = "Доспех для всех"
	def["base"] = "plate_armor"
	def["properties"] = ["any_wearer"]
	s.items["gen_any_plate"] = def
	ItemRules.add(c, "gen_any_plate", 1)
	assert_str(CharacterRules.can_equip(c, data, s.items, "gen_any_plate", "armor")).is_empty()
	assert_int(CharacterRules.armor_slow(def, 3, "human", data)).is_equal(0)
	assert_bool(data["items"]["properties"].has("any_wearer")).is_true()


## «в помещениях "полёт" не даёт способности не быть целью атаки ближнего боя … на улице — уже нет».
func test_a_flyer_under_a_roof_is_within_a_blade() -> void:
	var s := GameState.session
	s.room_id = "brod-tavern-hall"
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 0}], {})
	SpellEffects.apply_self(s, data, "fly", 3)
	CharacterRules.refresh(s.character, data, s.items)
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	TestUtils.beside(s, f)
	var me := CombatRules.player(s)
	assert_bool(CombatRules.airborne(s, data, me)).is_true()
	assert_bool(CombatRules.above_blades(s, data, me)).is_false()
	assert_bool(CombatRules.blade_reaches(s, data, f, me)).is_true()
	s.room_id = "brod-square"
	assert_bool(CombatRules.above_blades(s, data, me)).is_true()
	assert_bool(CombatRules.blade_reaches(s, data, f, me)).is_false()


## «"Сторожевой Грот" пустой»: the dream's guards keep their post and do not come to the den's fight.
func test_the_dream_guards_keep_their_post() -> void:
	var path := "res://data/worlds/tutorial/world.json"
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(bool(world["rooms"]["dream-5"]["encounter"].get("post", false))).is_true()
