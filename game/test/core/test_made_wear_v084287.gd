extends GdUnitTestSuite
## A thing the master makes may lay a status while it works (`wear`) and call creatures (`use.summon`) — the words and the
## rows the catalog's own magic things carry (v0.8.4.26), priced by items.json `wear_points` and `use_points.summon`
## (roadmap tail of v0.8.4.26, v0.8.4.28.7).

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = ChecklistProbe.session(data)
	s.character["level"] = 3
	fx = EffectEngine.new()


## The master's `move_item:world>hero` with a new thing; its id or the engine's refusal.
func _give(item: Dictionary) -> Dictionary:
	fx.searched["t-1"] = true
	fx._won["t-1"] = ["perception"]  # a magic find needs a check that passed
	var r := fx.validate(s, data, "t-1", {"kind": "move_item", "source": "world", "target": "hero", "item": item, "qty": 1, "reason": "находка"})
	if not bool(r["accepted"]):
		return {"reason": str(r.get("reason", ""))}
	fx.apply(s, "t-1", [r["effect_id"]])
	var c := s.character
	for id: String in s.items:
		if str(s.items[id].get("name", "")) == str(item["name"]):
			for held: String in c["inventory"]:  # worn where its look says (a cloak, boots), as the hero would
				var slot := CharacterRules.slot_for(ItemRules.def_of(data["items"], s.items, held), data)
				if ItemRules.real_id(held) == id and not slot.is_empty():
					c["equipped"][slot] = held
			CharacterRules.refresh(c, data, s.items)
			return {"id": id}
	return {"reason": "не найдено"}


func test_a_made_cloak_flies_at_its_speed_while_worn() -> void:
	var got := _give({"name": "Плащ нетопыря", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 40000,
		"description": "Кожистый плащ.", "wear": {"fly_speed": 40}})
	assert_bool(got.has("id")).override_failure_message(str(got)).is_true()
	var d: Dictionary = s.items[got["id"]]
	assert_str(str(d["rarity"])).is_equal("uncommon")
	assert_bool(bool(d["wear"]["flying"])).is_true()  # a flight brings `flying` along
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("fly", 0))).is_equal(40)
	assert_str(" ".join(CharacterRules.item_boons(s.character, data, s.items))).contains("Плащ нетопыря")


func test_made_boots_walk_on_water_at_the_wearers_walk() -> void:
	var got := _give({"name": "Сапоги водомерки", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 20000, "wear": {"water_walk": "walk"}})
	assert_bool(got.has("id")).override_failure_message(str(got)).is_true()
	assert_bool(SpellEffects.has(s.character, "water_walk")).is_true()
	assert_str(str(s.items[got["id"]]["wear"]["water_walk"])).is_equal("walk")
	# two words are priced together: 2 + 3 points — a rare thing
	var both := ItemRules.check_generated(data, {"name": "Сапоги", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100,
		"wear": {"water_walk": "walk", "see_invisible": true}}, 5)
	assert_str(str(both["def"]["rarity"])).is_equal("rare")


func test_what_the_engine_does_not_read_is_refused() -> void:
	assert_str(str(_give({"name": "Сапоги", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100, "wear": {"burrow_speed": 20}}).get("reason", ""))) \
		.contains("не читает")
	assert_str(str(_give({"name": "Сапоги", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100, "wear": {"fly_speed": 120}}).get("reason", ""))) \
		.contains("5–60")
	s.character["level"] = 1
	assert_str(str(_give({"name": "Сапоги", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100,
		"wear": {"fly_speed": "walk", "see_invisible": true}}).get("reason", ""))).contains("уровне")


func test_a_made_whistle_calls_its_wolves_with_the_hero() -> void:
	var got := _give({"name": "Свисток стаи", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 30000,
		"use": {"summon": {"monster": "wolf", "count": 2, "minutes": 60}, "charges": 2}})
	assert_bool(got.has("id")).override_failure_message(str(got)).is_true()
	var id := str(got["id"])
	assert_str(str(s.items[id]["rarity"])).is_equal("uncommon")  # 1 + CR ¼ × 2 rounded up
	ItemRules.belt_put(s.character, data, s.items, id)
	ItemRules.use(s.character, data, s.items, id, s.rng, s)
	var called := AllyRules.called(s)
	assert_int(called.size()).is_equal(2)
	assert_str(str(called[0]["monster"])).is_equal("wolf")
	assert_str(" ".join(AllyRules.summon_lines(s, data))).contains("Свисток стаи")
	assert_str(ItemInfo.use_line(data, id, s.items)).contains("Волк")


func test_a_foe_blows_the_same_whistle_for_its_side() -> void:
	var got := _give({"name": "Свисток стаи", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 30000,
		"use": {"summon": {"monster": "wolf", "count": 1, "minutes": 60}, "charges": 2}})
	var id := str(got["id"])
	var g := ChecklistProbe.fight(s, data, "goblin")
	var before := CombatRules.enemies(s).size()
	var lines := AllyRules.summon_by(s, data, g, id)
	assert_int(CombatRules.enemies(s).size()).is_equal(before + 1)
	assert_str(" ".join(lines)).contains("Свисток стаи")


func test_a_summon_of_what_is_not_in_the_bestiary_or_too_strong_is_refused() -> void:
	assert_str(str(_give({"name": "Рог", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 100,
		"use": {"summon": {"monster": "kraken"}, "charges": 1}}).get("reason", ""))).contains("бестиари")
	assert_str(str(_give({"name": "Рог", "item_type": "wondrous", "rarity": "rare", "value_cp": 100,
		"use": {"summon": {"monster": "dire_wolf", "count": 4}, "charges": 1}}).get("reason", ""))).contains("уровне")
