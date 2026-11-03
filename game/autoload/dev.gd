extends Node
## Debug tools (docs/tech/godot-client.md «Отладка»): console (~) with its cheats, F3 overlay, F12 bug snapshot. On by
## «Режим разработчика» in the settings (SaveManager.dev_mode: a debug build until turned off) or `--dev`.

const MESSAGES_KEPT := 50
## Every command, for the completion of the first word.
const COMMANDS: Array[String] = ["help", "backend", "reconnect", "say", "retry", "cancel", "save", "load", "seed", "snapshot", "clear",
	"room", "rooms", "quests", "items", "npc", "state", "find", "give", "gold", "spawn", "goto", "heal", "god", "slots", "xp", "level",
	"reset", "class", "spell", "feature", "trait", "resist", "cond", "units"]
## The cheats (Cheats): they change the game, each through the engine's own road.
const CHEATS: Array[String] = ["give", "gold", "spawn", "goto", "heal", "god", "slots", "xp", "level", "reset", "class", "spell",
	"feature", "trait", "resist", "cond"]
## The cheats that take a unit of the room after `@цель` instead of the hero.
const UNIT_CHEATS: Array[String] = ["give", "gold", "heal", "resist", "cond", "feature", "trait"]
## What a command's argument is: the kind `find` and the completion search (Cheats.KINDS).
const ARG_KIND := {"give": "item", "spawn": "monster", "goto": "room", "class": "class", "spell": "spell", "feature": "feature",
	"trait": "trait", "resist": "damage", "cond": "condition"}
## The last word of `spawn`: whose side the creatures take; of `resist` and `cond`: take it off.
const ALLY_WORDS: Array[String] = ["ally", "союзник"]
const FOE_WORDS: Array[String] = ["foe", "враг"]
const OFF_WORDS: Array[String] = ["off", "снять"]
const FOUND_SHOWN := 30
const HINTS_SHOWN := 8

var enabled: bool = false
var overlay_on: bool = false

var _layer: CanvasLayer
var _console: DevConsole
var _overlay: DevOverlay
var _messages: PackedStringArray = []
var _allies: Array = []  # `spawn … ally` out of a fight: they join the next spawned one


func _ready() -> void:
	set_enabled(SaveManager.dev_mode or LaunchArgs.has("--dev"))


## Turns the tools on or off while the game runs (the settings' toggle): the layer is made the first time.
func set_enabled(on: bool) -> void:
	enabled = on
	if _layer != null:
		_layer.visible = on
		if not on:
			_console.visible = false
		return
	if not on:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var root_ui := Control.new()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root_ui)
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = DevOverlay.new()
	_overlay.visible = false
	root_ui.add_child(_overlay)
	_console = DevConsole.new()
	root_ui.add_child(_console)
	EventBus.message.connect(_keep_message)


func _input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_QUOTELEFT:
			_console.toggle()
		KEY_F3:
			overlay_on = not overlay_on
			_overlay.visible = overlay_on
		KEY_F12:
			EventBus.message.emit(tr("DEV_SNAPSHOT").format({"path": ProjectSettings.globalize_path(snapshot())}))
		_:
			return
	get_viewport().set_input_as_handled()


func _keep_message(text: String) -> void:
	_messages.append(text)
	if _messages.size() > MESSAGES_KEPT:
		_messages = _messages.slice(_messages.size() - MESSAGES_KEPT)


# --- console commands ---------------------------------------------------------


