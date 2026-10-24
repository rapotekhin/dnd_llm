class_name Hotkeys
extends RefCounted
## Hotkeys as in BG3 (v0.7.22.27, UI audit С2, П1): the layout of data/game.json `keys` with the player's
## overrides (settings.cfg [keys]) put into the InputMap. Keys are bound by their physical place, so the Russian
## layout opens the sheet on «С» as on «C».


## {action: [key, where]} of game.json.
static func defaults() -> Dictionary:
	var out: Dictionary = (Catalog.game().get("keys", {}) as Dictionary).duplicate(true)
	out.erase("_doc")
	return out


## The key of an action now: the player's override, else the default.
static func key_of(action: String, overrides: Dictionary) -> String:
	return str(overrides.get(action, defaults().get(action, ["", ""])[0]))


static func where(action: String) -> String:
	return str(defaults().get(action, ["", "any"])[1])


## Every action into the InputMap with its one key.
static func apply(overrides: Dictionary) -> void:
	for action: String in defaults():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var code := OS.find_keycode_from_string(key_of(action, overrides))
		if code == KEY_NONE:
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)


## The action of the same place that already has this key ("" — none): the game screen and the fight never
## meet, `any` meets both.
static func clash(action: String, key: String, overrides: Dictionary) -> String:
	var mine := where(action)
	for other: String in defaults():
		if other == action or key_of(other, overrides) != key:
			continue
		var theirs := where(other)
		if mine == theirs or mine == "any" or theirs == "any":
			return other
	return ""


## «Персонаж [C]» for a tooltip; the text alone when the action has no key.
static func tip(text: String, action: String, overrides: Dictionary) -> String:
	var key := key_of(action, overrides)
	if key.is_empty():
		return text
	return "%s [%s]" % [text, key] if not text.is_empty() else "[%s]" % key


## The key name of a pressed key for the rebinding: its physical place.
static func name_of(event: InputEventKey) -> String:
	return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
