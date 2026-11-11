class_name EffectChips
extends HFlowContainer
## The hero's conditions, boons, exhaustion and concentration as chips with the time left (v0.7.8, the author: «chips
## everywhere — the sheet, over the input, the hero's card in a fight»); the tooltip says where it came from and what it
## does. Data — ConditionRules.shown; call refresh() after a state change.


var compact := false  ## small chips with the name only; the time and the cause go to the meta for a panel (v0.7.22.30)
var icons := 0  ## icons of this side instead of chips (v0.8.4.43.4, as in BG3): the name, the time and the cause at the cursor
var who: Dictionary = {}  ## whose statuses: the hero when empty, else `who` of Sheet (a companion)


func _init() -> void:
	name = "EffectChips"
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 6)


func refresh() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	visible = false
	if not GameState.has_session():
		return
	var list := ConditionRules.shown(GameState.session, Catalog.data, Sheet.HERO if who.is_empty() else who)
	visible = not list.is_empty()
	for e: Dictionary in list:
		if icons > 0:
			_icon(e)
			continue
		var chip := PanelContainer.new()
		chip.name = "Chip_" + (str(e["condition"]) if not str(e["condition"]).is_empty() else "boon")
		chip.theme_type_variation = UiTheme.CARD
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var tip: Array[String] = []
		if not str(e["source"]).is_empty():
			tip.append(tr("EFFECT_SOURCE").format({"source": e["source"]}))
		if not str(e["text"]).is_empty():
			tip.append(str(e["text"]))
		chip.tooltip_text = "\n".join(tip)
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = "%s · %s" % [e["name"], e["left"]]
		if compact:
			chip.set_meta("title", str(e["name"]))
			chip.set_meta("about", "%s\n%s" % [e["left"], chip.tooltip_text])
			chip.tooltip_text = ""
			l.text = str(e["name"])
			l.add_theme_font_size_override("font_size", 16)
		var cond := str(e["condition"])
		l.add_theme_color_override("font_color", UiTheme.ACCENT if cond.is_empty() else UiTheme.MUTED if cond == "concentration" else UiTheme.WARN)
		chip.add_child(l)
		add_child(chip)


## A status as an icon (v0.8.4.43.4): «Отравлен · 1 ч» is its line, the cause and what it does the card's body.
func _icon(e: Dictionary) -> void:
	var cond := str(e["condition"])
	var cell := IconSlot.make(str(e.get("icon", IconRules.ref("conditions", cond))), "%s · %s" % [e["name"], e["left"]], icons)
	cell.name = "Chip_" + (cond if not cond.is_empty() else "boon")
	cell.tip_title = str(e["name"])
	cell.tooltip_text = str(e["left"])
	var body: Array[String] = []
	if not str(e["source"]).is_empty():
		body.append(tr("EFFECT_SOURCE").format({"source": e["source"]}))
	if not str(e["text"]).is_empty():
		body.append(str(e["text"]))
	cell.tip_body = "\n".join(body)
	if e.has("count"):
		cell.badge = str(e["count"])
	cell.focus_mode = Control.FOCUS_NONE
	add_child(cell)
