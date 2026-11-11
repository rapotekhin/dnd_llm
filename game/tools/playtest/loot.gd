extends "res://tools/playtest/playtest_base.gd"
## Things after a fight (python tools/godot_playtest.py --scenario loot), v0.8.4.4: the results give only XP, a bandit lies
## where it fell, a click walks up and opens its menu, «Обыскать» opens its things like a chest; a wizard's list of spells
## comes first in the long rest's window and changes with the rest.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_wizard_yalika")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	await _rest(s, data)
	gs.start_combat([{"monster": "bandit", "name": "Разбойник"}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var id: String = CombatRules.enemies(s)[0]
	CombatRules.fighter(s, id)["status"] = "dead"
	CombatRules.fighter(s, id)["hp"] = 0
	var lines := CombatRules.after_player_action(s, data)
	step("won", str(s.combat.get("outcome", "")) == "victory", str(lines))
	gs.call("_combat_outcome") if gs.has_method("_combat_outcome") else null
	var finish: Array = [null]
	await wait_until(func() -> bool:
		finish[0] = find(screen(), "FinishCombat")
		return finish[0] != null and finish[0].is_visible_in_tree(), 30.0)
	var gold: int = s.character["gold_cp"]
	var bag: int = int(s.character["inventory"].size())
	if not step("the results", finish[0] != null):
		return
	await shot("results")
	await press(finish[0])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	step("nothing given by the fight", int(s.character["gold_cp"]) == gold and int(s.character["inventory"].size()) == bag)
	var body: Dictionary = {}
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		if str(c["state"]) == CreatureRules.DEAD:
			body = c
	if not step("the body lies here", not body.is_empty(), str(CreatureRules.here(s, s.room_id))):
		return
	var cid := str(body["id"])
	screen().call("_context", "cr:" + cid)  # v0.8.4.43.4: the right button — its one menu
	await wait_until(func() -> bool: return acts_menu() != null, 10.0)
	var act: Button = find(find(screen(), "ThingActs"), "Creature_search_" + cid)
	if not step("its menu says «Обыскать»", act != null):
		return
	step("and «Спрятать»", find(screen(), "Creature_hide_" + cid) != null)
	step("no blow at the dead", find(screen(), "Creature_attack_" + cid) == null and find(screen(), "Creature_bind_" + cid) == null)
	await shot("body_menu")
	await press(act)
	var take: Array = [null]
	await wait_until(func() -> bool:
		take[0] = find(screen(), "TakeOut_scimitar")
		return take[0] != null and take[0].is_visible_in_tree(), 5.0)
	if step("its things in a chest's window", take[0] != null):
		await shot("body_things")
		await press(take[0])
		await frames(3)
		step("the blade taken", int(s.character["inventory"].get("scimitar", 0)) >= 1, str(s.character["inventory"]))


## The list first in the rest's window: one spell changed, gone through with the bed.
func _rest(s: GameSession, data: Dictionary) -> void:
	var gs := node("GameState")
	s.room_id = "brod-tavern-upstairs"
	s.character["gold_cp"] = 100000
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "RestButton"))
	await frames(3)
	var count: Label = find(screen(), "PrepCount")
	if not step("the rest's window lists the spells", count != null and count.is_visible_in_tree()):
		return
	await shot("rest_list")
	var was: Array = (s.character["spells"]["prepared"] as Array).duplicate()
	var other := ""
	for id: Variant in SpellRules.prepare_pool(s.character, data)["pool"]:
		if not was.has(id):
			other = str(id)
	var off: CheckBox = find(screen(), "Prep_" + str(was[0]))
	if step("a spell to swap", off != null and not other.is_empty()):
		off.button_pressed = false
		await frames(3)
		(find(screen(), "Prep_" + other) as CheckBox).button_pressed = true
		await frames(3)
	var bed: Button = find(screen(), "RestInn")
	if not step("the bed", bed != null and not bed.disabled):
		return
	await press(bed)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the list changed with the rest", (s.character["spells"]["prepared"] as Array).has(other) and not (s.character["spells"]["prepared"] as Array).has(was[0]), str(s.character["spells"]["prepared"]))
	step("once", not SpellRules.can_prepare(s.character, data).is_empty())
