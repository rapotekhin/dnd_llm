class_name DetailsPanel
extends PanelContainer
## What the picked thing is (v0.7.7 fixes, the author: «a separate panel for the selected item, not stats on every
## row»): a title and the text in a box of a fixed size that scrolls inside — a long description never grows it.
## Used by the character sheet, the trade panel and the combat screen; the texts come from the static helpers here.

var _title: Label
var _body: Label


func _init(min_size: Vector2 = Vector2(0, 180)) -> void:
	name = "DetailsPanel"
	theme_type_variation = UiTheme.SIDE
	custom_minimum_size = min_size
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = Label.new()
	_title.name = "DetailsTitle"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	col.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(60.0, min_size.y - 60.0))
	col.add_child(scroll)
	_body = Label.new()
	_body.name = "DetailsText"
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.theme_type_variation = UiTheme.MUTED_LABEL
	scroll.add_child(_body)
	show_text(TranslationServer.translate("DETAILS_HINT"), "")


func show_text(title: String, body: String) -> void:
	_title.text = title
	_body.text = body


func title() -> String:
	return _title.text


func body() -> String:
	return _body.text


## Shows this text when `control` is hovered or pressed.
func hook(control: Control, title_text: String, body_text: String) -> void:
	control.mouse_entered.connect(func() -> void: show_text(title_text, body_text))
	if control is BaseButton:
		(control as BaseButton).pressed.connect(func() -> void: show_text(title_text, body_text))


# --- texts ----------------------------------------------------------------------------------------------------


static func item_text(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	var lines := ItemInfo.lines(c, data, session_items, id)
	var cmp := ItemInfo.compare(c, data, session_items, id)
	if not cmp.is_empty():
		lines.append(cmp)
	return "\n".join(lines)


static func spell_text(data: Dictionary, id: String, slot: int = 0) -> String:
	var s: Dictionary = data["spells"].get(id, {})
	if s.is_empty():
		return ""
	var lv := int(s.get("level", 0))
	var head: String = TranslationServer.translate("DETAILS_CANTRIP") if lv == 0 else TranslationServer.translate("DETAILS_CIRCLE").format({"n": lv})
	var lines: Array[String] = ["%s · %s · %s · %s%s" % [head, s.get("casting_time", ""), s.get("range", ""), s.get("duration", ""),
		(" · " + TranslationServer.translate("DETAILS_CONCENTRATION")) if bool(s.get("concentration", false)) else ""]]
	if not str(s.get("desc", "")).is_empty():
		lines.append(str(s["desc"]))
	var grown := SpellRules.at_slot(data, id, slot)  # v0.7.22.19: what the chosen slot gives
	if not grown.is_empty():
		lines.append(grown)
	return "\n".join(lines)


## A class feature or a race trait by id, or a resource of FeatureUses (its first feature).
static func feature_text(data: Dictionary, id: String) -> String:
	for pool: Dictionary in [data["classes"]["features"], data["races"]["traits"]]:
		if pool.has(id):
			return str(pool[id].get("desc", ""))
	var res: Dictionary = data["rules"]["resources"].get(id, {})
	for f: Variant in res.get("features", []):
		var t := feature_text(data, str(f))
		if not t.is_empty():
			return t
	return ""
