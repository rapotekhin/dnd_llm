class_name SettingsScreen
extends Control
## Settings: «Экран» (window) and «Мастер» (backend address, token, certificate, check).

const TAB_DISPLAY := 0
const TAB_MASTER := 1
const TAB_CONTROLS := 2  # v0.7.22.27: keys and the irreversible questions

var back: String
var start_tab: int
var _fullscreen: CheckBox
var _resolution: OptionButton
var _resolutions: Array[Vector2i] = []
var _url: LineEdit
var _token: LineEdit
var _ca: LineEdit
var _check_status: Label
var _model: OptionButton
var _provider: OptionButton
var _images_on: CheckBox  # v0.7.35: the brush
var _image_model: OptionButton
var _image_ids: Array[String] = []
var _image_extra: VBoxContainer  # v0.7.37: the additions to the prompt and the negative
var _image_prompt: TextEdit
var _image_negative: TextEdit
var _image_negative_only: CheckBox
var _provider_tags: Array = []
var _provider_sort: OptionButton
## The provider list's orders (v0.7.34.1): «ours» — the server's picks for «Авто» first, then the server's ranking.
const PROVIDER_SORTS := ["ours", "cost", "speed", "uptime", "name"]
var _budget_edit: LineEdit
var _budget_off: CheckBox
var _budget_status: Label
var _model_ids: Array[String] = []
var _key_buttons: Dictionary = {}  # action → its button
var _waiting := ""  # the action waiting for a key


func _init(back_to: String, tab: int) -> void:
	back = back_to
	start_tab = tab


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 320)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)
	var title := Label.new()
	title.text = "TITLE_SETTINGS"
	title.theme_type_variation = UiTheme.HEADING
	col.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	tabs.add_child(_display_tab())
	tabs.add_child(_master_tab())
	tabs.add_child(_controls_tab())
	tabs.set_tab_title(TAB_DISPLAY, tr("TAB_DISPLAY"))
	tabs.set_tab_title(TAB_MASTER, tr("TAB_MASTER"))
	tabs.set_tab_title(TAB_CONTROLS, tr("TAB_CONTROLS"))
	tabs.current_tab = start_tab

	var back_btn := Button.new()
	back_btn.text = "BTN_BACK"
	back_btn.custom_minimum_size = Vector2(240, 56)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.pressed.connect(_back)
	col.add_child(back_btn)
	EventBus.backend_state_changed.connect(_on_backend_state)
	Backend.diagnosed.connect(_on_diagnosed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") and _waiting.is_empty():
		_back()
		get_viewport().set_input_as_handled()


# --- controls (v0.7.22.27) ----------------------------------------------------------------------------------------


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.name = "ControlsBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var ask := CheckBox.new()
	ask.name = "ConfirmRisky"
	ask.text = "OPT_CONFIRM_RISKY"
	ask.tooltip_text = "OPT_CONFIRM_RISKY_TIP"
	ask.button_pressed = SaveManager.confirm_risky
	ask.toggled.connect(func(on: bool) -> void:
		SaveManager.confirm_risky = on
		SaveManager.save_settings())
	box.add_child(ask)
	var head := Label.new()
	head.text = "OPT_KEYS"
	head.theme_type_variation = UiTheme.MUTED_LABEL
	box.add_child(head)
	for action: String in Hotkeys.defaults():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var lbl := Label.new()
		lbl.text = "KEY_ACT_" + action.to_upper()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var b := Button.new()
		b.name = "Key_" + action
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(220, 44)
		b.pressed.connect(func() -> void:
			_waiting = action
			_show_keys())
		row.add_child(b)
		_key_buttons[action] = b
		box.add_child(row)
	var reset := Button.new()
	reset.name = "KeysReset"
	reset.text = "BTN_KEYS_RESET"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		SaveManager.keys = {}
		_save_keys())
	box.add_child(reset)
	_show_keys()
	return scroll


func _show_keys() -> void:
	for action: String in _key_buttons:
		(_key_buttons[action] as Button).text = tr("KEY_PRESS") if action == _waiting else Hotkeys.key_of(action, SaveManager.keys)


