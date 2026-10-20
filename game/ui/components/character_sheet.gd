class_name CharacterSheet
extends Control
## The character sheet over the game screen (roadmap v0.5.0): abilities, saves and skills; features, traits
## and spells; equipment with equip / unequip. Numbers come from the derived cache (CharacterRules.refresh).
## v0.6.0: «Использовать» for features with limited uses and consumables, «Колдовать» with a slot choice,
## «Подготовить заклинания» after a long rest. A cast or use closes the sheet: the master answers in the chat.

signal prepare_requested

var _tabs: TabContainer
var _picked_item := ""  # the item shown in the details panel of the gear tab (v0.7.7 fixes)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	var close := Button.new()
	close.name = "CloseSheetButton"
	close.text = "BTN_CLOSE"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	var current := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var c := GameState.session.character
	_tabs.add_child(_stats_tab(c))
	_tabs.add_child(_abilities_tab(c))
	_tabs.add_child(_gear_tab(c))
	_tabs.current_tab = clampi(current, 0, 2)


func _page(title_key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tr(title_key)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _text(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _stats_tab(c: Dictionary) -> Control:
	var box := _page("SHEET_TAB_STATS")
	var d := Catalog.data
	var sub: Dictionary = d["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	_text(box, str(c["name"]), UiTheme.HEADING)
	_text(box, tr("SHEET_LINE").format({"race": c["race_name"], "class": c["class_name"] + (" (%s)" % sub["name"] if not sub.is_empty() else ""),
		"level": c["level"], "background": d["backgrounds"].get(str(c["background"]), {}).get("name", "")}), UiTheme.MUTED_LABEL)
	_text(box, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) + ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""))
	var chips := EffectChips.new()  # conditions, boons, exhaustion, concentration (v0.7.8)
	box.add_child(chips)
	chips.refresh()
	var resist := HeroDefense.resistances(GameState.session, d)
	if not resist.is_empty():
		_text(box, tr("SHEET_RESIST").format({"list": ", ".join(resist.keys().map(func(t: Variant) -> String:
			return "%s (%s)" % [d["misc"]["damage_types"].get(str(t), t), resist[t]]))}))
	_text(box, tr("SHEET_PROF_SPEED").format({"prof": c["prof_bonus"], "speed": c["speed"]}) + " · " +
		tr("SHEET_PASSIVE").format({"n": c["passive_perception"]}))
	for hand: String in ["main_hand", "off_hand"]:
		var wid := str(c.get("equipped", {}).get(hand, ""))
		if hand == "off_hand" and wid.is_empty():
			continue
		var w := CombatRules.weapon_profile(c, d, GameState.session.items, wid, hand == "off_hand")
		var b := int(w["bonus"])
		_text(box, tr("SHEET_ATTACK").format({"name": w["name"], "hit": "%+d" % int(w["to_hit"]),
			"dmg": str(w["dice"]).replace("d", tr("DICE_D")) + (("%+d" % b) if b != 0 else "")}))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	box.add_child(row)
	var abil := VBoxContainer.new()
	abil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(abil)
	_text(abil, tr("SHEET_ABILITIES"), UiTheme.MUTED_LABEL)
	for a: String in CharacterRules.ABILITIES:
		var score := int(c["abilities"][a])
		var prof := " ●" if (c.get("save_profs", []) as Array).has(a) else ""
		_text(abil, tr("SHEET_ABILITY_ROW").format({"name": tr("ABILITY_" + a.to_upper()), "score": score,
			"mod": "%+d" % CharacterRules.mod(score), "save": "%+d" % int(c["saves"][a])}) + prof)
	var skills := VBoxContainer.new()
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(skills)
	_text(skills, tr("SHEET_SKILLS"), UiTheme.MUTED_LABEL)
	var ids: Array = (d["rules"]["skills"] as Dictionary).keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return tr("SKILL_" + x.to_upper()) < tr("SKILL_" + y.to_upper()))
	for s: String in ids:
		var mark := " ●●" if (c.get("expertise", []) as Array).has(s) else (" ●" if (c.get("skill_profs", []) as Array).has(s) else "")
		_text(skills, "%s %+d%s" % [tr("SKILL_" + s.to_upper()), int(c["skills"][s]), mark])
	var langs: Array = (c.get("languages", []) as Array).map(func(l: Variant) -> String: return str(d["misc"]["languages"].get(str(l), {}).get("name", l)))
	_text(box, tr("SHEET_LANGUAGES").format({"list": ", ".join(langs)}), UiTheme.MUTED_LABEL)
	return box.get_parent()


