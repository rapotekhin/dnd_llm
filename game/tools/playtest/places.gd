extends "res://tools/playtest/playtest_base.gd"
## Places playtest (python tools/godot_playtest.py --scenario places), v0.7.20.1: a place the master makes on the open
## edge of the woodcutters' trail — its exit appears on the side panel, the hero walks in, the map shows it.


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
	var game := screen()
	s.room_id = "pushcha-trail"
	s.encounters_done.append("trail_wolves")  # no wolves for this check
	var fx: EffectEngine = gs.effects
	fx.searched_places["t-pt"] = true
	var r := fx.validate(s, data, "t-pt", {"kind": "create_place", "edge": 0, "rooms": [
		{"key": "a", "name": "Бурелом", "description": "Поваленные ели, мох по пояс.", "exits": ["b"]},
		{"key": "b", "name": "Барсучья нора", "description": "Тёмный лаз под корнями.", "dark": true}]})
	if not step("the place is accepted on the open edge", bool(r["accepted"]), str(r)):
		return
	fx.apply(s, "t-pt", [r["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var first := str(s.generated["edge_exits"]["pushcha-trail"][0])
	var exit: Button = find(game, "Exit_" + first)
	if step("the side panel shows the new exit", exit != null and not exit.disabled):
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("the hero is in the new place", s.room_id == first, s.room_id)
		await shot("new_place")
	await press(find(game, "MapButton"))
	await frames(5)
	await shot("map")
	step("the map knows the new room", s.visited.has(first))
