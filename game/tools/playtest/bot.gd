extends "res://tools/playtest/playtest_base.gd"
## Bot player (roadmap v0.6.0): a random character plays N steps on the stub master (which also proposes damage,
## coins, conditions and healing) through the GameState commands a player has — actions, exits, talk and trade,
## deals and haggling, rests, quests, level-up, casting, features, items, preparing spells, save and load — and
## after every step checks the invariants of the session. Seeded: a failure replays with the same seed.
##   python tools/godot_playtest.py --scenario bot            (120 steps, seed 7)
##   GODOT_BOT_STEPS=300 GODOT_BOT_SEED=3 python tools/godot_playtest.py --scenario bot

var rng := RandomNumberGenerator.new()
var gs: Node
var data: Dictionary
var counts := {}


func run() -> void:
	gs = node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 20.0)):
		return
	var steps := int(OS.get_environment("GODOT_BOT_STEPS")) if not OS.get_environment("GODOT_BOT_STEPS").is_empty() else 120
	rng.seed = int(OS.get_environment("GODOT_BOT_SEED")) if not OS.get_environment("GODOT_BOT_SEED").is_empty() else 7
	data = node("Catalog").data
	var preset := str(_pick(data["presets"].map(func(p: Dictionary) -> String: return p["id"])))
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_" + preset)
	if not step("ready-made character " + preset, await tap("StartButton")):
		return
	data = node("Catalog").data
	await _idle()
	var broken := ""
	for i in steps:
		var what := await _act()
		counts[what] = int(counts.get(what, 0)) + 1
		await _idle()
		broken = _invariants()
		if not broken.is_empty():
			step("invariants after step %d (%s)" % [i + 1, what], false, broken)
			await shot("broken")
			return
	step("invariants held for %d steps" % steps, true, str(counts))
	var systems: Array = gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_SYSTEM)
	step("no failed turns", systems.is_empty(), str(systems.map(func(e: Dictionary) -> String: return str(e["key"]))))
	var c: Dictionary = gs.session.character
	step("info: end state", true, "level %d, xp %d, HP %d/%d, %d cp, day %d, room %s, quests %s" % [c["level"], c["xp"], c["hp"],
		c["max_hp"], c["gold_cp"], gs.session.day, gs.session.room_id, gs.session.quests_done])
	if CombatRules.active(gs.session):
		var cb: Dictionary = gs.session.combat
		step("info: fight", true, "turn %s, round %d, outcome '%s', busy %s, playing %s, retry %s, economy %s, foes %s" % [CombatRules.current(gs.session),
			cb["round"], cb.get("outcome", ""), gs.busy_turn, gs.combat_playing, gs.can_retry(), cb.get("economy", {}),
			CombatRules.enemies(gs.session, false).map(func(id: String) -> String: return "%s %s col %d hp %d" % [id, cb["fighters"][id]["status"], cb["fighters"][id]["col"], cb["fighters"][id]["hp"]])])
	await shot("end")


func _idle() -> void:
	await frames(2)
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	if gs.can_retry():
		gs.retry()
		await frames(2)
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)


func _pick(a: Array) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)] if not a.is_empty() else null