## The key for the waiting action; Esc cancels. A key another action of the same place has — refused.
func _input(event: InputEvent) -> void:
	if _waiting.is_empty() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	var action := _waiting
	_waiting = ""
	var key := Hotkeys.name_of(event as InputEventKey)
	if (event as InputEventKey).physical_keycode == KEY_ESCAPE and action != "pause_menu":
		_show_keys()
		return
	var other := Hotkeys.clash(action, key, SaveManager.keys)
	if not other.is_empty():
		EventBus.message.emit(tr("KEY_TAKEN").format({"key": key, "action": tr("KEY_ACT_" + other.to_upper())}))
		_show_keys()
		return
	SaveManager.keys[action] = key
	_save_keys()


func _save_keys() -> void:
	SaveManager.save_settings()
	Hotkeys.apply(SaveManager.keys)
	_show_keys()


func _display_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Display"
	box.add_theme_constant_override("separation", 14)
	_fullscreen = CheckBox.new()
	_fullscreen.text = "OPT_FULLSCREEN"
	_fullscreen.button_pressed = SaveManager.fullscreen
	_fullscreen.toggled.connect(func(on: bool) -> void:
		SaveManager.fullscreen = on
		_apply_display())
	box.add_child(_fullscreen)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = "OPT_RESOLUTION"
	row.add_child(lbl)
	_resolution = OptionButton.new()
	_resolutions = SaveManager.available_resolutions()
	for r: Vector2i in _resolutions:
		_resolution.add_item("%d × %d" % [r.x, r.y])
	_resolution.selected = maxi(0, _resolutions.find(SaveManager.resolution))
	_resolution.item_selected.connect(func(i: int) -> void:
		SaveManager.resolution = _resolutions[i]
		_apply_display())
	row.add_child(_resolution)
	box.add_child(row)
	_options(box, "UiScale", "OPT_UI_SCALE", SaveManager.UI_SCALES.map(func(v: float) -> String: return "%d%%" % roundi(v * 100)),
		SaveManager.UI_SCALES.find(SaveManager.ui_scale), func(i: int) -> void:
			SaveManager.ui_scale = SaveManager.UI_SCALES[i]
			_apply_display())
	var speeds: Array = SaveManager.COMBAT_SPEEDS.keys()
	_options(box, "CombatSpeed", "OPT_COMBAT_SPEED", speeds.map(func(k: String) -> String: return tr("OPT_COMBAT_SPEED_" + k.to_upper())),
		speeds.find(SaveManager.combat_speed), func(i: int) -> void:
			SaveManager.combat_speed = str(speeds[i])
			GameState.combat_delay = SaveManager.combat_delay()
			SaveManager.save_settings())
	return box


