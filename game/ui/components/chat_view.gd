class_name ChatView
extends ScrollContainer
## The session chat: master narration (serif), player lines (italic accent), check cards, engine notices.
## Rebuilt from GameState.session on creation, then appended entry by entry; follows the bottom.
## The story leads; the engine's lines (`GameSession.ENGINE_KINDS`) are quiet, and a repeat of one is its own line
## counted «×N», rebuilt where it stands (v0.8.4.43.5.1).

signal image_requested(path: String)  ## the link of an event's image (v0.7.35)

## One look per kind of a text line (v0.8.4.43.5.1): the story in Literata, the engine's lines all alike and quiet.
const STYLE := {
	GameSession.KIND_DM: UiTheme.DM_TEXT, GameSession.KIND_PLAYER: UiTheme.PLAYER_TEXT, GameSession.KIND_NPC: UiTheme.NPC_TEXT,
	GameSession.KIND_EFFECT: UiTheme.ENGINE_TEXT, GameSession.KIND_SYSTEM: UiTheme.ENGINE_TEXT,
}

var _list: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	add_child(_list)
	if GameState.has_session():
		for e: Dictionary in GameState.session.chat:
			_add(e)
	EventBus.chat_appended.connect(_on_appended)
	EventBus.image_drawn.connect(_on_image)
	_scroll_to_end.call_deferred()


func _on_appended(entry: Dictionary) -> void:
	var line := _line_of(entry)
	if line == null:
		_add(entry)
	else:  # the engine said its line again: the same line, its count grown
		var fresh := _line(entry)
		_list.add_child(fresh)
		_list.move_child(fresh, line.get_index())
		_list.remove_child(line)
		line.queue_free()
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)


func _add(e: Dictionary) -> void:
	_list.add_child(_line(e))
	if str(e.get("kind", "")) in [GameSession.KIND_DM, GameSession.KIND_NPC] and not ImageFrame.image_of(e).is_empty():
		_link_after(_list.get_child(_list.get_child_count() - 1), e)


## The node of an entry by its kind; the entry rides on it, so a new image or a repeat finds its place.
func _line(e: Dictionary) -> Control:
	var kind := str(e.get("kind", ""))
	var line: Control
	match kind:
		GameSession.KIND_DM:
			line = _text(str(e.get("text", "")), STYLE[kind])
		GameSession.KIND_PLAYER:
			line = _text("— " + str(e.get("text", "")), STYLE[kind])
		GameSession.KIND_NPC:
			# The master writes the line with its own remarks and quotes; only the speaker is added.
			line = _text("%s — %s" % [e.get("name", ""), without_name(str(e.get("text", "")), str(e.get("name", "")))], STYLE[kind])
		GameSession.KIND_EFFECT:
			line = _text(GameSession.counted(" · ".join(e.get("lines", [])), e), STYLE[kind])
			line.tooltip_text = RollParts.entry_text(e)  # the rolls of the line on hover (v0.7.39.5), of every repeat
		GameSession.KIND_CHECK:
			line = CheckCard.new(e)
		GameSession.KIND_SYSTEM:
			line = _text(GameSession.counted(tr(str(e.get("key", ""))).format(e.get("args", {})), e), STYLE[kind])
		GameSession.KIND_ROLLS:  # a fight's round, folded as in the fight (v0.8.4.21.1)
			var block := UiParts.rolls_block(true)
			block.set_meta("rolls", true)
			var tips: Dictionary = e.get("tips", {})
			for l: Variant in e.get("lines", []):
				UiParts.roll_line(block.get_node("Lines"), str(l), str(tips.get(str(l), "")))
			UiParts.fold_rolls(block, true)
			line = block
		_:
			line = _text(str(e.get("text", "")), UiTheme.ENGINE_TEXT)
	line.set_meta("entry", e)
	return line


func _line_of(entry: Dictionary) -> Node:
	for line in _list.get_children():
		if line.has_meta("entry") and is_same(line.get_meta("entry"), entry):
			return line
	return null


