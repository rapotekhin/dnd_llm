class_name GameEntry
extends RefCounted
## Entering a game needs the master: without a connection the player gets the offline screen, which
## performs the same action once the backend is READY. Actions: {"kind": "new", "character": built character}
## or {"kind": "load", "slot": s}.


static func enter(action: Dictionary) -> void:
	if Backend.is_ready():
		perform(action)
	else:
		EventBus.navigate.emit("offline", {"action": action})


static func perform(action: Dictionary) -> void:
	match str(action.get("kind", "")):
		"new":
			GameState.new_game(action.get("character", {}), action.get("settings", {}), -1, action.get("choices", {}))
		"heir":  # v0.7.32
			GameState.continue_as_heir(action.get("character", {}))
		"load":
			var err := GameState.load_from(str(action.get("slot", "")))
			if not err.is_empty():
				EventBus.message.emit(TranslationServer.translate(err))
				EventBus.navigate.emit("menu", {})


## The screen a game opens on, new, loaded or the heir's (v0.8.4.43.9): a game whose hero is dead — only its death screen
## with the master's words; the autosave after a death opened on a fight that waited for nothing.
static func opened(s: GameSession) -> Dictionary:
	if s != null and s.hero_dead():
		return {"screen": "death", "args": {"epitaph": s.epitaph}}
	return {"screen": "game", "args": {}}
