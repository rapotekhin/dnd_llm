extends "res://tools/playtest/playtest_base.gd"
## Factions (python tools/godot_playtest.py --scenario factions), v0.7.50: sneaking onto the woodcutters' trail, the
## wolf calmed by «Успокоить»; the standing grows and the spider of the hollow keeps the peace; the journal's tab; the
## Rats' friend walks into the den free.

const TRAIL := "pushcha-trail"
const HOLLOW := "pushcha-hollow"


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
	s.settings["needs"] = false
	s.minute = 10 * 60
	s.settings["difficulty"] = "trivial"  # the checks are not a test of luck
	s.room_id = "pushcha-edge"
	s.sneaking = true
	node("EventBus").state_changed.emit()
	await frames(3)

	await _go(gs, TRAIL)
	var calm: Button = find(screen(), "Encounter_calm")
	if not step("«Успокоить» at the unaware wolf", calm != null and not calm.disabled):
		await shot("no_calm")
		return
	await shot("calm")
	s.rng.randi()  # this seed's next d20 is a natural 1
	await press(calm)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the wolf stands by as a truce", CreatureRules.here(s, TRAIL).any(func(x: Dictionary) -> bool: return str(x["state"]) == "truce"))
	step("the beasts think better of the hero", FactionRules.points(s, data, "wild_beasts") == int(FactionRules.cfg(data)["sources"]["calm"]))

	FactionRules.add(s, data, "wild_beasts", 20, "playtest")
	s.sneaking = false
	await _go(gs, HOLLOW)
	step("no fight with a friend of the beasts", not s.in_combat() if s.has_method("in_combat") else s.combat.is_empty())
	step("the spider keeps the peace", s.encounters_peace.has("hollow_spiders"))
	await shot("peace")

	var game := screen()
	await press(find(game, "JournalButton"))
	var tab: Button = find(game, "JournalTab_factions")
	if step("the journal's tab of factions", tab != null):
		await press(tab)
		await frames(3)
		await shot("journal")

	FactionRules.add(s, data, "night_rats", 30, "playtest")
	step("the Rats' friend walks in free", OrgRules.entry_why(s, data, "night_rats") == "ORG_ENTRY_OPEN")


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var ok: bool = gs.go(to)
	step("walked to %s" % to, ok)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
