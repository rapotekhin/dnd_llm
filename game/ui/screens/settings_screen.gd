class_name SettingsScreen
extends Control
## Settings: «Экран» (window) and «Мастер» (backend address, token, certificate, check).

const TAB_DISPLAY := 0
const TAB_MASTER := 1

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
var _provider_tags: Array = []
var _budget_edit: LineEdit
var _budget_off: CheckBox
var _budget_status: Label
var _model_ids: Array[String] = []


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
	tabs.set_tab_title(TAB_DISPLAY, tr("TAB_DISPLAY"))
	tabs.set_tab_title(TAB_MASTER, tr("TAB_MASTER"))
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
	if event.is_action_pressed("pause_menu"):
		_back()
		get_viewport().set_input_as_handled()


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
	return box


func _apply_display() -> void:
	SaveManager.save_settings()
	SaveManager.apply_settings()


func _master_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Master"
	box.add_theme_constant_override("separation", 10)
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
	box.add_child(provider_label)
	_provider = OptionButton.new()
	_provider.name = "ProviderOption"
	_provider.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_provider.item_selected.connect(_on_provider_selected)
	box.add_child(_provider)
	_fill_models()
	_budget_row(box)
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
	return box


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
			for p: Variant in m.get("providers", []):
				_provider_tags.append(str(p.get("tag", "")))
				_provider.add_item(str(p.get("name", p.get("tag", ""))))
	var pinned := str(SaveManager.master_providers.get(SaveManager.master_model, ""))
	_provider.selected = maxi(0, _provider_tags.find(pinned))
	_provider.disabled = _provider_tags.size() < 2


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