func _abilities_tab(c: Dictionary) -> Control:
	var box := _page("SHEET_TAB_FEATURES")
	var d := Catalog.data
	var feats: Dictionary = d["classes"]["features"]
	var traits: Dictionary = d["races"]["traits"]
	for id: Variant in c.get("features", []):
		var f: Dictionary = feats.get(str(id), {})
		if not f.is_empty() and not f.has("options"):
			_entry(box, str(f["name"]), str(f.get("desc", "")))
	for id: Variant in c.get("traits", []):
		var t: Dictionary = traits.get(str(id), {})
		if not t.is_empty() and not t.has("options"):
			_entry(box, str(t["name"]), str(t.get("desc", "")))
	var bg: Dictionary = d["backgrounds"].get(str(c.get("background", "")), {})
	if not bg.is_empty():
		_entry(box, str(bg["feature"]["name"]), str(bg["feature"]["desc"]))
	var can_act := Backend.is_ready() and not GameState.is_busy()
	box.add_child(HSeparator.new())
	_text(box, tr("SHEET_HIT_DICE").format({"left": ExplorationRules.hit_dice_left(c), "max": int(c.get("level", 1))}), UiTheme.MUTED_LABEL)
	var res := FeatureUses.lines(c, d)
	if not res.is_empty():
		_text(box, tr("SHEET_RESOURCES"), UiTheme.MUTED_LABEL)
		for r: Dictionary in res:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			box.add_child(row)
			_text(row, tr("SHEET_RESOURCE").format({"name": r["name"], "left": r["left"], "max": r["max"],
				"rest": tr("REST_KIND_" + str(r["recharge"]).to_upper())}))
			if str(r["id"]) == "sorcery_points":  # Font of Magic: slots and points (v0.7.10)
				for o: Dictionary in FeatureRules.font_options(c, d):
					_action(row, "Font_" + str(o["id"]), str(o["label"]), can_act, GameState.font_convert.bind(str(o["id"])))
				continue
			_action(row, "Use_" + str(r["id"]), "BTN_USE", can_act and int(r["left"]) > 0, GameState.use_feature.bind(str(r["id"])))
	if str(c.get("spell_ability", "")).is_empty():
		return box.get_parent()
	box.add_child(HSeparator.new())
	_text(box, tr("SHEET_SPELLCASTING").format({"ability": tr("ABILITY_" + str(c["spell_ability"]).to_upper()),
		"dc": c.get("spell_dc", 0), "attack": "%+d" % int(c.get("spell_attack", 0))}))
	var slots: Array[String] = []
	for i in 5:
		var m := int(c["slots_max"][i])
		if m > 0:
			slots.append(tr("SHEET_SLOT").format({"level": i + 1, "left": m - int(c["slots_used"][i]), "max": m}))
	if not slots.is_empty():
		_text(box, " · ".join(slots), UiTheme.MUTED_LABEL)
	if not str(c.get("concentration", "")).is_empty():
		_text(box, tr("SHEET_CONCENTRATION").format({"spell": d["spells"].get(str(c["concentration"]), {}).get("name", "")}))
	if SpellRules.prepares(c, d):
		var why := SpellRules.can_prepare(c, d, GameState.session.day)
		var prep := Button.new()
		prep.name = "PrepareButton"
		prep.text = "BTN_PREPARE"
		prep.disabled = not why.is_empty() or GameState.is_busy()
		prep.tooltip_text = tr(why) if not why.is_empty() else ""
		prep.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		prep.pressed.connect(prepare_requested.emit)
		box.add_child(prep)
	var ready_ids := SpellRules.ready(c)
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "prepared", "always", "known"]:
		var ids: Array = sp.get(list, [])
		if list == "known" and ids == sp.get("prepared", []):
			continue
		if ids.is_empty():
			continue
		_text(box, tr("SHEET_SPELLS_" + list.to_upper()), UiTheme.MUTED_LABEL)
		for id: Variant in ids:
			var s: Dictionary = d["spells"].get(str(id), {})
			_entry(box, "%s — %s, %s, %s" % [s.get("name", id), s.get("casting_time", ""), s.get("range", ""), s.get("duration", "")], str(s.get("desc", "")))
			if list != "known" and ready_ids.has(str(id)):
				_cast_row(box, c, str(id), int(s.get("level", 0)), can_act)
	return box.get_parent()


