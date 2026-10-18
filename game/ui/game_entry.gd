class_name GameEntry
extends RefCounted
## Entering a game needs the master: without a connection the player gets the offline screen, which
## performs the same action once the backend is READY. Actions: {"kind": "new"} or {"kind": "load", "slot": s}.


static func enter(action: Dictionary) -> void:
	if Backend.is_ready():
		perform(action)
	else:
		EventBus.navigate.emit("offline", {"action": action})


static func perform(action: Dictionary) -> void:
	match str(action.get("kind", "")):
		"new":
			GameState.new_game()
		"load":
			var err := GameState.load_from(str(action.get("slot", "")))
			if not err.is_empty():
				EventBus.message.emit(TranslationServer.translate(err))
				EventBus.navigate.emit("menu", {})