func _options(box: Control, node_name: String, label_key: String, items: Array, selected: int, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = label_key
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.name = node_name
	ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for t: Variant in items:
		ob.add_item(str(t))
	ob.selected = maxi(0, selected)
	ob.item_selected.connect(on_pick)
	row.add_child(ob)
	box.add_child(row)


func _apply_display() -> void:
	SaveManager.save_settings()
	SaveManager.apply_settings()


func _master_tab() -> Control:
	var scroll := ScrollContainer.new()  # big test #1 (v0.7.22.5): the tab grew past the window
	scroll.name = "Master"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.name = "MasterBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	var cfg := Backend.config
	_url = _field(box, "OPT_BACKEND_URL", cfg.url, false)
	_token = _field(box, "OPT_BACKEND_TOKEN", cfg.token, true)
	_ca = _field(box, "OPT_BACKEND_CA", cfg.ca_cert_path, false)
	var hint := Label.new()
	hint.text = "HINT_BACKEND"
	hint.theme_type_variation = UiTheme.MUTED_LABEL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var check := Button.new()
	check.name = "CheckButton"
	check.text = "BTN_SAVE_AND_CHECK"
	check.theme_type_variation = UiTheme.ACCENT_BUTTON
	check.custom_minimum_size = Vector2(0, 56)
	check.pressed.connect(_save_and_check)
	row.add_child(check)
	_check_status = Label.new()
	_check_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_check_status)
	box.add_child(row)
	var status := BackendStatus.new()
	box.add_child(status)
	var model_label := Label.new()
	model_label.text = "OPT_MODEL"
	model_label.theme_type_variation = UiTheme.MUTED_LABEL
	box.add_child(model_label)
	_model = OptionButton.new()
	_model.name = "ModelOption"
	_model.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_model.item_selected.connect(_on_model_selected)
	box.add_child(_model)
	var provider_label := Label.new()  # v0.7.20.5: the provider pinned by hand
	provider_label.text = "OPT_PROVIDER"
	provider_label.theme_type_variation = UiTheme.MUTED_LABEL
	provider_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(provider_label)
	var sort_row := HBoxContainer.new()
	var sort_label := Label.new()
	sort_label.text = "OPT_PROVIDER_SORT"
	sort_label.theme_type_variation = UiTheme.MUTED_LABEL
	sort_row.add_child(sort_label)
	_provider_sort = OptionButton.new()
	_provider_sort.name = "ProviderSortOption"
	_provider_sort.fit_to_longest_item = false
	for key: String in PROVIDER_SORTS:
		_provider_sort.add_item("OPT_PROVIDER_SORT_" + key.to_upper())
	_provider_sort.selected = maxi(0, PROVIDER_SORTS.find(SaveManager.provider_sort))
	_provider_sort.item_selected.connect(_on_provider_sort_selected)
	sort_row.add_child(_provider_sort)
	box.add_child(sort_row)
	_provider = OptionButton.new()
	_provider.name = "ProviderOption"
	_provider.fit_to_longest_item = false  # v0.7.34.1: rows with prices are long, the popup shows them whole
	_provider.clip_text = true
	_provider.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_provider.item_selected.connect(_on_provider_selected)
	box.add_child(_provider)
	_budget_row(box)
	_images_row(box)
	_fill_models()
	var rx_label := Label.new()  # v0.7.10: reactions in a fight, as in Baldur's Gate 3
	rx_label.text = "OPT_REACTIONS"
	rx_label.theme_type_variation = UiTheme.MUTED_LABEL
	box.add_child(rx_label)
	var rx := OptionButton.new()
	rx.name = "ReactionsOption"
	var policies: Array[String] = ["ask", "always", "never"]
	for p: String in policies:
		rx.add_item(tr("REACTIONS_" + p.to_upper()))
	rx.selected = maxi(0, policies.find(SaveManager.reactions))
	rx.item_selected.connect(func(i: int) -> void:
		SaveManager.reactions = policies[i]
		SaveManager.save_settings()
		if GameState.has_session():
			GameState.session.settings["reactions"] = policies[i])
	box.add_child(rx)
	if GameState.has_session():
		var style_label := Label.new()
		style_label.text = "OPT_DM_STYLE"
		style_label.theme_type_variation = UiTheme.MUTED_LABEL
		box.add_child(style_label)
		var style := OptionButton.new()
		style.name = "DmStyleOption"
		for s: String in WorldPack.DM_STYLES:
			style.add_item(tr("DM_STYLE_" + s.to_upper()))
		style.selected = WorldPack.DM_STYLES.find(str(GameState.session.settings.get("dm_style", "classic")))
		style.item_selected.connect(func(i: int) -> void: GameState.set_dm_style(WorldPack.DM_STYLES[i]))
		box.add_child(style)
		var diff_label := Label.new()
		diff_label.text = "OPT_DIFFICULTY"
		diff_label.theme_type_variation = UiTheme.MUTED_LABEL
		box.add_child(diff_label)
		var diff := OptionButton.new()
		diff.name = "DifficultyOption"
		var levels := DifficultyRules.levels(Catalog.data)
		for d: Variant in levels:
			diff.add_item(tr("DIFFICULTY_" + str(d).to_upper()))
		diff.selected = levels.find(DifficultyRules.level(GameState.session, Catalog.data))
		diff.item_selected.connect(func(i: int) -> void: GameState.set_difficulty(str(levels[i])))
		box.add_child(diff)
		var needs := CheckButton.new()  # v0.7.23
		needs.name = "NeedsOption"
		needs.text = "OPT_NEEDS"
		needs.button_pressed = NeedRules.on(GameState.session)
		needs.toggled.connect(GameState.set_needs)
		box.add_child(needs)
		var adult := CheckButton.new()  # v0.7.38.7
		adult.name = "AdultOption"
		adult.text = "OPT_ADULT"
		adult.button_pressed = bool(GameState.session.settings.get("adult", false))
		adult.toggled.connect(GameState.set_adult)
		box.add_child(adult)
	return scroll


