class_name InfoBox
extends PanelContainer
## The rules text of the choice under the mouse or just picked (roadmap v0.6.6, playtest-1: «I pick features
## blindly by their names»): a box under a list of races, classes, features, spells, items. Tooltips stay too, but
## this is always visible. The text can be selected and copied.

var _title: Label
var _body: RichTextLabel


func _init(min_height: int = 130) -> void:
	name = "InfoBox"
	theme_type_variation = UiTheme.SIDE
	custom_minimum_size = Vector2(0, min_height)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	col.add_child(_title)
	_body = RichTextLabel.new()
	_body.name = "InfoText"
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.fit_content = true
	_body.scroll_active = false
	_body.selection_enabled = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	show_text(tr("INFO_HINT"), "")


## A column of its own beside a list (v0.7.22.5, big test #36): a fixed width, the text scrolls inside, the box does
## not jump in size from one choice to another.
func as_column(width: int) -> InfoBox:
	custom_minimum_size = Vector2(width, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_body.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	return self


func show_text(title: String, body: String) -> void:
	_title.text = title
	_body.text = body


func text() -> String:
	return _body.text


## Shows `title` / `body` in `box` when `control` is hovered, focused or pressed.
static func hook(control: Control, box: InfoBox, title: String, body: String) -> void:
	if box == null or body.is_empty():
		return
	control.mouse_entered.connect(func() -> void: box.show_text(title, body))
	control.focus_entered.connect(func() -> void: box.show_text(title, body))
	if control is BaseButton:
		(control as BaseButton).pressed.connect(func() -> void: box.show_text(title, body))


# --- rules texts of SRD choices ------------------------------------------------------------------------


static func _ab(a: String) -> String:
	return TranslationServer.translate("ABILITY_" + a.to_upper())


static func race_text(data: Dictionary, id: String) -> String:
	var r: Dictionary = data["races"]["races"].get(id, data["races"]["subraces"].get(id, {}))
	var bonus: Array[String] = []
	for a: String in r.get("ability_bonuses", {}):
		bonus.append("%s %+d" % [_ab(a), int(r["ability_bonuses"][a])])
	var lines: Array[String] = []
	if not bonus.is_empty() or r.has("speed"):
		lines.append(", ".join(bonus) + ((" · скорость %s фт" % r["speed"]) if r.has("speed") else ""))
	if not str(r.get("desc", "")).is_empty():
		lines.append(str(r["desc"]))
	for t: Variant in r.get("traits", []):
		var d: Dictionary = data["races"]["traits"].get(str(t), {})
		if not d.is_empty():
			lines.append("%s: %s" % [d["name"], d.get("desc", "")])
	return "\n".join(lines)


static func class_text(data: Dictionary, id: String) -> String:
	var k: Dictionary = data["classes"]["classes"].get(id, {})
	if k.is_empty():
		return ""
	var saves: Array = (k.get("saves", []) as Array).map(func(a: Variant) -> String: return _ab(str(a)))
	var lines: Array[String] = ["Кость хитов к%d · спасброски: %s%s" % [int(k["hit_die"]), ", ".join(saves),
		(" · заклинатель (%s)" % _ab(str(k["spellcasting"]["ability"]))) if k.has("spellcasting") else ""]]
	for f: Variant in k["levels"]["1"].get("features", []):
		var d: Dictionary = data["classes"]["features"].get(str(f), {})
		if not d.is_empty():
			lines.append("%s: %s" % [d["name"], d.get("desc", "")])
	return "\n".join(lines)


static func subclass_text(data: Dictionary, id: String) -> String:
	var s: Dictionary = data["classes"]["subclasses"].get(id, {})
	if s.is_empty():
		return ""
	var lines: Array[String] = []
	if not str(s.get("desc", "")).is_empty():
		lines.append(str(s["desc"]))
	var levels: Array = (s.get("features", {}) as Dictionary).keys()
	levels.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for lv: Variant in levels:
		for f: Variant in s["features"][lv]:
			var d: Dictionary = data["classes"]["features"].get(str(f), {})
			if not d.is_empty():
				lines.append("%s ур. — %s: %s" % [lv, d["name"], d.get("desc", "")])
	return "\n".join(lines)


static func background_text(data: Dictionary, id: String) -> String:
	var b: Dictionary = data["backgrounds"].get(id, {})
	if b.is_empty():
		return ""
	var skills: Array = (b.get("skills", []) as Array).map(func(x: Variant) -> String: return TranslationServer.translate("SKILL_" + str(x).to_upper()))
	return "%s\nНавыки: %s\n%s: %s" % [b.get("desc", ""), ", ".join(skills), b["feature"]["name"], b["feature"]["desc"]]

