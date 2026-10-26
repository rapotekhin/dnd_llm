extends "res://tools/playtest/playtest_base.gd"
## The underworld (python tools/godot_playtest.py --scenario underworld), v0.7.33: Aira joins the Night Rats at Сыч in
## the den under the mill, the trial — a night burglary of the townhall by the «Дела» window; the clerk's signet refused
## by the smith and sold to Fern; the cut paid, a masked robbery on the outpost road, casks past the gate; rest in the
## hideout; her own band in the river house with the serving girl. Difficulty «trivial»: only a natural 1 fails.


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
	s.rng.seed = 7
	_go(s, "brod-den", 20)
	await frames(3)

	await open_row("More_npc_guildhead")
	var ob: Button = find(screen(), "Org_npc_guildhead")
	if not step("«Братство» at Сыч", ob != null and not ob.disabled):
		await shot("no_org_button")
		return
	await press(ob)
	await frames(4)
	var org: Control = find(screen(), "OrgView")
	await shot("org_join")
	await press(find(org, "OrgJoin_night_rats"))
	await frames(4)
	step("a candidate with the trial", OrgRules.candidate(c, "night_rats") and HeistRules.status(c, "heist_townhall") == "active", _last_effects(s))
	await shot("org_trial")
	org.visible = false

	ItemRules.found(c, data, s.items, "thieves_tools", 1)
	_go(s, "brod-townhall", 23)
	await frames(3)
	var hb: Button = find(screen(), "HeistButton")
	if not step("«Дела» on the panel", hb != null):
		await shot("no_heists")
		return
	await press(hb)
	await frames(4)
	var hv: Control = find(screen(), "HeistView")
	await press(find(hv, "Step_heist_townhall_tools"))
	await frames(3)
	await press(find(hv, "Step_heist_townhall_scout"))
	await frames(3)
	step("prepared", HeistRules.prep(s, data, "heist_townhall") > 0, _last_effects(s))
	await shot("heist_prepared")
	await press(find(hv, "Act_heist_townhall"))
	await frames(4)
	step("the townhall robbed", HeistRules.status(c, "heist_townhall") == "done", _last_effects(s))
	step("the trial passed — one of the Rats", OrgRules.member(c, "night_rats"))
	step("the clerk's signet is stolen", int(OwnerRules.foreign(s).get("signet_ring", {}).get("npc_clerk", 0)) == 1)
	await shot("heist_done")
	hv.visible = false

	_go(s, "brod-smithy", 12)
	await frames(3)
	step("the smith knows a stolen thing", str(TradeRules.quote(s, data, "npc_smith", {"sell": {"signet_ring": 1}})["error"]) == "TRADE_ERR_STOLEN")
	_go(s, "brod-square", 12)
	await frames(3)
	var gold := int(c["gold_cp"])
	var q := TradeRules.quote(s, data, "npc_merchant", {"sell": {"signet_ring": 1}})
	step("Fern buys it", str(q["error"]).is_empty(), str(q))
	if str(q["error"]).is_empty():
		TradeRules.execute(s, data, "npc_merchant", {"sell": {"signet_ring": 1}})
	step("sold at the fence's price", int(c["gold_cp"]) > gold, "%d → %d" % [gold, int(c["gold_cp"])])
	step("Fern sells picks to a Rat", int(TradeRules.merchant(s, data, "npc_merchant")["stock"].get("thieves_tools", 0)) >= 2)

	_go(s, "brod-den", 13)
	await frames(3)
	await open_row("More_npc_guildhead")
	await press(find(screen(), "Org_npc_guildhead"))
	await frames(4)
	org = find(screen(), "OrgView")
	await shot("org_owed")
	await press(find(org, "OrgPay_night_rats"))
	await frames(3)
	step("the cut paid", int(OrgRules.view(c)["night_rats"]["owed_cp"]) == 0, _last_effects(s))
	await press(find(org, "OrgTake_heist_convoy"))
	await frames(3)
	await press(find(org, "OrgTake_heist_casks"))
	await frames(3)
	step("two jobs taken", HeistRules.active(c).size() == 2, str(HeistRules.active(c)))
	await shot("org_member")
	org.visible = false
	step("the hideout's cots are free", bool(ExplorationRules.rest_place(data["world"], s.room_id, s, data).get("free", false)))

	_go(s, "outpost-road", 12)
	await frames(3)
	await press(find(screen(), "HeistButton"))
	await frames(4)
	hv = find(screen(), "HeistView")
	await press(find(hv, "Step_heist_convoy_mask"))
	await frames(3)
	await press(find(hv, "Step_heist_convoy_ambush"))
	await frames(3)
	await shot("robbery")
	await press(find(hv, "Act_heist_convoy"))
	await frames(4)
	step("the convoy robbed", HeistRules.status(c, "heist_convoy") == "done", _last_effects(s))
	step("masked — not wanted", not s.wanted.has("brod"), str(s.wanted))

	_go(s, "brod-gate", 14)
	await frames(3)
	await press(find(hv, "Step_heist_casks_hide"))
	await frames(3)
	await press(find(hv, "Step_heist_casks_watch"))
	await frames(3)
	await press(find(hv, "Act_heist_casks"))
	await frames(4)
	step("the casks through the gate", HeistRules.status(c, "heist_casks") == "done" and int(c["inventory"].get("contraband_cask", 0)) == 0, _last_effects(s))
	await shot("smuggled")
	hv.visible = false

	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(c)["river_house"]["deed"] = true
	_go(s, "brod-river-house", 15)
	await frames(3)
	var ob2: Button = find(screen(), "OrgButton")
	if not step("«Братство» on the panel", ob2 != null):
		await shot("no_org_row")
		return
	await press(ob2)
	await frames(4)
	org = find(screen(), "OrgView")
	(find(org, "OrgFoundName") as LineEdit).text = "Речные тени"
	await shot("org_found")
	await press(find(org, "OrgFound"))
	await frames(4)
	step("own band founded", OrgRules.own(s, data) == "own", _last_effects(s))
	org.visible = false

	c["bonds"] = {"npc_serving": {"kind": "friend", "points": 40}}
	_go(s, "brod-tavern-hall", 16)
	await frames(3)
	await open_row("More_npc_serving")
	var rb: Button = find(screen(), "Recruit_npc_serving")
	if not step("«В братство» at the serving girl", rb != null and not rb.disabled):
		await shot("no_recruit")
		return
	await press(rb)
	await frames(4)
	step("she joins", OrgRules.members(s, data, "own").has("npc_serving"), _last_effects(s))
	await press(find(screen(), "OrgButton"))
	await frames(4)
	await shot("own_band")


func _go(s: GameSession, room: String, hour: int) -> void:
	s.room_id = room
	s.minute = hour * 60
	node("EventBus").state_changed.emit()


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
