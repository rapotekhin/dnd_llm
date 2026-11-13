extends "res://tools/playtest/playtest_base.gd"
## Portraits instead of letters (python tools/godot_playtest.py --scenario portraits), v0.8.4.43.5.2, the author: «заменить
## буквы на аватарки-портреты NPC и монстров, сгенеренные Анимой». Until tools/anima lays the files, the scenario lays plain
## stand-in faces in the cache (squares of colour: a head, eyes, hair) on the very paths PortraitRules asks for, so the
## screenshots show where a face goes: the creation screen's five picks, the map's people and the hero, the names under the
## key that do not cover one another, the fight's bodies and its queue, the creature's card. A face drawn already is shown.

const SLOT := "res://ui/components/icon_slot.gd"


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await frames(3)
	var blanks: Control = find(screen(), "PortraitPicks")  # v0.8.4.43.49: faces only by the sex and the age picked
	step("blanks until the age is picked", blanks != null and blanks.get_child_count() == 5 and (find(blanks, "Portrait_1") as BaseButton).disabled)
	var age_pick: OptionButton = find(screen(), "Body_age")
	if age_pick != null and age_pick.selected == 0:
		age_pick.select(1)
		age_pick.item_selected.emit(1)
		await frames(3)
	var picks: Control = find(screen(), "PortraitPicks")
	if not step("five faces to pick at creation", picks != null and picks.get_child_count() == 5, str(picks.get_child_count() if picks != null else -1)):
		return
	await shot("creation_numbers")
	var ch: Dictionary = screen().get("choices")
	var gender := str(ch.get("gender", "male"))
	var age := str(BodyRules.make(data, gender, BodyRules.fit(data, ch.get("body", {}) if ch.get("body") is Dictionary else {}, gender), "hero:" + str(ch["name"]), true)["age"])
	_lay(PortraitRules.variants(data, str(ch["race"]), gender, age))
	await press(find(screen(), "Portrait_3"))
	await frames(3)
	step("the third face picked", int(screen().get("choices").get("portrait", 0)) == 3)
	step("the faces drawn in the picks", str(find(screen(), "Portrait_3").get("picture")).ends_with("__3.webp"))
	await shot("creation_faces")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	step("the hero keeps its face", int(s.character.get("portrait", 0)) == 3 and PortraitRules.of(s, data, Sheet.HERO).ends_with("__3.webp"))

	s.room_id = "brod-tavern-hall"
	if not s.visited.has(s.room_id):
		s.visited.append(s.room_id)
	PortraitRules.forget()  # as it was: letters, for the author's «before»
	node("EventBus").state_changed.emit()
	await frames(6)
	await shot("map_letters")
	_lay(PortraitRules.variants(data, str(s.character["race"]), str(s.character["gender"]), str(s.character["body"]["age"])))
	for id: String in s.npcs_here(data["world"], s.room_id):
		var n: Dictionary = WorldView.new(data["world"]).npc(id)
		_lay(PortraitRules.variants(data, CharacterRules.race_id(data, n), str(n.get("gender", "")), str(BodyRules.npc(data, id, n)["age"])))
	node("EventBus").state_changed.emit()
	await frames(6)
	var field: Control = find(screen(), "Field")
	var people: Array = (field.get("things") as Array).filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "npc")
	step("the people of the hall on the map", not people.is_empty(), str(people.size()))
	step("every person has its face", people.all(func(t: Dictionary) -> bool: return not str(t["portrait"]).is_empty()), str(people.map(func(t: Dictionary) -> String: return t["portrait"])))
	step("the hero's token has its face", str(field.get("hero_face")).ends_with("__3.webp"))
	await shot("map_faces")
	field.set("labels", true)
	field.queue_redraw()
	await frames(3)
	var laid: Array = field.get("laid_names")
	var crossed := false
	for i in laid.size():
		for k in range(i + 1, laid.size()):
			if (laid[i] as Rect2).intersects(laid[k]):
				crossed = true
		for box: Rect2 in field.get("_exit_boxes"):
			if (laid[i] as Rect2).intersects(box):
				crossed = true
	step("names under the key cover neither one another nor a way out's label", not laid.is_empty() and not crossed, "%d names" % laid.size())
	await shot("names_key")
	field.set("labels", false)

	gs.start_combat([{"monster": "wolf", "name": "Волк", "count": 2}], {})
	if not step("a fight with the wolves", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 90.0)):
		return
	await frames(4)
	var kept := PortraitRules._exists.duplicate()
	PortraitRules.forget()
	node("EventBus").state_changed.emit()
	await frames(4)
	await shot("fight_letters")
	PortraitRules._exists.merge(kept, true)
	var wolves: Array[String] = []
	for n in range(1, 6):
		wolves.append(PortraitRules.root(data) + "monsters/wolf__%d.webp" % n)
	_lay(wolves)
	node("EventBus").state_changed.emit()
	await frames(4)
	var bodies: Array = field.get("fighters")
	step("the wolves have their faces in the fight", bodies.filter(func(f: Dictionary) -> bool: return str(f["portrait"]).contains("wolf__")).size() == 2,
		str(bodies.map(func(f: Dictionary) -> String: return f["portrait"])))
	var foe: String = CombatRules.enemies(s)[0]
	var turn: Node = find(screen(), "Turn_" + foe)
	step("the queue shows the faces", turn != null and find(turn, "Face") != null)
	await shot("fight_faces")
	node("EventBus").card_requested.emit(foe)
	await frames(4)
	step("the creature's card shows its face", find(screen(), "CardPortrait") != null)
	await shot("card_face")


## Stand-in faces on `paths` not drawn yet: a picture in the interface's cache, the file «drawn» for PortraitRules; a
## face tools/anima has laid is shown as it is.
func _lay(paths: Array) -> void:
	var cache: Dictionary = load(SLOT).get("_textures")
	for p: String in paths:
		if ResourceLoader.exists(p):
			continue
		cache[p] = ImageTexture.create_from_image(_face(p))
		PortraitRules._exists[p] = true


## A plain face of squares, its colours by its path: the background, the hair, the head, the eyes and the mouth.
func _face(path: String) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(path)
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(rng.randf(), 0.35, 0.45))
	var skin := Color.from_hsv(0.07, rng.randf_range(0.2, 0.55), rng.randf_range(0.55, 0.95))
	img.fill_rect(Rect2i(30, 22, 68, 30), Color.from_hsv(rng.randf(), 0.5, rng.randf_range(0.15, 0.7)))
	img.fill_rect(Rect2i(36, 34, 56, 64), skin)
	img.fill_rect(Rect2i(26, 96, 76, 32), Color.from_hsv(rng.randf(), 0.5, 0.5))
	img.fill_rect(Rect2i(48, 56, 9, 7), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(71, 56, 9, 7), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(54, 80, 20, 5), skin.darkened(0.4))
	return img
