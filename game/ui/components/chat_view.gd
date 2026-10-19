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


func _text(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Chat text comes from the model and the player: never treat it as a translation key.
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


## The line without the speaker's name in front (the card is already signed): «Бруно Хмель понижает голос» →
## «понижает голос»; the first name alone too (v0.6.5, playtest-1).
static func without_name(text: String, name: String) -> String:
	for n: String in [name, name.get_slice(" ", 0)]:
		if not n.is_empty() and text.begins_with(n + " "):
			return text.substr(n.length()).lstrip(" —–-:,")
	return text

