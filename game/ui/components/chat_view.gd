class_name ChatView
extends ScrollContainer
## The session chat: master narration (serif), player lines (italic accent), check cards, engine notices.
## Rebuilt from GameState.session on creation, then appended entry by entry; follows the bottom.

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
	_scroll_to_end.call_deferred()


func entry_count() -> int:
	return _list.get_child_count()


func _on_appended(entry: Dictionary) -> void:
	_add(entry)
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)


func _add(e: Dictionary) -> void:
	match str(e.get("kind", "")):
		GameSession.KIND_DM:
			_list.add_child(_text(str(e.get("text", "")), UiTheme.DM_TEXT))
		GameSession.KIND_PLAYER:
			_list.add_child(_text("— " + str(e.get("text", "")), UiTheme.PLAYER_TEXT))
		GameSession.KIND_NPC:
			# The master writes the line with its own remarks and quotes; only the speaker is added.
			_list.add_child(_text("%s — %s" % [e.get("name", ""), without_name(str(e.get("text", "")), str(e.get("name", "")))], UiTheme.NPC_TEXT))
		GameSession.KIND_EFFECT:
			_list.add_child(_text(" · ".join(e.get("lines", [])), UiTheme.EFFECT_TEXT))
		GameSession.KIND_CHECK:
			_list.add_child(CheckCard.new(e))
		GameSession.KIND_SYSTEM:
			_list.add_child(_text(tr(str(e.get("key", ""))).format(e.get("args", {})), UiTheme.SYSTEM_TEXT))


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

