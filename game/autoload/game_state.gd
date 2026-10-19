extends Node
## The current session and the turn loop (ADR-0009): player input → turn.request with a snapshot →
## engine.* callbacks (checks, effect reserves, lookup, item search) → turn.result → apply listed reserves.
## Modes: exploration, social and trade with an NPC of the room. One turn at a time.
## Deterministic moves (exits, talking to an NPC, leaving a conversation) do not ask the model to decide.

var session: GameSession
## turn_id of the turn in flight, "" when idle.
var busy_turn: String = ""
var effects := EffectEngine.new()

## Enemy turns of a fight are being played out (with a pause per line).
var combat_playing: bool = false
## Seconds between enemy lines; 0 in tests (LaunchArgs --combat-delay).
var combat_delay: float = 0.6
const COMBAT_SAVE := "autosave_combat"

var _last_kind: String = ""
var _last_input: String = ""


func has_session() -> bool:
	return session != null


func is_busy() -> bool:
	return not busy_turn.is_empty() or combat_playing


func world() -> WorldView:
	return WorldView.new(Catalog.data["world"])


## A new game: `settings` from the new game screen (world pack and master settings; {} = the active world's
## defaults) and a built character ({} = the world's first ready-made character).
func new_game(character: Dictionary = {}, settings: Dictionary = {}, game_seed: int = -1) -> void:
	if game_seed < 0:
		game_seed = int(LaunchArgs.value("--seed", str(randi())))
	if settings.has("world"):
		Catalog.activate(str(settings["world"]))
	if settings.is_empty():
		settings = WorldPack.default_settings(Catalog.data["pack"])
	if character.is_empty():
		character = CharacterBuilder.build_preset(Catalog.data["presets"][0], Catalog.data)
	var s := GameSession.create(game_seed, Time.get_datetime_string_from_system(), world().start_room(), character)
	s.world_id = Catalog.active_world
	s.world_version = str(Catalog.data["pack"].get("version", ""))
	s.settings = settings.duplicate(true)
	s.settings["world"] = Catalog.active_world
	start(s)
	_request("enter", "")


## Long rest button (ADR-0010 §6): only in a safe room, outside a conversation, with the price paid. The engine
## restores the character and clears the check locks, then the master describes the morning (kind=rest).
func long_rest() -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "REST_BUSY"
	var why := ExplorationRules.can_rest(session, Catalog.data["world"])
	if not why.is_empty():
		return why
	var lines := ExplorationRules.long_rest(session, Catalog.data)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("rest", "")
	return ""


