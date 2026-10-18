extends Node
## Global signals only, no logic.

signal session_started
signal session_closed
## A chat entry was appended to the current session (GameSession.chat).
signal chat_appended(entry: Dictionary)
## Turn lifecycle: busy while the master thinks; options for the buttons under the chat.
signal turn_started(turn_id: String)
signal turn_finished(turn_id: String, ok: bool)
signal options_changed(options: Array[String])
## World state changed outside the chat (room, mode, character, items) — side panels redraw.
signal state_changed
## Connection to the LLM backend (BackendClient.State as int + human detail).
signal backend_state_changed(state: int, detail: String)
## Short player-facing status line, already translated.
signal message(text: String)
signal settings_applied
## Screen switch handled by main.gd: "menu", "game", "slots", "settings", "offline".
signal navigate(screen: String, args: Dictionary)
