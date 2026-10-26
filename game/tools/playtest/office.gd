extends "res://tools/playtest/playtest_base.gd"
## Offices (python tools/godot_playtest.py --scenario office), v0.7.34: Aira, well known in Brod, asks Tikhon for the
## collector's place, decides the day's cases (one honestly, one with a squeeze), gets a week's wage; joins the militia
## at the captain; the judge's place after her service; elected headman at the townhall — the tax, the palisade built,
## the gate with its new palisade; the temple's conditions. Difficulty «trivial»: only a natural 1 fails.


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
	var data: Dictionary = node("Catalog").data
	var s: GameSession = gs.session
	var c := s.character
	c["gold_cp"] = 100000
	s.settings["needs"] = false
	s.settings["difficulty"] = "trivial"
	s.rested_at = TimeRules.abs_minute(s) + 400 * 1440
	s.reputation["brod"] = 1000
	ReputationRules.refresh(s, data)
	s.rng.seed = 11
	_go(s, "brod-townhall", 10)
	await frames(3)

	await open_row("More_npc_clerk")
	var ob: Button = find(screen(), "Office_npc_clerk")
	if not step("«Должности» at Tikhon", ob != null and not ob.disabled):
		await shot("no_offices")
		return
	await press(ob)
	await frames(4)
	var ov: Control = find(screen(), "OfficeView")
	await shot("offers")
	await press(find(ov, "OfficeAppoint_brod_collector"))
	await frames(4)
	step("the collector's place", OfficeRules.holds(c, "brod_collector"), _last_effects(s))
	await frames(2)
	var gold := int(c["gold_cp"])
	await press(find(ov, "Decide_brod_collector_0_collect"))
	await frames(3)
	await press(find(ov, "Decide_brod_collector_1_squeeze"))
	await frames(3)
	step("the cases decided", (OfficeRules.today(s, data, "brod_collector") as Array).all(func(x: Dictionary) -> bool: return bool(x["done"])), _last_effects(s))
	step("a squeeze in the pocket", int(c["gold_cp"]) >= gold + 400, "%d → %d" % [gold, int(c["gold_cp"])])
	await shot("cases")
	ov.visible = false

	OfficeRules.view(c)["brod_collector"]["last_day"] = s.day + 7
	gold = int(c["gold_cp"])
	TimeRules.advance(s, data, 7 * 1440)
	step("a week's wage", int(c["gold_cp"]) >= gold + 700, "%d → %d" % [gold, int(c["gold_cp"])])

	_go(s, "brod-gate", 10)
	await frames(3)
	await open_row("More_npc_captain")
	await press(find(screen(), "Office_npc_captain"))
	await frames(4)
	ov = find(screen(), "OfficeView")
	await press(find(ov, "OfficeAppoint_brod_militia"))
	await frames(4)
	step("in the militia", OfficeRules.holds(c, "brod_militia"), _last_effects(s))
	OfficeRules.view(c)["brod_collector"]["merit"] = 30
	node("EventBus").state_changed.emit()
	await frames(3)
	var jb: Button = find(ov, "OfficeAppoint_brod_judge")
	step("the judge's place after the service", jb != null and not jb.disabled)
	await shot("captain")
	await press(jb)
	await frames(4)
	step("the judge", OfficeRules.holds(c, "brod_judge"), _last_effects(s))
	ov.visible = false

	_go(s, "brod-townhall", 11)
	await frames(3)
	var sb: Button = find(screen(), "OfficeButton")
	if not step("«Служба» on the panel", sb != null):
		await shot("no_office_row")
		return
	await press(sb)
	await frames(4)
	ov = find(screen(), "OfficeView")
	await press(find(ov, "OfficeElect_brod_headman"))
	await frames(4)
	step("elected headman", OfficeRules.holds(c, "brod_headman"), _last_effects(s))
	await press(find(ov, "Tax_brod_headman_high"))
	await frames(3)
	await press(find(ov, "Build_brod_headman_palisade"))
	await frames(3)
	step("the palisade begun", (OfficeRules.town(s, data, "brod")["builds"] as Dictionary).has("palisade"))
	await shot("headman")
	ov.visible = false
	for id: String in OfficeRules.held(c):
		OfficeRules.view(c)[id]["last_day"] = s.day + 5
	TimeRules.advance(s, data, 5 * 1440)
	step("the palisade stands", s.flags.has("brod_palisade"))
	_go(s, "brod-gate", 12)
	await frames(3)
	step("the gate shows it", (SceneRules.room(s, data["world"], "brod-gate")["hooks"] as Array).any(func(h: String) -> bool: return h.contains("частокол")))

	_go(s, "brod-temple", 12)
	await frames(3)
	await open_row("More_npc_priestess")
	await press(find(screen(), "Office_npc_priestess"))
	await frames(4)
	ov = find(screen(), "OfficeView")
	var ab: Button = find(ov, "OfficeAppoint_brod_abbot")
	step("the temple asks for Religion and closeness", ab != null and ab.disabled)
	await shot("temple")


func _go(s: GameSession, room: String, hour: int) -> void:
	s.room_id = room
	s.minute = hour * 60
	node("EventBus").state_changed.emit()


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
