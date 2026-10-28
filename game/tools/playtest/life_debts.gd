extends "res://tools/playtest/playtest_base.gd"
## The empty boxes of «Своя жизнь» (python tools/godot_playtest.py --scenario life_debts), v0.7.39.1: a dagger +1
## made at the forge by «Артефакция» from a dagger and arcane dust; Bruno following the hero eats from its things;
## Ostap's artel — joined in its window, the convoy guard hired at Ostap and a shift that ends with bandits.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	s.settings["needs"] = false
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["inventory"]["dagger"] = 1
	c["inventory"]["arcane_dust"] = 8
	c["gold_cp"] = 50000
	DevelopmentRules.state(c, "artifice")["xp"] = 60
	(DevelopmentRules.state(c, "artifice")["skills"] as Array).append("enchant_weapon")
	s.room_id = "brod-smithy"
	s.minute = 8 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await press(find(screen(), "CraftButton"))
	await frames(4)
	var win: Control = find(screen(), "CraftView")
	var id := "tpl:enchant_weapon:dagger_plus_1"
	step("«Кинжал +1» among the recipes", find(win, "Recipe_" + id.validate_node_name()) != null)
	await shot("enchant_recipe")
	await press(find(win, "CraftStart_" + id.validate_node_name()))
	await frames(3)
	step("the dagger and the dust go", not c["inventory"].has("dagger") and not c["inventory"].has("arcane_dust"))
	for i in 6:
		if CraftRules.project(c).is_empty():
			break
		s.minute = 8 * 60  # the forge's hours
		node("EventBus").state_changed.emit()
		await frames(2)
		var work: Button = find(win, "CraftWork_8")
		if work == null or work.disabled:
			break
		await press(work)
		await wait_until(func() -> bool: return not gs.is_busy(), 20.0)
		await frames(3)
	var made := (c["inventory"] as Dictionary).keys().filter(func(k: String) -> bool:
		return k == "dagger_plus_1" or str(ItemRules.def_of(data["items"], s.items, k).get("base", "")) == "dagger_plus_1")
	step("a dagger +1 made, «Артефакция» grows", made.size() == 1 and DevelopmentRules.xp(c, "artifice") > 60, _last_effects(s))
	await shot("enchanted")
	win.visible = false

	s.settings["needs"] = true
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	FollowRules.apply(s, {"follow_npc": "npc_innkeeper", "on": true, "room": ""})
	c["inventory"]["rations"] = 3
	var lines := TimeRules.advance(s, data, 25 * 60)
	step("Bruno eats from the hero's things", "\n".join(lines).contains("Бруно Хмель поел"), "\n".join(lines.filter(func(l: String) -> bool: return l.contains("Бруно"))))
	FollowRules.apply(s, {"follow_npc": "npc_innkeeper", "on": false, "room": ""})
	s.settings["needs"] = false

	s.room_id = "brod-gate"
	s.minute = 12 * 60
	(DevelopmentRules.state(c, "work")["skills"] as Array).append("good_word")  # hired without the interview's roll
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_drover")
	var ob: Button = find(screen(), "Org_npc_drover")
	if not step("«Артель» among Ostap's acts", ob != null and ob.text == "Артель", ob.text if ob != null else ""):
		await shot("no_artel")
		return
	await press(ob)
	await frames(4)
	var org: Control = find(screen(), "OrgView")
	await shot("artel_window")
	await press(find(org, "OrgJoin_drovers"))
	await frames(4)
	step("joined the artel, its work named", OrgRules.member(c, "drovers") and find(org, "OrgWork") != null, _last_effects(s))
	await shot("artel_member")
	org.visible = false
	await frames(2)

	await open_row("More_npc_drover")
	await press(find(screen(), "Jobs_npc_drover"))
	await frames(4)
	var jv: Control = find(screen(), "JobView")
	step("the convoy guard among Ostap's jobs", jv != null and find(jv, "Job_caravan_guard") != null)
	await press(find(jv, "JobHire_caravan_guard"))
	await frames(4)
	step("hired as the convoy guard", JobRules.hired(c, "caravan_guard"), _last_effects(s))
	await shot("convoy_hired")
	data["world"]["jobs"]["caravan_guard"]["fight"]["chance"] = 1.0
	await press(find(jv, "JobShift_caravan_guard"))
	var fought := await wait_until(func() -> bool: return screen_is("CombatScreen") or s.mode == GameSession.MODE_COMBAT, 60.0)
	step("bandits fall on the convoy", fought, _last_effects(s))
	await frames(6)
	await shot("convoy_fight")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