## The brush (v0.7.35): on or off, and the image model with its price per image; the images count in the day's limit.
func _images_row(box: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "OPT_IMAGES"
	label.theme_type_variation = UiTheme.MUTED_LABEL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_images_on = CheckBox.new()
	_images_on.name = "ImagesOn"
	_images_on.text = "OPT_IMAGES_ON"
	_images_on.button_pressed = SaveManager.images_on
	_images_on.toggled.connect(func(on: bool) -> void:
		SaveManager.images_on = on
		SaveManager.save_settings()
		_image_model.disabled = not on or _image_ids.size() < 2
		_fill_image_extra())
	row.add_child(_images_on)
	_image_model = OptionButton.new()
	_image_model.name = "ImageModelOption"
	_image_model.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_image_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image_model.item_selected.connect(func(i: int) -> void:
		SaveManager.image_model = _image_ids[i]
		SaveManager.save_settings()
		_fill_image_extra())
	row.add_child(_image_model)
	_image_extra_box(box)


## The player's additions to the picked model's prompt (v0.7.37): before every prompt, and the negative — with the
## master's tags or alone; they start from the model's own, «Как у модели» returns to them.
func _image_extra_box(box: VBoxContainer) -> void:
	_image_extra = VBoxContainer.new()
	_image_extra.name = "ImageExtra"
	box.add_child(_image_extra)
	_image_prompt = _image_text(tr("OPT_IMAGE_PROMPT"), "ImagePromptAdd")
	_image_negative = _image_text(tr("OPT_IMAGE_NEGATIVE"), "ImageNegativeAdd")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_image_extra.add_child(row)
	_image_negative_only = CheckBox.new()
	_image_negative_only.name = "ImageNegativeOnly"
	_image_negative_only.text = "OPT_IMAGE_NEGATIVE_ONLY"
	_image_negative_only.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image_negative_only.toggled.connect(func(_on: bool) -> void: _save_image_extra())
	row.add_child(_image_negative_only)
	var reset := Button.new()
	reset.name = "ImagePromptsReset"
	reset.text = "OPT_IMAGE_PROMPTS_RESET"
	reset.pressed.connect(func() -> void:
		SaveManager.image_prompts.erase(SaveManager.current_image_model())
		SaveManager.save_settings()
		_fill_image_extra())
	row.add_child(reset)


func _image_text(caption: String, node_name: String) -> TextEdit:
	var label := Label.new()
	label.text = caption
	label.name = node_name + "Label"
	label.theme_type_variation = UiTheme.MUTED_LABEL
	_image_extra.add_child(label)
	var edit := TextEdit.new()
	edit.name = node_name
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(0, 84)  # three lines of tags
	edit.text_changed.connect(_save_image_extra)
	_image_extra.add_child(edit)
	return edit


func _fill_image_extra() -> void:
	if _image_extra == null:
		return
	var id := SaveManager.current_image_model()
	var info := SaveManager.image_model_info(id)
	_image_extra.visible = SaveManager.images_on and not info.is_empty()
	var own: Dictionary = SaveManager.image_prompts.get(id, {})
	var neg := bool(info.get("negative", false))
	for n: Node in [_image_prompt, _image_negative, _image_negative_only]:
		n.set_block_signals(true)
	_image_prompt.text = str(own.get("prompt", info.get("prompt_add", "")))
	_image_negative.text = str(own.get("negative", info.get("negative_add", "")))
	_image_negative_only.button_pressed = bool(own.get("only", false))
	for n: Node in [_image_prompt, _image_negative, _image_negative_only]:
		n.set_block_signals(false)
	for n: String in ["ImageNegativeAdd", "ImageNegativeAddLabel", "ImageNegativeOnly"]:
		(_image_extra.find_child(n, true, false) as Control).visible = neg


func _save_image_extra() -> void:
	var id := SaveManager.current_image_model()
	if id.is_empty():
		return
	SaveManager.image_prompts[id] = {"prompt": _image_prompt.text.strip_edges(), "negative": _image_negative.text.strip_edges(),
		"only": _image_negative_only.button_pressed}
	SaveManager.save_settings()


func _fill_image_models() -> void:
	if _image_model == null:
		return
	_image_model.clear()
	_image_ids = []
	var default_id := Backend.default_image_model()
	for m: Variant in Backend.image_models():
		if m is Dictionary:
			var id := str(m.get("id", ""))
			_image_ids.append("" if id == default_id else id)
			var price := float(m.get("usd_per_image", 0))
			_image_model.add_item((tr("OPT_IMAGE_MODEL").format({"name": m.get("name", id), "price": "%.3f" % price}) if price > 0
				else tr("OPT_IMAGE_MODEL_FREE").format({"name": m.get("name", id)}))
				+ (tr("OPT_IMAGE_MODEL_DEFAULT") if id == default_id else ""))
	if _image_ids.is_empty():
		_image_ids.append("")
		_image_model.add_item(tr("OPT_IMAGES_NONE"))
	_image_model.selected = maxi(0, _image_ids.find(SaveManager.image_model))
	_image_model.disabled = not SaveManager.images_on or _image_ids.size() < 2
	_fill_image_extra()


## The server's daily spending limit (v0.7.3): spent today of the limit, the limit in dollars or «без лимита».
func _budget_row(box: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "OPT_BUDGET"
	label.theme_type_variation = UiTheme.MUTED_LABEL
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_budget_edit = LineEdit.new()
	_budget_edit.name = "BudgetEdit"
	_budget_edit.placeholder_text = "1.00"
	_budget_edit.custom_minimum_size = Vector2(140, 52)
	row.add_child(_budget_edit)
	_budget_off = CheckBox.new()
	_budget_off.name = "BudgetOff"
	_budget_off.text = "OPT_BUDGET_OFF"
	_budget_off.toggled.connect(func(on: bool) -> void: _budget_edit.editable = not on)
	row.add_child(_budget_off)
	var save := Button.new()
	save.name = "BudgetSave"
	save.text = "OPT_BUDGET_SAVE"
	save.custom_minimum_size = Vector2(0, 52)
	save.pressed.connect(_save_budget)
	row.add_child(save)
	_budget_status = Label.new()
	_budget_status.name = "BudgetStatus"
	_budget_status.theme_type_variation = UiTheme.MUTED_LABEL
	_budget_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_budget_status)
	_refresh_budget()


func _refresh_budget() -> void:
	if _budget_status == null:
		return
	var b := await Backend.budget()
	_show_budget(b)


func _show_budget(b: Dictionary) -> void:
	if b.is_empty():
		_budget_status.text = tr("OPT_BUDGET_UNKNOWN")
		return
	var limit: Variant = b.get("daily_usd")
	_budget_off.set_pressed_no_signal(limit == null)
	_budget_edit.editable = limit != null
	if limit != null:
		_budget_edit.text = "%.2f" % float(limit)
	var spent := float(b.get("spent_today_usd", 0.0))
	_budget_status.text = tr("OPT_BUDGET_SPENT_OFF").format({"spent": "%.3f" % spent}) if limit == null \
		else tr("OPT_BUDGET_SPENT").format({"spent": "%.3f" % spent, "limit": "%.2f" % float(limit), "left": "%.3f" % maxf(0.0, float(limit) - spent)})


func _save_budget() -> void:
	var limit: Variant = null
	if not _budget_off.button_pressed:
		var text := _budget_edit.text.strip_edges().replace(",", ".")
		if not text.is_valid_float() or float(text) <= 0.0 or float(text) > 1000.0:
			_budget_status.text = tr("OPT_BUDGET_BAD")
			return
		limit = float(text)
	var b := await Backend.set_budget(limit)
	_show_budget(b)


## Models come from the server (session.hello); "" = the server's default. Price per million tokens in/out.
func _fill_models() -> void:
	_model.clear()
	_model_ids = [""]
	if not SaveManager.master_model.is_empty() and not SaveManager.offered(SaveManager.master_model):
		SaveManager.master_model = ""  # the server no longer offers it: back to its default
		SaveManager.save_settings()
	var default_name := Backend.default_model()
	_model.add_item(tr("OPT_MODEL_DEFAULT").format({"model": default_name if not default_name.is_empty() else "—"}))
	for m: Variant in Backend.models():
		if m is Dictionary:
			_model_ids.append(str(m.get("id", "")))
			_model.add_item("%s  ($%.2f / $%.2f)" % [m.get("name", m.get("id", "")), float(m.get("input_usd_per_mtok", 0)),
				float(m.get("output_usd_per_mtok", 0))])
	if not _model_ids.has(SaveManager.master_model):
		_model_ids.append(SaveManager.master_model)
		_model.add_item(SaveManager.master_model)
	_model.selected = _model_ids.find(SaveManager.master_model)
	_model.disabled = Backend.models().is_empty()
	_fill_providers()
	_fill_image_models()


## The providers of the chosen model (session.hello): «Авто» — the server picks the cheapest fast one and may change it.
func _fill_providers() -> void:
	if _provider == null:
		return
	_provider.clear()
	_provider_tags = [""]
	_provider.add_item(tr("OPT_PROVIDER_AUTO"))
	var id := SaveManager.master_model if not SaveManager.master_model.is_empty() else Backend.default_model()
	for m: Variant in Backend.models():
		if m is Dictionary and str(m.get("id", "")) == id:
			for p: Variant in sort_providers(m.get("providers", []), SaveManager.provider_sort):
				_provider_tags.append(str(p.get("tag", "")))
				_provider.add_item(provider_text(p))
				_provider.set_item_tooltip(_provider.item_count - 1, provider_tooltip(p))
	var pinned := str(SaveManager.master_providers.get(SaveManager.master_model, ""))
	_provider.selected = maxi(0, _provider_tags.find(pinned))
	_provider.disabled = _provider_tags.size() < 2


## One row of the provider list (v0.7.34.1): the name with its tag, the cost of 1000 turns and our measured speed.
static func provider_text(p: Dictionary) -> String:
	var name := str(p.get("name", p.get("tag", "")))
	var tag := str(p.get("tag", ""))
	if not tag.is_empty() and tag.to_lower() != name.to_lower():
		name += " (%s)" % tag
	var cost := float(p.get("usd_per_1000_turns", 0))
	if cost <= 0:  # an old server or the config's short list: the name alone
		return name
	var tps := float(p.get("tokens_per_s", 0))
	var speed: String = TranslationServer.translate("OPT_PROVIDER_SPEED") % roundi(tps) if tps > 0 else TranslationServer.translate("OPT_PROVIDER_SPEED_NONE")
	var text: String = TranslationServer.translate("OPT_PROVIDER_ITEM") % [name, cost, speed]
	if bool(p.get("picked", false)):
		text += TranslationServer.translate("OPT_PROVIDER_PICKED")
	return text


## The row's tooltip: the prices per million tokens, our bills, uptime and quantization.
static func provider_tooltip(p: Dictionary) -> String:
	if float(p.get("usd_per_1000_turns", 0)) <= 0:
		return ""
	var cache: Variant = p.get("cache_usd_per_mtok")
	var lines := [TranslationServer.translate("OPT_PROVIDER_TIP_PRICES") % [float(p.get("input_usd_per_mtok", 0)), float(p.get("output_usd_per_mtok", 0)),
		("$%.4f" % float(cache)) if cache != null else TranslationServer.translate("OPT_PROVIDER_TIP_NO_CACHE")]]
	var factor := float(p.get("bill_factor", 1.0))
	if absf(factor - 1.0) >= 0.15:
		lines.append(TranslationServer.translate("OPT_PROVIDER_TIP_BILLS") % factor)
	var uptime: Variant = p.get("uptime")
	if uptime != null:
		lines.append(TranslationServer.translate("OPT_PROVIDER_TIP_UPTIME") % float(uptime))
	if not str(p.get("quantization", "")).is_empty() and str(p.get("quantization", "")) != "unknown":
		lines.append(TranslationServer.translate("OPT_PROVIDER_TIP_QUANT") % str(p.get("quantization", "")))
	return "\n".join(lines)


## The providers in the order the player chose; the server's order (its ranking) breaks ties.
static func sort_providers(list: Array, key: String) -> Array:
	var rows := []
	for i in list.size():
		if list[i] is Dictionary:
			rows.append({"p": list[i], "i": i})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Dictionary = a["p"]
		var pb: Dictionary = b["p"]
		if key == "name":
			var na := str(pa.get("name", "")).to_lower()
			var nb := str(pb.get("name", "")).to_lower()
			if na != nb:
				return na < nb
		var x := _sort_value(pa, key)
		var y := _sort_value(pb, key)
		return x < y if x != y else int(a["i"]) < int(b["i"]))
	return rows.map(func(r: Dictionary) -> Dictionary: return r["p"])


