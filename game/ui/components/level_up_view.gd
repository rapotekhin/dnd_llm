class_name LevelUpView
extends Control

const WIDE := 1300.0
const COMPACT := 620.0
## The level-up screen over the game (roadmap v0.5.4): what the next level brings (HP by the average, new
## features) and the picks it needs — subclass, feature options, expertise, ability increase, spells.
## Rules and checks are LevelUp's; «Подтвердить» calls GameState.level_up.

var picks := {}
var _box: VBoxContainer
var confirm: Button
var frame: ModalFrame
## The rules text of the hovered choice (v0.6.6); hidden when the level has nothing to choose (О3).
var _info: DetailsPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make("", WIDE)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	var mid := HBoxContainer.new()  # the choices on the left, what the picked one does on the right (big test #36)
	mid.add_theme_constant_override("separation", 16)
	frame.body.add_child(mid)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	mid.add_child(_box)
	_info = DetailsPanel.new(Vector2(480, 320))
	_info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_info.show_text(tr("INFO_HINT"), "")
	mid.add_child(_info)
	frame.add_button("BTN_LATER", func() -> void: visible = false)
	confirm = frame.add_button("BTN_LEVEL_UP_CONFIRM", _on_confirm, true)
	confirm.name = "LevelUpConfirm"
	frame.note.name = "LevelUpError"
	visibility_changed.connect(func() -> void:
		if visible:
			picks = {}
		_rebuild())


func open() -> void:
	visible = true


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	var c := GameState.session.character
	var data := Catalog.data
	if not LevelUp.can_level_up(c, data):
		visible = false
		return
	var p := LevelUp.plan(c, data, picks)
	var feats: Dictionary = data["classes"]["features"]
	var choices := bool(p["subclass"]) or not (p["options"] as Array).is_empty() or int(p["expertise"]) > 0 or bool(p["asi"]) \
		or int(p["cantrips"]) > 0 or int(p["spells"]) > 0 or int(p["prepared"]) > 0
	frame.set_width(WIDE if choices else COMPACT)  # a level with nothing to pick is a small window (О3)
	_info.visible = choices
	frame.title.text = tr("LVL_TITLE").format({"level": p["level"], "class": c.get("class_name", "")})
	_text(tr("LVL_HP").format({"gain": p["hp_gain"]}), "")
	var names: Array = (p["features"] as Array).map(func(f: String) -> String: return str(feats.get(f, {}).get("name", f)))
	if not names.is_empty():
		_text(tr("LVL_FEATURES").format({"list": ", ".join(names)}), "")
	if int(p["max_spell_level"]) > 0:
		var slots: Array = CharacterRules.class_def(c, data)["levels"][str(p["level"])].get("slots", [])
		_text(tr("LVL_SLOTS").format({"list": ", ".join(range(slots.size()).filter(func(i: int) -> bool: return int(slots[i]) > 0)
			.map(func(i: int) -> String: return "%d круг ×%d" % [i + 1, int(slots[i])]))}), UiTheme.MUTED_LABEL)

	if bool(p["subclass"]):
		var subs: Dictionary = data["classes"]["subclasses"]
		_choice("LVL_SUBCLASS", "subclass", p["subclasses"], func(id: String) -> String: return str(subs.get(id, {}).get("name", id)), 1,
			[str(picks["subclass"])] if picks.has("subclass") else [], func(sel: Array) -> void:
				if sel.is_empty():
					picks.erase("subclass")
				else:
					picks["subclass"] = sel[0]
				picks.erase("options"))
	for o: Dictionary in p["options"]:
		var fid := str(o["id"])
		var chosen: Array = picks.get("options", {}).get(fid, [])
		_choice_text(tr("LVL_OPTION").format({"name": o["name"], "n": o["choose"]}), "opt_" + fid, o["from"],
			func(id: String) -> String: return str(feats.get(id, {}).get("name", id)), int(o["choose"]), chosen,
			func(sel: Array) -> void:
				var opts: Dictionary = picks.get("options", {})
				opts[fid] = sel
				picks["options"] = opts)
	if int(p["expertise"]) > 0:
		var pool := (c.get("skill_profs", []) as Array).filter(func(s: Variant) -> bool: return not (c.get("expertise", []) as Array).has(s))
		_choice_text(tr("LVL_EXPERTISE").format({"n": p["expertise"]}), "exp", pool,
			func(id: String) -> String: return tr("SKILL_" + id.to_upper()), int(p["expertise"]), picks.get("expertise", []),
			func(sel: Array) -> void: picks["expertise"] = sel)
	if bool(p["asi"]):
		_asi(c)
	var spells: Dictionary = data["spells"]
	var spell_name := func(id: String) -> String:  # the circle is the group's heading (v0.7.22.21)
		return str(spells.get(id, {}).get("name", id))
	if int(p["cantrips"]) > 0:
		_choice_text(tr("LVL_CANTRIPS").format({"n": p["cantrips"]}), "cantrip", p["cantrip_list"], spell_name, int(p["cantrips"]),
			picks.get("cantrips", []), func(sel: Array) -> void: picks["cantrips"] = sel)
	if int(p["spells"]) > 0:
		_choice_text(tr("LVL_SPELLS_SPELLBOOK" if p["spell_mode"] == "spellbook" else "LVL_SPELLS").format({"n": p["spells"]}), "spell",
			p["spell_list"], spell_name, int(p["spells"]), picks.get("spells", []), func(sel: Array) -> void:
				picks["spells"] = sel
				picks.erase("prepared"))
	var prep := mini(int(p["prepared"]), (p["prepared_list"] as Array).size())
	if prep > 0:
		_choice_text(tr("LVL_PREPARED").format({"n": prep}), "prep", p["prepared_list"], spell_name, prep,
			picks.get("prepared", []), func(sel: Array) -> void: picks["prepared"] = sel)

	var errs := LevelUp.errors(c, data, _clean(p))
	frame.set_note(tr(errs[0]) if not errs.is_empty() else "")
	confirm.disabled = not errs.is_empty() or GameState.is_busy()