## Runs one console line and returns its output.
func run(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var args := parts.slice(1)
	if parts[0].begins_with("@"):
		return _at(parts[0], args)
	if CHEATS.has(parts[0]):
		return _cheat(parts[0], args)
	match parts[0]:
		"help":
			return "help · backend · reconnect · say <text> · retry · cancel · save <slot> · load <slot> · seed · snapshot · clear\n" \
				+ "мир: room [id] · rooms · quests · items [поиск] · npc <id|имя> · state\n" \
				+ "читы: give <вещь> [n] · gold <зм> · spawn <монстр> [n] [ally] · goto <комната> · heal · god · slots · xp <n> · " \
				+ "level [до] · reset · class <класс> · spell <имя> · feature <имя> · trait <имя> · resist <урон> [off] · cond <состояние> [off]\n" \
				+ "на юнита комнаты: @<цель> %s · units — кто здесь\n" % ", ".join(UNIT_CHEATS) \
				+ "поиск: find <%s> <часть имени> · Tab — дополнить имя" % "|".join(Cheats.KINDS)
		"units":
			if not GameState.has_session():
				return "no session"
			return _units()
		"find":
			if not GameState.has_session():
				return "no session"
			return _find(args)
		"backend":
			var c := Backend.client
			return "%s %s reason=%s server=%s last_ms=%s" % [BackendClient.State.keys()[c.state], Backend.config.describe(),
				c.reason, c.server_info, Backend.last_ms]
		"reconnect":
			Backend.reconnect()
			return "reconnecting"
		"say":
			return "sent" if GameState.submit(" ".join(args)) else "not sent (no session, busy or offline)"
		"retry":
			GameState.retry()
			return "retrying" if GameState.is_busy() else "nothing to retry"
		"cancel":
			GameState.cancel_turn()
			return "cancel requested"
		"save":
			return "saved" if GameState.save_to(_slot(args)) else "save failed"
		"load":
			var err := GameState.load_from(_slot(args))
			return "loaded" if err.is_empty() else err
		"seed":
			return str(GameState.session.game_seed) if GameState.has_session() else "no session"
		"snapshot":
			return ProjectSettings.globalize_path(snapshot())
		"clear":
			_console.clear()
			return ""
		"room", "rooms", "quests", "items", "npc", "state":
			if not GameState.has_session():
				return "no session"
			return _world_report(parts[0], " ".join(args))
	return "unknown command: %s (help)" % parts[0]


## The world inspection commands (WorldReport): the pack's data and what this game already knows about it.
func _world_report(cmd: String, arg: String) -> String:
	var s: GameSession = GameState.session
	match cmd:
		"room":
			return WorldReport.room(s, Catalog.data, arg if not arg.is_empty() else s.room_id)
		"rooms":
			return WorldReport.rooms(s, Catalog.data)
		"quests":
			return WorldReport.quests(s, Catalog.data)
		"items":
			return WorldReport.items(s, Catalog.data, arg)
		"npc":
			return WorldReport.npc(s, Catalog.data, arg) if not arg.is_empty() else "npc <id или часть имени>"
	return WorldReport.state(s)


# --- cheats -------------------------------------------------------------------------------------------


## `@<цель> <команда …>`: a cheat of UNIT_CHEATS on a unit of this room (Cheats.unit) instead of the hero.
func _at(target: String, args: PackedStringArray) -> String:
	if not GameState.has_session():
		return "no session"
	if args.is_empty() or not UNIT_CHEATS.has(args[0]):
		return "@<цель> <%s> (units — кто здесь)" % "|".join(UNIT_CHEATS)
	var u := Cheats.unit(GameState.session, Catalog.data, target)
	if u.has("reason"):
		return str(u["reason"])
	return _cheat(args[0], args.slice(1), u)


## `units`: who a cheat may aim at here, with the id to put after `@`.
func _units() -> String:
	var s: GameSession = GameState.session
	var out := PackedStringArray()
	for u: Dictionary in Cheats.units(s, Catalog.data):
		var w := Sheet.own(s, str(u["id"]))
		var top := Sheet.max_hp(s, Catalog.data, w)
		out.append("%s [@%s]%s · HP %d/%d" % [u["name"], u["id"], " — %s, %s" % [u["side"], u["status"]] if bool(u["fighter"]) else "",
			int(Sheet.holder(s, w).get("hp", top)), top])
	return "\n".join(out) if not out.is_empty() else "здесь никого"


## One cheat on the hero, or on the unit `u` (Cheats.unit) when given: refused without a session, while the master
## answers or where the act has no sense (a fight).
func _cheat(cmd: String, args: PackedStringArray, u: Dictionary = {}) -> String:
	if not GameState.has_session():
		return "no session"
	if GameState.is_busy():
		return "мастер ещё отвечает — подожди"
	var s: GameSession = GameState.session
	var data: Dictionary = Catalog.data
	var c := s.character
	var who := str(u.get("id", Being.HERO))
	var to := "%s: " % u["name"] if not u.is_empty() else ""
	if CombatRules.active(s) and cmd in ["goto", "level", "reset", "class"]:
		return "в бою нельзя: %s" % cmd
	Cheats.note(c, cmd)
	match cmd:
		"give":
			var q := _counted(args)
			var n := int(q["n"])
			var r := Cheats.resolve(s, data, "item", str(q["words"]))
			if r.has("reason"):
				return str(r["reason"])
			Gear.give(s, data, who, str(r["id"]), n)
			_changed()
			return "%s+%d %s [%s]" % [to, n, ItemRules.display_name(data["items"], s.items, str(r["id"])), r["id"]]
		"gold":
			if args.is_empty() or not args[0].is_valid_int():
				return "gold <зм> (с минусом — забрать)"
			Gear.pay(s, data, who, int(args[0]) * Money.GP)
			_changed()
			return "%sмонеты: %s" % [to, Money.format(Gear.coins(s, data, who))]
		"spawn":
			return _spawn(s, data, args)
		"goto":
			var r := Cheats.resolve(s, data, "room", " ".join(args))
			if r.has("reason"):
				return str(r["reason"])
			var why := GameState.teleport(str(r["id"]))
			return tr(why) if not why.is_empty() else "→ %s [%s]" % [GameState.world().room(str(r["id"])).get("name", ""), r["id"]]
		"heal":
			var lines := Rest.long(s, data, who)
			_changed()
			var w := Sheet.own(s, who)
			var top := Sheet.max_hp(s, data, w)
			return "%sHP %d/%d, ячейки и заряды полны%s" % [to, int(Sheet.holder(s, w).get("hp", top)), top,
				"; " + "; ".join(lines) if not lines.is_empty() else ""]
		"god", "slots":
			var on := Cheats.toggle(c, cmd)
			_changed()
			return "%s: %s" % [cmd, "вкл" if on else "выкл"]
		"xp":
			if args.is_empty() or not args[0].is_valid_int():
				return "xp <n>"
			var lines := XpRules.award(c, data, int(args[0]), "консоль")
			_changed()
			return "; ".join(lines) + " · всего %d" % int(c.get("xp", 0))
		"level":
			return _level(c, data, args)
		"reset", "class":
			var klass := ""
			if cmd == "class":
				var r := Cheats.resolve(s, data, "class", " ".join(args))
				if r.has("reason"):
					return str(r["reason"])
				klass = str(r["id"])
			var lines := Cheats.rebuild(s, data, klass)
			_changed()
			return lines[0]
		"spell":
			var r := Cheats.resolve(s, data, "spell", " ".join(args))
			if r.has("reason"):
				return str(r["reason"])
			var id := str(r["id"])
			StudyRules.learn_spell(c, id)
			_changed()
			var circle := SpellRules.level_of(data, id)
			return "заклинание: %s [%s] — всегда готово%s" % [data["spells"][id]["name"], id,
				" (ячеек %d круга нет — slots)" % circle if circle > 0 and SpellRules.slots_left(c, circle) <= 0 else ""]
		"resist", "cond":
			var off := not args.is_empty() and OFF_WORDS.has(args[-1])
			var r := Cheats.resolve(s, data, ARG_KIND[cmd], " ".join(args.slice(0, args.size() - 1) if off else args))
			if r.has("reason"):
				return str(r["reason"])
			var line := Cheats.resist(s, data, who, str(r["id"]), not off) if cmd == "resist" \
				else "; ".join(Cheats.condition(s, data, who, str(r["id"]), not off))
			_changed()
			return to + line
		"feature", "trait":
			var r := Cheats.resolve(s, data, cmd, " ".join(args))
			if r.has("reason"):
				return str(r["reason"])
			if not u.is_empty() and not bool(u["fighter"]):
				return "%sспособности и черты — только бойцу: сначала бой (spawn)" % to
			var h := c if u.is_empty() else Sheet.holder(s, Sheet.own(s, who))
			var list: Array = h.get(cmd + "s", [])
			if not list.has(str(r["id"])):
				list.append(str(r["id"]))
			h[cmd + "s"] = list
			_changed()
			return "%s%s: %s [%s]" % [to, "способность" if cmd == "feature" else "черта", Cheats.pool(s, data, cmd)[r["id"]].get("name", ""), r["id"]]
	return "unknown cheat: %s" % cmd


## `spawn <монстр> [n] [ally|foe]`: in a fight they come in at once on their side (CombatRules.add_allies); out of it a
## foe starts the fight in this room by the engine's start (GameState.start_combat) with the allies spawned before it.
func _spawn(s: GameSession, data: Dictionary, args: PackedStringArray) -> String:
	var side := "enemy"
	if not args.is_empty() and (ALLY_WORDS.has(args[-1]) or FOE_WORDS.has(args[-1])):
		side = "ally" if ALLY_WORDS.has(args[-1]) else "enemy"
		args = args.slice(0, args.size() - 1)
	var q := _counted(args)
	var n := int(q["n"])
	var r := Cheats.resolve(s, data, "monster", str(q["words"]))
	if r.has("reason"):
		return str(r["reason"])
	var spec := {"monster": str(r["id"]), "count": n}
	var title := "%s ×%d" % [data["monsters"][r["id"]]["name"], n]
	if CombatRules.active(s):
		var ids := CombatRules.add_allies(s, data, [spec], true, side)
		EventBus.state_changed.emit()
		return "%s в бою: %s" % ["союзники" if side == "ally" else "враги", ", ".join(Array(ids).map(func(id: String) -> String: return str(CombatRules.fighter(s, id)["name"])))]
	if side == "ally":
		_allies.append(spec)
		return "%s ждёт боя: spawn <враг> начнёт его вместе с ним" % title
	var allies := _allies
	_allies = []
	GameState.start_combat([spec], {"room_from": s.room_id, "allies": allies})
	return "бой: %s%s" % [title, " · союзники: %d" % allies.size() if not allies.is_empty() else ""]


## `level [до]`: up to the level (the next one by default) by the level-up's own road with its first picks.
func _level(c: Dictionary, data: Dictionary, args: PackedStringArray) -> String:
	var top := LevelUp.max_level(c, data)
	var to := mini(int(args[0]) if not args.is_empty() and args[0].is_valid_int() else int(c["level"]) + 1, top)
	if to <= int(c["level"]):
		return "уже %d уровень (наибольший %d; к первому — reset)" % [int(c["level"]), top]
	while int(c["level"]) < to:
		XpRules.award(c, data, LevelUp.xp_for(data, int(c["level"]) + 1) - int(c.get("xp", 0)), "консоль")
		var why := GameState.level_up(LevelUp.default_picks(c, data))
		if not why.is_empty():
			return tr(why)
	return "%s — %d уровень (выбор по умолчанию; свой — xp и окно уровня)" % [c["name"], int(c["level"])]


## `find <вид> <часть имени>`: a kind of Cheats.KINDS or a command whose argument it is.
func _find(args: PackedStringArray) -> String:
	if args.is_empty():
		return "find <%s> <часть имени>" % "|".join(Cheats.KINDS)
	var kind := str(ARG_KIND.get(args[0], args[0]))
	if not Cheats.KINDS.has(kind):
		return "нет вида %s: %s" % [args[0], ", ".join(Cheats.KINDS)]
	var found := Cheats.find(GameState.session, Catalog.data, kind, " ".join(args.slice(1)))
	var out := PackedStringArray(found.slice(0, FOUND_SHOWN).map(func(e: Dictionary) -> String: return "%s [%s]" % [e["name"], e["id"]]))
	if found.size() > FOUND_SHOWN:
		out.append("…и ещё %d" % (found.size() - FOUND_SHOWN))
	return "\n".join(out) if not out.is_empty() else "ничего не найдено"


## The completion of a console line: {hints: lines to show, line: the line with the first hint put in (Tab)}.
func complete(line: String) -> Dictionary:
	var none := {"hints": PackedStringArray(), "line": line}
	var parts := line.strip_edges(true, false).split(" ", false)
	if parts.is_empty():
		return none
	if parts[0].begins_with("@"):
		return _complete_at(line, parts)
	if parts.size() == 1 and not line.ends_with(" "):
		var cmds := COMMANDS.filter(func(x: String) -> bool: return x.begins_with(parts[0]))
		return {"hints": PackedStringArray(cmds), "line": cmds[0] + " " if not cmds.is_empty() else line}
	var head := parts.slice(0, 1)
	var args := parts.slice(1)
	if parts[0] == "find" and not args.is_empty():
		head.append(args[0])
		args = args.slice(1)
	var kind := str(ARG_KIND.get(head[-1], head[-1]))
	if not GameState.has_session() or not Cheats.KINDS.has(kind) or args.is_empty():
		return none
	var tail := PackedStringArray()
	while args.size() > 1 and (args[-1].is_valid_int() or ALLY_WORDS.has(args[-1]) or FOE_WORDS.has(args[-1]) or OFF_WORDS.has(args[-1])):
		tail.insert(0, args[-1])
		args = args.slice(0, args.size() - 1)
	var found := Cheats.find(GameState.session, Catalog.data, kind, " ".join(args), HINTS_SHOWN)
	if found.is_empty():
		return none
	var hints := PackedStringArray(found.map(func(e: Dictionary) -> String: return "%s [%s]" % [e["name"], e["id"]]))
	return {"hints": hints, "line": " ".join(head + PackedStringArray([str(found[0]["id"])]) + tail)}


## `@цель …`: the units of the room for the first word, then the rest as a line of its own after it.
func _complete_at(line: String, parts: PackedStringArray) -> Dictionary:
	if not GameState.has_session():
		return {"hints": PackedStringArray(), "line": line}
	if parts.size() == 1 and not line.ends_with(" "):
		var q := parts[0].trim_prefix("@").to_lower()
		var hit := Cheats.units(GameState.session, Catalog.data).filter(func(u: Dictionary) -> bool:
			return str(u["id"]).to_lower().begins_with(q) or str(u["name"]).to_lower().replace(" ", "").begins_with(q))
		return {"hints": PackedStringArray(hit.map(func(u: Dictionary) -> String: return "%s [@%s]" % [u["name"], u["id"]])),
			"line": "@%s " % hit[0]["id"] if not hit.is_empty() else line}
	var rest := line.strip_edges(true, false).trim_prefix(parts[0]).strip_edges(true, false)
	var inner := complete(rest)
	return {"hints": inner["hints"], "line": "%s %s" % [parts[0], inner["line"]]}


## A trailing count off the words: {words, n} (n 1 when none).
func _counted(args: PackedStringArray) -> Dictionary:
	if args.size() > 1 and args[-1].is_valid_int():
		return {"words": " ".join(args.slice(0, args.size() - 1)), "n": maxi(1, int(args[-1]))}
	return {"words": " ".join(args), "n": 1}


func _changed() -> void:
	CharacterRules.refresh(GameState.session.character, Catalog.data, GameState.session.items)
	EventBus.state_changed.emit()


func _slot(args: PackedStringArray) -> String:
	if args.is_empty():
		return "slot_1"
	return args[0] if args[0].begins_with("slot_") or args[0] == SaveManager.AUTOSAVE else "slot_" + args[0]


# --- bug snapshot (F12) ---------------------------------------------------------


## <profile>/bugs/<time>/: save, screenshot, protocol log tail, recent messages, the Godot log. No token inside.
func snapshot() -> String:
	var dir := SaveManager.path_in_profile("bugs/" + Time.get_datetime_string_from_system().replace(":", "-"))
	DirAccess.make_dir_recursive_absolute(dir)
	if GameState.has_session():
		_write(dir + "/save.json", JSON.stringify(SaveManager.build_save(GameState.session), "\t"))
	_write(dir + "/protocol.jsonl", "\n".join(Backend.protocol_log.recent))
	_write(dir + "/messages.txt", "\n".join(_messages))
	_write(dir + "/backend.txt", run("backend"))
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(dir + "/screenshot.png")
	var log_path := "user://logs/godot.log"
	if FileAccess.file_exists(log_path):
		DirAccess.copy_absolute(log_path, dir + "/godot.log")
	return dir


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