## One random player command; returns its name for the report.
func _act() -> String:
	var s: GameSession = gs.session
	var c := s.character
	var w := WorldView.new(data["world"])
	if CombatRules.active(s):
		return await _combat_step(s)
	if LevelUp.can_level_up(c, data):
		gs.level_up(LevelUp.default_picks(c, data))
		return "level_up"
	if not s.in_conversation() and rng.randf() < 0.08:
		gs.set_sneaking(not s.sneaking)
		return "sneak_on" if s.sneaking else "sneak_off"
	if s.mode == GameSession.MODE_TRADE:
		match rng.randi_range(0, 3):
			0:
				var info := TradeRules.info(s, data, s.npc_id)
				var line: Variant = _pick(info["stock"])
				if line != null and int(c["gold_cp"]) >= int(line["price_cp"]):
					gs.deal({"buy": {line["item_id"]: 1}, "sell": {}})
					return "buy"
			1:
				var info := TradeRules.info(s, data, s.npc_id)
				var line: Variant = _pick(info["buys"])
				if line != null and int(info["purse_cp"]) >= int(line["price_cp"]):
					gs.deal({"buy": {}, "sell": {line["item_id"]: 1}})
					return "sell"
			2:
				gs.haggle()
				return "haggle"
		gs.leave_conversation()
		return "leave_trade"
	if s.in_conversation():
		if rng.randf() < 0.4:
			gs.leave_conversation()
			return "leave"
		if w.is_trader(s.npc_id) and rng.randf() < 0.3:
			gs.set_trade(true)
			return "to_trade"
		gs.submit(_pick(["Расскажи, что слышно в округе", "Налей мне эля", "Сбавь цену, а?", "Прощай"]))
		return "say"
	# The commands of exploration in a random order; the first that goes through is the step.
	var tries: Array[Callable] = [
		func() -> String: return "action" if gs.submit(_pick(["Осматриваюсь", "Обыскиваю углы", "Прислушиваюсь", "Иду к двери"])) else "",
		func() -> String: return "go" if gs.go(str(_pick(w.exits(s.room_id)))) else "",
		func() -> String:
			var npc: Variant = _pick(w.npcs_in(s.room_id))
			return "talk" if npc != null and gs.talk_to(npc, w.is_trader(npc) and rng.randf() < 0.5) else "",
		func() -> String:
			for q: String in XpRules.quests_here(s, data["world"]):
				if gs.complete_quest(q).is_empty():
					return "quest"
			return "",
		func() -> String:
			for q: String in QuestRules.offers_here(s, data["world"]):
				if gs.accept_quest(q).is_empty():
					return "quest_take"
			for t: Dictionary in QuestRules.talks_here(s, data["world"]):
				if gs.quest_talk(str(t["quest_id"])).is_empty():
					return "quest_step"
			return "",
		func() -> String:
			var ft: Variant = _pick(ExplorationRules.found_traps(s, data["world"], s.room_id))
			if ft == null:
				return ""
			var disarm := rng.randf() < 0.5
			return ("trap_disarm" if disarm else "trap_bypass") if gs.trap_action(str(ft["to"]), disarm).is_empty() else "",
		func() -> String: return "long_rest" if gs.long_rest().is_empty() else "",
		func() -> String: return "short_rest" if rng.randf() < 0.5 and gs.short_rest(rng.randi_range(0, 2)).is_empty() else "",
		func() -> String:
			var spell: Variant = _pick(SpellRules.ready(c))
			return "cast" if spell != null and gs.cast(spell).is_empty() else "",
		func() -> String:
			var res: Variant = _pick(FeatureUses.owned(c, data))
			return "feature" if res != null and gs.use_feature(res).is_empty() else "",
		func() -> String:
			for id: String in c["inventory"]:
				if gs.use_item(id).is_empty():
					return "use_item"
			return "",
		func() -> String:
			if not SpellRules.can_prepare(c, data, s.day).is_empty():
				return ""
			var p := SpellRules.prepare_pool(c, data)
			var ids: Array = (p["pool"] as Array).duplicate()
			ids.shuffle()
			return "prepare" if gs.prepare_spells(ids.slice(0, mini(int(p["count"]), ids.size()))).is_empty() else "",
		func() -> String:
			if rng.randf() > 0.3:
				return ""
			var before := JSON.stringify(s.to_dict(500))
			gs.save_to("slot_1")
			gs.load_from("slot_1")
			if before != JSON.stringify(gs.session.to_dict(500)):
				counts["save_mismatch"] = int(counts.get("save_mismatch", 0)) + 1
			return "save_load",
	]
	for k in tries.size():
		var j := rng.randi_range(k, tries.size() - 1)
		var t := tries[k]
		tries[k] = tries[j]
		tries[j] = t
	for t: Callable in tries:
		var done: String = t.call()
		if not done.is_empty():
			return done
	gs.submit("Жду и смотрю по сторонам")
	return "wait"