## Smaller comes first; unknown values go last.
static func _sort_value(p: Dictionary, key: String) -> float:
	match key:
		"ours":
			return 0.0 if bool(p.get("picked", false)) else 1.0
		"cost":
			var cost := float(p.get("usd_per_1000_turns", 0))
			return cost if cost > 0 else INF
		"speed":
			var tps := float(p.get("tokens_per_s", 0))
			return -tps if tps > 0 else INF
		"uptime":
			return -float(p["uptime"]) if p.get("uptime") != null else INF
	return 0.0


func _on_provider_sort_selected(i: int) -> void:
	SaveManager.provider_sort = PROVIDER_SORTS[i]
	SaveManager.save_settings()
	_fill_providers()


func _on_provider_selected(i: int) -> void:
	SaveManager.master_providers[SaveManager.master_model] = _provider_tags[i]
	SaveManager.save_settings()


func _on_model_selected(i: int) -> void:
	SaveManager.master_model = _model_ids[i]
	SaveManager.save_settings()
	_fill_providers()


func _field(parent: Control, key: String, value: String, secret: bool) -> LineEdit:
	var lbl := Label.new()
	lbl.text = key
	lbl.theme_type_variation = UiTheme.MUTED_LABEL
	parent.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = value
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, 52)
	parent.add_child(edit)
	return edit


func _save_and_check() -> void:
	_check_status.text = tr("MSG_CHECKING")
	_check_status.add_theme_color_override("font_color", UiTheme.MUTED)
	Backend.save_config(_url.text.strip_edges(), _token.text.strip_edges(), _ca.text.strip_edges())


func _on_backend_state(state: int, _detail: String) -> void:
	if state == BackendClient.State.READY:
		_fill_models()
		_refresh_budget()
	if _check_status == null or _check_status.text.is_empty():
		return
	if state == BackendClient.State.READY:
		_check_status.text = tr("MSG_CHECK_OK")
		_check_status.add_theme_color_override("font_color", UiTheme.OK)
	elif state in [BackendClient.State.WAITING_RETRY, BackendClient.State.FAILED, BackendClient.State.OFFLINE]:
		Backend.request_diagnosis()


func _on_diagnosed(diag: String) -> void:
	if _check_status.text.is_empty() or Backend.is_ready():
		return
	_check_status.text = tr(OfflineScreen.diagnosis_key(diag))
	_check_status.add_theme_color_override("font_color", UiTheme.BAD)


func _back() -> void:
	EventBus.navigate.emit(back, {})
