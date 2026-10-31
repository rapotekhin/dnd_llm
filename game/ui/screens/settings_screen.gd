class_name SettingsScreen
extends Control
## Settings: «Экран» (window) and «Мастер» (backend address, token, certificate, check).

const SCENE := "res://ui/screens/settings_screen.tscn"
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


static func make(back_to: String, tab: int) -> SettingsScreen:
	var screen := UiScenes.open(SCENE) as SettingsScreen
	screen.back = back_to
	screen.start_tab = tab
	return screen


func required() -> Dictionary:
	var nodes := {
		"%Tabs": "TabContainer", "%BackButton": "Button", "%Fullscreen": "CheckBox", "%Url": "LineEdit", "%Token": "LineEdit",
		"%CaPath": "LineEdit", "%CheckButton": "Button", "%CheckStatus": "Label", "%BudgetEdit": "LineEdit",
		"%BudgetOff": "CheckBox", "%BudgetSave": "Button", "%BudgetStatus": "Label", "%ImagesOn": "CheckBox",
		"%ImageExtra": "VBoxContainer", "%ImagePromptAdd": "TextEdit", "%ImageNegativeAdd": "TextEdit",
		"%ImagePromptAddLabel": "Label", "%ImageNegativeAddLabel": "Label", "%ImageNegativeOnly": "CheckBox",
		"%ImagePromptsReset": "Button", "%GameOptions": "VBoxContainer", "%NeedsOption": "CheckButton",
		"%AdultOption": "CheckButton", "%ConfirmRisky": "CheckBox", "%KeyList": "VBoxContainer", "%KeysReset": "Button",
	}
	for path: String in ["%Resolution", "%UiScale", "%CombatSpeed", "%ModelOption", "%ProviderOption", "%ProviderSortOption",
			"%ImageModelOption", "%ReactionsOption", "%DmStyleOption", "%DifficultyOption"]:
		nodes[path] = "OptionButton"
	return nodes