## Picks without empty lists the plan does not ask for (errors() wants exact counts).
func _clean(p: Dictionary) -> Dictionary:
	var out := picks.duplicate(true)
	for key: String in ["cantrips", "spells", "prepared", "expertise"]:
		if not out.has(key):
			out[key] = []
	if not bool(p["asi"]):
		out.erase("asi")
	return out


func _text(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _choice(title_key: String, group: String, ids: Array, label: Callable, n: int, chosen: Array, on_change: Callable) -> void:
	_choice_text(tr(title_key), group, ids, label, n, chosen, on_change)


## A «pick n of these» list of checkboxes; a full list ignores more ticks (a single pick switches instead).
func _choice_text(title: String, group: String, ids: Array, label: Callable, n: int, chosen: Array, on_change: Callable) -> void:
	_box.add_child(HSeparator.new())
	_text(title, "").add_theme_color_override("font_color", UiTheme.ACCENT)
	var spells: Dictionary = Catalog.data["spells"]
	var all_spells := not ids.is_empty() and ids.all(func(x: Variant) -> bool: return spells.has(str(x)))
	var order := ids.duplicate()
	if all_spells:  # v0.7.22.21 (#20): spells by circle, framed by school
		order.sort_custom(func(a: Variant, b: Variant) -> bool:
			var la := int(spells[str(a)].get("level", 0))
			var lb := int(spells[str(b)].get("level", 0))
			return la < lb or (la == lb and str(spells[str(a)]["name"]) < str(spells[str(b)]["name"])))
	var flow: HFlowContainer = null
	var circle := -1
	for id: Variant in order:
		var lv := int(spells.get(str(id), {}).get("level", 0)) if all_spells else 0
		if flow == null or (all_spells and lv != circle):
			circle = lv
			if all_spells:
				_text(tr("DETAILS_CANTRIP") if lv == 0 else tr("DETAILS_CIRCLE").format({"n": lv}), UiTheme.MUTED_LABEL)
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 16)
			_box.add_child(flow)
		var cb := CheckBox.new()
		cb.name = "Pick_%s_%s" % [group, id]
		cb.text = label.call(str(id))
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.button_pressed = chosen.has(id)
		InfoBox.hook(cb, _info, cb.text, _tip(str(id)))
		if all_spells:
			UiTheme.school_frame(cb, str(spells[str(id)].get("school_id", "")))
		cb.toggled.connect(func(on: bool) -> void:
			var sel := chosen.duplicate()
			if on and not sel.has(id):
				if n == 1:
					sel = [id]
				elif sel.size() < n:
					sel.append(id)
			elif not on:
				sel.erase(id)
			on_change.call(sel)
			_rebuild.call_deferred())
		flow.add_child(cb)


## The rules text of a spell, feature or subclass for the info column: a spell with its circle, time, range and
## duration; a feature with the spells it gives (big test #18, v0.7.22.5).
func _tip(id: String) -> String:
	var data := Catalog.data
	if data["classes"]["subclasses"].has(id):
		return InfoBox.subclass_text(data, id)
	if data["spells"].has(id):
		return DetailsPanel.spell_text(data, id)
	var f: Dictionary = data["classes"]["features"].get(id, {})
	if f.is_empty():
		return ""
	var out := str(f.get("desc", f.get("flavor", "")))
	for sid: Variant in data["rules"].get("feature_spells", {}).get(id, []):
		out += "\n\n%s (по желанию, без ячейки)\n%s" % [data["spells"].get(str(sid), {}).get("name", sid), DetailsPanel.spell_text(data, str(sid))]
	return out


func _asi(c: Dictionary) -> void:
	_box.add_child(HSeparator.new())
	_text(tr("LVL_ASI"), "").add_theme_color_override("font_color", UiTheme.ACCENT)
	var asi: Dictionary = picks.get("asi", {})
	var used := 0
	for a: String in asi:
		used += int(asi[a])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	_box.add_child(grid)
	for a: String in CharacterRules.ABILITIES:
		var score := int(c["abilities"].get(a, 10))
		var add := int(asi.get(a, 0))
		var name_l := Label.new()
		name_l.text = tr("ABILITY_" + a.to_upper())
		grid.add_child(name_l)
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.text = "%d → %d" % [score, score + add] if add > 0 else str(score)
		grid.add_child(value)
		var minus := Button.new()
		minus.name = "Asi_minus_" + a
		minus.text = "−"
		minus.disabled = add <= 0
		minus.pressed.connect(_asi_change.bind(a, -1))
		grid.add_child(minus)
		var plus := Button.new()
		plus.name = "Asi_plus_" + a
		plus.text = "+"
		plus.disabled = used >= 2 or add >= 2 or score + add >= 20
		plus.pressed.connect(_asi_change.bind(a, 1))
		grid.add_child(plus)


func _asi_change(a: String, delta: int) -> void:
	var asi: Dictionary = picks.get("asi", {})
	var v := int(asi.get(a, 0)) + delta
	if v <= 0:
		asi.erase(a)
	else:
		asi[a] = v
	picks["asi"] = asi
	_rebuild()


func _on_confirm() -> void:
	var err := GameState.level_up(_clean(LevelUp.plan(GameState.session.character, Catalog.data, picks)))
	if err.is_empty():
		visible = false
	else:
		frame.set_note(tr(err))