## A fight: finish when it is over (take all loot), else on the player's turn attack, cast or step closer.
func _combat_step(s: GameSession) -> String:
	if not str(s.combat.get("outcome", "")).is_empty():
		if str(s.combat["outcome"]) == "dead":
			gs.load_from(gs.COMBAT_SAVE)
			return "died_and_loaded"
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		gs.finish_combat((s.combat.get("loot", []) as Array).map(func(l: Dictionary) -> String: return l["item_id"]))
		return "combat_end"
	if not CombatRules.player_can_act(s) or gs.is_busy():
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		return "combat_wait"
	var skill: String = _pick(CombatRules.cfg(data)["parley"]["skills"])
	if rng.randf() < 0.15 and CombatRules.can_parley(s, data, skill).is_empty() and int(CombatRules.economy(s).get("action", 0)) > 0:
		gs.combat_parley(skill)
		return "combat_parley"
	if rng.randf() < 0.2 and CombatRules.can_hide(s, data).is_empty():
		gs.combat_hide()
		return "combat_hide"
	for id: String in CombatRules.enemies(s):
		if CombatRules.can_attack(s, data, id).is_empty():
			gs.combat_attack(id)
			return "combat_attack"
	var spell: Variant = _pick(SpellRules.ready(s.character))
	var foe: Variant = _pick(CombatRules.enemies(s))
	if spell != null and foe != null and CombatRules.can_cast(s, data, spell, 0, foe).is_empty() and rng.randf() < 0.5:
		gs.combat_cast(spell, 0, foe)
		return "combat_cast"
	if foe != null and int(CombatRules.economy(s).get("move", 0)) > 0 and int(CombatRules.fighter(s, foe)["col"]) != int(CombatRules.player(s)["col"]):
		var dir := 1 if int(CombatRules.fighter(s, foe)["col"]) > int(CombatRules.player(s)["col"]) else -1
		gs.combat_move(dir)
		return "combat_move"
	gs.combat_end_turn()
	return "combat_end_turn"


## "" when the session is consistent, otherwise what broke.
func _invariants() -> String:
	var s: GameSession = gs.session
	var c := s.character
	var w := WorldView.new(data["world"])
	if counts.has("save_mismatch"):
		return "save → load changed the session"
	if int(c["hp"]) < (0 if CombatRules.active(s) else 1) or int(c["hp"]) > int(c["max_hp"]):
		return "HP %d of %d" % [c["hp"], c["max_hp"]]
	if s.minute < 0 or s.minute >= 1440:
		return "minute %d" % s.minute
	for q: String in s.quests_active:
		if QuestRules.current(s, data["world"], q).is_empty() or s.quests_done.has(q):
			return "quest %s at a bad step %s" % [q, s.quests_active[q]]
	if int(c["gold_cp"]) < 0:
		return "coins %d" % c["gold_cp"]
	for id: String in c["inventory"]:
		if int(c["inventory"][id]) <= 0:
			return "inventory %s ×%d" % [id, c["inventory"][id]]
	for i in 5:
		if int(c["slots_used"][i]) < 0 or int(c["slots_used"][i]) > int(c["slots_max"][i]):
			return "slots %s of %s" % [c["slots_used"], c["slots_max"]]
	for id: String in c.get("resources_used", {}):
		if int(c["resources_used"][id]) > FeatureUses.max_uses(c, data, id):
			return "feature %s used %d" % [id, c["resources_used"][id]]
	if int(c.get("hit_dice_used", 0)) > int(c["level"]) or int(c.get("hit_dice_used", 0)) < 0:
		return "hit dice used %d" % c["hit_dice_used"]
	if w.room(s.room_id).is_empty():
		return "room %s" % s.room_id
	if CombatRules.active(s):
		for id: String in s.combat["fighters"]:
			var f: Dictionary = s.combat["fighters"][id]
			if absi(int(f.get("col", 0))) > CombatRules.edge(data) or int(f.get("hp", 0)) < 0:
				return "fighter %s at col %d hp %d" % [id, f.get("col", 0), f.get("hp", 0)]
		if s.mode != GameSession.MODE_COMBAT:
			return "a fight without combat mode"
	if s.in_conversation() and not w.npcs_in(s.room_id).has(s.npc_id):
		return "talking to %s who is not here" % s.npc_id
	if s.mode == GameSession.MODE_TRADE and not w.is_trader(s.npc_id):
		return "trading with a non-trader %s" % s.npc_id
	for npc: String in s.merchants:
		var m: Dictionary = s.merchants[npc]
		if int(m["purse_cp"]) < 0:
			return "merchant %s purse %d" % [npc, m["purse_cp"]]
		for id: String in m["stock"]:
			if int(m["stock"][id]) < 0:
				return "merchant %s stock %s %d" % [npc, id, m["stock"][id]]
	for cond: Variant in c.get("conditions", []):
		if not (c.get("condition_ends", {}) as Dictionary).has(cond):
			return "condition %s without an end" % cond
	return ""