func _ready() -> void:
	var tabs: TabContainer = UiScenes.need(self, "%Tabs")
	tabs.set_tab_title(TAB_DISPLAY, tr("TAB_DISPLAY"))
	tabs.set_tab_title(TAB_MASTER, tr("TAB_MASTER"))
	tabs.set_tab_title(TAB_CONTROLS, tr("TAB_CONTROLS"))
	tabs.current_tab = start_tab
	(UiScenes.need(self, "%BackButton") as Button).pressed.connect(_back)
	_display_tab()
	_master_tab()
	_controls_tab()
	EventBus.backend_state_changed.connect(_on_backend_state)
	Backend.diagnosed.connect(_on_diagnosed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") and _waiting.is_empty():
		_back()
		get_viewport().set_input_as_handled()


# --- controls (v0.7.22.27) ----------------------------------------------------------------------------------------


func _controls_tab() -> void:
	var ask: CheckBox = UiScenes.need(self, "%ConfirmRisky")
	ask.button_pressed = SaveManager.confirm_risky
	ask.toggled.connect(func(on: bool) -> void:
		SaveManager.confirm_risky = on
		SaveManager.save_settings())
	var list: Control = UiScenes.need(self, "%KeyList")
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
		list.add_child(row)
	(UiScenes.need(self, "%KeysReset") as Button).pressed.connect(func() -> void:
		SaveManager.keys = {}
		_save_keys())
	_show_keys()


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


func _display_tab() -> void:
	_fullscreen = UiScenes.need(self, "%Fullscreen")
	_fullscreen.button_pressed = SaveManager.fullscreen
	_fullscreen.toggled.connect(func(on: bool) -> void:
		SaveManager.fullscreen = on
		_apply_display())
	_resolutions = SaveManager.available_resolutions()
	_resolution = _options("%Resolution", _resolutions.map(func(r: Vector2i) -> String: return "%d × %d" % [r.x, r.y]),
		_resolutions.find(SaveManager.resolution), func(i: int) -> void:
			SaveManager.resolution = _resolutions[i]
			_apply_display())
	_options("%UiScale", SaveManager.UI_SCALES.map(func(v: float) -> String: return "%d%%" % roundi(v * 100)),
		SaveManager.UI_SCALES.find(SaveManager.ui_scale), func(i: int) -> void:
			SaveManager.ui_scale = SaveManager.UI_SCALES[i]
			_apply_display())
	var speeds: Array = SaveManager.COMBAT_SPEEDS.keys()
	_options("%CombatSpeed", speeds.map(func(k: String) -> String: return tr("OPT_COMBAT_SPEED_" + k.to_upper())),
		speeds.find(SaveManager.combat_speed), func(i: int) -> void:
			SaveManager.combat_speed = str(speeds[i])
			GameState.combat_delay = SaveManager.combat_delay()
			SaveManager.save_settings())


func _options(path: String, items: Array, selected: int, on_pick: Callable) -> OptionButton:
	var ob: OptionButton = UiScenes.need(self, path)
	for t: Variant in items:
		ob.add_item(str(t))
	ob.selected = maxi(0, selected)
	ob.item_selected.connect(on_pick)
	return ob


func _apply_display() -> void:
	SaveManager.save_settings()
	SaveManager.apply_settings()


func _master_tab() -> void:
	var cfg := Backend.config
	_url = _field("%Url", cfg.url)
	_token = _field("%Token", cfg.token)
	_ca = _field("%CaPath", cfg.ca_cert_path)
	(UiScenes.need(self, "%CheckButton") as Button).pressed.connect(_save_and_check)
	_check_status = UiScenes.need(self, "%CheckStatus")
	_model = UiScenes.need(self, "%ModelOption")
	_model.item_selected.connect(_on_model_selected)
	_provider_sort = UiScenes.need(self, "%ProviderSortOption")  # v0.7.20.5: the provider pinned by hand
	for key: String in PROVIDER_SORTS:
		_provider_sort.add_item("OPT_PROVIDER_SORT_" + key.to_upper())
	_provider_sort.selected = maxi(0, PROVIDER_SORTS.find(SaveManager.provider_sort))
	_provider_sort.item_selected.connect(_on_provider_sort_selected)
	_provider = UiScenes.need(self, "%ProviderOption")  # v0.7.34.1: rows with prices are long, the popup shows them whole
	_provider.item_selected.connect(_on_provider_selected)
	_budget_row()
	_images_row()
	_fill_models()
	var policies: Array[String] = ["ask", "always", "never"]  # v0.7.10: reactions in a fight, as in Baldur's Gate 3
	_options("%ReactionsOption", policies.map(func(p: String) -> String: return tr("REACTIONS_" + p.to_upper())),
		policies.find(SaveManager.reactions), func(i: int) -> void:
			SaveManager.reactions = policies[i]
			SaveManager.save_settings()
			if GameState.has_session():
				GameState.session.settings["reactions"] = policies[i])
	var in_game := GameState.has_session()
	(UiScenes.need(self, "%GameOptions") as Control).visible = in_game
	if not in_game:
		return
	_options("%DmStyleOption", WorldPack.DM_STYLES.map(func(s: String) -> String: return tr("DM_STYLE_" + s.to_upper())),
		WorldPack.DM_STYLES.find(str(GameState.session.settings.get("dm_style", "classic"))),
		func(i: int) -> void: GameState.set_dm_style(WorldPack.DM_STYLES[i]))
	var levels := DifficultyRules.levels(Catalog.data)
	_options("%DifficultyOption", levels.map(func(d: Variant) -> String: return tr("DIFFICULTY_" + str(d).to_upper())),
		levels.find(DifficultyRules.level(GameState.session, Catalog.data)), func(i: int) -> void: GameState.set_difficulty(str(levels[i])))
	var needs: CheckButton = UiScenes.need(self, "%NeedsOption")  # v0.7.23
	needs.button_pressed = NeedRules.on(GameState.session)
	needs.toggled.connect(GameState.set_needs)
	var adult: CheckButton = UiScenes.need(self, "%AdultOption")  # v0.7.38.7
	adult.button_pressed = bool(GameState.session.settings.get("adult", false))
	adult.toggled.connect(GameState.set_adult)


## The brush (v0.7.35): on or off, and the image model with its price per image; the images count in the day's limit.
func _images_row() -> void:
	_images_on = UiScenes.need(self, "%ImagesOn")
	_images_on.button_pressed = SaveManager.images_on
	_images_on.toggled.connect(func(on: bool) -> void:
		SaveManager.images_on = on
		SaveManager.save_settings()
		_image_model.disabled = not on or _image_ids.size() < 2
		_fill_image_extra())
	_image_model = UiScenes.need(self, "%ImageModelOption")
	_image_model.item_selected.connect(func(i: int) -> void:
		SaveManager.image_model = _image_ids[i]
		SaveManager.save_settings()
		_fill_image_extra())
	_image_extra_box()


## The player's additions to the picked model's prompt (v0.7.37): before every prompt, and the negative — with the
## master's tags or alone; they start from the model's own, «Как у модели» returns to them.
func _image_extra_box() -> void:
	_image_extra = UiScenes.need(self, "%ImageExtra")
	_image_prompt = UiScenes.need(self, "%ImagePromptAdd")
	_image_prompt.text_changed.connect(_save_image_extra)
	_image_negative = UiScenes.need(self, "%ImageNegativeAdd")
	_image_negative.text_changed.connect(_save_image_extra)
	_image_negative_only = UiScenes.need(self, "%ImageNegativeOnly")
	_image_negative_only.toggled.connect(func(_on: bool) -> void: _save_image_extra())
	(UiScenes.need(self, "%ImagePromptsReset") as Button).pressed.connect(func() -> void:
		SaveManager.image_prompts.erase(SaveManager.current_image_model())
		SaveManager.save_settings()
		_fill_image_extra())


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
	for n: Control in [_image_negative, UiScenes.need(self, "%ImageNegativeAddLabel"), _image_negative_only]:
		n.visible = neg


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
func _budget_row() -> void:
	_budget_edit = UiScenes.need(self, "%BudgetEdit")
	_budget_off = UiScenes.need(self, "%BudgetOff")
	_budget_off.toggled.connect(func(on: bool) -> void: _budget_edit.editable = not on)
	(UiScenes.need(self, "%BudgetSave") as Button).pressed.connect(_save_budget)
	_budget_status = UiScenes.need(self, "%BudgetStatus")
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


func _field(path: String, value: String) -> LineEdit:
	var edit: LineEdit = UiScenes.need(self, path)
	edit.text = value
	return edit


func _save_and_check() -> void:
	_check_status.text = tr("MSG_CHECKING")
	_check_status.theme_type_variation = UiTheme.MUTED_LABEL
	Backend.save_config(_url.text.strip_edges(), _token.text.strip_edges(), _ca.text.strip_edges())


func _on_backend_state(state: int, _detail: String) -> void:
	if state == BackendClient.State.READY:
		_fill_models()
		_refresh_budget()
	if _check_status == null or _check_status.text.is_empty():
		return
	if state == BackendClient.State.READY:
		_check_status.text = tr("MSG_CHECK_OK")
		_check_status.theme_type_variation = UiTheme.OK_LABEL
	elif state in [BackendClient.State.WAITING_RETRY, BackendClient.State.FAILED, BackendClient.State.OFFLINE]:
		Backend.request_diagnosis()


func _on_diagnosed(diag: String) -> void:
	if _check_status.text.is_empty() or Backend.is_ready():
		return
	_check_status.text = tr(OfflineScreen.diagnosis_key(diag))
	_check_status.theme_type_variation = UiTheme.BAD_LABEL


func _back() -> void:
	EventBus.navigate.emit(back, {})
