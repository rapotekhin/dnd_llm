extends "res://tools/playtest/playtest_base.gd"
## A spell aimed at a portrait, as in BG3 (python tools/godot_playtest.py --scenario portrait_aim), v0.8.4.43.8, the
## author: «а как же Нацелить заклинание или умение на портрет». Out of a fight: Cure Wounds pinned to the words, the
## follower's portrait in the party column rings her token under the mouse and becomes the target by a click; Bless ticks
## the hero and her. In a fight: Cure Wounds picked — the foes' faces in the queue grey, the follower's face rings her
## token and says the heal, a click on it heals her; Sacred Flame picked — the wolf's face in the queue says its save,
## a click casts at it.

const FOLLOWER := "npc_mercenary"


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	s.room_id = "brod-square"
	Being.follow(s, FOLLOWER)
	node("EventBus").state_changed.emit()
	await frames(4)
	var field: Control = find(screen(), "Field")

	# Out of a fight: a pinned heal aimed by the follower's portrait.
	gs.attach("spell", "cure_wounds", 1)
	await frames(4)
	var her: Control = find(screen(), "Portrait_" + FOLLOWER)
	if not step("the follower's portrait in the party column", her != null):
		return
	step("its card says a click aims the heal", str(her.get("tip_body")).contains("сделать целью"), str(her.get("tip_body")))
	her.mouse_entered.emit()
	await frames(2)
	step("the mouse over it rings her token", field.get("pointed") == field.call("cell_of", "npc:" + FOLLOWER) and (field.get("pointed") as Vector2i).x >= 0,
		"%s / %s" % [field.get("pointed"), field.call("cell_of", "npc:" + FOLLOWER)])
	await press(her as BaseButton)
	await frames(4)
	step("a click makes her the heal's target", str(gs.attached.get("target", "")) == FOLLOWER, str(gs.attached))
	var pick: OptionButton = find(screen(), "AttachTarget")
	step("the chip at the input says her too", pick != null and pick.get_item_text(pick.selected) == str(data["world"]["npcs"][FOLLOWER]["name"]))
	her = find(screen(), "Portrait_" + FOLLOWER)
	her.mouse_entered.emit()
	await frames(2)
	await shot("peace_heal_her")
	her.mouse_exited.emit()
	gs.attach("spell", "bless", 1)
	await frames(3)
	await press(find(screen(), "Portrait_hero") as BaseButton)
	await frames(3)
	await press(find(screen(), "Portrait_" + FOLLOWER) as BaseButton)
	await frames(3)
	step("Bless ticks the hero and her by their portraits", (gs.attached.get("targets", []) as Array) == [gs.SELF_TARGET, FOLLOWER], str(gs.attached))
	step("the chip's boxes agree", (find(screen(), "AttachPick_" + FOLLOWER) as CheckBox).button_pressed and (find(screen(), "AttachPick_self") as CheckBox).button_pressed)
	await shot("peace_bless_two")
	gs.detach()
	await frames(2)
	await press(find(screen(), "Portrait_" + FOLLOWER) as BaseButton)  # nothing pinned: its own act — the hero walks up and talks
	await wait_until(func() -> bool: return not gs.is_busy() and not field.call("walking"), 30.0)
	gs.detach()
	await frames(2)

	# In a fight: the queue's faces.
	gs.start_combat([{"monster": "wolf", "name": "Волк", "count": 2}], {})
	if not step("a fight with the wolves, the follower beside", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 90.0)):
		return
	await frames(4)
	var ally := ""
	for id: String in CombatRules.allies(s, false):
		if str(CombatRules.fighter(s, id).get("npc_id", "")) == FOLLOWER:
			ally = id
	if not step("the follower fights on the hero's side", not ally.is_empty(), str(CombatRules.allies(s, false))):
		return
	var a := CombatRules.fighter(s, ally)
	a["hp"] = maxi(1, int(a["max_hp"]) - 6)
	var hurt := int(a["hp"])
	var wolf: String = CombatRules.enemies(s)[0]
	var cure: Button = find(screen(), "Cast_cure_wounds")
	if not step("Cure Wounds on the bar", cure != null and not cure.disabled):
		return
	await press(cure)
	await frames(4)
	var wolf_face: Control = find(screen(), "Turn_" + wolf)
	step("the wolf's face greys for a heal and says why", wolf_face != null and wolf_face.modulate.a < 1.0 and wolf_face.tooltip_text.contains("Не та цель"), wolf_face.tooltip_text if wolf_face != null else "")
	var face: Control = find(screen(), "Turn_" + ally)
	if not step("the follower's face in the queue", face != null and face.modulate.a == 1.0):
		return
	face.mouse_entered.emit()
	await frames(2)
	var hint: Label = find(screen(), "Hint")
	step("the mouse over it rings her token", field.get("pointed") == FightGrid.shown(a), "%s / %s" % [field.get("pointed"), FightGrid.shown(a)])
	step("the hint says what the heal gives her", hint != null and hint.text.contains(str(a["name"])) and hint.text.contains("Лечение"), hint.text if hint != null else "")
	await shot("fight_heal_hover")
	await _click(face)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	step("a click on her face heals her", int(CombatRules.fighter(s, ally)["hp"]) > hurt, "%d → %d" % [hurt, int(CombatRules.fighter(s, ally)["hp"])])
	await shot("fight_healed")

	# Sacred Flame at the wolf's face: the next turn of the hero.
	if CombatRules.is_player_turn(s):  # the heal took the action: the turn ends
		await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return not CombatRules.active(s) or (CombatRules.is_player_turn(s) and not gs.is_busy()), 90.0)
	s.character["hp"] = int(s.character["max_hp"])  # the wolves' bites must not end the scenario
	if not step("the hero's turn again", CombatRules.active(s) and CombatRules.is_player_turn(s)):
		return
	await frames(4)
	wolf = ""
	for id: String in CombatRules.enemies(s):
		if str(CombatRules.fighter(s, id).get("status", "")) == "active":
			wolf = id
	var flame: Button = find(screen(), "Cast_sacred_flame")
	if not step("Sacred Flame on the bar", flame != null and not flame.disabled and not wolf.is_empty()):
		return
	await press(flame)
	await frames(4)
	wolf_face = find(screen(), "Turn_" + wolf)
	wolf_face.mouse_entered.emit()
	await frames(2)
	var f := CombatRules.fighter(s, wolf)
	step("the wolf's face rings its token", field.get("pointed") == FightGrid.shown(f))
	await shot("fight_flame_hover")
	var log_n: int = (s.combat.get("log", []) as Array).size()
	var wolf_hp := int(f["hp"])
	await _click(wolf_face)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	var said := " | ".join((s.combat.get("log", []) as Array).slice(log_n))
	step("a click on the wolf's face casts Sacred Flame at it", said.contains("Священное пламя") or int(CombatRules.fighter(s, wolf).get("hp", wolf_hp)) < wolf_hp, said.left(300))
	await shot("fight_flame_cast")


## A left click on a control as the player's.
func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)
	await frames(3)
