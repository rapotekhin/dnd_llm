extends "res://tools/playtest/playtest_base.gd"
## Disguise Self as one of a faction (python tools/godot_playtest.py --scenario disguise), v0.7.63: the look named by the
## master, the status on the panel, the cult's road open, Bruno of Brod who takes the hero for a foe will not talk, and
## all of it back when the spell runs out.


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
	var fx: EffectEngine = gs.effects
	c["spell_dc"] = 30
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-tavern-hall"
	var friendly := s.attitude("npc_innkeeper")

	var plain := fx.validate(s, data, "g-0", {"kind": "guise", "look": "старый нищий"})
	step("no look without the spell", not bool(plain["accepted"]), str(plain.get("reason", "")))
	SpellEffects.apply_self(s, data, "disguise_self", 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the master is asked to name the look", str(TurnSnapshot.build(s, data, 2000)["character"]["guise"]).contains("облик не назван"))

	var look := fx.validate(s, data, "g-1", {"kind": "guise", "look": "сектант в закопчённом плаще", "faction": "ash_cult"})
	if not step("the look named", bool(look["accepted"]), str(look.get("summary", look.get("reason", "")))):
		return
	fx.apply(s, "g-1", [look["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	var snap: Dictionary = TurnSnapshot.build(s, data, 2000)
	step("the master reads the look, its people and their foes", str(snap["character"]["guise"]).contains("ash_cult") and str(snap["character"]["guise"]).contains("для них враг"), str(snap["character"]["guise"]))
	step("Bruno of Brod takes the hero for a foe", s.attitude("npc_innkeeper") < friendly and SocialRules.refuses(s, data, "npc_innkeeper"), str(s.attitude("npc_innkeeper")))
	await shot("foe_in_brod")
	var road: Dictionary = data["world"]["rooms"]["outpost-road"]["encounter"]
	step("the cult's road lets the hero be", FactionRules.peaceful(s, data, road))

	for e: Dictionary in ConditionRules.effects(c):
		if e.has("guise"):
			e["ends"] = {"at": 0}
	TimeRules.advance(s, data, 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the look ran out, Bruno talks again", s.attitude("npc_innkeeper") == friendly and not SocialRules.refuses(s, data, "npc_innkeeper"))
	step("the cult's road is the road again", not FactionRules.peaceful(s, data, road))
	await shot("after")