## «Колдовать» with the slot circle to spend (the lowest fitting one first).
func _cast_row(parent: Control, c: Dictionary, id: String, level: int, can_act: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var pick := OptionButton.new()
	pick.name = "Slot_" + id
	pick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if level == 0:
		pick.add_item(tr("SLOT_CANTRIP"), 0)
	else:
		for lv in range(level, 6):
			var left := SpellRules.slots_left(c, lv)
			if left > 0:
				pick.add_item(tr("SLOT_CIRCLE").format({"n": lv, "left": left}), lv)
	row.add_child(pick)
	_action(row, "Cast_" + id, "BTN_CAST", can_act and pick.item_count > 0,
		func() -> String: return GameState.cast(id, pick.get_selected_id() if pick.item_count > 0 else 0))


## A button that calls `action` (returns "" or a reason): on success the sheet closes, otherwise a toast.
func _action(parent: Control, node_name: String, text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if err.is_empty():
			visible = false
		else:
			EventBus.message.emit(tr(err)))
	parent.add_child(b)


func _entry(parent: Control, title: String, body: String) -> void:
	_text(parent, title).add_theme_color_override("font_color", UiTheme.ACCENT)
	if not body.is_empty():
		_text(parent, body, UiTheme.MUTED_LABEL)


func _gear_tab(c: Dictionary) -> Control:
	var box := _page("SHEET_TAB_GEAR")
	var list_scroll := box.get_parent()
	var root := HBoxContainer.new()
	root.name = list_scroll.name
	root.add_theme_constant_override("separation", 16)
	list_scroll.name = "GearList"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(list_scroll)
	var details := DetailsPanel.new(Vector2(560, 0))
	details.name = "ItemDetails"
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(details)
	var s := GameState.session
	var items: Dictionary = Catalog.data["items"]
	var busy := GameState.is_busy()
	_text(box, tr("SHEET_EQUIPPED"), UiTheme.MUTED_LABEL)
	for slot: String in CharacterRules.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var id := str(c["equipped"].get(slot, ""))
		if id.is_empty():
			_text(row, "%s: —" % tr("SLOT_" + slot.to_upper()))
		else:
			_item_button(row, details, c, id, "%s: %s" % [tr("SLOT_" + slot.to_upper()), ItemRules.display_name(items, s.items, id)], "Slot_" + slot)
		if not id.is_empty():
			var b := Button.new()
			b.text = "BTN_UNEQUIP"
			b.name = "Unequip_" + slot
			b.disabled = busy
			b.pressed.connect(GameState.unequip.bind(slot))
			row.add_child(b)
	box.add_child(HSeparator.new())
	_text(box, tr("SIDE_COINS").format({"coins": Money.format(int(c["gold_cp"]))}))
	var weight := _text(box, tr("SHEET_WEIGHT").format({"n": int(ceilf(CharacterRules.carried_weight(c, Catalog.data, s.items))), "max": CharacterRules.capacity(c, Catalog.data)}),
		UiTheme.MUTED_LABEL)
	weight.name = "CarriedWeight"
	if CharacterRules.overloaded(c, Catalog.data, s.items):
		weight.text += " — " + tr("TOO_HEAVY")
		weight.add_theme_color_override("font_color", UiTheme.WARN)
	for id: String in c.get("inventory", {}):
		var def := ItemRules.def_of(items, s.items, id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var qty := int(c["inventory"][id])
		_item_button(row, details, c, id, "%s%s" % [def.get("name", id), " ×%d" % qty if qty > 1 else ""], "Item_" + id)
		if not ItemRules.consumable(Catalog.data, id).is_empty():
			_action(row, "UseItem_" + id, "BTN_USE", Backend.is_ready() and not busy, GameState.use_item.bind(id))
		var slot := CharacterRules.slot_for(def)
		var targets: Array[String] = []
		if not slot.is_empty():
			targets.append(slot)
		if slot == "main_hand" and (def.get("properties", []) as Array).has("light"):
			targets.append("off_hand")
		for t: String in targets:
			if str(c["equipped"].get(t, "")) == id:
				continue
			var why := CharacterRules.can_equip(c, Catalog.data, s.items, id, t)
			var b := Button.new()
			b.text = tr("BTN_EQUIP_" + t.to_upper())
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.name = "Equip_%s_%s" % [t, id]
			b.disabled = busy or not why.is_empty()
			if not why.is_empty():
				b.tooltip_text = tr(why)
			b.pressed.connect(func() -> void:
				var err := GameState.equip(id, t)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			row.add_child(b)
	var shown := _picked_item if (c.get("inventory", {}) as Dictionary).has(_picked_item) else ""
	if not shown.is_empty():
		details.show_text(ItemRules.display_name(items, s.items, shown), DetailsPanel.item_text(c, Catalog.data, s.items, shown))
	return root


## The item's name as a flat button: a click shows what it is in the details panel (v0.7.7 fixes).
func _item_button(row: Control, details: DetailsPanel, c: Dictionary, id: String, text: String, node_name: String) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == _picked_item:
		b.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	b.pressed.connect(func() -> void:
		_picked_item = id
		details.show_text(ItemRules.display_name(Catalog.data["items"], GameState.session.items, id), DetailsPanel.item_text(c, Catalog.data, GameState.session.items, id)))
	row.add_child(b)