## Trade panel (roadmap v0.5.3): the engine checks both purses and stocks and makes the deal at once, then the
## master narrates it (kind=deal, the deal lines as input). Returns the quote; its `error` is "" on success.
func deal(cart: Dictionary) -> Dictionary:
	if session == null or is_busy() or not Backend.is_ready() or session.mode != GameSession.MODE_TRADE:
		return {"error": "TRADE_ERR_BUSY", "args": {}}
	var q := TradeRules.quote(session, Catalog.data, session.npc_id, cart)
	if not str(q["error"]).is_empty():
		return q
	var lines := TradeRules.execute(session, Catalog.data, session.npc_id, cart)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_add(GameSession.effect_entry(lines))
	_log("Сделка: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("deal", TradeRules.deal_note(lines, int(q["net_cp"])))
	return q


## Haggle button: a Persuasion or Deception check (the better one) against the DC of the merchant's attitude;
## the master plays the merchant's reaction (kind=haggle). "" on success or a localization key.
func haggle() -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.mode != GameSession.MODE_TRADE:
		return "TRADE_ERR_BUSY"
	var why := TradeRules.can_haggle(session, Catalog.data, session.npc_id)
	if not why.is_empty():
		return why
	var params := {"skill": TradeRules.best_skill(session, Catalog.data), "dc_tier": "medium", "target_id": session.npc_id}
	var result := _haggle_check(params)
	EventBus.state_changed.emit()
	_request("haggle", str(result["note"]))
	return ""


## Switches a conversation with a trader between talk and the deal panel without a turn: the master's options
## stay as they are (B33), the next turn's snapshot carries the new mode.
func set_trade(on: bool) -> bool:
	if session == null or is_busy() or not session.in_conversation():
		return false
	if on and not world().is_trader(session.npc_id):
		return false
	var mode := GameSession.MODE_TRADE if on else GameSession.MODE_SOCIAL
	if session.mode == mode:
		return false
	session.mode = mode
	EventBus.state_changed.emit()
	return true


## Quest button (XpRules): the engine completes a pack quest in its room — reward and experience — then the
## master narrates it (kind=quest, the quest's done_text and the reward as input). "" or a localization key.
func complete_quest(quest_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "QUEST_BUSY"
	var why := XpRules.can_complete(session, Catalog.data["world"], quest_id)
	if not why.is_empty():
		return why
	var lines := XpRules.complete(session, Catalog.data, quest_id)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	var q: Dictionary = XpRules.quests(Catalog.data["world"])[quest_id]
	var reward := lines.slice(1).filter(func(l: String) -> bool: return not l.begins_with("можно"))
	_request("quest", "%s Награда: %s." % [q["done_text"], ", ".join(reward)])
	return ""


## Level-up screen (LevelUp): applies the next level with the player's picks. Not while the master thinks:
## the snapshot of the turn in flight would no longer match. "" or a localization key.
func level_up(picks: Dictionary) -> String:
	if session == null or is_busy():
		return "LVL_ERR_BUSY"
	var errs := LevelUp.errors(session.character, Catalog.data, picks)
	if not errs.is_empty():
		return errs[0]
	var lines := LevelUp.apply(session.character, Catalog.data, picks, session.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## «Колдовать» on the sheet (SpellRules): the engine checks and spends the slot, the master narrates the cast
## (kind=ability). `slot` 0 = the lowest fitting one. "" or a reason for the toast.
func cast(spell_id: String, slot: int = 0) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return tr("ABILITY_BUSY")
	var chk := SpellRules.check(session.character, Catalog.data, spell_id, slot)
	if chk.has("reason"):
		return str(chk["reason"])
	var lines := SpellRules.cast(session.character, Catalog.data, chk["spell_id"], int(chk["slot"]))
	_ability(lines, "Игрок колдует " + SpellRules.describe(Catalog.data, chk["spell_id"], int(chk["slot"])) +
		". Движок уже потратил ячейку — не вызывай cast сам; опиши, как это выглядит и что происходит.")
	return ""


## «Использовать» a feature with limited uses on the sheet (FeatureUses). "" or a reason.
func use_feature(resource_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return tr("ABILITY_BUSY")
	var why := FeatureUses.can_use(session.character, Catalog.data, resource_id, 1)
	if not why.is_empty():
		return why
	var lines := FeatureUses.use(session.character, Catalog.data, resource_id, 1, session.rng)
	_ability(lines, "Игрок использует умение «%s». Движок уже учёл использование: %s. Опиши, как это выглядит." %
		[FeatureUses.display_name(session.character, Catalog.data, resource_id), ", ".join(lines)])
	return ""


## «Использовать» an item on the sheet (ItemRules consumables). "" or a reason.
func use_item(item_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return tr("ABILITY_BUSY")
	var why := ItemRules.can_use(session.character, Catalog.data, session.items, item_id)
	if not why.is_empty():
		return why
	var lines := ItemRules.use(session.character, Catalog.data, session.items, item_id, session.rng)
	_ability(lines, "Игрок использует предмет. Движок уже применил: %s. Опиши коротко." % ", ".join(lines))
	return ""


func _ability(lines: Array[String], facts: String) -> void:
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("ability", facts)


## «Короткий отдых» (ExplorationRules): an hour, `dice` hit dice; no master turn — the line goes to the history.
func short_rest(dice: int) -> String:
	if session == null or is_busy():
		return "REST_BUSY"
	var why := ExplorationRules.can_short_rest(session, Catalog.data)
	if not why.is_empty():
		return why
	var lines := ExplorationRules.short_rest(session, Catalog.data, dice, session.rng)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## The prepared spells of the day (SpellRules): once after each long rest. "" or a localization key.
func prepare_spells(ids: Array) -> String:
	if session == null or is_busy():
		return "PREP_BUSY"
	var why := SpellRules.prepare_error(session.character, Catalog.data, session.day, ids)
	if not why.is_empty():
		return why
	SpellRules.prepare(session.character, ids, session.day)
	_add(GameSession.effect_entry(["Подготовлены заклинания: %d" % ids.size()]))
	EventBus.state_changed.emit()
	return ""


# --- combat (v0.6.1, CombatRules) ---------------------------------------------------------------


## Starts a fight: an autosave to come back to, the combat screen, the master describes the start.
func start_combat(foes: Array, source: Dictionary = {}) -> void:
	if session == null:
		return
	_end_conversation()
	combat_delay = float(LaunchArgs.value("--combat-delay", str(combat_delay)))
	SaveManager.save_slot(COMBAT_SAVE, session)
	var lines := CombatRules.start(session, Catalog.data, foes, source)
	session.mode = GameSession.MODE_COMBAT
	session.npc_id = ""
	_combat_log(lines)
	EventBus.state_changed.emit()
	EventBus.navigate.emit("combat", {})
	session.combat["log"] = []  # the start goes to the master as combat_start, not again with round 1
	_request("combat_start", "\n".join(lines))


func _start_pending_fight() -> void:
	var foes := session.pending_fight.duplicate(true)
	session.pending_fight = []
	start_combat(foes, {"room_from": session.room_id})


func _combat_log(lines: Array[String]) -> void:
	if lines.is_empty() or not CombatRules.active(session):
		return
	var log: Array = session.combat.get("log", [])
	log.append_array(lines)
	session.combat["log"] = log
	EventBus.combat_lines.emit(lines)


func _combat_ready() -> bool:
	return session != null and CombatRules.is_player_turn(session) and not is_busy() and Backend.is_ready() \
		and int(session.character["hp"]) > 0


## One player command in a fight: `why` "" means do it; the lines go to the log; an outcome ends the fight.
func _combat_do(why: String, act: Callable) -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN" if session != null and CombatRules.active(session) else "COMBAT_NONE"
	if not why.is_empty():
		return why
	var lines: Array[String] = act.call()
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_combat_log(lines)
	_combat_log(CombatRules.after_player_action(session, Catalog.data))
	EventBus.state_changed.emit()
	if not str(session.combat.get("outcome", "")).is_empty():
		_combat_continue()
	elif int(session.character["hp"]) <= 0:  # dropped on its own turn (an attack of opportunity): the turn is over
		CombatRules.end_player_turn(session, Catalog.data)
		_combat_continue()
	return ""


func combat_attack(target_id: String, offhand: bool = false) -> String:
	return _combat_do(CombatRules.can_attack(session, Catalog.data, target_id, offhand) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_attack(session, Catalog.data, target_id, offhand))


## A spell in a fight: engine spells resolve at once; others spend the slot and go to the master (it costs the action).
func combat_cast(spell_id: String, slot: int, target_id: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var why := CombatRules.can_cast(session, Catalog.data, spell_id, slot, target_id)
	var sp: Dictionary = Catalog.data["spells"].get(spell_id, {})
	if why.is_empty() and not CombatRules.is_engine_spell(Catalog.data, spell_id) and not sp.has("heal_at_slot"):
		if not _combat_ready():
			return "COMBAT_NOT_YOUR_TURN"
		var lines := CombatRules.player_cast(session, Catalog.data, spell_id, slot, "")
		_combat_log(lines)
		var target := str(CombatRules.fighter(session, target_id).get("name", "")) if not target_id.is_empty() else ""
		_request("action", "Игрок колдует %s%s. Ячейка уже потрачена движком — `cast` не нужен; реши исход проверками и эффектами с target_id врага." %
			[SpellRules.describe(Catalog.data, spell_id, slot if slot > 0 else SpellRules.lowest_slot(session.character, Catalog.data, spell_id)),
			(" на " + target) if not target.is_empty() else ""])
		return ""
	return _combat_do(why, func() -> Array[String]: return CombatRules.player_cast(session, Catalog.data, spell_id, slot, target_id))


func combat_simple(what: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN"
	var why := CombatRules.player_simple(session, Catalog.data, what)
	if why.is_empty():
		_combat_log([tr("COMBAT_DID_" + what.to_upper()).format({"name": session.character["name"]})])
		EventBus.state_changed.emit()
	return why


func combat_move(dir: int) -> String:
	return _combat_do(CombatRules.can_move(session, Catalog.data, dir) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_move(session, Catalog.data, dir))


## A feature in a fight costs what rules.resources say (combat_cost): Rage and Second Wind — a bonus action,
## Action Surge — free and gives one more action.
func combat_use_feature(resource_id: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var spec: Dictionary = FeatureUses.table(Catalog.data).get(resource_id, {})
	var cost := str(spec.get("combat_cost", "action"))
	var why := FeatureUses.can_use(session.character, Catalog.data, resource_id, 1)
	if why.is_empty() and cost != "free" and int(CombatRules.economy(session).get(cost, 0)) <= 0:
		why = "COMBAT_NO_ACTION" if cost == "action" else "COMBAT_NO_BONUS"
	return _combat_do(why, func() -> Array[String]:
		var e := CombatRules.economy(session)
		if cost != "free":
			e[cost] = int(e[cost]) - 1
		if resource_id == "action_surge":
			e["action"] = int(e["action"]) + 1
		if resource_id == "rage":
			session.combat["raging"] = true
		return FeatureUses.use(session.character, Catalog.data, resource_id, 1, session.rng))


func combat_use_item(item_id: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var why := ItemRules.can_use(session.character, Catalog.data, session.items, item_id)
	if why.is_empty() and int(CombatRules.economy(session).get("action", 0)) <= 0:
		why = "COMBAT_NO_ACTION"
	return _combat_do(why, func() -> Array[String]:
		CombatRules.economy(session)["action"] = int(CombatRules.economy(session)["action"]) - 1
		return ItemRules.use(session.character, Catalog.data, session.items, item_id, session.rng))


func combat_end_turn() -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN"
	CombatRules.end_player_turn(session, Catalog.data)
	EventBus.state_changed.emit()
	_combat_continue()
	return ""


## Plays the turns of the others with a pause per actor until it is the player's turn (alive), the round ends
## (the master narrates it) or the fight ends (the final narration, then the results).
func _combat_continue() -> void:
	if combat_playing or session == null or not CombatRules.active(session) or not busy_turn.is_empty():
		return
	var s := session
	combat_playing = true
	while CombatRules.active(s) and session == s:
		if bool(s.combat.get("round_ended", false)):
			s.combat.erase("round_ended")
			combat_playing = false
			_narrate_round()
			return
		if not str(s.combat.get("outcome", "")).is_empty():
			combat_playing = false
			_combat_outcome()
			return
		if CombatRules.is_player_turn(s) and int(s.character["hp"]) > 0:
			break
		var lines := CombatRules.next_actor(s, Catalog.data)
		CharacterRules.refresh(s.character, Catalog.data, s.items)
		_combat_log(lines)
		EventBus.state_changed.emit()
		if combat_delay > 0.0 and not lines.is_empty():
			await get_tree().create_timer(combat_delay).timeout
	combat_playing = false
	EventBus.state_changed.emit()


func _narrate_round() -> void:
	var log: Array = session.combat.get("log", [])
	session.combat["log"] = []
	_request("combat_round", "\n".join(log))


## The fight is over: the final narration (death — the epitaph), then the results wait for finish_combat().
func _combat_outcome() -> void:
	var s := session
	if bool(s.combat.get("narrated", false)):
		return
	s.combat["narrated"] = true
	var outcome := str(s.combat["outcome"])
	if outcome == "victory":
		var enc_loot := {}
		var enc_id := str(s.combat.get("encounter", ""))
		for rid: String in Catalog.data["world"]["rooms"]:
			var enc: Dictionary = Catalog.data["world"]["rooms"][rid].get("encounter", {})
			if str(enc.get("id", "")) == enc_id and not enc_id.is_empty():
				enc_loot = enc.get("loot", {})
		CombatRules.results(s, Catalog.data, enc_loot)
		var xp_lines := XpRules.award(s.character, Catalog.data, int(s.combat["xp"]), "бой")
		_combat_log(xp_lines)
	var log: Array = s.combat.get("log", [])
	s.combat["log"] = []
	if outcome == "dead":
		_request("death", "\n".join(log) + "\n" + _hero_path())
	else:
		_request("combat_round", "\n".join(log) + "\nИтог боя: " + tr("COMBAT_OUTCOME_" + outcome.to_upper()))


func _hero_path() -> String:
	var c := session.character
	return "Путь героя: %s, %s %s %d уровня; дней в пути %d; выполнено заданий %d." % [c["name"], c.get("race_name", ""),
		c.get("class_name", ""), int(c.get("level", 1)), session.day, session.quests_done.size()]


## The player leaves the results: the chosen loot is taken, the world remembers the fight, back to the game.
func finish_combat(take: Array = []) -> void:
	if session == null or not CombatRules.active(session) or is_busy():
		return
	var s := session
	var outcome := str(s.combat.get("outcome", ""))
	if outcome == "dead":
		return
	var lines: Array[String] = [tr("COMBAT_OUTCOME_" + outcome.to_upper())]
	if outcome == "victory":
		var cp := int(s.combat.get("coins_cp", 0))
		if cp > 0:
			s.character["gold_cp"] = int(s.character["gold_cp"]) + cp
			lines.append("+" + Money.format(cp))
		for l: Dictionary in s.combat.get("loot", []):
			if take.has(str(l["item_id"])):
				s.character["inventory"][l["item_id"]] = int(s.character["inventory"].get(l["item_id"], 0)) + int(l["qty"])
				lines.append("Взято: %s%s" % [ItemRules.display_name(Catalog.data["items"], s.items, str(l["item_id"])), " ×%d" % int(l["qty"]) if int(l["qty"]) > 1 else ""])
		if int(s.combat.get("xp", 0)) > 0:
			lines.append("+%d опыта" % int(s.combat["xp"]))
		if not str(s.combat.get("encounter", "")).is_empty():
			s.encounters_done.append(str(s.combat["encounter"]))
	for id: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, id)
		if str(f.get("status")) == "dead" and not str(f.get("npc_id", "")).is_empty():
			s.dead_npcs.append(str(f["npc_id"]))
	if outcome == "player_fled" and not str(s.combat.get("room_from", "")).is_empty():
		s.room_id = str(s.combat["room_from"])
	if int(s.character["hp"]) <= 0:
		s.character["hp"] = 1
	ConditionRules.remove(s.character, "unconscious")
	s.combat = {}
	s.mode = GameSession.MODE_EXPLORATION
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	_set_options([])
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	EventBus.state_changed.emit()
	EventBus.navigate.emit("game", {})


## Changes the master style of the running game (settings screen); kept in the save.
func set_dm_style(style: String) -> void:
	if session != null and WorldPack.DM_STYLES.has(style):
		session.settings["dm_style"] = style


func start(s: GameSession) -> void:
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	ExplorationRules.enter_room(s, Catalog.data["world"], s.room_id)
	session = s
	busy_turn = ""
	_last_kind = ""
	effects = EffectEngine.new()
	EventBus.session_started.emit()


func close_session() -> void:
	cancel_turn()
	session = null
	busy_turn = ""
	EventBus.session_closed.emit()


## Returns false when the input cannot be sent now (empty, a turn in flight, no master).
func submit(text: String) -> bool:
	text = text.strip_edges()
	if session == null or text.is_empty() or is_busy() or not Backend.is_ready():
		return false
	if session.mode == GameSession.MODE_COMBAT:
		if not CombatRules.is_player_turn(session) or int(CombatRules.economy(session).get("action", 0)) <= 0:
			EventBus.message.emit(tr("COMBAT_NO_ACTION"))
			return false
		CombatRules.economy(session)["action"] = int(CombatRules.economy(session)["action"]) - 1
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	_request("action", text)
	return true


## Exit button: the engine moves the player (no model decision), then the master describes the new room.
func go(room_id: String) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not world().exits(session.room_id).has(room_id):
		return false
	_end_conversation()
	var from := session.room_id
	ExplorationRules.enter_room(session, Catalog.data["world"], room_id)
	_add(GameSession.effect_entry(["Переход: %s" % world().room(room_id).get("name", room_id)]))
	EventBus.state_changed.emit()
	var enc: Dictionary = world().room(room_id).get("encounter", {})
	if not enc.is_empty() and not session.encounters_done.has(str(enc["id"])):
		start_combat(enc["enemies"], {"encounter": str(enc["id"]), "room_from": from})
		return true
	_request("enter", "")
	return true


## NPC button: start a conversation (or trade with a trader); the NPC greets the player.
func talk_to(npc_id: String, trade: bool = false) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not session.npcs_alive(world().npcs_in(session.room_id)).has(npc_id):
		return false
	if trade and not world().is_trader(npc_id):
		return false
	_begin_conversation(npc_id, GameSession.MODE_TRADE if trade else GameSession.MODE_SOCIAL)
	_request("enter", "")
	return true


func leave_conversation() -> bool:
	if session == null or is_busy() or not session.in_conversation() or not Backend.is_ready():
		return false
	_end_conversation()
	_request("resume", "")
	return true


## Repeats the last failed request as a new turn (ADR-0009 §5: no idempotency, a retry is a new turn_id).
func retry() -> void:
	if can_retry():
		_request(_last_kind, _last_input)


## The last turn failed and can be repeated.
func can_retry() -> bool:
	return session != null and not is_busy() and not _last_kind.is_empty()


func cancel_turn() -> void:
	if is_busy() and Backend.is_ready():
		Backend.request("turn.cancel", {"turn_id": busy_turn}, 5.0)


## Puts an owned item into an equipment slot (CharacterRules.SLOTS). "" on success, else a localization key.
## Not while the master thinks: the snapshot of the turn in flight would no longer match.
func equip(item_id: String, slot: String) -> String:
	if session == null or is_busy():
		return "EQUIP_BUSY"
	var c := session.character
	var why := CharacterRules.can_equip(c, Catalog.data, session.items, item_id, slot)
	if not why.is_empty():
		return why
	c["equipped"][slot] = item_id
	if slot == "main_hand" and str(c["equipped"].get("off_hand", "")) == item_id and int(c["inventory"][item_id]) < 2:
		c["equipped"]["off_hand"] = ""
	CharacterRules.refresh(c, Catalog.data, session.items)
	EventBus.state_changed.emit()
	return ""


func unequip(slot: String) -> void:
	if session == null or is_busy():
		return
	session.character["equipped"][slot] = ""
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	EventBus.state_changed.emit()


func save_to(slot: String) -> bool:
	return SaveManager.save_slot(slot, session)


## "" on success or a localization key.
func load_from(slot: String) -> String:
	var res: Variant = SaveManager.read_slot(slot)
	if res is String:
		return res
	start(res)
	return ""


# --- turn --------------------------------------------------------------------------


func _add(entry: Dictionary) -> void:
	session.append(entry)
	EventBus.chat_appended.emit(entry)


func _set_options(options: Array[String]) -> void:
	session.options = options
	EventBus.options_changed.emit(options)


func _log(line: String) -> void:
	var cap := int(Catalog.game()["summaries"]["events_max"])
	session.location_log.append(line)
	if session.location_log.size() > cap:
		session.location_log = session.location_log.slice(session.location_log.size() - cap)
	if session.in_conversation():
		session.dialogue_log.append(line)


func _request(kind: String, input: String) -> void:
	var s := session
	var turn_id := s.next_turn_id()
	_last_kind = kind
	_last_input = input
	busy_turn = turn_id
	_set_options([])
	EventBus.turn_started.emit(turn_id)
	var params := {
		"turn_id": turn_id,
		"mode": s.mode,
		"kind": kind,
		"input": input,
		"snapshot": TurnSnapshot.build(s, Catalog.data, int(Catalog.game()["chat"]["history_chars"])),
	}
	if s.in_conversation():
		params["npc_id"] = s.npc_id
	if not SaveManager.master_model.is_empty():
		params["model"] = SaveManager.master_model
	var call := await Backend.request("turn.request", params, float(Catalog.game()["turn"]["client_timeout_s"]))
	if session != s or busy_turn != turn_id:
		return  # the session was closed or replaced while the master was thinking
	busy_turn = ""
	if call.is_error():
		effects.discard(turn_id)
		_add(GameSession.system_entry(_error_key(call.reason())))
		EventBus.turn_finished.emit(turn_id, false)
		return
	_last_kind = ""
	var follow_up := _apply_result(s, turn_id, call.result)
	EventBus.turn_finished.emit(turn_id, true)
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_maybe_summarize_location()
	if follow_up == "combat":
		_start_pending_fight()
	elif not follow_up.is_empty():
		_request(follow_up, "")
	elif s.mode == GameSession.MODE_COMBAT:
		if str(s.combat.get("outcome", "")) == "dead" and kind == "death":
			EventBus.navigate.emit("death", {"epitaph": str(call.result.get("narration", ""))})
		else:
			_combat_continue()


## Shows the narration, applies listed reserves, handles next_mode. Returns the follow-up turn kind or "".
func _apply_result(s: GameSession, turn_id: String, result: Dictionary) -> String:
	var text := str(result.get("narration", ""))
	if s.in_conversation():
		_add(GameSession.npc_entry(s.npc_id, str(world().npc(s.npc_id).get("name", s.npc_id)), text, turn_id))
	else:
		_add(GameSession.dm_entry(text, turn_id))
	_log(("%s: " % world().npc(s.npc_id).get("name", "")) + text if s.in_conversation() else "Мастер: " + text)
	var room_before := s.room_id
	var lines := effects.apply(s, turn_id, result.get("effect_ids", []))
	CharacterRules.refresh(s.character, Catalog.data, s.items)  # an item given away is unequipped
	if not lines.is_empty():
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))
	var options: Array[String] = []
	for o: Variant in result.get("options", []):
		options.append(str(o))
	_set_options(options)

	if s.mode == GameSession.MODE_COMBAT:
		var after := CombatRules.after_player_action(s, Catalog.data)
		if not after.is_empty():
			_combat_log(after)
		return ""
	if not s.pending_fight.is_empty():
		return "combat"
	if int(s.character["hp"]) <= 0:
		var out := ExplorationRules.knock_out(s)
		_add(GameSession.effect_entry(out))
		_log("События: " + ", ".join(out))
		_end_conversation()
		return "downed"

	if s.room_id != room_before:
		ExplorationRules.enter_room(s, Catalog.data["world"], s.room_id)
		_end_conversation()
		return "enter"
	var next: Variant = result.get("next_mode")
	if not (next is Dictionary):
		return ""
	var mode := str(next.get("mode", ""))
	var npc_id := str(next.get("npc_id", "")) if next.get("npc_id") != null else ""
	if mode == GameSession.MODE_EXPLORATION and s.in_conversation():
		_end_conversation()
		return "resume"
	if mode == GameSession.MODE_COMBAT and s.npcs_alive(world().npcs_in(s.room_id)).has(npc_id):
		var npc := world().npc(npc_id)
		s.pending_fight = [{"monster": str(npc.get("monster", CombatRules.cfg(Catalog.data)["default_npc_monster"])),
			"name": str(npc.get("name", npc_id)), "desc": str(npc.get("description", "")), "npc_id": npc_id, "col": 0}]
		return "combat"
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and s.npcs_alive(world().npcs_in(s.room_id)).has(npc_id):
		if mode == GameSession.MODE_TRADE and not world().is_trader(npc_id):
			mode = GameSession.MODE_SOCIAL
		if s.in_conversation() and s.npc_id == npc_id:
			# The same partner: the master already answered, no new greeting (B33). Leaving the deal panel is the
			# player's button: talk goes on in trade mode too, so the master never closes the panel.
			if mode == GameSession.MODE_TRADE:
				s.mode = mode
			return ""
		_begin_conversation(npc_id, mode)
		return "enter"
	return ""


func _begin_conversation(npc_id: String, mode: String) -> void:
	if session.in_conversation() and session.npc_id != npc_id:
		_end_conversation()
	session.mode = mode
	session.npc_id = npc_id
	EventBus.state_changed.emit()


## Back to exploration; the conversation log goes to summary.request (kept in the save, ADR-0009 §3).
func _end_conversation() -> void:
	if not session.in_conversation():
		return
	var npc_id := session.npc_id
	var events := session.dialogue_log.duplicate()
	TradeRules.end_visit(session, npc_id)
	session.mode = GameSession.MODE_EXPLORATION
	session.npc_id = ""
	session.dialogue_log.clear()
	EventBus.state_changed.emit()
	if not events.is_empty():
		_summarize("dialogue", npc_id, "dialogue:" + npc_id, events)


func _maybe_summarize_location() -> void:
	var every := int(Catalog.game()["summaries"]["location_every_turns"])
	if session.location_log.size() < every:
		return
	var loc := world().location_id(session.room_id)
	var events := session.location_log.duplicate()
	session.location_log.clear()
	_summarize("location", str(world().location(loc).get("name", loc)), "location:" + loc, events)


func _summarize(kind: String, subject: String, key: String, events: Array) -> void:
	var s := session
	var params := {"kind": kind, "subject_id": subject, "previous": str(s.summaries.get(key, "")), "events": events}
	if not SaveManager.master_model.is_empty():
		params["model"] = SaveManager.master_model
	var call := await Backend.request("summary.request", params, float(Catalog.game()["turn"]["summary_timeout_s"]))
	if session == s and not call.is_error():
		s.summaries[key] = str(call.result.get("summary", ""))


static func _error_key(reason: String) -> String:
	match reason:
		"turn_cancelled":
			return "MSG_TURN_CANCELLED"
		"turn_timeout", "client_timeout", "engine_timeout":
			return "MSG_TURN_TIMEOUT"
		"server_busy", "turn_in_progress":
			return "MSG_SERVER_BUSY"
		"budget_exceeded":
			return "MSG_BUDGET_EXCEEDED"
		"llm_unavailable", "llm_invalid_output":
			return "MSG_MASTER_FAILED"
		_:
			return "MSG_NO_MASTER"


# --- engine.* handlers (only for the turn in flight, ADR-0009 §3) ---------------------


func _active(params: Dictionary) -> bool:
	return session != null and str(params.get("turn_id", "")) == busy_turn


func handle_engine_check(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	if TradeRules.is_haggle(session, Catalog.data, params):
		return _haggle_check(params)
	params.erase("dc")  # the DC number and condition effects are the engine's
	var mods := ConditionRules.check_mods(session.character, Catalog.data, params)
	var cond_name := func(id: Variant) -> String: return tr("COND_" + str(id).to_upper())
	params["disadvantage_reason"] = ", ".join((mods["disadvantage"] as Array).map(cond_name))
	params["auto_fail_reason"] = ", ".join((mods["auto_fail"] as Array).map(cond_name))
	var room := session.room_id
	var result: Dictionary
	var lock := ExplorationRules.locked(session, params, room)
	if not lock.is_empty():
		# A repeat without a change: the old result, no roll (ADR-0008 §2).
		result = (lock["result"] as Dictionary).duplicate()
		result["check_id"] = session.next_check_id()
		result["blocked"] = true
	else:
		var bonus := CheckEngine.bonus_for(session.character, params)
		result = CheckEngine.roll(Catalog.rules(), session.rng, params, bonus, session.next_check_id())
		if result.has("error"):
			return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, str(result["error"]))
		ExplorationRules.lock(session, params, room, result)
		if bool(result["success"]) and params.get("skill") != null:
			result["revealed"] = ExplorationRules.active_reveal(session, Catalog.data["world"], str(params["skill"]), int(result["total"]))
	_add(GameSession.check_entry(params, result))
	return result


## A haggling check (the button or the master's request_check in trade mode): DC by attitude, the haggle percent or
## the day lock (TradeRules). A repeat returns the old result without a roll. Adds the check card.
func _haggle_check(params: Dictionary) -> Dictionary:
	var npc_id := session.npc_id
	var m := TradeRules.merchant(session, Catalog.data, npc_id)
	var skill := str(params["skill"])
	var result: Dictionary
	var pct := 0
	if not TradeRules.can_haggle(session, Catalog.data, npc_id).is_empty() and not (m["haggle_result"] as Dictionary).is_empty():
		result = (m["haggle_result"] as Dictionary).duplicate()
		result["check_id"] = session.next_check_id()
		result["blocked"] = true
	else:
		var p := params.duplicate()
		p["dc"] = TradeRules.haggle_dc(session, Catalog.data, npc_id)
		p["dc_tier"] = "medium"
		result = CheckEngine.roll(Catalog.rules(), session.rng, p, CheckEngine.bonus_for(session.character, p), session.next_check_id())
		pct = TradeRules.apply_haggle(session, Catalog.data, npc_id, result)
		result["haggle_pct"] = pct
	result["note"] = TradeRules.haggle_note(tr("SKILL_" + skill.to_upper()), result, pct)
	_add(GameSession.check_entry(params, result))
	return result


func handle_engine_validate(params: Dictionary) -> Dictionary:
	if not _active(params) or not (params.get("effect") is Dictionary):
		return JsonRpcPeer.fail(-32041, "no such active turn or no effect")
	return effects.validate(session, Catalog.data, busy_turn, params["effect"])


func handle_engine_lookup(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	return Lookup.find(session, Catalog.data, str(params.get("kind", "")), str(params.get("id", "")))


func handle_engine_find_items(params: Dictionary) -> Dictionary:
	if not _active(params):
		return JsonRpcPeer.fail(-32041, "no such active turn")
	effects.mark_searched(busy_turn)
	var base := str(params.get("base", "")) if params.get("base") != null else ""
	return {"items": ItemRules.find(Catalog.data["items"], session.items, str(params.get("query", "")), base,
		params.get("properties", []))}
