extends GdUnitTestSuite
## v0.8.4.42.1, the author: arrows would not go into the quiver from the sheet, and neither arrows nor a quiver to the belt.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	ItemRules.add(s.character, "quiver", 1)
	ItemRules.add(s.character, "arrows", 30)
	ContainerRules.sync_bags(s.character, data)
	return s


func test_ammunition_and_its_quiver_go_to_the_belt() -> void:
	var s := _hero()
	var c := s.character
	c["belt"] = ["", "", "", "", ""]  # the hero laid an empty belt
	assert_str(ItemRules.belt_why(c, data, s.items, "arrows")).is_empty()
	assert_str(ItemRules.belt_why(c, data, s.items, "quiver")).is_empty()
	ItemRules.belt_put(c, data, s.items, "arrows")
	ItemRules.belt_put(c, data, s.items, "quiver")
	assert_bool(ItemRules.on_belt(c, data, s.items, "arrows") and ItemRules.on_belt(c, data, s.items, "quiver")).is_true()
	assert_bool(ItemRules.belt_fits(data, s.items, "longsword")).is_false()  # a sword stays in the hands


func test_arrows_go_straight_into_the_quiver_as_many_as_it_holds() -> void:
	var s := _hero()
	var into := ContainerRules.bags_for(s, data, "arrows")
	assert_int(into.size()).is_equal(1)  # the quiver, not the backpack: only a bag with its own `holds`
	assert_int(int(into[0]["n"])).is_equal(20)
	var r := ContainerRules.plan_put(s, data, str(into[0]["bag"]), "arrows", 20)
	ContainerRules.apply_put(s, data, r["plan"])
	assert_int(Gear.ammo_left(data, s.character, "arrows")).is_equal(30)  # a belt never laid carries them: 20 in the quiver, 10 loose
	assert_array(ContainerRules.bags_for(s, data, "arrows")).is_empty()  # full
	assert_array(ContainerRules.bags_for(s, data, "longsword")).is_empty()


## The author: a shot takes only from the belt — the arrows laid there or a quiver on it; the pack's are not shot, and the
## sheet warns of a bow with nothing to shoot.
func test_a_shot_takes_only_from_the_belt() -> void:
	var s := _hero()
	var c := s.character
	var r := ContainerRules.plan_put(s, data, str(ContainerRules.bags_for(s, data, "arrows")[0]["bag"]), "arrows", 20)
	ContainerRules.apply_put(s, data, r["plan"])
	c["equipped"]["main_hand"] = "longbow"
	c["belt"] = ["", "", "", "", ""]
	assert_int(Gear.ammo_left(data, c, "arrows")).is_equal(0)
	assert_array(Gear.unfed(data, s.items, c)).contains(["longbow"])
	ItemRules.belt_put(c, data, s.items, "arrows")
	assert_int(Gear.ammo_left(data, c, "arrows")).is_equal(10)  # the loose ones on the belt
	ItemRules.belt_put(c, data, s.items, "quiver")
	assert_int(Gear.ammo_left(data, c, "arrows")).is_equal(30)
	assert_array(Gear.unfed(data, s.items, c)).is_empty()


func test_a_foe_that_never_laid_its_belt_still_shoots_and_drinks() -> void:
	var foe := {"inventory": {"healing_potion": 1, "arrows": 12, "quiver": 1}}
	var belt := ItemRules.belt(foe, data, {})
	assert_str(belt[0]).is_equal("healing_potion")  # what is used first
	assert_int(Gear.ammo_left(data, foe, "arrows")).is_equal(12)


func _preset(id: String) -> Dictionary:
	for p: Dictionary in data["presets"]:
		if str(p["id"]) == id:
			return CharacterBuilder.build_preset(p, data)
	return {}


## The author: a class that starts with a bow or a crossbow starts with its quiver or case, the ammunition in it, on the belt.
func test_a_start_kit_that_shoots_has_its_quiver_on_the_belt() -> void:
	var checked := 0
	for id: String in ["ranger_velena", "rogue_damir", "fighter_aira", "sorcerer_zlata", "warlock_fiber"]:
		var c := _preset(id)
		var shoots := Gear.unfed(data, {}, c)
		for slot: String in ["main_hand", "off_hand"]:
			for row: String in ["equipped", "stowed"]:
				var w := str((c.get(row, {}) as Dictionary).get(slot, ""))
				var ammo := Gear.ammo_of(data, {}, w) if not w.is_empty() else ""
				if not ammo.is_empty():
					checked += 1
					var holder := ContainerRules.holder_of(data, ammo)
					assert_int(int(c["inventory"].get(holder, 0))).override_failure_message("%s: no %s" % [id, holder]).is_equal(1)
					assert_bool(ItemRules.on_belt(c, data, {}, holder)).override_failure_message("%s: %s not on the belt" % [id, holder]).is_true()
					assert_int(Gear.ammo_left(data, c, ammo)).override_failure_message("%s: nothing to shoot" % id).is_greater(0)
		assert_array(shoots).override_failure_message("%s: %s unfed" % [id, shoots]).is_empty()
		var kinds := (c["inventory"] as Dictionary).keys().filter(func(k: String) -> bool: return bool(ContainerRules.cfg(data)["kinds"].get(k, {}).get("at_hand", false)))
		assert_array(kinds).override_failure_message("%s: %s" % [id, kinds]).not_contains(["efficient_quiver"])  # v0.8.4.42.5: never a magic one for the bow itself
		assert_bool(kinds.size() <= 1).override_failure_message("%s: %s" % [id, kinds]).is_true()  # one quiver, not one per weapon
	assert_int(checked).is_greater_equal(1)  # the ranger's longbow


func test_the_creation_shows_what_the_class_always_gives() -> void:
	var kit := CharacterBuilder.fixed_kit({"class": "ranger"}, data)
	var ids: Array = kit.map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_array(ids).contains(["longbow", "arrows", "quiver"])  # v0.8.4.42.5: the bow was never shown at creation
	assert_array(ids).not_contains(["efficient_quiver"])
	assert_bool(ContainerRules.at_hand_thing(data, {}, "longbow")).is_false()  # a bow is not ammunition for the belt
	assert_bool(ContainerRules.at_hand_thing(data, {}, "arrows")).is_true()
