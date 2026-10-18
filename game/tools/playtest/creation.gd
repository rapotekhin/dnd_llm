extends "res://tools/playtest/playtest_base.gd"
## Character creation by hand (no llm_server needed): a human fighter-soldier like the start preset, step by
## step with a screenshot of each step; then a wizard to see the spell step; «Начать игру» without the master
## leads to the offline screen. Run: python tools/godot_playtest.py --scenario creation --no-server


func run() -> void:
	await tap("NewGameButton")
	if not step("new game screen", screen_is("NewGameScreen")):
		return
	await tap("death_mode_one_life")
	await shot("new_game_one_life")
	await tap("NextButton")
	if not step("creation screen", screen_is("CreationScreen")):
		return
	var cs: Control = screen()
	step("ready-made characters offered", find(cs, "Preset_fighter_aira") != null and find(cs, "Preset_wizard_yalika") != null)
	await shot("presets")
	await tap("Preset_wizard_yalika")
	step("a preset is complete at once", not (find(cs, "StartButton") as Button).disabled and cs.get("step") == "details")
	await shot("preset_details")
	cs.set("step", "start")
	cs.call("_redraw")
	await tap("OwnButton")
	step("«Далее» locked until a race is picked", (find(cs, "NextButton") as Button).disabled)
	await tap("Pick_human")
	await shot("race")
	await tap("NextButton")
	await tap("Pick_fighter")
	await shot("class")
	await tap("NextButton")
	step("step: background", cs.get("step") == "background", str(cs.get("step")))
	await tap("Pick_soldier")
	await tap("NextButton")
	for pair: Array in [["str", 7], ["con", 6], ["dex", 5], ["wis", 4], ["cha", 2]]:
		for i in int(pair[1]):
			await tap("Plus_" + pair[0])
	step("27 points spent", CharacterBuilder.point_cost(cs.get("choices"), node("Catalog").data) == 27)
	step("no point left for INT", (find(cs, "Plus_int") as Button).disabled)
	await shot("abilities")
	await tap("NextButton")
	await tick("Check_perception")
	await tick("Check_survival")
	step("a third skill is locked", (find(cs, "Check_athletics") == null or (find(cs, "Check_acrobatics") as BaseButton).disabled))
	await shot("skills")
	await tap("NextButton")
	await tick("Check_fighter_fighting_style_defense")
	await shot("features")
	await tap("NextButton")
	for b: String in ["Equip_0_0", "Equip_1_0", "Equip_2_1", "Equip_3_1"]:
		await tap(b)
	await shot("equipment")
	await tap("NextButton")
	var name_edit: LineEdit = find(cs, "NameEdit")
	name_edit.text = "Айра"
	name_edit.text_changed.emit("Айра")
	name_edit.text_submitted.emit("Айра")
	await frames(2)
	await tap("Pick_female")
	await tick("Check_dwarvish")
	var start: Button = find(cs, "StartButton")
	step("character complete", start.visible and not start.disabled, str(cs.get("choices")))
	await shot("details")
	var built := CharacterBuilder.build(cs.get("choices"), node("Catalog").data)
	step("same numbers as the start preset", built["ac"] == 19 and built["max_hp"] == 12 and built["skills"]["athletics"] == 5,
		"AC %d, HP %d" % [built["ac"], built["max_hp"]])

	# A caster: the spell step appears and needs its picks.
	await tap("NextButton")  # still on the last step: no-op
	cs.set("step", "class")
	cs.call("_redraw")
	await tap("Pick_wizard")
	step("wizard adds the spell step", (cs.get("choices") as Dictionary)["class"] == "wizard"
		and CharacterBuilder.steps(cs.get("choices"), node("Catalog").data).has("spells"))
	cs.set("step", "spells")
	cs.call("_redraw")
	await frames(2)
	await shot("spells")

	await tap("RandomButton")
	await shot("random")
	await tap("StartButton")
	step("no master: the offline screen", screen_is("OfflineScreen"))
