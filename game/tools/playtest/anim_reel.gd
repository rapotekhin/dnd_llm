extends "res://tools/playtest/playtest_base.gd"
## The frames of one animation of a fight (python tools/godot_playtest.py --scenario anim_reel), v0.8.4.23: the hero casts at a
## wolf and the kind is shot phase by phase, a frame at each step, to be seen as a reel. GODOT_ANIM_KIND (burst), GODOT_ANIM_SPELL
## (fireball: its area and colour), GODOT_ANIM_DTYPE (when no spell), GODOT_ANIM_STEPS (frames a phase, 6).


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
	gs.start_combat([{"monster": "wolf", "count": 3, "name": "Волк"}], {})
	if not step("the combat screen", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy(), 60.0)):
		return
	await frames(5)
	var data: Dictionary = node("Catalog").data
	var s: GameSession = gs.session
	var kind := OS.get_environment("GODOT_ANIM_KIND")
	var spell := OS.get_environment("GODOT_ANIM_SPELL")
	if kind.is_empty():
		kind = "burst" if spell.is_empty() else AnimRules.of_spell(data, spell)
	if kind == "burst" and spell.is_empty():
		spell = "fireball"
	var steps := maxi(2, int(OS.get_environment("GODOT_ANIM_STEPS")) if not OS.get_environment("GODOT_ANIM_STEPS").is_empty() else 6)
	var field = find(screen(), "Field")
	var anims = find(screen(), "FightAnims")
	if not step("the animations' layer on the map", field != null and anims != null):
		return
	var hero := CombatRules.player(s)
	var foe: Dictionary = {}
	for id in CombatRules.enemies(s):  # the farthest: a sphere at a wolf beside the hero would cover the hero too
		var f := CombatRules.fighter(s, str(id))
		if foe.is_empty() or FightGrid.dist(f, hero) > FightGrid.dist(foe, hero):
			foe = f
	var aim := FightGrid.cell(foe)
	var e := {"by": CombatRules.PLAYER, "to": str(foe["id"]), "by_at": FightGrid.tag(FightGrid.cell(hero)), "to_at": FightGrid.tag(aim),
		"dtype": OS.get_environment("GODOT_ANIM_DTYPE") if spell.is_empty() else AnimRules.spell_colour(data, spell), "n": 1}
	if not spell.is_empty() and data["spells"][spell].has("area"):
		var sp: Dictionary = data["spells"][spell]
		e["cells"] = FightGrid.pack_cells(FightGrid.area(s, data, sp["area"], FightGrid.cell(hero), aim, int(sp.get("range_ft", 0)) == 0))
	field.zoom(2.5,field.cell_point(Vector2i((Vector2(FightGrid.cell(hero)) + Vector2(aim)) / 2.0)))
	await frames(3)
	var phases: Array = data["anims"]["kinds"][kind]["phases"]
	var n := 0
	for i in phases.size():
		for j in steps:
			anims.hold(e, kind, i, float(j) / float(steps - 1))
			await frames(1)
			n += 1
			await shot("%s_%d_%s_%02d" % [kind, i, phases[i]["phase"], j])
	anims.clear()
	step("the reel of %s: %d frames over %d phases" % [kind, n, phases.size()], n == phases.size() * steps)
