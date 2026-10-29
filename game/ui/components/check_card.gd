class_name CheckCard
extends PanelContainer
## Roll card after an engine check (ADR-0008 §2): «Внимательность: 12 + 3 = 15 против DC 15 ✓», with what it
## found, the repeat mark and the haggle outcome.

var entry: Dictionary


func _init(check_entry: Dictionary) -> void:
	entry = check_entry


func _ready() -> void:
	theme_type_variation = UiTheme.CARD
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tooltip_text = breakdown(entry)  # every part of the bonus on hover (v0.7.39.5)
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
	if entry.has("haggle_pct"):
		var h := Label.new()
		h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var pct := int(entry["haggle_pct"])
		h.text = tr("CHECK_HAGGLE_WON").format({"pct": pct}) if pct > 0 else tr("CHECK_HAGGLE_LOST")
		h.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT if pct > 0 else UiTheme.MUTED)
		col.add_child(h)
	for found: Variant in entry.get("revealed", []):
		var f := Label.new()
		f.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size = Vector2(520, 0)
		f.text = tr("CHECK_FOUND").format({"what": found})
		f.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
		col.add_child(f)
	if not str(entry.get("difficulty_note", "")).is_empty():  # v0.7.20.4: the game's difficulty in the total
		var diff := Label.new()
		diff.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		diff.theme_type_variation = UiTheme.MUTED_LABEL
		diff.text = tr("CHECK_DIFFICULTY").format({"note": entry["difficulty_note"]})
		col.add_child(diff)
	if not str(entry.get("dc_reason", "")).is_empty():  # v0.7.15.1: the DC of a social check by the NPC
		var why := Label.new()
		why.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		why.theme_type_variation = UiTheme.MUTED_LABEL
		why.text = tr("CHECK_DC_REASON").format({"dc": int(entry.get("dc", 0)), "reason": entry["dc_reason"]})
		col.add_child(why)
	for key: String in ["disadvantage_reason", "auto_fail_reason"]:
		if not str(entry.get(key, "")).is_empty():
			var l := Label.new()
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			l.theme_type_variation = UiTheme.MUTED_LABEL
			l.add_theme_color_override("font_color", UiTheme.WARN)
			l.text = tr("CHECK_" + key.trim_suffix("_reason").to_upper()).format({"reason": entry[key]})
			col.add_child(l)
	var reason := str(entry.get("advantage_reason", ""))
	if not reason.is_empty():
		var adv := Label.new()
		adv.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		adv.theme_type_variation = UiTheme.MUTED_LABEL
		adv.text = tr("CHECK_ADVANTAGE").format({"reason": reason})
		col.add_child(adv)


## The roll's breakdown: the dice, each labelled part, the total against the DC ("" for an old entry without parts).
static func breakdown(e: Dictionary) -> String:
	if not e.has("parts"):
		return ""
	return RollParts.text({"rolls": e.get("rolls", []), "nat": e.get("nat", 0), "parts": e["parts"], "total": e.get("total", 0), "dc": e.get("dc", 0)})


func text_for(e: Dictionary) -> String:
	var skill := str(e.get("skill", ""))
	var what := tr("SKILL_" + skill.to_upper()) if not skill.is_empty() else tr("ABILITY_" + str(e["ability"]).to_upper()) 		if not str(e.get("ability", "")).is_empty() else tr("SAVE_" + str(e.get("save", "")).to_upper())
	var rolls: Array = e.get("rolls", [])
	var dice := str(int(e.get("nat", 0))) if rolls.size() <= 1 else "%s→%d" % [", ".join(rolls.map(func(r: Variant) -> String: return str(int(r)))), int(e.get("nat", 0))]
	return tr("CHECK_LINE").format({
		"what": what, "roll": dice, "bonus": ("+ %d" if int(e.get("bonus", 0)) >= 0 else "− %d") % absi(int(e.get("bonus", 0))), "total": int(e.get("total", 0)),
		"dc": int(e.get("dc", 0)), "mark": "✓" if bool(e.get("success", false)) else "✗",
	})
