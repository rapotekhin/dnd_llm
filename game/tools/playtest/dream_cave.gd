extends "res://tools/playtest/playtest_base.gd"
## The halls of the tutorial's cave (python tools/godot_playtest.py --scenario dream_cave), v0.8.4.44.4: «Найти выход» from
## the first moment; «Обыскать» finds the trap of DC 2 at the way out, the old chest in its niche gives its coins and
## things; the found trap is gone around; the body of the second hall is searched and its armour put on; the second
## trap springs on the way out whatever was searched; the fighter is untied and goes along, the archer's body searched;
## the cleric waits under the goblins' guard; the fifth hall's step brings the hero and the fighter to the 2nd level.
## The fights themselves are the combat scenarios': here they are counted fought. v0.8.4.44.5: the screens of teaching of
## each hall are shot as they come, darkened with their arrow, and passed by «Продолжить»; the fourth hall's ready words
## and the sixth's three are the only options under the chat. v0.8.4.44.6: the sixth hall's first ask makes a legendary
## sword past every budget.


func _go(gs: Node, to: String) -> bool:
	var ok: bool = gs.go(to)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	return ok


func run() -> void:
	var gs := node("GameState")
	var sm := node("SaveManager")
	sm.tutorial_done = false
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await frames(3)
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("the dream began", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	step("«Найти выход» from the first moment", s.quests_active.has("find_the_exit") and QuestRules.tracked(s, data["world"]) == "find_the_exit",
		str(s.quests_active))
	var map := WalkRules.view(s, data)
	step("the hall is drawn of its own chunk", str(map["picks"]["dream-1"]["chunk"]) == "dream_1")
	step("the old chest stands on the map", MapSpots.of(s, data, map).any(func(t: Dictionary) -> bool: return str(t["ref"]) == "prop:f_chest"))
	step("no trap seen in passing", ExplorationRules.found_traps(s, data["world"], "dream-1").is_empty())
	step("the first hall's screens: walking, then «Осмотреться»", await lessons("teach") == ["walk", "look"])
	await shot("hall_1")
	await tap("LookButton")
	step("after the look — «Обыскать»", await lessons("teach") == ["search"])

	await tap("SearchButton")
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	var checks: Array = s.chat.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "check")
	var dc := int(checks.back().get("dc", -1)) if not checks.is_empty() else -1
	var found := not ExplorationRules.found_traps(s, data["world"], "dream-1").is_empty()
	var all := ", ".join(checks.map(func(e: Dictionary) -> String: return "%s Сл %d" % [e.get("skill", ""), int(e.get("dc", -1))]))
	step("«Обыскать» rolls against the trap's DC 2 and finds it", checks.any(func(e: Dictionary) -> bool: return str(e.get("skill", "")) == "perception" and int(e.get("dc", -1)) == 2) and found,
		"%s; найдена: %s" % [all, found])
	await shot("hall_1_search")

	await tap("PlaceButton")
	await frames(3)
	await tap("Container_f_chest")
	await frames(3)
	var view: Control = find(screen(), "ContainerView")
	var gold := Ledger.balance(s)
	if view != null:
		await press(find(view, "TakeAll"))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	step("the chest gives its coins and things", Ledger.balance(s) - gold == 1500 and int(s.character["inventory"].get("healing_potion", 0)) == 2,
		"%d, %s" % [Ledger.balance(s) - gold, s.character["inventory"]])
	await shot("hall_1_chest")
	if view != null:
		await press(find(view, "CloseContainerButton"))
		await frames(3)

	if found:
		step("the found trap stops the way", not gs.go("dream-2") and s.room_id == "dream-1")
		await frames(3)
		step("gone around it", gs.trap_action("dream-2", false).is_empty())
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
	if s.room_id != "dream-2":
		await _go(gs, "dream-2")
	if not step("in the hall of bones", s.room_id == "dream-2", s.room_id):
		return
	step("the body's screen", await lessons("teach") == ["body"])
	var body: Array = CreatureRules.here(s, "dream-2").filter(func(c: Dictionary) -> bool: return str(c["state"]) == CreatureRules.DEAD)
	step("the body lies by the wall", not body.is_empty())
	await shot("hall_2")
	step("the body searched", not body.is_empty() and gs.creature_act(str(body[0]["id"]), "search").is_empty()
		and gs.container_take_all(CreatureRules.BOX + str(body[0]["id"])).is_empty()
		and int(s.character["inventory"].get("leather_armor", 0)) == 1 and int(s.character["inventory"].get("shield", 0)) == 1, str(s.character["inventory"]))
	step("the armour taken — the screen of gear", await lessons("teach") == ["gear"])
	step("the leather armour put on", gs.equip("leather_armor", "armor").is_empty() and str(s.character["equipped"].get("armor", "")) == "leather_armor",
		str(s.character["equipped"]))
	var hp := int(s.character["hp"])
	await _go(gs, "dream-3")
	step("the second trap springs on the way out, unsearched", s.traps.get("dream-2:needles", "") == "sprung" and int(s.character["hp"]) < hp,
		"%d → %d" % [hp, int(s.character["hp"])])
	if not step("in the hall of the rings", s.room_id == "dream-3", s.room_id):
		return
	step("the third hall's screens: the wound, then the captive", await lessons("teach") == ["hurt", "captive"])
	await shot("hall_3")
	step("the fighter is bound, nothing on him", s.held_as_creature("npc_dream_fighter") and (Gear.of(s, data, "npc_dream_fighter")["inventory"] as Dictionary).is_empty())
	step("«Развязать»", gs.creature_act("npc_dream_fighter", "untie").is_empty())
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	step("the fighter goes along", Being.follows(s, "npc_dream_fighter"))
	var archer: Array = CreatureRules.here(s, "dream-3").filter(func(c: Dictionary) -> bool: return str(c.get("pack", "")) == "archer")
	step("the archer's bow, arrows and quiver", not archer.is_empty() and gs.creature_act(str(archer[0]["id"]), "search").is_empty()
		and gs.container_take_all(CreatureRules.BOX + str(archer[0]["id"])).is_empty()
		and int(s.character["inventory"].get("shortbow", 0)) == 1 and int(s.character["inventory"].get("quiver", 0)) == 1, str(s.character["inventory"]))
	step("the quiver taken — the screen of arrows", await lessons("teach") == ["arrows"])
	await shot("hall_3_party")

	step("the goblins wait in their den, the guards in the grotto", not EncounterRules.live(s, data, "dream-4").is_empty() and not EncounterRules.live(s, data, "dream-5").is_empty())
	s.encounters_done.append("dream_goblins")  # not a combat test
	await _go(gs, "dream-4")
	step("in the goblins' den", s.room_id == "dream-4", s.room_id)
	step("the cleric is free to untie once the goblins are beaten", CreatureRules.can(s, "npc_dream_cleric", "untie", data).is_empty())
	step("«Развязать» the cleric", gs.creature_act("npc_dream_cleric", "untie").is_empty())
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	step("the cleric does not go along by herself", not Being.follows(s, "npc_dream_cleric"))
	step("talked into it at DC 2", int(SocialRules.dc(s, data, "npc_dream_cleric", "persuasion", "easy")["dc"]) == 2)
	step("the cleric free — the screen of improvising", await lessons("teach") == ["improvise"])
	step("its ready words the only option, Persuasion against DC 2", s.options.size() == 1 and s.options[0].contains("жрице")
		and int(gs.option_preview(0).get("dc", -1)) == 2, "%s, %s" % [s.options, gs.option_preview(0)])
	await shot("hall_4")

	s.encounters_done.append("dream_guards")
	await _go(gs, "dream-5")
	step("the fifth hall's step: the hero ready for the 2nd level", int(s.character["xp"]) >= LevelUp.xp_for(data, 2) and LevelUp.can_level_up(s.character, data),
		str(s.character["xp"]))
	step("and the fighter beside", GrowthRules.ready(s, data, "npc_dream_fighter"))
	await shot("hall_5_level")
	await _go(gs, "dream-6")
	step("the sixth hall's screen and its three asks", await lessons("teach") == ["making"] and s.options.size() == 3, str(s.options))
	await shot("hall_6")
	var spent := s.reward_spent
	gs.choose_option(0)  # v0.8.4.44.6: the archangel's sword asked; the stub makes a legendary one past every budget
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	var made: Array = (s.character["inventory"] as Dictionary).keys().filter(func(id: String) -> bool:
		return str(ItemRules.def_of(data["items"], s.items, id).get("rarity", "")) == "legendary")
	step("the sixth hall makes a legendary sword outside the budget", made.size() == 1 and s.reward_spent == spent and s.magic_given == 0, str(s.character["inventory"]))
	await shot("hall_6_made")
	await _go(gs, "dream-7")
	step("the last hall: the dream's end, «Проснуться»", await lessons("teach") == ["wake"])
	await shot("hall_7")
	step("«Найти выход» done in the last hall", s.quests_done.has("find_the_exit"), str(s.quests_active))
	sm.tutorial_done = false
	sm.save_settings()
