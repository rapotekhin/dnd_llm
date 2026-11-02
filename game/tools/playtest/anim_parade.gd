extends "res://tools/playtest/playtest_base.gd"
## Foes' strikes and spells as the engine sees them (python tools/godot_playtest.py --scenario anim_parade), v0.8.4.23: a guard, a
## hobgoblin, an orc, a goblin, a wolf, a brown bear and a mage in one fight. Each foe steps beside the hero; its token is shot close
## (its weapon and its shield from its SRD gear), then each of its melee attacks at the hero phase by phase as `AnimRules.of_blow`
## reads it, then the hero's miss at it and every defence its gear allows. A caster casts its spells by the act of the buttons and
## the AI, and its real events are shot. GODOT_ANIM_FOES — other templates, comma separated; GODOT_ANIM_STEPS — frames a phase (4).

const SEEN := ["guard", "hobgoblin", "orc", "goblin", "wolf", "brown_bear", "mage"]


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
	var ids: Array = SEEN if OS.get_environment("GODOT_ANIM_FOES").is_empty() else Array(OS.get_environment("GODOT_ANIM_FOES").split(","))
	var steps := 4 if OS.get_environment("GODOT_ANIM_STEPS").is_empty() else maxi(2, int(OS.get_environment("GODOT_ANIM_STEPS")))
	gs.combat_delay = 0.0  # seven foes' first turns at once: the stills are held by hand below
	var groups: Array = []
	for id: String in ids:
		groups.append({"monster": id})
	gs.start_combat(groups, {"sneak": true, "stealth_total": 99})  # all caught off guard: the hero's turn first, nobody strikes
	var ready: bool = await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy(), 60.0)
	await shot("00_start")
	if not step("the combat screen", ready, "busy %s" % gs.is_busy()):
		return
	s.character["hp"] = 500  # the casts below are real: the parade is looked at, not fought
	await frames(5)
	var field = find(screen(), "Field")
	var anims = find(screen(), "FightAnims")
	if not step("the animations' layer on the map", field != null and anims != null):
		return
	var hero := CombatRules.player(s)
	var kinds: Dictionary = data["anims"]["kinds"]
	var beside := FightGrid.cell(hero) + Vector2i(1, 0)
	var n := 0
	var i := 0
	for fid: Variant in CombatRules.enemies(s):
		i += 1
		var foe := CombatRules.fighter(s, str(fid))
		var tid := Sheet.template_id(data, foe)
		var was := FightGrid.cell(foe)
		var there := _at(s, beside)  # whoever stands beside the hero steps into this one's place for a while
		if not there.is_empty():
			FightGrid.put(there, was)
		FightGrid.put(foe, beside)
		anims.clear()
		node("EventBus").state_changed.emit()
		await frames(3)
		field.zoom(3.0, field.cell_point(beside))
		await frames(3)
		var g := AnimRules.gear(s, data, foe)
		step("%s: on its token %s, a shield %s" % [tid, str(g["sprite"]) if not str(g["sprite"]).is_empty() else "nothing in its hands", g["shield"]], true)
		await shot("%02d_%s_token" % [i, tid])
		var at := {"by": str(fid), "to": CombatRules.PLAYER, "by_at": FightGrid.tag(beside), "to_at": FightGrid.tag(FightGrid.cell(hero)), "n": i}
		for a: Dictionary in Sheet.template(data, foe).get("actions", []):
			if str(a.get("kind")) != "melee" or (a.get("damage", []) as Array).is_empty():
				continue
			var look := AnimRules.of_blow(s, data, foe, hero, Attack.of_action(data, foe, a))
			var e := at.merged(look, true)
			e["result"] = "hit"
			step("%s — %s: %s" % [tid, str(a.get("name_en")), str(look["anim"])], kinds.has(str(look["anim"])))
			for kind: String in [str(look["anim"]), "impact"]:
				n += await _reel(anims, e, kind, kinds, steps, "%02d_%s_%s" % [i, tid, str(a.get("name_en")).to_lower().replace(" ", "_")])
		# Its spells, cast on the one road of the buttons and the AI: the engine's own events.
		var offered := {}
		for o: Dictionary in MonsterRules.castable(data, foe):
			offered[str(o["id"])] = o
		for spell: String in ["fire_bolt", "magic_missile", "sacred_flame", "hold_person"]:
			if not offered.has(spell):
				continue
			AnimRules.take(s)
			Acts.one("cast").go(s, data, foe, CombatRules.PLAYER, {"spell": spell}.merged(offered[spell]))
			for e: Dictionary in AnimRules.take(s):
				step("%s casts %s: %s → %s, %s" % [tid, spell, str(e["by"]), str(e.get("to", "")), str(e["anim"])], str(e["by"]) == str(fid) or str(e["act"]) == "outcome")
				for kind: String in _chain(e, kinds):
					n += await _reel(anims, e, kind, kinds, steps, "%02d_%s_%s" % [i, tid, spell])
		# The hero swings and misses: each look the foe's gear allows.
		var mine := AnimRules.of_blow(s, data, hero, foe, Attack.blade(s, data, hero))
		var back := {"by": CombatRules.PLAYER, "to": str(fid), "by_at": at["to_at"], "to_at": at["by_at"], "n": i, "result": "miss"}.merged(mine, true)
		var defs := AnimRules.defences(s, data, foe, str(mine["anim"]))
		step("%s defends by %s" % [tid, ", ".join(defs)], not defs.is_empty())
		for d: String in defs:
			n += await _reel(anims, back, str(mine["anim"]), kinds, steps, "%02d_%s_vs_%s" % [i, tid, d], 1)
			n += await _reel(anims, back, d, kinds, steps, "%02d_%s_vs_%s" % [i, tid, d])
		FightGrid.put(foe, was)
		if not there.is_empty():
			FightGrid.put(there, beside)
	anims.clear()
	step("the parade: %d frames" % n, n > 0)


## The kinds an event plays, as the player of the fight chains them: the strike or the cast, then the hit or the look of the miss.
func _chain(e: Dictionary, kinds: Dictionary) -> Array[String]:
	var out: Array[String] = [str(e["anim"])]
	if str(e.get("result", "")) == "miss" and not str(e.get("miss", "")).is_empty():
		out.append(str(e["miss"]))
	elif str(e.get("result", "")) in ["hit", "crit"] and str(kinds.get(str(e["anim"]), {}).get("group", "")) in ["strike", "spell"]:
		out.append("crit" if str(e["result"]) == "crit" else "impact")
	return out


func _at(s: GameSession, at: Vector2i) -> Dictionary:
	for id: Variant in CombatRules.enemies(s):
		var f := CombatRules.fighter(s, str(id))
		if FightGrid.cell(f) == at:
			return f
	return {}


## The phases of one kind shot one by one, `upto` of them (0 — all); the number of frames.
func _reel(anims: Variant, e: Dictionary, kind: String, kinds: Dictionary, steps: int, name: String, upto: int = 0) -> int:
	var phases: Array = kinds[kind]["phases"]
	var n := 0
	for p in phases.size() if upto == 0 else mini(upto, phases.size()):
		for j in steps:
			anims.hold(e, kind, p, float(j) / float(steps - 1))
			await frames(1)
			await shot("%s_%s_%d_%s_%02d" % [name, kind, p, phases[p]["phase"], j])
			n += 1
	return n
