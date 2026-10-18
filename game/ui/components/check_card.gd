class_name CheckCard
extends PanelContainer
## Roll card after an engine check (ADR-0008 §2): «Внимательность: 12 + 3 = 15 против DC 15 ✓».

var entry: Dictionary


func _init(check_entry: Dictionary) -> void:
	entry = check_entry


func _ready() -> void:
	theme_type_variation = UiTheme.CARD
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	add_child(col)
	var line := Label.new()
	line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	line.text = text_for(entry)
	line.add_theme_color_override("font_color", UiTheme.OK if bool(entry.get("success", false)) else UiTheme.BAD)
	col.add_child(line)
	if bool(entry.get("blocked", false)):
		var rep := Label.new()
		rep.text = "CHECK_REPEAT"
		rep.theme_type_variation = UiTheme.MUTED_LABEL
		col.add_child(rep)
	for found: Variant in entry.get("revealed", []):
		var f := Label.new()
		f.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size = Vector2(520, 0)
		f.text = tr("CHECK_FOUND").format({"what": found})
		f.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
		col.add_child(f)
	var reason := str(entry.get("advantage_reason", ""))
	if not reason.is_empty():
		var adv := Label.new()
		adv.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		adv.theme_type_variation = UiTheme.MUTED_LABEL
		adv.text = tr("CHECK_ADVANTAGE").format({"reason": reason})
		col.add_child(adv)


func text_for(e: Dictionary) -> String:
	var skill := str(e.get("skill", ""))
	var what := tr("SKILL_" + skill.to_upper()) if not skill.is_empty() else tr("SAVE_" + str(e.get("save", "")).to_upper())
	var rolls: Array = e.get("rolls", [])
	var dice := str(int(e.get("nat", 0))) if rolls.size() <= 1 else "%s→%d" % [", ".join(rolls.map(func(r: Variant) -> String: return str(int(r)))), int(e.get("nat", 0))]
	return tr("CHECK_LINE").format({
		"what": what, "roll": dice, "bonus": ("+ %d" if int(e.get("bonus", 0)) >= 0 else "− %d") % absi(int(e.get("bonus", 0))), "total": int(e.get("total", 0)),
		"dc": int(e.get("dc", 0)), "mark": "✓" if bool(e.get("success", false)) else "✗",
	})
