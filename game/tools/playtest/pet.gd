extends "res://tools/playtest/playtest_base.gd"
## Pets (python tools/godot_playtest.py --scenario pet), v0.7.43: the tavern's stray cat tamed with a piece of meat by
## the «Приручить…» window, named and fed by hand; at the North Gate the master's `beast` brings a raven, it is tamed
## and scouts the outpost road — the room on the map with its danger.

const SQUARE := "brod-square"
const HALL := "brod-tavern-hall"
const GATE := "brod-gate"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	s.settings["needs"] = false
	s.minute = 10 * 60
	c["skills"]["animal_handling"] = 30
	c["inventory"]["raw_meat"] = 3
	s.room_id = SQUARE
	for r: String in [SQUARE, GATE]:
		if not s.visited.has(r):
			s.visited.append(r)
	node("EventBus").state_changed.emit()
	await frames(3)

	await _go(gs, HALL)
	var cats := CreatureRules.here(s, HALL).filter(func(x: Dictionary) -> bool: return str(x["monster"]) == "cat")
	if not step("a stray cat in the tavern hall", cats.size() == 1):
		await shot("no_cat")
		return
	var cat: Dictionary = cats[0]
	var cid := str(cat["id"])
	await open_row("CreatureMore_" + cid)
	c["skills"]["animal_handling"] = 30  # the walk refreshed the sheet; not a test of luck
	var tame: Button = find(screen(), "Creature_tame_" + cid)
	if not step("«Приручить…» at the cat", tame != null and not tame.disabled):
		await shot("no_tame")
		return
	await press(tame)
	await frames(3)
	var win: Control = find(screen(), "PetView")
	step("the taming window with the DC and a treat", win.visible and find(win, "PetTameCheck") != null and find(win, "PetTame_raw_meat") != null)
	await shot("tame_window")
	await press(find(win, "PetTame_raw_meat"))
	await frames(4)
	step("the cat tamed", bool(cat.get("pet", false)), _last_effects(s))
	step("the window turns to the pet", find(win, "PetName") != null)
	var edit: LineEdit = find(win, "PetName")
	if edit != null:
		edit.text = "Рыжик"
		await press(find(win, "PetRename"))
		await frames(3)
	step("named Рыжик", str(cat["name"]) == "Рыжик", str(cat["name"]))
	var feed: Button = find(win, "PetFeed_raw_meat")
	if step("«Покормить» with meat", feed != null and not feed.disabled):
		var before := int(cat.get("close", 0))
		await press(feed)
		await frames(3)
		step("closer after a meal", int(cat.get("close", 0)) > before, "%d → %d" % [before, int(cat.get("close", 0))])
	await shot("pet_window")
	win.visible = false

	# The North Gate: the master brings a raven, it is tamed and scouts.
	await _go(gs, SQUARE)
	await _go(gs, GATE)
	step("the cat goes along", PropertyRules.room_of(s, cid) == GATE)
	var fx: EffectEngine = gs.effects
	var r := fx.validate(s, data, "pt-1", {"kind": "beast", "monster": "raven", "cause": "ворон с подбитым крылом сидит на воротах"})
	if not step("the master's raven accepted", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		return
	fx.apply(s, "pt-1", [r["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var raven: Dictionary = CreatureRules.here(s, GATE).back()
	var rid := str(raven["id"])
	c["skills"]["animal_handling"] = 30
	await open_row("CreatureMore_" + rid)
	await press(find(screen(), "Creature_tame_" + rid))
	await frames(3)
	await press(find(win, "PetTame_raw_meat"))
	await frames(4)
	if not step("the raven tamed", bool(raven.get("pet", false)), _last_effects(s)):
		await shot("raven_failed")
		return
	var scout: Button = find(win, "PetScout_outpost-road")
	if step("«Разведать» the outpost road", scout != null and not scout.disabled):
		await press(scout)
		await frames(4)
		step("the raven saw the danger", _last_effects(s).contains("опасность"), _last_effects(s))
		step("the road known on the map", (WorldMap.known(s, data["world"])["rooms"] as Array).has("outpost-road"))
	await shot("scouted")
	win.visible = false
	var map: Button = find(screen(), "MapButton")
	if map != null:
		await press(map)
		await frames(5)
		await shot("map")


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var ok: bool = gs.go(to)
	step("walked to %s" % to, ok)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