func _on_image(entry: Dictionary) -> void:
	var line := _line_of(entry)
	if line != null:
		var i := line.get_index() + 1
		if i >= _list.get_child_count() or not _list.get_child(i).has_meta("image_link"):
			_link_after(line, entry)


## «Картинка» under an event that has one.
func _link_after(line: Node, e: Dictionary) -> void:
	var b := Button.new()
	b.name = "ImageLink"
	b.set_meta("image_link", true)
	b.text = "BTN_CHAT_IMAGE"
	b.flat = true
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void: image_requested.emit(ImageFrame.image_of(e)))
	_list.add_child(b)
	_list.move_child(b, line.get_index() + 1)


## A chat line (v0.6.6, playtest-1): selectable and copyable; the master's **bold**, names of people and places and
## «speech» are marked up. Chat text comes from the model and the player: never a translation key, never raw BBCode.
func _text(text: String, variation: String) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.selection_enabled = true
	l.context_menu_enabled = true
	l.theme_type_variation = variation + UiTheme.RICH
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = rich(text, _names()) if variation in [UiTheme.DM_TEXT, UiTheme.NPC_TEXT] else rich(text, [])
	return l


static var _name_rx: Array[RegEx] = []


## Patterns of the pack's people and places, stems that catch Russian endings («Бруно Хмелю», «в Ольховом Броде»).
func _names() -> Array[RegEx]:
	if _name_rx.is_empty() and not Catalog.data.is_empty():
		var w: Dictionary = Catalog.data.get("world", {})
		var names: Array[String] = []
		for n: Dictionary in w.get("npcs", {}).values():
			names.append(str(n.get("name", "")))
		for l: Dictionary in w.get("locations", {}).values():
			names.append(str(l.get("name", "")))
		names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
		for n: String in names:
			var parts: Array[String] = []
			for word: String in n.replace("«", "").replace("»", "").split(" ", false):
				parts.append(_stem(word))
			if parts.is_empty():
				continue
			var rx := RegEx.new()
			if rx.compile("(?<![\\p{L}])" + "\\s+".join(parts) + "(?![\\p{L}])") == OK:
				_name_rx.append(rx)
	return _name_rx


static func _stem(word: String) -> String:
	var w := word.strip_edges()
	var base := w.left(w.length() - 2) if w.length() > 5 else w.left(w.length() - 1) if w.length() > 3 else w
	return _escape(base) + ("\\p{L}{0,3}" if base != w else "")


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in ".^$|()[]{}*+?\\" else ch
	return out


## Plain text → BBCode: [ escaped, names in colour, **bold**, «speech» in its colour.
static func rich(text: String, names: Array[RegEx]) -> String:
	var t := text.replace("[", "[lb]")
	for rx: RegEx in names:
		t = rx.sub(t, "[color=#%s]$0[/color]" % UiTheme.NAME_COLOR.to_html(false), true)
	var bold := RegEx.new()
	bold.compile("\\*\\*(.+?)\\*\\*")
	t = bold.sub(t, "[b]$1[/b]", true)
	var italic := RegEx.new()
	italic.compile("(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)")
	t = italic.sub(t, "[i]$1[/i]", true)
	var speech := RegEx.new()
	speech.compile("«[^»]*»")
	t = speech.sub(t, "[color=#%s]$0[/color]" % UiTheme.SPEECH_COLOR.to_html(false), true)
	return t


## The line without the speaker's name in front (the card is already signed): «Бруно Хмель понижает голос» →
## «понижает голос»; the first name alone too (v0.6.5, playtest-1).
static func without_name(text: String, name: String) -> String:
	var lead := "*" if text.begins_with("*") else ""  # «*Бруно откладывает кружку…*» keeps its remark mark
	var body := text.substr(lead.length())
	for n: String in [name, name.get_slice(" ", 0)]:
		if not n.is_empty() and body.begins_with(n + " "):
			return lead + body.substr(n.length()).lstrip(" —–-:,")
	return text

