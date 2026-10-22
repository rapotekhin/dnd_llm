extends Node
## Save slots (JSON, docs/tech/save-format.md) and display settings (settings.cfg).
## `--profile=<name>` keeps saves, settings and logs apart in user://profiles/<name>/ (agent checks use "agent").

const AUTOSAVE := "autosave"

var profile: String = ""
var profile_dir: String = "user:/"
var save_dir: String = "user://saves"
var settings_path: String = "user://settings.cfg"

var fullscreen: bool = false
## Window size in windowed mode; the viewport stays 1920×1080 and stretches.
var resolution: Vector2i = Vector2i(1600, 900)
## The player's model pick from the server list; "" = the server default.
var master_model: String = ""
## The OpenRouter provider pinned for a model (v0.7.20.5): model id ("" — the server's default) → provider tag.
var master_providers: Dictionary = {}
## Reactions and choices of the hero's features in a fight (v0.7.10, as in Baldur's Gate 3): "ask" — a window
## «Использовать?»; "always" — the engine uses them; "never".
var reactions: String = "ask"


func _ready() -> void:
	profile = LaunchArgs.value("--profile", "preview" if LaunchArgs.has("--preview") else "")  # a preview never touches real saves
	if not profile.is_empty():
		profile_dir = "user://profiles/" + profile
		save_dir = profile_dir + "/saves"
		settings_path = profile_dir + "/settings.cfg"
	DirAccess.make_dir_recursive_absolute(save_dir)
	load_settings()
	apply_settings()


func path_in_profile(file_name: String) -> String:
	return "%s/%s" % [profile_dir, file_name]


# --- slots -------------------------------------------------------------------


func manual_slots() -> Array[String]:
	var out: Array[String] = []
	for i in int(Catalog.game()["saves"]["manual_slots"]):
		out.append("slot_%d" % (i + 1))
	return out


func all_slots() -> Array[String]:
	var out := manual_slots()
	out.append(AUTOSAVE)
	return out


func _path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]


func build_save(session: GameSession) -> Dictionary:
	return SaveFormat.build(session, str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		Time.get_datetime_string_from_system(), int(Catalog.game()["chat"]["kept_in_save"]))


## Atomic: writes a temp file, then replaces the slot.
func save_slot(slot: String, session: GameSession) -> bool:
	if session == null:
		return false
	var path := _path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(build_save(session), "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


## The session from a slot, or a localization key (String) describing the error.
func read_slot(slot: String) -> Variant:
	var text := FileAccess.get_file_as_string(_path(slot))
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var problem := SaveFormat.check(data)
	if not problem.is_empty():
		return problem
	SaveFormat.migrate(data, {"world": Catalog.bundle(str(Catalog.base["game"].get("default_world", "")))})
	var s := GameSession.from_dict(data["session"])
	if not Catalog.activate(s.world_id):
		return "MSG_WORLD_MISSING"
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	return s


func slot_meta(slot: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(_path(slot))
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not (data is Dictionary):
		return {}
	var meta: Dictionary = data.get("meta", {})
	meta["saved_at"] = data.get("saved_at", "")
	return meta


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))


func latest_slot() -> String:
	var best := ""
	var best_time := ""
	for slot: String in all_slots():
		var meta := slot_meta(slot)
		if not meta.is_empty() and str(meta["saved_at"]) > best_time:
			best_time = str(meta["saved_at"])
			best = slot
	return best


# --- settings ----------------------------------------------------------------


func load_settings() -> void:
	var r: Array = Catalog.game()["ui"]["default_resolution"]
	resolution = Vector2i(int(r[0]), int(r[1]))
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", false)
		resolution = cfg.get_value("display", "resolution", resolution)
		master_model = str(cfg.get_value("master", "model", ""))
		master_providers = cfg.get_value("master", "providers", {})
		reactions = str(cfg.get_value("game", "reactions", "ask"))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("master", "model", master_model)
	cfg.set_value("master", "providers", master_providers)
	cfg.set_value("game", "reactions", reactions)
	cfg.save(settings_path)


func apply_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var m: Array = Catalog.game()["ui"]["min_resolution"]
	DisplayServer.window_set_min_size(Vector2i(int(m[0]), int(m[1])))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if not fullscreen and DisplayServer.window_get_size() != resolution:
		DisplayServer.window_set_size(resolution)
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(usable.position + (usable.size - resolution) / 2)
	EventBus.settings_applied.emit()


## Window sizes from data/game.json that fit the current screen; the saved one is always listed.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array[Vector2i] = []
	for r: Array in Catalog.game()["ui"]["resolutions"]:
		var v := Vector2i(int(r[0]), int(r[1]))
		if v.x <= screen.x and v.y <= screen.y:
			out.append(v)
	if not out.has(resolution):
		out.append(resolution)
		out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return out


## The master's model and pinned provider for turn.request and summary.request (v0.7.20.5).
func master_params(params: Dictionary) -> Dictionary:
	if not master_model.is_empty():
		params["model"] = master_model
	var provider := str(master_providers.get(master_model, ""))
	if not provider.is_empty():
		params["provider"] = provider
	return params
