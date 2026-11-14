extends "res://tools/playtest/playtest_base.gd"
## The icons of the master's inventions (python tools/godot_playtest.py --scenario made_icons), v0.8.4.44.1: a thing the
## master made and a spell it made are drawn by `icon.request` (the stub server's chroma frame with a dark square; --real:
## FLUX, ~2 cents), cut by IconCut into the profile's folder, and the thing's cell in the character window shows that
## picture; with the setting off nothing is asked.

const THING := {"name": "Пепельный кинжал", "item_type": "weapon", "base": "dagger", "rarity": "uncommon", "value_cp": 5000,
	"properties": [], "description": "Кинжал из чёрного обсидиана, рукоять обмотана красной кожей, по клинку бегут тлеющие трещины.",
	"generated": true}


func run() -> void:
	var gs := node("GameState")
	var sm := node("SaveManager")
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
	var root := MadeIcons.root(sm.profile_dir)
	for kind: String in ["items", "spells"]:
		for f: String in (DirAccess.get_files_at(root + kind) if DirAccess.dir_exists_absolute(root + kind) else PackedStringArray()):
			DirAccess.remove_absolute(root + kind + "/" + f)
	IconRules.forget()
	var id := ItemRules.generated_id(THING)
	s.items[id] = THING.duplicate(true)
	ItemRules.add(s.character, id)
	WorldGen.generated(s)["made"] = {"gen_sp_mirror": {"what": "spell", "name": "Зеркальный шаг",
		"text": "Маг отражается в воздухе и шагает из своего отражения."}}
	var asked: Array = []
	var wants := MadeIcons.wanted(s, data)
	step("the thing and the spell want icons", wants.size() == 2, str(wants.map(func(w: Dictionary) -> String: return w["ref"])))
	var thing_file := MadeIcons.path_of(root, "items/" + id)
	var spell_file := MadeIcons.path_of(root, "spells/gen_sp_mirror")
	gs.draw_made_icons()
	if not step("both are drawn into the profile", await wait_until(func() -> bool:
			return FileAccess.file_exists(thing_file) and FileAccess.file_exists(spell_file) and not gs._icons_busy, 120.0), root):
		return
	var icon := Image.load_from_file(thing_file)
	var side := int(MadeIcons.cfg(data)["cut"]["side"])
	step("the icon is cut: its side, its ground clear", icon.get_width() == side and icon.get_pixel(1, 1).a < 0.05,
		"%d px, corner alpha %.2f" % [icon.get_width(), icon.get_pixel(1, 1).a])
	var ic := IconRules.of(data, s.items, "items/" + id)
	step("the thing's icon is its own picture", str(ic["path"]) == thing_file and bool(ic["real"]), str(ic["path"]))
	step("nothing more is wanted", MadeIcons.wanted(s, data).is_empty())
	node("EventBus").state_changed.emit()
	var game := screen()
	await press(find(game, "SheetButton"))
	await frames(6)
	await shot("made_icons_sheet")
	await press(find(game, "SheetButton"))
	await frames(3)
	sm.made_icons_on = false
	var other := THING.duplicate(true)
	other["name"] = "Кольцо болотника"
	other["description"] = "Медное кольцо с камнем в виде зелёного лягушачьего глаза."
	var ring := ItemRules.generated_id(other)
	s.items[ring] = other
	step("a green subject goes on magenta", str(MadeIcons.wanted(s, data)[0]["ground"]) == "magenta")
	gs.draw_made_icons()
	await frames(30)
	step("the setting off asks nothing", not FileAccess.file_exists(MadeIcons.path_of(root, "items/" + ring)) and not gs._icons_busy)
	sm.made_icons_on = true
	asked.append(ring)
	node("EventBus").navigate.emit("settings", {"back": "game", "tab": 1})  # SettingsScreen.TAB_MASTER
	if not step("the settings opened", await wait_until(func() -> bool: return find(current_scene, "MadeIconsOn") != null, 10.0)):
		return
	await frames(4)
	var box: CheckBox = find(current_scene, "MadeIconsOn")
	step("the setting is on the master's tab, on", box != null and box.is_visible_in_tree() and box.button_pressed)
	var up := box.get_parent()
	while up != null and not (up is ScrollContainer):
		up = up.get_parent()
	if up != null:
		(up as ScrollContainer).ensure_control_visible(box)
	await frames(4)
	await shot("made_icons_settings")
	box.button_pressed = false
	await frames(2)
	step("unticked — off and kept", not sm.made_icons_on)
	box.button_pressed = true
	await frames(2)
	step("ticked again — on", sm.made_icons_on)
