extends "res://tools/playtest/playtest_base.gd"
## Interactive world playtest (python tools/godot_playtest.py --scenario world; --real for the real master), v0.7.0:
## the tavern hall is furnished on entering (with the real master — `furnish`; the stub master leaves it bare), the
## pockets window of Mira by the button, a theft by «Стащить», then the guard's reaction on a second, failed try.

func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_rogue_damir")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	step("info: the hall furnished", true, str(PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return "%s%s" % [p["name"], " [%s]" % p["item_id"] if not str(p["item_id"]).is_empty() else ""])))
	await shot("hall")
	await open_row("More_npc_serving")  # v0.7.22.23: the acts under the name
	var pk: Button = find(screen(), "Pockets_npc_serving")
	if not step("pockets button of Mira", pk != null and not pk.disabled):
		return
	await press(pk)
	await frames(3)
	var view: Control = find(screen(), "TheftView")
	step("the pockets window", view != null and view.visible, str(TheftRules.pockets(s, node("Catalog").data, "npc_serving").map(func(e: Dictionary) -> String: return "%s Сл %d" % [e["name"], e["dc"]])))
	await shot("pockets")
	s.character["skills"]["sleight_of_hand"] = 40  # a sure hand for the first try
	var first: Button = find(view, "Steal_k1")
	if step("steal the first thing", first != null and not first.disabled):
		var gold: int = s.character["gold_cp"]
		await press(first)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("taken", int(s.character["gold_cp"]) > gold or s.character["inventory"].size() > 0, "gold %d → %d" % [gold, s.character["gold_cp"]])
	s.character["skills"]["sleight_of_hand"] = -40  # and a clumsy one for the second
	var next: Button = find(screen(), "TheftView").find_child("Steal_k2", true, false) if find(screen(), "TheftView") != null else null
	if next != null and not next.disabled:
		await press(next)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("caught: Mira calls the guard", int(s.caught_by.get("npc_serving", 0)) == s.day and s.attitude("npc_serving") < 0,
			"attitude %d, gold %d" % [s.attitude("npc_serving"), s.character["gold_cp"]])
		await frames(3)
		await shot("caught")
	_report.append("----- chat -----")
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 14)):
		match str(e["kind"]):
			GameSession.KIND_DM:
				_report.append("МАСТЕР: " + str(e["text"]))
			GameSession.KIND_EFFECT:
				_report.append("ЭФФЕКТЫ: " + " · ".join(e["lines"]))
