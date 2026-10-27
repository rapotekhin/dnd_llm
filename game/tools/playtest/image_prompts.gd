extends "res://tools/playtest/playtest_base.gd"
## The image model's additions (python tools/godot_playtest.py --scenario image_prompts; no turn, no cost), v0.7.37:
## the fields start from the model's own, a model without a negative hides it, an edit is kept, «Как у модели» returns.


func run() -> void:
	var sm := node("SaveManager")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	sm.image_prompts = {}
	sm.image_model = ""  # the server's default, a model without a negative
	node("EventBus").navigate.emit("settings", {"back": "menu", "tab": 1})  # SettingsScreen.TAB_MASTER
	await frames(5)
	var models: OptionButton = find(screen(), "ImageModelOption")
	var prompt: TextEdit = find(screen(), "ImagePromptAdd")
	var negative: TextEdit = find(screen(), "ImageNegativeAdd")
	if not step("the additions are under the image model", models != null and prompt != null and prompt.is_visible_in_tree()):
		return
	var ids: Array = node("Backend").image_models().map(func(m: Dictionary) -> String: return str(m["id"]))
	var own := ids.find("sd:amix-illustrious")
	step("a model without a negative hides it", not negative.is_visible_in_tree(), str(sm.current_image_model()))
	if own < 0:
		step("the own Forge's A-Mix is offered (needs Forge at 127.0.0.1:7860)", false, str(ids))
		return
	models.select(own)
	models.item_selected.emit(own)
	await frames(3)
	step("A-Mix starts from its own additions with the LoRA", prompt.text.contains("<lora:rimixO:0.65>") and negative.is_visible_in_tree()
		and negative.text.begins_with("lowres"), prompt.text)
	var scroll: Node = prompt
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll != null:
		(scroll as ScrollContainer).ensure_control_visible(find(screen(), "ImagePromptsReset"))
	await frames(3)
	await shot("amix_defaults")
	prompt.text = "masterpiece, <lora:rimixO:0.8>"
	prompt.text_changed.emit()
	(find(screen(), "ImageNegativeOnly") as CheckBox).button_pressed = true
	await frames(2)
	var saved: Dictionary = sm.image_prompts.get("sd:amix-illustrious", {})
	step("the edit is kept for the model", str(saved.get("prompt", "")) == "masterpiece, <lora:rimixO:0.8>" and bool(saved.get("only", false)), str(saved))
	var p: Dictionary = sm.image_params({})
	step("the brush sends them", str(p.get("prompt_add", "")).contains("0.8") and bool(p.get("negative_only", false)), str(p))
	await shot("amix_edited")
	await press(find(screen(), "ImagePromptsReset"))
	await frames(2)
	step("«Как у модели» returns its own", not sm.image_prompts.has("sd:amix-illustrious") and prompt.text.contains("0.65"), prompt.text)
	models.select(0)
	models.item_selected.emit(0)
	await frames(2)
