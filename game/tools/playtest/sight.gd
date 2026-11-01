extends "res://tools/playtest/playtest_base.gd"
## Sight and stealth on the map (python tools/godot_playtest.py --scenario sight), v0.8.3: the fog on the street, wolves
## that stand further along the trail, a sneaking walk by rounds with cones, an attack from hiding; a dark gallery by the
## hero's torch, a trap sprung underfoot on a click's walk.

var field: Control


func run() -> void:
	var gs := node("GameState")
	gs.instant_walk = false
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
	still_sky(s)
	s.room_id = "pushcha-edge"
	s.visited.append("pushcha-edge")
	s.character["skills"]["stealth"] = 40  # nobody notices this one
	s.character["traits"] = (s.character.get("traits", []) as Array).filter(func(t: Variant) -> bool: return str(t) != "darkvision")
	s.character["inventory"].erase("torch")
	node("EventBus").state_changed.emit()
	await frames(3)
	field = find(screen(), "Field")
	step("the fog: not all of the map is seen", field.fog and not field.now.is_empty() and field.now.size() < int(field.map["w"]) * int(field.map["h"]), "%d squares" % field.now.size())
	await shot("day")

	s.sneaking = true
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "Exit_pushcha-trail"))
	await wait_until(func() -> bool: return s.room_id == "pushcha-trail" and not gs.is_busy(), 60.0)
	await frames(5)
	step("no fight from the way in", s.mode != GameSession.MODE_COMBAT and not EncounterRules.lurking(s, s.room_id).is_empty())

	var foes := MapSpots.foes(s, data, field.map)
	var lair := Vector2i(int(foes[0]["x"]), int(foes[0]["y"]))
	var longest := 0
	for i: int in 30:
		if EncounterRules.sighted(s, s.room_id) and field.things.any(func(t: Dictionary) -> bool: return str(t["kind"]) == "foe"):
			break
		var from: Vector2i = field.hero_cell()
		var way := WalkRules.near(field.map, data["layouts"], from, lair, 2, s.room_id)
		if way.is_empty():
			break
		await _click(way[-1])
		await wait_until(func() -> bool: return not field.walking() and not gs.is_busy(), 20.0)
		await frames(2)
		longest = maxi(longest, WalkRules.distance(from, field.hero_cell()))
	step("the wolves in view", field.things.any(func(t: Dictionary) -> bool: return str(t["kind"]) == "foe"), "at %s" % field.hero_cell())
	await frames(3)
	step("the cones under watch", not field.cones.is_empty(), "%d squares" % field.cones.size())
	await shot("cones")
	var round_was := int(s.layouts.get("round", 0))
	var far := WalkRules.near(field.map, data["layouts"], field.hero_cell(), lair, 1, s.room_id)
	var was: Vector2i = field.hero_cell()
	if far.size() > WatchRules.round_steps(s):
		await _click(far[-1])
		await wait_until(func() -> bool: return not field.walking(), 20.0)
		await frames(2)
		step("a click goes one round's squares", WalkRules.distance(was, field.hero_cell()) <= WatchRules.round_steps(s), "%s → %s" % [was, field.hero_cell()])
	else:
		step("info: close already", true, str(far.size()))
	var wait: Button = find(screen(), "SneakWait")
	if step("«Переждать» while sneaking", wait != null) and not wait.disabled:
		var turned := int(s.layouts.get("round", 0))
		await press(wait)
		await frames(3)
		step("the watchers turn", int(s.layouts.get("round", 0)) > turned and turned >= round_was)
	var attack: Button = find(screen(), "Encounter_attack")
	if step("the attack from hiding", attack != null and not attack.disabled):
		await press(attack)
		await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)
		await frames(3)
		step("the wolves caught off guard", CombatRules.active(s) and CombatRules.enemies(s).all(func(id: String) -> bool: return bool(CombatRules.fighter(s, id).get("surprised", false))))
		s.combat = {}
		s.mode = GameSession.MODE_EXPLORATION
		s.encounters_done.append("trail_wolves")
		node("EventBus").navigate.emit("game", {})
		await wait_until(func() -> bool: return screen_is("GameScreen"), 10.0)
	await frames(3)

	s.sneaking = false
	s.encounters_done.append("gallery_kobolds")
	s.room_id = "mine-gallery"
	s.visited.append("mine-gallery")
	node("EventBus").state_changed.emit()
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	await frames(3)
	field = find(screen(), "Field")
	var blind: int = field.now.size()
	step("in the dark the hero sees only beside it", blind <= 9, "%d squares" % blind)
	await shot("dark")
	s.character["inventory"]["torch"] = 1
	node("EventBus").state_changed.emit()
	await frames(3)
	step("a torch gives eight squares", field.now.size() > blind, "%d squares" % field.now.size())
	await shot("torch")

	var trap: Dictionary = {}
	for sec: Dictionary in ExplorationRules.secrets(data["world"], s.room_id):
		if sec.get("trap") is Dictionary:
			trap = sec
	s.character["passive_perception"] = 1
	var at := MapSpots.secret_cell(s, data, field.map, s.room_id, trap)
	var hp := int(s.character["hp"])
	await _click(at)
	await wait_until(func() -> bool: return not field.walking() and not gs.is_busy(), 30.0)
	await frames(3)
	step("the trap sprung underfoot", s.traps.has(ExplorationRules.secret_key(s.room_id, trap)), "at %s, the square %s" % [field.hero_cell(), at])
	step("it hurt", int(s.character["hp"]) <= hp, "%d → %d" % [hp, int(s.character["hp"])])
	await shot("trap")


func _click(cell: Vector2i) -> void:
	var at: Vector2 = field.corner() + (Vector2(cell) + Vector2(0.5, 0.5)) * field.tile()
	_button(at, true)
	_button(at, false)
	await frames(2)


func _button(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	field._gui_input(e)
