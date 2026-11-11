class_name UiParts
extends RefCounted
## The small parts every window builds (v0.8.4.19): a line of the game's text, a heading, the button of an act, an HP bar.
## A window takes them from here and keeps no copy of its own.


## A wrapped line of the game's own words (never translated) in `parent`; with a null parent it is only made.
## The words of a thing's acts (`PropRules.acts`): one table for the place window and the map's menu (v0.8.4.43.4).
const THING_ACTS := {"read": "BTN_BOARD_READ", "open": "BTN_OPEN_SHORT", "take": "BTN_TAKE", "look": "BTN_LOOK_AT"}


## A line of a window: it wraps and fills the width; `fit` — as wide as its words, in one line (a caption beside icons).
static func label(parent: Control, text: String, variation: String = "", fit := false) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_OFF if fit else TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if fit else Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	if parent != null:
		parent.add_child(l)
	return l


static func heading(parent: Control, text: String) -> Label:
	return label(parent, text, UiTheme.ACCENT_LABEL)


## The line under a partner's name: role, race, build and height, attitude and the bond (v0.8.4.29.6: the talk and the trade).
static func partner_line(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var npc := WorldView.new(data["world"]).npc(npc_id)
	var line := TranslationServer.translate("PARTNER_LINE").format({"role": npc.get("role", ""), "race": npc.get("race", ""),
		"body": BodyRules.npc_text(data, npc_id, npc), "attitude": GameSession.attitude_word(data, s.attitude(npc_id))})
	var bw := BondRules.word(s.character, data, npc_id)  # v0.7.31
	return line + (" · " + bw if not bw.is_empty() else "")


## The button of an act: grey with its reason on the hover while `why` is a key or the game is busy; `action` gives ""
## or the key of a refusal, which goes to the message line.
static func act_button(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = str(TranslationServer.translate(why)) if not why.is_empty() else ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		var err: Variant = action.call()
		if err is String and not (err as String).is_empty():
			EventBus.message.emit(str(TranslationServer.translate(err))))
	parent.add_child(b)
	return b


## «Осмотреть» (v0.8.4.41): the card of a person, a creature or a foe (CreatureCardPanel) — a look only, so it stays open
## while the master thinks and needs no walk up.
static func card_button(parent: Control, id: String) -> Button:
	var b := Button.new()
	b.name = "Card_" + id
	b.text = TranslationServer.translate("BTN_CARD")
	b.tooltip_text = TranslationServer.translate("BTN_CARD_TIP")
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: EventBus.card_requested.emit(id))
	parent.add_child(b)
	return b


## A line of a fight's rolls: a hit is red (the damage), a miss grey; its breakdown on the hover (v0.7.49.4).
static func roll_line(parent: Control, text: String, tip: String = "") -> Label:
	var l := label(parent, text, UiTheme.MUTED_LABEL)
	if text.contains("— промах") or text.contains("— провал"):
		l.add_theme_color_override("font_color", UiTheme.MUTED.darkened(0.25))
	elif text.contains("— попадание") or text.contains("критическ"):
		l.add_theme_color_override("font_color", UiTheme.BAD)
	if not tip.is_empty():
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## The height of the first `n` rows of a list as they are drawn — fonts, margins and the interface size included; a list
## of more scrolls under it (v0.8.4.43.9: a fixed 38 px a row showed two and a half ways out of three).
static func rows_height(list: BoxContainer, n: int) -> float:
	var rows := list.get_children().filter(func(r: Node) -> bool: return r is Control and (r as Control).visible).slice(0, n)
	var h := 0.0
	for r: Control in rows:
		h += r.get_combined_minimum_size().y
	return h + list.get_theme_constant("separation") * maxi(0, rows.size() - 1)


## «Броски раунда (n)» (Б6): a round's rolls under a fold — the head opens and shuts its lines. The fight's log and the
## chat after the fight (v0.8.4.21.1) build it here.
static func rolls_block(folded: bool) -> VBoxContainer:
	var block := VBoxContainer.new()
	var head := Button.new()
	head.name = "Head"
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_theme_color_override("font_color", UiTheme.MUTED)
	block.add_child(head)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.add_theme_constant_override("separation", 4)
	block.add_child(lines)
	head.pressed.connect(func() -> void: fold_rolls(block, lines.visible))
	fold_rolls(block, folded)
	return block


static func fold_rolls(block: VBoxContainer, folded: bool) -> void:
	var lines := block.get_node("Lines")
	lines.visible = not folded
	(block.get_node("Head") as Button).text = TranslationServer.translate("COMBAT_ROLLS").format(
		{"n": lines.get_child_count(), "fold": "▸" if folded else "▾"})


## An HP bar: green, yellow, red by the share left (Б2).
## The HP bar with the temporary hit points as a blue piece of their own after it, in proportion (v0.8.4.30: one bar for
## the side panel, the hero's portrait and a foe's card, in a fight and out of it).
static func hp_line(value: int, most: int, temp: int, height: float = 14.0, corner: int = 3) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := hp_bar(value, most, height, corner)
	bar.name = "Hp"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio = maxf(1.0, most)
	row.add_child(bar)
	if temp > 0:
		var tb := ProgressBar.new()
		tb.name = "TempHp"
		tb.max_value = 1
		tb.value = 1
		tb.show_percentage = false
		tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tb.custom_minimum_size = Vector2(0, height)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.size_flags_stretch_ratio = float(temp)
		tb.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.TEMP_HP, UiTheme.TEMP_HP, 0, 0, corner))
		tb.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, corner))
		row.add_child(tb)
	return row


static func hp_bar(value: int, most: int, height: float = 14.0, corner: int = 3) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, most)
	bar.value = clampi(value, 0, maxi(1, most))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiTheme.hp_color(float(value) / maxf(1.0, most))
	bar.add_theme_stylebox_override("fill", UiTheme.box(col, col, 0, 0, corner))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, corner))
	return bar
