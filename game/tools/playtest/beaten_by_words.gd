extends "res://tools/playtest/playtest_base.gd"
## Words instead of blows (python tools/godot_playtest.py --scenario beaten_by_words), v0.7.50.1: Bless pinned to the
## words lands on the hero and an NPC by the boxes; goblins talked round stay in the room, one comes along, the next
## of their faction here waits for the hero's words.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var sp: Dictionary = s.character["spells"]
	sp["always"] = ["bless"]
	s.character["slots_max"] = [4, 3, 0, 0, 0]
	s.character["slots_used"] = [0, 0, 0, 0, 0]
	s.character["cha"] = 40
	CharacterRules.refresh(s.character, node("Catalog").data, s.items)
	var npcs := s.npcs_here(gs.world().world, s.room_id)
	if not step("people in the room", not npcs.is_empty()):
		return

	gs.attach("spell", "bless", 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	var me: BaseButton = find(screen(), "AttachPick_self")
	var other: BaseButton = find(screen(), "AttachPick_" + str(npcs[0]))
	if not step("boxes for the hero and the NPC", me != null and other != null):
		return
	me.button_pressed = true
	await frames(2)
	find(screen(), "AttachPick_" + str(npcs[0])).button_pressed = true
	await frames(2)
	step("both ticked", (gs.attached.get("targets", []) as Array).size() == 2, str(gs.attached))
	await shot("boxes")
	var game := screen()
	game.get("input").text = "Благословляю нас"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the NPC carries the blessing", s.npc_buffs.has(str(npcs[0])), str(s.npc_buffs))
	step("the hero too", ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless"))

	s.room_id = "pushcha-hollow"
	var goblins := [{"monster": "goblin", "name": "Гоблин", "count": 2}]
	s.lurking[s.room_id] = {"foes": goblins, "from": "pushcha-trail"}
	node("EventBus").state_changed.emit()
	await frames(3)
	var talk: Button = find(screen(), "Encounter_persuasion")
	if not step("talk to the lurking goblins", talk != null):
		return
	await press(talk)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	if not EncounterRules.lurking(s, s.room_id).is_empty() or s.mode == GameSession.MODE_COMBAT:
		return
	var kept: Array = CreatureRules.here(s, s.room_id).filter(func(c: Dictionary) -> bool: return bool(c.get("kept", false)))
	step("both goblins stay", kept.size() == 2, str(CreatureRules.here(s, s.room_id)))
	var id := str(kept[0]["id"])
	await open_row("CreatureMore_" + id)
	var join: Button = find(screen(), "Creature_join_" + id)
	if step("«Взять с собой»", join != null and not join.disabled):
		await press(join)
		await frames(3)
		step("it comes along", bool(CreatureRules.find(s, s.room_id, id).get("ally", false)))
	await shot("kept")
	s.day += 10
	step("still here days later", CreatureRules.tick(s, node("Catalog").data).is_empty() and CreatureRules.here(s, s.room_id).size() == 2)
	FactionRules.won_by_word(s, node("Catalog").data, "mine_kobolds", s.room_id, "проверка")
	var m := EncounterRules.meet(s, node("Catalog").data, s.room_id, "pushcha-trail",
		{"id": "t_next", "faction": "mine_kobolds", "ambush": true, "enemies": [{"monster": "goblin", "name": "Гоблин-страж"}]})
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the next of the faction waits for words", bool(m["lurk"]), str(m))
	await shot("next")
