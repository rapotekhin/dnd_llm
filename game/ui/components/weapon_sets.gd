class_name WeaponSets
extends HBoxContainer
## The two weapon sets of the hero (v0.8.4.1, as in BG3): the one in the hands is lit, a click on the other brings it to
## hand for nothing. Under the hero on the panel, in a fight and out of it; the key is `swap_weapons`.


func _init() -> void:
	name = "WeaponSets"
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	var s := GameState.session
	var c := s.character
	var why := Acts.one("swap").can(s, Catalog.data, Sheet.HERO)
	var held := _button("WeaponSetHeld", _label(c, c.get("equipped", {})), CharacterRules.hands_kind(c.get("equipped", {}), Catalog.data, s.items))
	held.theme_type_variation = UiTheme.ACCENT_BUTTON
	held.mouse_filter = Control.MOUSE_FILTER_IGNORE  # lit, not a button: disabled would grey it out
	var other := _button("WeaponSetStowed", _label(c, CharacterRules.stowed(c)), CharacterRules.hands_kind(CharacterRules.stowed(c), Catalog.data, s.items))
	other.disabled = not why.is_empty()
	other.tooltip_text = Hotkeys.tip(tr("SWAP_WEAPONS"), "swap_weapons", SaveManager.keys) if why.is_empty() else tr(why)
	other.pressed.connect(func() -> void:
		var err := GameState.swap_weapons()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))


func _button(node_name: String, text: String, kind: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tr("SET_" + kind.to_upper()) if not kind.is_empty() else ""  # by what the set holds (v0.8.4.24.1)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 32)
	add_child(b)
	return b


func _label(c: Dictionary, hands: Dictionary) -> String:
	for slot: String in CharacterRules.HANDS:
		var id := str(hands.get(slot, ""))
		if not id.is_empty():
			var name := ItemRules.display_name(Catalog.data["items"], GameState.session.items, id)
			var shots := Gear.ready_shots(Catalog.data, GameState.session.items, c, id)
			return name if shots < 0 else "%s · %d" % [name, shots]  # v0.8.4.42.6: the shots at hand
	return "—"
