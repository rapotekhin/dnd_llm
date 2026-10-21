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
## The spell, feature or consumable pinned to the next message at the input field (roadmap v0.7.7, the author's
## request): {kind, id, slot, target} or {}. The engine spends it when the message goes, and the master gets the
## cast and the player's intent in one turn. Not saved.
var attached: Dictionary = {}
## The character before an attached spend: back if that turn fails to reach the master (the slot is returned).
var _refund: Dictionary = {}
var _refund_what: Dictionary = {}  # the attachment spent then
var _retry_spend: Dictionary = {}  # an attachment given back by a failed turn: «Повторить» spends it again
## A combat spell pinned to words aimed at an NPC (v0.7.7, as in BG3): if that turn starts the fight, the hero
## strikes first with it, the NPC caught off guard. {spell, slot, npc_id} or {}.
var _opening: Dictionary = {}


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
	BackgroundRules.apply_ties(s, Catalog.data)  # the people of the hero's past (v0.7.11)
	start(s)
	_request("enter", "")


## Long rest (ADR-0010 §6): in a safe room outside a conversation with the price paid, or — v0.7.8, the author: «as in
## Baldur's Gate» — a camp anywhere safe for `supplies` {item_id: qty} of food from the pack. The engine restores the
## character, clears the check locks and all exhaustion, then the master describes the morning (kind=rest).
func long_rest(supplies: Dictionary = {}) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "REST_BUSY"
	var why := ExplorationRules.can_rest(session, Catalog.data["world"], Catalog.data) if supplies.is_empty() \
		else ExplorationRules.camp_error(session, Catalog.data, supplies)
	if not why.is_empty():
		return why
	var began := session.minute
	var lines := ExplorationRules.long_rest(session, Catalog.data, supplies)
	TimeRules.after_long_rest(session, Catalog.data, began)
	lines.append_array(ConditionRules.expire(session, Catalog.data))
	CharacterRules.refresh(session.character, Catalog.data, session.items)
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
	if on and (not world().is_trader(session.npc_id) or TimeRules.shops_closed(session, Catalog.data) or TheftRules.shop_closed_for(session, session.npc_id)):
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
	return _use_alone({"kind": "spell", "id": spell_id, "slot": slot})


## «Использовать» a feature with limited uses on the sheet (FeatureUses). "" or a reason.
func use_feature(resource_id: String) -> String:
	return _use_alone({"kind": "feature", "id": resource_id})


## «Использовать» an item on the sheet (ItemRules consumables). "" or a reason.
func use_item(item_id: String) -> String:
	return _use_alone({"kind": "item", "id": item_id})


func _use_alone(what: Dictionary) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return tr("ABILITY_BUSY")
	var spent := _spend(what)
	if spent.has("reason"):
		return str(spent["reason"])
	_ability(spent["lines"], str(spent["facts"]))
	return ""


## A spell, a feature use or a consumable checked and spent by the engine (v0.7.7: shared by the sheet buttons and
## the attachment at the input field): {"lines", "facts"} or {"reason"}. `what`: {kind spell|feature|item, id,
## slot (spells, 0 = the lowest fitting), target (an NPC id of the scene, optional)}.
func _spend(what: Dictionary) -> Dictionary:
	var c := session.character
	var id := str(what.get("id", ""))
	var lines: Array[String] = []
	var facts := ""
	match str(what.get("kind", "")):
		"spell":
			var chk := SpellRules.check(c, Catalog.data, id, int(what.get("slot", 0)))
			if chk.has("reason"):
				return {"reason": str(chk["reason"])}
			lines = SpellRules.cast(c, Catalog.data, chk["spell_id"], int(chk["slot"]), session, str(what.get("target", "")).is_empty())
			what["spent_slot"] = int(chk["slot"])
			facts = "Игрок колдует " + SpellRules.describe(Catalog.data, chk["spell_id"], int(chk["slot"])) + \
				". Движок уже потратил ячейку — не вызывай cast сам; опиши, как это выглядит и что происходит."
		"feature":
			var why := FeatureUses.can_use(c, Catalog.data, id, 1)
			if not why.is_empty():
				return {"reason": why}
			lines = FeatureUses.use(c, Catalog.data, id, 1, session.rng)
			facts = "Игрок использует умение «%s». Движок уже учёл использование: %s. Опиши, как это выглядит." % \
				[FeatureUses.display_name(c, Catalog.data, id), ", ".join(lines)]
		"item":
			var why := ItemRules.can_use(c, Catalog.data, session.items, id)
			if not why.is_empty():
				return {"reason": why}
			lines = ItemRules.use(c, Catalog.data, session.items, id, session.rng, session)
			facts = "Игрок использует предмет. Движок уже применил: %s. Опиши коротко." % ", ".join(lines)
		"feature_note":
			var f: Dictionary = Catalog.data["classes"]["features"].get(id, Catalog.data["races"]["traits"].get(id, {}))
			lines = ["Умение: %s" % f.get("name", id)]
			facts = "Игрок пускает в ход умение «%s» (%s). Движок его не считает: реши исход по правилам — проверкой engine.check, если нужна." % \
				[f.get("name", id), str(f.get("desc", "")).left(240)]
		"item_note":
			if int(c.get("inventory", {}).get(id, 0)) <= 0:
				return {"reason": "EQUIP_NOT_OWNED"}
			var nm := ItemRules.display_name(Catalog.data["items"], session.items, id)
			lines = ["Предмет: %s" % nm]
			facts = "Игрок пускает в ход предмет «%s» [%s] из своего снаряжения. Опиши по правилам; трата или потеря — эффектом." % [nm, id]
		_:
			return {"reason": "ABILITY_BUSY"}
	var target := str(what.get("target", ""))
	if not target.is_empty():
		facts += " Цель — %s [%s]." % [world().npc(target).get("name", target), target]
	CharacterRules.refresh(c, Catalog.data, session.items)
	return {"lines": lines, "facts": facts}


func _ability(lines: Array[String], facts: String) -> void:
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("ability", facts)


func attach(kind: String, id: String, slot: int = 0, target: String = "") -> void:
	attached = {"kind": kind, "id": id, "slot": slot, "target": target}
	EventBus.state_changed.emit()


func detach() -> void:
	attached = {}
	EventBus.state_changed.emit()


## What can be pinned now (v0.7.7 fixes: everything, not only spells): [{kind, id, name, slots [circles], off}].
## spell — ready spells (`off` when no slot is left); feature — uses that the engine spends; feature_note — any other
## feature or trait of the hero; item — consumables the engine uses; item_note — any other thing in the pack.
func attach_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null:
		return out
	var c := session.character
	var data: Dictionary = Catalog.data
	for sid: Variant in SpellRules.ready(c):
		var lv := SpellRules.level_of(data, str(sid))
		var slots: Array[int] = []
		for circle in range(maxi(1, lv), 6):
			if lv > 0 and SpellRules.slots_left(c, circle) > 0:
				slots.append(circle)
		out.append({"kind": "spell", "id": str(sid), "name": str(data["spells"][str(sid)]["name"]), "slots": slots, "off": lv > 0 and slots.is_empty()})
	var with_uses: Array[String] = []
	for r: Dictionary in FeatureUses.lines(c, data):
		out.append({"kind": "feature", "id": str(r["id"]), "name": "%s (%d/%d)" % [r["name"], int(r["left"]), int(r["max"])], "slots": [], "off": int(r["left"]) <= 0})
		for f: Variant in data["rules"]["resources"].get(str(r["id"]), {}).get("features", []):
			with_uses.append(str(f))
	for pool: Array in [[c.get("features", []), data["classes"]["features"]], [c.get("traits", []), data["races"]["traits"]]]:
		for fid: Variant in pool[0]:
			var f: Dictionary = (pool[1] as Dictionary).get(str(fid), {})
			if f.is_empty() or with_uses.has(str(fid)) or f.has("options") or _quiet_feature(str(fid)):
				continue
			out.append({"kind": "feature_note", "id": str(fid), "name": str(f["name"]), "slots": [], "off": false})
	for iid: String in c.get("inventory", {}):
		var usable := not ItemRules.consumable(data, iid).is_empty()
		out.append({"kind": "item" if usable else "item_note", "id": iid,
			"name": "%s ×%d" % [ItemRules.display_name(data["items"], session.items, iid), int(c["inventory"][iid])], "slots": [], "off": false})
	return out


## Features that are bookkeeping, not something to use: spellcasting, ability increases, the choice of a subclass.
static func _quiet_feature(id: String) -> bool:
	return id.begins_with("spellcasting") or id.contains("ability_score_improvement") or id.ends_with("_expertise_1") or id in [
		"bonus_cantrip", "bonus_proficiency", "bonus_proficiencies", "arcane_tradition", "bard_college", "divine_domain", "druid_circle",
		"martial_archetype", "monastic_tradition", "otherworldly_patron", "primal_path", "ranger_archetype", "roguish_archetype",
		"sacred_oath", "sorcerous_origin", "fighter_fighting_style", "ranger_fighting_style", "paladin_fighting_style", "pact_magic"]


## «Короткий отдых» (ExplorationRules): an hour, `dice` hit dice; no master turn — the line goes to the history.
func short_rest(dice: int) -> String:
	if session == null or is_busy():
		return "REST_BUSY"
	var why := ExplorationRules.can_short_rest(session, Catalog.data)
	if not why.is_empty():
		return why
	var lines := ExplorationRules.short_rest(session, Catalog.data, dice, session.rng)
	lines.append_array(TimeRules.advance(session, Catalog.data, int(TimeRules.cfg(Catalog.data)["short_rest_minutes"])))
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	if _exhaustion_death():
		return ""
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## Exhaustion 6 outside a fight (v0.7.8, 5e): the hero dies — the master's epitaph, then the death screen. True
## when it happened.
func _exhaustion_death() -> bool:
	if session == null or not ConditionRules.dead(session.character) or CombatRules.active(session):
		return false
	_request("death", "Герой умирает от истощения (шестая степень).\n" + _hero_path())
	return true


## The hero cannot act outside a fight (asleep, paralysed for a while — v0.7.8): the engine lets the time pass until
## the longest such effect ends. Lines.
func _sleep_through() -> Array[String]:
	var c := session.character
	var longest := 0
	for cond: String in ConditionRules.INCAPACITATING:
		for e: Dictionary in ConditionRules.effects_of(c, cond):
			longest = maxi(longest, ConditionRules.rounds_left(session, e))
	if longest <= 0:
		return []
	var minutes := ceili(longest / float(ConditionRules.ROUNDS_PER_MINUTE))
	var lines: Array[String] = ["Без чувств: %d мин" % minutes]
	lines.append_array(TimeRules.advance(session, Catalog.data, minutes))
	return lines


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
	session.fight_on_load = {"foes": foes.duplicate(true), "source": source.duplicate(true)}
	SaveManager.save_slot(COMBAT_SAVE, session)  # loading it starts this fight again (a lost fight is not skipped)
	session.fight_on_load = {}
	var lines := CombatRules.start(session, Catalog.data, foes, source)
	lines.append_array(_opening_strike(source.get("opening", {})))
	session.mode = GameSession.MODE_COMBAT
	session.npc_id = ""
	session.combat["start_lines"] = lines  # shown after the master's description (playtest-1: the order)
	EventBus.state_changed.emit()
	EventBus.navigate.emit("combat", {})
	_request("combat_start", "\n".join(lines))


## The pinned spell that started the fight lands first (v0.7.7): its slot was spent with the words, so it is given
## back and spent again by the combat cast — on that NPC, now caught off guard. Lines.
func _opening_strike(opening: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if opening.is_empty():
		return lines
	var data: Dictionary = Catalog.data
	var target := CombatRules.fighter_of_npc(session, str(opening["npc_id"]))
	var spell := str(opening["spell"])
	var slot := int(opening.get("slot", 0))
	if target.is_empty():
		return lines
	if slot > 0:
		var used: Array = session.character["slots_used"]
		used[slot - 1] = maxi(0, int(used[slot - 1]) - 1)
	var why := CombatRules.can_cast(session, data, spell, slot, target)
	if not why.is_empty():
		lines.append("%s не удаётся: %s — ячейка не потрачена" % [data["spells"][spell]["name"], tr(why)])
		return lines
	lines.append_array(CombatRules.player_cast(session, data, spell, slot, target))
	return lines


## The engine lines of the fight's start go to the combat log once the master has described the scene.
func _show_start_lines() -> void:
	if session == null or not CombatRules.active(session) or not session.combat.has("start_lines"):
		return
	var lines: Array[String] = []
	for l: Variant in session.combat["start_lines"]:
		lines.append(str(l))
	session.combat.erase("start_lines")
	EventBus.combat_lines.emit(lines)


func _start_pending_fight() -> void:
	var foes := session.pending_fight.duplicate(true)
	session.pending_fight = []
	var source := {"room_from": session.room_id}
	if not _opening.is_empty() and foes.any(func(f: Dictionary) -> bool: return str(f.get("npc_id", "")) == str(_opening["npc_id"])):
		source["opening"] = _opening
	_opening = {}
	start_combat(foes, source)


func _combat_log(lines: Array[String]) -> void:
	if lines.is_empty() or not CombatRules.active(session):
		return
	var log: Array = session.combat.get("log", [])
	log.append_array(lines)
	session.combat["log"] = log
	EventBus.combat_lines.emit(lines)


func _combat_ready() -> bool:
	return session != null and CombatRules.player_can_act(session) and not is_busy() and Backend.is_ready()


## One player command in a fight: `why` "" means do it; the lines go to the log; an outcome ends the fight.
func _combat_do(why: String, act: Callable) -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN" if session != null and CombatRules.active(session) else "COMBAT_NONE"
	if session.combat.has("prompt"):
		return "COMBAT_ANSWER_FIRST"
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
		_combat_log(CombatRules.end_player_turn(session, Catalog.data))
		_combat_continue()
	return ""


func combat_attack(target_id: String, offhand: bool = false) -> String:
	return _combat_do(CombatRules.can_attack(session, Catalog.data, target_id, offhand) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_attack(session, Catalog.data, target_id, offhand))


## «Схватить» / «Сбить с ног» (v0.7.7): instead of one attack, Athletics against the foe (CombatRules.grapple).
func combat_grapple(target_id: String, shove: bool) -> String:
	return _combat_do(CombatRules.can_grapple(session, Catalog.data, target_id) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.grapple(session, Catalog.data, target_id, shove))


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
	if cost == "never":
		why = "COMBAT_FEATURE_TAB"
	if resource_id == "rage" and str(CharacterRules.item_def(session.character, Catalog.data, session.items, "armor").get("armor", {}).get("category", "")) == "heavy":
		why = "COMBAT_RAGE_ARMOR"
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


## «Встать» (v0.7.8): the whole move of the turn.
func combat_stand() -> String:
	return _combat_do(CombatRules.can_stand(session) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.stand(session))


## «Вырваться» (v0.7.8): an action, Athletics or Acrobatics against the hold.
func combat_escape() -> String:
	return _combat_do(CombatRules.can_escape(session) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.escape(session, Catalog.data))


## «Неистовство» of a berserker (v0.7.8): while raging, a melee attack as a bonus action every turn; when the fight
## ends, a level of exhaustion.
func combat_frenzy() -> String:
	return _combat_do(CombatRules.can_frenzy(session) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.frenzy(session))


func combat_frenzy_attack(target_id: String) -> String:
	return _combat_do(CombatRules.can_frenzy_attack(session, Catalog.data, target_id) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_attack(session, Catalog.data, target_id, false, true))


func combat_use_item(item_id: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var why := ItemRules.can_use(session.character, Catalog.data, session.items, item_id)
	# Fast Hands (thief, v0.7.10): an item is a bonus action
	var cost := "bonus" if FeatureRules.has(session.character, "fast_hands") and int(CombatRules.economy(session).get("bonus", 0)) > 0 else "action"
	if why.is_empty() and int(CombatRules.economy(session).get(cost, 0)) <= 0:
		why = "COMBAT_NO_ACTION"
	return _combat_do(why, func() -> Array[String]:
		CombatRules.economy(session)[cost] = int(CombatRules.economy(session)[cost]) - 1
		return ItemRules.use(session.character, Catalog.data, session.items, item_id, session.rng, session))


func combat_end_turn() -> String:
	if not _combat_ready():
		return "COMBAT_NOT_YOUR_TURN"
	_combat_log(CombatRules.end_player_turn(session, Catalog.data))
	EventBus.state_changed.emit()
	_combat_continue()
	return ""


## A feature action of the fight (v0.7.10, FeatureRules): Reckless Attack, the ki techniques, Channel Divinity, Wild
## Shape, Font of Magic, Breath Weapon. "" or a localization key.
func combat_feature(id: String, target_id: String = "") -> String:
	return _combat_do(FeatureRules.can_act(session, Catalog.data, id, target_id) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return FeatureRules.act(session, Catalog.data, id, target_id))


## The answer to a prompt of the hero's turn (Divine Smite, the beast of Wild Shape, Font of Magic).
func combat_answer(choice: String) -> String:
	if session == null or not CombatRules.active(session) or not session.combat.has("prompt"):
		return "COMBAT_NONE"
	var lines := FeatureRules.answer_prompt(session, Catalog.data, choice)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_combat_log(lines)
	_combat_log(CombatRules.after_player_action(session, Catalog.data))
	EventBus.state_changed.emit()
	if not str(session.combat.get("outcome", "")).is_empty():
		_combat_continue()
	return ""


## The answer to a reaction prompt in a foe's turn (Uncanny Dodge, Deflect Missiles, Cutting Words, Giant Killer).
func combat_react(choice: String) -> String:
	if session == null or not CombatRules.active(session) or not session.combat.has("pending"):
		return "COMBAT_NONE"
	var lines := CombatRules.answer_reaction(session, Catalog.data, choice)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_combat_log(lines)
	EventBus.state_changed.emit()
	_combat_continue()
	return ""


## Font of Magic outside a fight (the sheet): a slot for points or points for a slot. Stays out of the master's turns.
func font_convert(id: String) -> String:
	if session == null or is_busy():
		return "ABILITY_BUSY"
	var lines := FeatureRules.font_convert(session, Catalog.data, id)
	_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	return ""


## The metamagic of the next spell (a toggle; "" — none).
func combat_metamagic(id: String) -> void:
	if session == null or not CombatRules.active(session):
		return
	if str(session.combat.get("metamagic", "")) == id or id.is_empty():
		session.combat.erase("metamagic")
	else:
		session.combat["metamagic"] = id
	EventBus.state_changed.emit()


## Inspect a foe (v0.6.6): a bonus action, a knowledge check by the creature type; success opens the kind's numbers.
func combat_inspect(target_id: String) -> String:
	return _combat_do(CombatRules.can_inspect(session, Catalog.data, target_id) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_inspect(session, Catalog.data, target_id))


## Hide in a fight (v0.6.2): an action (a bonus action with Cunning Action), Stealth against the foes' Perception.
func combat_hide() -> String:
	return _combat_do(CombatRules.can_hide(session, Catalog.data) if session != null and CombatRules.active(session) else "COMBAT_NONE",
		func() -> Array[String]: return CombatRules.player_hide(session, Catalog.data))


## Parley in a fight (v0.6.2): the action, an engine check of Intimidation or Persuasion against the parley DC; the
## outcome (surrender, flight, truce) is the engine's, the master narrates it with the round.
func combat_parley(skill: String) -> String:
	if session == null or not CombatRules.active(session):
		return "COMBAT_NONE"
	var why := CombatRules.can_parley(session, Catalog.data, skill)
	if why.is_empty() and int(CombatRules.economy(session).get("action", 0)) <= 0:
		why = "COMBAT_NO_ACTION"
	return _combat_do(why, func() -> Array[String]:
		CombatRules.economy(session)["action"] = int(CombatRules.economy(session)["action"]) - 1
		return _parley_check({"skill": skill, "dc_tier": "medium"})["lines"])


## A parley check (the button or the master's request_check of Intimidation / Persuasion in a fight): the DC is the
## engine's, the outcome is applied at once and goes to the master in `note`. Adds the check card.
func _parley_check(params: Dictionary) -> Dictionary:
	var skill := str(params["skill"])
	var p := params.duplicate()
	p["dc"] = CombatRules.parley_dc(session, Catalog.data)
	p["dc_tier"] = "medium"
	var mods := ConditionRules.check_mods(session.character, Catalog.data, p)
	var cond_name := func(id: Variant) -> String: return tr("COND_" + str(id).to_upper())
	var dis_why: Array = (mods["disadvantage"] as Array).map(cond_name)
	if skill == "intimidation" and not CombatRules.parley_understood(session, Catalog.data):
		dis_why.append("без общего языка — жесты и оружие")  # v0.7.11
	p["disadvantage_reason"] = ", ".join(dis_why)
	p["auto_fail_reason"] = ", ".join((mods["auto_fail"] as Array).map(cond_name))
	var result := CheckEngine.roll(Catalog.rules(), session.rng, p, CheckEngine.bonus_for(session.character, p), session.next_check_id())
	var lines: Array[String] = ["%s — %s: %d против Сл %d — %s" % [session.character["name"], tr("SKILL_" + skill.to_upper()),
		int(result["total"]), int(result["dc"]), "успех" if bool(result["success"]) else "провал"]]
	var outcome := CombatRules.parley_apply(session, Catalog.data, skill, bool(result["success"]))
	lines.append_array(outcome)
	result["note"] = "Переговоры (исход решил движок): " + "; ".join(outcome)
	_add(GameSession.check_entry(p, result))
	return {"result": result, "lines": lines}


## «Осмотреться» (Perception) and «Обыскать» (Investigation, 10 minutes) buttons (v0.6.6, playtest-1): the engine
## rolls for the room (with the lock of a repeat), the master narrates the result and asks for no new check.
## "" or a localization key.
func search_room(skill: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session) or not ExplorationRules.SEARCH_SKILLS.has(skill):
		return "WAIT_NOT_NOW"
	var params := {"skill": skill, "dc_tier": "medium"}
	var result := _engine_check(params)
	if result.has("error"):
		return "MSG_MASTER_FAILED"
	if skill == "investigation":
		var passed := TimeRules.advance(session, Catalog.data, int(TimeRules.cfg(Catalog.data)["search_minutes"]))
		if not passed.is_empty():
			_add(GameSession.effect_entry(passed))
	var found: Array = result.get("revealed", [])
	var what := tr("SKILL_" + skill.to_upper())
	var note := "[движок уже бросил: %s %d%s — %s]" % [what, int(result["total"]), " (повтор без изменений)" if bool(result.get("blocked", false)) else "",
		("найдено: " + "; ".join(found)) if not found.is_empty() else "ничего нового"]
	var text := tr("SEARCH_SAY_" + skill.to_upper())
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	EventBus.state_changed.emit()
	_request("action", text + " " + note)
	return ""


## «Забрать всё» (the author, v0.7.8): the engine takes every portable thing of the room nobody owns, as long as the
## hero can carry it (PropRules.take_all), then the master narrates it — the same as the words «I take everything I
## can carry». "" or a localization key.
func take_all() -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var plan := PropRules.take_all_plan(session, Catalog.data)
	if (plan["take"] as Array).is_empty():
		return "TAKE_ALL_TOO_HEAVY" if not (plan["left"] as Array).is_empty() else "TAKE_ALL_NOTHING"
	var names := PropRules.take_all(session, Catalog.data)
	var left: Array = (plan["left"] as Array).map(func(p: Dictionary) -> String: return str(p["name"]))
	var lines: Array[String] = ["Взято: " + ", ".join(names)]
	if not left.is_empty():
		lines.append("не унести: " + ", ".join(left))
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	var text := tr("TAKE_ALL_SAY")
	_add(GameSession.player_entry(text))
	_add(GameSession.effect_entry(lines))
	_log("Игрок: " + text)
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже забрал: %s%s — эффекты take_prop не нужны; опиши коротко, как герой собирает вещи]" %
		[", ".join(names), ("; не унести: " + ", ".join(left)) if not left.is_empty() else ""])
	return ""


## The theft window (v0.7.0): a Sleight of Hand against the entry's DC; success — it is taken; failure — the NPC
## reacts by its kind. The master narrates it (kind=theft); a fight it causes starts after. "" or a localization key.
func steal(npc_id: String, entry_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "WAIT_BUSY"
	var why := TheftRules.can_steal(session, Catalog.data, npc_id)
	if not why.is_empty():
		return why
	var entry := {}
	for e: Dictionary in TheftRules.pockets(session, Catalog.data, npc_id):
		if str(e["id"]) == entry_id:
			entry = e
	if entry.is_empty():
		return "THEFT_NOBODY"
	var params := {"skill": "sleight_of_hand", "dc_tier": "medium", "dc": int(entry["dc"]), "target_id": npc_id}
	var mods := ConditionRules.check_mods(session.character, Catalog.data, params)
	var cond_name := func(id: Variant) -> String: return tr("COND_" + str(id).to_upper())
	params["disadvantage_reason"] = ", ".join((mods["disadvantage"] as Array).map(cond_name))
	params["advantage_reason"] = tr("THEFT_HIDDEN") if session.sneaking else ""
	var result := CheckEngine.roll(Catalog.rules(), session.rng, params, CheckEngine.bonus_for(session.character, params), session.next_check_id())
	_add(GameSession.check_entry(params, result))
	var lines := TheftRules.steal(session, Catalog.data, npc_id, entry_id, bool(result["success"]))
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("theft", "карманы %s — %s (%s): %s" % [world().npc(npc_id).get("name", npc_id), entry["name"],
		"успех" if bool(result["success"]) else "провал", "; ".join(lines)])
	return ""


## The «Красться» toggle of exploration (v0.6.2): entering a room with an encounter the engine rolls Stealth for
## surprise; passive Perception for hidden things is 5 lower while sneaking (PHB).
## Among people (v0.6.5, playtest-1) it is a Stealth roll against the best passive Perception of the NPCs here: a
## failure — they noticed, no sneaking in this room until the player leaves it. "" or a localization key.
func set_sneaking(on: bool) -> String:
	if session == null:
		return "SNEAK_BUSY"
	if not on:
		session.sneaking = false
		EventBus.state_changed.emit()
		return ""
	if session.sneak_noticed == session.room_id:
		EventBus.state_changed.emit()
		return "SNEAK_NOTICED"
	var line := _sneak_past_people(session.room_id)
	if not line.is_empty():
		_add(GameSession.effect_entry([line]))
		_log("События: " + line)
	session.sneaking = session.sneak_noticed != session.room_id
	EventBus.state_changed.emit()
	return "" if session.sneaking else "SNEAK_NOTICED"


## A Stealth roll against the NPCs of `room_id` (none — no roll, ""). A failure marks the room noticed. The line.
func _sneak_past_people(room_id: String) -> String:
	var npcs := session.npcs_alive(world().npcs_in(room_id))
	if npcs.is_empty():
		return ""
	var best := 0
	var who := ""
	for id: String in npcs:
		var m: Dictionary = Catalog.data["monsters"].get(str(world().npc(id).get("monster", CombatRules.cfg(Catalog.data)["default_npc_monster"])), {})
		var pp := int(m.get("passive_perception", 10)) - ConditionRules.unseen_penalty(session.character, Catalog.data)
		if pp >= best:
			best = pp
			who = str(world().npc(id).get("name", id))
	var roll := CombatRules.stealth_roll(session, Catalog.data)
	if int(roll["total"]) >= best:
		return "Крадётесь: Скрытность %d%s против Внимательности %d — никто не обращает внимания" % [int(roll["total"]), roll["note"], best]
	session.sneak_noticed = room_id
	session.sneaking = false
	return "Крадётесь: Скрытность %d%s против Внимательности %d — %s замечает вас" % [int(roll["total"]), roll["note"], best, who]


## Plays the turns of the others with a pause per actor until it is the player's turn (alive), the round ends
## (the master narrates it) or the fight ends (the final narration, then the results).
func _combat_continue() -> void:
	if combat_playing or session == null or not CombatRules.active(session) or not busy_turn.is_empty():
		return
	var s := session
	combat_playing = true
	while CombatRules.active(s) and session == s:
		if s.combat.has("pending"):  # the hero is asked about a reaction (v0.7.10): combat_react goes on
			break
		if bool(s.combat.get("round_ended", false)):
			s.combat.erase("round_ended")
			combat_playing = false
			_narrate_round()
			return
		if not str(s.combat.get("outcome", "")).is_empty():
			combat_playing = false
			_combat_outcome()
			return
		if CombatRules.player_can_act(s):
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
	if outcome in ["victory", "truce"]:
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
	if outcome in ["victory", "truce"]:
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
	for cond: String in ["unconscious", "prone", "grappled"]:  # the fight is over: up, and nobody holds the hero
		ConditionRules.remove(s.character, cond)
	lines.append_array(FeatureRules.end_shape(s, Catalog.data, 0))  # the beast form ends with the fight (v0.7.10)
	var frenzied := bool(s.combat.get("frenzy", false))
	var minutes := ceili(int(s.combat.get("round", 1)) / float(ConditionRules.ROUNDS_PER_MINUTE))
	s.combat = {}
	lines.append_array(TimeRules.advance(s, Catalog.data, minutes))  # the rounds of the fight on the clock (v0.7.8)
	if frenzied:
		lines.append_array(ConditionRules.add_exhaustion(s, Catalog.data, 1, "неистовство"))
	s.mode = GameSession.MODE_EXPLORATION
	CharacterRules.refresh(s.character, Catalog.data, s.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	_set_options([])
	_quest_progress()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	EventBus.state_changed.emit()
	EventBus.navigate.emit("game", {})


## Changes the master style of the running game (settings screen); kept in the save.
func set_dm_style(style: String) -> void:
	if session != null and WorldPack.DM_STYLES.has(style):
		session.settings["dm_style"] = style


func start(s: GameSession) -> void:
	s.settings["reactions"] = SaveManager.reactions  # the player's choice of the settings (v0.7.10)
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


## An option button of the master: a paid one (option_costs, v0.6.5) takes the coins first — the engine, not the
## master's words; the turn input tells the master it is paid. "" or a localization key.
func choose_option(index: int) -> String:
	if session == null or index < 0 or index >= session.options.size():
		return "MSG_NO_MASTER"
	var text := session.options[index]
	var cost := session.option_costs[index] if index < session.option_costs.size() else 0
	if cost <= 0:
		return "" if submit(text) else "MSG_NO_MASTER"
	if int(session.character["gold_cp"]) < cost:
		return "MSG_NO_MONEY"
	if is_busy() or not Backend.is_ready():
		return "MSG_NO_MASTER"
	session.character["gold_cp"] = int(session.character["gold_cp"]) - cost
	var paid := "−" + Money.format(cost)
	_add(GameSession.effect_entry([paid]))
	_log("События: " + paid)
	EventBus.state_changed.emit()
	return "" if submit(text, "[движок уже списал %s]" % Money.format(cost)) else "MSG_NO_MASTER"


## «Ждать» (v0.6.5): an hour or until a part of the day; not in a conversation or a fight. The master tells how the
## time passed (kind=wait). "" or a localization key.
func wait(target: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "WAIT_BUSY"
	if session.in_conversation() or CombatRules.active(session):
		return "WAIT_NOT_NOW"
	var mins := TimeRules.minutes_until(session, Catalog.data, target)
	if mins <= 0:
		return "WAIT_NOT_NOW"
	var lines: Array[String] = ["Ожидание до %s" % TimeRules.clock_after(session, mins)]
	lines.append_array(TimeRules.advance(session, Catalog.data, mins))
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("wait", "; ".join(lines))
	return ""


## Returns false when the input cannot be sent now (empty, a turn in flight, no master). `engine_note` goes to the
## master after the text (a paid option), never into the chat.
func submit(text: String, engine_note: String = "") -> bool:
	text = text.strip_edges()
	var pinned := not attached.is_empty() and session != null and session.mode != GameSession.MODE_COMBAT
	if session == null or (text.is_empty() and not pinned) or is_busy() or not Backend.is_ready():
		return false
	if pinned and text.is_empty():  # the attachment alone: a cast as from the sheet
		var why := _use_alone(attached)
		if not why.is_empty():
			EventBus.message.emit(tr(why))
			return false
		attached = {}
		return true
	if session.mode == GameSession.MODE_COMBAT:
		if not CombatRules.player_can_act(session) or int(CombatRules.economy(session).get("action", 0)) <= 0:
			EventBus.message.emit(tr("COMBAT_NO_ACTION"))
			return false
		CombatRules.economy(session)["action"] = int(CombatRules.economy(session)["action"]) - 1
	var facts := ""
	if pinned:
		var backup := session.character.duplicate(true)
		var spent := _spend(attached)
		if spent.has("reason"):
			EventBus.message.emit(tr(str(spent["reason"])))
			return false
		_refund = backup
		_refund_what = attached
		_retry_spend = {}
		_opening = {}
		var data: Dictionary = Catalog.data
		if str(attached.get("kind", "")) == "spell" and not str(attached.get("target", "")).is_empty() and CombatRules.is_engine_spell(data, str(attached["id"])):
			_opening = {"spell": str(attached["id"]), "slot": int(attached.get("spent_slot", 0)), "npc_id": str(attached["target"])}
			spent["facts"] = str(spent["facts"]) + " Если этим игрок нападает на NPC — начни бой с ним (next_mode combat): исход заклинания движок разрешит первым ходом боя, урон и последствия не описывай."
		attached = {}
		_add(GameSession.effect_entry(spent["lines"]))
		_log("События: " + ", ".join(spent["lines"]))
		facts = " [Вместе с этим, до слов игрока: %s]" % spent["facts"]
	_add(GameSession.player_entry(text))
	_log("Игрок: " + text)
	_request("action", text + facts + ((" " + engine_note) if not engine_note.is_empty() else ""))
	return true


## Exit button: the engine moves the player (no model decision), then the master describes the new room.
func go(room_id: String) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not ExplorationRules.open_exits(session, Catalog.data["world"], session.room_id).has(room_id):
		return false
	if CharacterRules.overloaded(session.character, Catalog.data, session.items):
		EventBus.message.emit(tr("TOO_HEAVY"))
		return false
	_end_conversation()
	var from := session.room_id
	var lines: Array[String] = []
	var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, room_id)
	if not trap.is_empty():
		if ExplorationRules.is_found(session, from, trap):
			return false  # a found trap: disarm it or go around it (trap_action)
		lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
		if _trap_downed(lines):
			return true
	_move_to(room_id, lines)
	return true


## Steps into `room_id`: time passes, passive Perception (sneaking, darkness), caches, quest steps; an encounter
## starts the fight, otherwise the master describes the room. `lines` — what happened on the way (a trap).
func _move_to(room_id: String, lines: Array[String]) -> void:
	var from := session.room_id
	_step(room_id, lines)
	lines.push_front("Переход: %s" % world().room(room_id).get("name", room_id))
	_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	if _live_encounter(room_id):
		var enc: Dictionary = world().room(room_id)["encounter"]
		start_combat(enc["enemies"], {"encounter": str(enc["id"]), "room_from": from, "sneak": session.sneaking,
			"ambush": bool(enc.get("ambush", false)), "waves": enc.get("waves", []), "help": enc.get("help", {}), "parley": str(enc.get("parley", ""))})
		return
	_request("enter", "\n".join(lines.slice(1)))


## The engine side of a step into `room_id` (no master, no fight): sneaking past people, time, passive Perception,
## caches, quest steps. Appends the lines; returns what passive Perception found on entering.
func _step(room_id: String, lines: Array[String]) -> Array[String]:
	var from := session.room_id
	if session.sneak_noticed != room_id:
		session.sneak_noticed = ""  # a new room: people there have not seen the player sneak yet
	if session.sneaking:
		var seen := _sneak_past_people(room_id)
		if not seen.is_empty():
			lines.append(seen)
	lines.append_array(TimeRules.on_move(session, Catalog.data, from, room_id))
	var found := ExplorationRules.enter_room(session, Catalog.data["world"], room_id, TimeRules.passive_penalty(session, Catalog.data))
	lines.append_array(ExplorationRules.take_caches(session, Catalog.data, room_id))
	lines.append_array(QuestRules.advance(session, Catalog.data))
	return found


func _live_encounter(room_id: String) -> bool:
	var enc: Dictionary = world().room(room_id).get("encounter", {})
	return not enc.is_empty() and not session.encounters_done.has(str(enc["id"]))


## «Идти сюда» on the map (roadmap v0.7.6, decisions of the author): a fast travel to a visited room along known
## paths. The engine walks the route step by step without the master: time, sneaking, passive Perception, caches,
## quest steps; the line «Путь: … · N мин» goes to the chat and the history. It stops on a live encounter (that
## step is an ordinary move — the fight starts), on a trap that springs (an ordinary move — the master tells it)
## and before an exit whose trap the hero has just noticed. "" or a localization key.
func travel(to: String) -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.mode == GameSession.MODE_COMBAT:
		return "TRAVEL_BUSY"
	var path := WorldMap.route(session, Catalog.data["world"], session.room_id, to)
	if path.is_empty():
		return "TRAVEL_NO_ROUTE"
	if CharacterRules.overloaded(session.character, Catalog.data, session.items):
		return "TOO_HEAVY"
	_end_conversation()
	var names: Array[String] = [str(world().room(session.room_id).get("name", session.room_id))]
	var lines: Array[String] = []
	var minute0 := session.day * 1440 + session.minute
	for to_room: String in path:
		var from := session.room_id
		var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, to_room)
		if not trap.is_empty() and ExplorationRules.is_found(session, from, trap):
			lines.append("Дальше путь стережёт найденная ловушка — переход остановлен")
			break
		if not trap.is_empty() or _live_encounter(to_room):
			_travel_line(names, minute0, lines)
			var step_lines: Array[String] = []
			if not trap.is_empty():
				step_lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
				if _trap_downed(step_lines):
					return ""
			_move_to(to_room, step_lines)
			return ""
		for f: String in _step(to_room, lines):
			lines.append("Замечено: " + f)
		names.append(str(world().room(to_room).get("name", to_room)))
		if ConditionRules.dead(session.character):
			break
	_travel_line(names, minute0, lines)
	EventBus.state_changed.emit()
	if _exhaustion_death():
		return ""
	SaveManager.save_slot(SaveManager.AUTOSAVE, session)
	return ""


## «Путь: A → B → C · N мин» and what happened on the way, into the chat and the history (no master turn).
func _travel_line(names: Array[String], minute0: int, lines: Array[String]) -> void:
	if names.size() < 2 and lines.is_empty():
		return
	var all: Array[String] = ["Путь: %s · %d мин" % [" → ".join(names), session.day * 1440 + session.minute - minute0]]
	all.append_array(lines)
	_add(GameSession.effect_entry(all))
	_log("События: " + ", ".join(all))


## A trap brought the character to 0 HP outside combat: they come to on the spot (no death), the master tells the
## cost. True when that happened (the move does not go on).
func _trap_downed(lines: Array[String]) -> bool:
	if int(session.character["hp"]) > 0:
		return false
	lines.append_array(ExplorationRules.knock_out(session))
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("downed", "")
	return true


## A found trap on the exit to `to`: «Обезвредить» (Sleight of Hand with thieves' tools) — success spends it,
## the player stays; «Обойти» (Acrobatics) — success passes on. Both against disarm_dc; a failure springs the trap.
## "" or a localization key.
func trap_action(to: String, disarm: bool) -> String:
	if session == null or is_busy() or not Backend.is_ready() or session.in_conversation():
		return "TRAP_BUSY"
	var from := session.room_id
	var trap := ExplorationRules.trap_on_exit(session, Catalog.data["world"], from, to)
	if trap.is_empty() or not ExplorationRules.is_found(session, from, trap):
		return "TRAP_NONE"
	var t: Dictionary = trap["trap"]
	var params := {"skill": "sleight_of_hand" if disarm else "acrobatics", "dc_tier": "medium", "dc": int(t["disarm_dc"]),
		"target_id": str(trap["id"])}
	var bonus := CheckEngine.bonus_for(session.character, params)
	if disarm:
		var db := ExplorationRules.disarm_bonus(session.character)
		bonus = int(db["bonus"])
		params["disadvantage_reason"] = str(db["disadvantage_reason"])
	var result := CheckEngine.roll(Catalog.rules(), session.rng, params, bonus, session.next_check_id())
	_add(GameSession.check_entry(params, result))
	var lines: Array[String] = []
	if bool(result["success"]):
		if disarm:
			ExplorationRules.disarm_trap(session, from, trap)
			lines.append("Ловушка обезврежена: %s" % trap["text"])
			_add(GameSession.effect_entry(lines))
			_log("События: " + ", ".join(lines))
			EventBus.state_changed.emit()
			_request("trap", "\n".join(lines))
			return ""
		lines.append("Ловушка обойдена — она по-прежнему на месте")
		_move_to(to, lines)
		return ""
	lines = ExplorationRules.spring_trap(session, Catalog.data, from, trap)
	if _trap_downed(lines):
		return ""
	if disarm:
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))
		EventBus.state_changed.emit()
		_request("trap", "\n".join(lines))
		return ""
	_move_to(to, lines)
	return ""


## The giver's button: take a quest with steps (QuestRules); the master plays the giver (kind=quest). "" or a key.
func accept_quest(quest_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_accept(session, Catalog.data["world"], quest_id)
	if not why.is_empty():
		return why
	var q := QuestRules.quest(Catalog.data["world"], quest_id)
	var lines := QuestRules.accept(session, Catalog.data, quest_id)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("quest", "%s даёт игроку задание «%s». %s %s" % [world().npc(str(q["giver"])).get("name", ""), q["title"],
		str(q.get("offer_text", q.get("description", ""))), " ".join(lines.slice(1))])
	return ""


## A talk step of a quest: the button at the NPC closes it (the item is handed over); the master narrates. "" or a key.
func quest_talk(quest_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_talk(session, Catalog.data["world"], quest_id)
	if not why.is_empty():
		return why
	var step := QuestRules.current(session, Catalog.data["world"], quest_id)
	var lines := QuestRules.talk(session, Catalog.data, quest_id)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("quest", "%s Итог: %s." % [str(step.get("done_text", step["text"])), ", ".join(lines)])
	return ""


## A choice step of a quest (v0.6.4): the button in its room makes the choice — its rewards and world flag — and the
## master narrates it with the choice's done_text. "" or a localization key.
func quest_choose(quest_id: String, choice_id: String) -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "QUEST_BUSY"
	var why := QuestRules.can_choose(session, Catalog.data["world"], quest_id, choice_id)
	if not why.is_empty():
		return why
	var c := QuestRules.choice(session, Catalog.data["world"], quest_id, choice_id)
	var lines := QuestRules.choose(session, Catalog.data, quest_id, choice_id)
	CharacterRules.refresh(session.character, Catalog.data, session.items)
	_add(GameSession.effect_entry(lines))
	_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()
	_request("quest", "%s Итог: %s." % [str(c.get("done_text", c["action"])), ", ".join(lines)])
	return ""


## Quest steps closed by new facts (a fight finished, a secret found, a flag set) go to the chat.
func _quest_progress() -> void:
	var lines := QuestRules.advance(session, Catalog.data)
	if not lines.is_empty():
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))


## NPC button: start a conversation (or trade with a trader); the NPC greets the player.
func talk_to(npc_id: String, trade: bool = false) -> bool:
	if session == null or is_busy() or not Backend.is_ready() or not session.npcs_alive(world().npcs_in(session.room_id)).has(npc_id):
		return false
	if trade and (not world().is_trader(npc_id) or TimeRules.shops_closed(session, Catalog.data) or TheftRules.shop_closed_for(session, npc_id)):
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
## An attached spend given back by the failed turn is spent again first (its facts are in the input).
func retry() -> void:
	if not can_retry():
		return
	if not _retry_spend.is_empty():
		var backup := session.character.duplicate(true)
		var spent := _spend(_retry_spend)
		if spent.has("reason"):
			EventBus.message.emit(tr(str(spent["reason"])))
			return
		_refund = backup
		_refund_what = _retry_spend
		_retry_spend = {}
		_add(GameSession.effect_entry(spent["lines"]))
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
	if (slot == "armor" or slot == "shield") and session.mode == GameSession.MODE_COMBAT:
		return "EQUIP_IN_COMBAT"
	var why := CharacterRules.can_equip(c, Catalog.data, session.items, item_id, slot)
	if not why.is_empty():
		return why
	var before: Dictionary = (c["equipped"] as Dictionary).duplicate()
	c["equipped"][slot] = item_id
	if slot == "main_hand" and str(c["equipped"].get("off_hand", "")) == item_id and int(c["inventory"][item_id]) < 2:
		c["equipped"]["off_hand"] = ""
	_gear_changed(before)
	return ""


func unequip(slot: String) -> void:
	if session == null or is_busy():
		return
	if (slot == "armor" or slot == "shield") and session.mode == GameSession.MODE_COMBAT:
		EventBus.message.emit(tr("EQUIP_IN_COMBAT"))
		return
	var before: Dictionary = (session.character["equipped"] as Dictionary).duplicate()
	session.character["equipped"][slot] = ""
	_gear_changed(before)


## After the sheet changed the gear: the minutes of armour (v0.7.7, rules.equip_minutes) pass and show in the chat
## and the history, so the master knows the hero is now in other clothes.
func _gear_changed(before: Dictionary) -> void:
	var c := session.character
	CharacterRules.refresh(c, Catalog.data, session.items)
	var minutes := CharacterRules.gear_minutes(Catalog.data, session.items, before, c["equipped"])
	if minutes > 0 and session.mode != GameSession.MODE_COMBAT:
		var lines: Array[String] = []
		for slot: String in ["armor", "shield"]:
			var was := str(before.get(slot, ""))
			var now := str(c["equipped"].get(slot, ""))
			if was != now:
				if not was.is_empty():
					lines.append("Снято: " + ItemRules.display_name(Catalog.data["items"], session.items, was))
				if not now.is_empty():
					lines.append("Надето: " + ItemRules.display_name(Catalog.data["items"], session.items, now))
		lines.append("Переодевание: %d мин" % minutes)
		lines.append_array(TimeRules.advance(session, Catalog.data, minutes))
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))
	EventBus.state_changed.emit()


func save_to(slot: String) -> bool:
	return SaveManager.save_slot(slot, session)


## "" on success or a localization key.
func load_from(slot: String) -> String:
	var res: Variant = SaveManager.read_slot(slot)
	if res is String:
		return res
	start(res)
	if not session.fight_on_load.is_empty() and not CombatRules.active(session):
		var fight := session.fight_on_load
		session.fight_on_load = {}
		_restart_fight.call_deferred(fight)  # after the game screen opens
	return ""


## The pre-fight save was loaded: the same fight starts again (v0.7.2).
func _restart_fight(fight: Dictionary) -> void:
	if session != null and not CombatRules.active(session):
		start_combat(fight.get("foes", []), fight.get("source", {}))


# --- turn --------------------------------------------------------------------------


func _add(entry: Dictionary) -> void:
	session.append(entry)
	EventBus.chat_appended.emit(entry)


func _set_options(options: Array[String], costs: Array[int] = []) -> void:
	session.options = options
	session.option_costs = costs
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
	_retry_spend = {}  # a new turn: an older given-back spend is not repeated
	_last_kind = kind
	if kind in ["action", "ability"]:
		effects.player_turns[turn_id] = true
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
		if not _refund.is_empty():  # the attached spend did not reach the master: give the slot back
			session.character.clear()
			session.character.merge(_refund)
			_refund = {}
			_retry_spend = _refund_what
			_refund_what = {}
			_opening = {}
			_add(GameSession.system_entry("ATTACH_REFUNDED"))
		_show_start_lines()
		_add(GameSession.system_entry(_error_key(call.reason())))
		EventBus.turn_finished.emit(turn_id, false)
		return
	_refund = {}
	_refund_what = {}
	_retry_spend = {}
	var turn_kind := _last_kind
	_last_kind = ""
	var follow_up := _apply_result(s, turn_id, call.result, turn_kind)
	EventBus.turn_finished.emit(turn_id, true)
	EventBus.state_changed.emit()
	SaveManager.save_slot(SaveManager.AUTOSAVE, s)
	_maybe_summarize_location()
	if follow_up != "combat":
		_opening = {}
	if kind == "death" and s.mode != GameSession.MODE_COMBAT:
		EventBus.navigate.emit("death", {"epitaph": str(call.result.get("narration", ""))})
		return
	if follow_up == "combat":
		_start_pending_fight()
	elif not follow_up.is_empty():
		_request(follow_up, "")
	elif s.mode == GameSession.MODE_COMBAT:
		_show_start_lines()
		if str(s.combat.get("outcome", "")) == "dead" and kind == "death":
			EventBus.navigate.emit("death", {"epitaph": str(call.result.get("narration", ""))})
		else:
			_combat_continue()


## Shows the narration, applies listed reserves, handles next_mode. Returns the follow-up turn kind or "".
func _apply_result(s: GameSession, turn_id: String, result: Dictionary, turn_kind: String = "") -> String:
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
	var costs: Array[int] = []
	for c: Variant in result.get("option_costs", []):
		costs.append(maxi(0, int(c)))
	_set_options(options, costs)

	if s.mode == GameSession.MODE_COMBAT:
		var after := CombatRules.after_player_action(s, Catalog.data)
		if not after.is_empty():
			_combat_log(after)
		return ""
	if not s.pending_fight.is_empty():
		return "combat"
	if ConditionRules.incapacitated(s.character) and int(s.character["hp"]) > 0:
		var slept := _sleep_through()
		if not slept.is_empty():
			_add(GameSession.effect_entry(slept))
			_log("События: " + ", ".join(slept))
	if ConditionRules.dead(s.character) and turn_kind != "death":
		_request.call_deferred("death", "Герой умирает от истощения (шестая степень).\n" + _hero_path())
		return ""
	if int(s.character["hp"]) <= 0:
		var out := ExplorationRules.knock_out(s)
		_add(GameSession.effect_entry(out))
		_log("События: " + ", ".join(out))
		_end_conversation()
		return "downed"

	_quest_progress()
	if s.room_id != room_before:
		var moved := TimeRules.on_move(s, Catalog.data, room_before, s.room_id)
		ExplorationRules.enter_room(s, Catalog.data["world"], s.room_id, TimeRules.passive_penalty(s, Catalog.data))
		moved.append_array(ExplorationRules.take_caches(s, Catalog.data, s.room_id))
		moved.append_array(QuestRules.advance(s, Catalog.data))
		if not moved.is_empty():
			_add(GameSession.effect_entry(moved))
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
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and not s.in_conversation() and turn_kind != "action":
		return ""  # a conversation starts only from the player's own words (v0.7.2: the master opened one on «resume»)
	if mode in [GameSession.MODE_SOCIAL, GameSession.MODE_TRADE] and s.npcs_alive(world().npcs_in(s.room_id)).has(npc_id):
		if mode == GameSession.MODE_TRADE and (not world().is_trader(npc_id) or TimeRules.shops_closed(s, Catalog.data) or TheftRules.shop_closed_for(s, npc_id)):
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
	if session.mode == GameSession.MODE_COMBAT and CombatRules.active(session) and params.get("skill") != null \
			and CombatRules.can_parley(session, Catalog.data, str(params["skill"])).is_empty():
		var parley := _parley_check(params)
		_combat_log(parley["lines"])
		return parley["result"]
	return _engine_check(params)


## An engine check (the master's request_check or a button of the client): DC by tier, conditions and darkness,
## the lock of a repeat, theft, hidden things and caches found. Adds the check card.
func _engine_check(params: Dictionary) -> Dictionary:
	params.erase("dc")  # the DC number and condition effects are the engine's
	var mods := ConditionRules.check_mods(session.character, Catalog.data, params)
	var cond_name := func(id: Variant) -> String: return tr("COND_" + str(id).to_upper())
	var dis: Array = (mods["disadvantage"] as Array).map(cond_name)
	if str(params.get("skill", "")) == "perception" and TimeRules.dark(session, Catalog.data):
		dis.append("темнота")
	params["disadvantage_reason"] = ", ".join(dis)
	params["auto_fail_reason"] = ", ".join((mods["auto_fail"] as Array).map(cond_name))
	params["reroll_ones"] = CharacterRules.has_trait(session.character, "lucky")  # v0.7.10
	# v0.7.11: the words reach only who understands them; a tool of the check.
	var skill_id := str(params.get("skill", "")) if params.get("skill") != null else ""
	var listener := _listener(params)
	if not listener.is_empty():
		var gate := LanguageRules.check_gate(session.character, Catalog.data, skill_id, LanguageRules.npc_understands(session.character, Catalog.data, listener))
		if gate.has("auto_fail"):
			params["auto_fail_reason"] = ", ".join(([params["auto_fail_reason"]] if not str(params["auto_fail_reason"]).is_empty() else []) + [gate["auto_fail"]])
		if gate.has("disadvantage"):
			params["disadvantage_reason"] = ", ".join(([params["disadvantage_reason"]] if not str(params["disadvantage_reason"]).is_empty() else []) + [gate["disadvantage"]])
	var tool := str(params.get("tool", "")) if params.get("tool") != null else ""
	var tool_fx := BackgroundRules.tool_check(session.character, Catalog.data, tool, skill_id)
	if not str(tool_fx["auto_fail"]).is_empty():
		params["auto_fail_reason"] = ", ".join(([params["auto_fail_reason"]] if not str(params["auto_fail_reason"]).is_empty() else []) + [tool_fx["auto_fail"]])
	if not str(tool_fx["advantage"]).is_empty() and str(params.get("advantage_reason", "")).is_empty():
		params["advantage_reason"] = tool_fx["advantage"]
	if CombatRules.active(session) and bool(session.combat.get("raging", false)) and str(params.get("skill", "")) == "athletics" \
			and str(params.get("advantage_reason", "")).is_empty():
		params["advantage_reason"] = "ярость"
	var boots := CharacterRules.carried_with(session.character, Catalog.data, session.items, "stealth_advantage")
	if str(params.get("skill", "")) == "stealth" and not boots.is_empty() and str(params.get("advantage_reason", "")).is_empty():
		params["advantage_reason"] = boots
	var room := session.room_id
	var result: Dictionary
	var lock := ExplorationRules.locked(session, params, room)
	if not lock.is_empty():
		# A repeat without a change: the old result, no roll (ADR-0008 §2).
		result = (lock["result"] as Dictionary).duplicate()
		result["check_id"] = session.next_check_id()
		result["blocked"] = true
	else:
		var bonus := CheckEngine.bonus_for(session.character, params) + _terrain_bonus(params) + int(tool_fx["bonus"])
		result = CheckEngine.roll(Catalog.rules(), session.rng, params, bonus, session.next_check_id())
		if result.has("error"):
			return JsonRpcPeer.fail(JsonRpcPeer.ERR_INVALID_PARAMS, str(result["error"]))
		if not bool(result["success"]) and int(result["nat"]) != 1 and str(params.get("auto_fail_reason", "")).is_empty():
			var insp := FeatureRules.use_inspiration(session)  # Bardic Inspiration on a failed check (v0.7.10)
			if insp > 0:
				result["total"] = int(result["total"]) + insp
				result["bonus"] = int(result["bonus"]) + insp
				result["success"] = int(result["total"]) >= int(result["dc"])
		ExplorationRules.lock(session, params, room, result)
		var mark := _theft_target(params)
		if not mark.is_empty():
			result["note"] = _theft(mark, bool(result["success"]))
		if bool(result["success"]) and params.get("skill") != null:
			result["revealed"] = ExplorationRules.active_reveal(session, Catalog.data["world"], str(params["skill"]), int(result["total"]))
	_add(GameSession.check_entry(params, result))
	if not (result.get("revealed", []) as Array).is_empty():
		var found := ExplorationRules.take_caches(session, Catalog.data, room)
		found.append_array(QuestRules.advance(session, Catalog.data))
		if not found.is_empty():
			_add(GameSession.effect_entry(found))
			_log("События: " + ", ".join(found))
	return result


## The NPC a social check speaks to: the check's target or the one the hero talks with ({} — none).
func _listener(params: Dictionary) -> Dictionary:
	var tid := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	if tid.is_empty() and session.in_conversation():
		tid = session.npc_id
	return world().npc(tid) if not tid.is_empty() else {}


## «Выступить» (v0.7.11): a Performance check on a stage of the pack, once a day; coins and, for an entertainer, a free
## room tonight; the master narrates the show. "" or a localization key.
func perform() -> String:
	if session == null or is_busy() or not Backend.is_ready():
		return "WAIT_BUSY"
	var why := BackgroundRules.can_perform(session, Catalog.data)
	if not why.is_empty():
		return why
	var text := tr("PERFORM_SAY")
	_add(GameSession.player_entry(text))
	var result := _engine_check({"skill": "performance", "dc_tier": str(Catalog.rules()["backgrounds"]["_perform"]["dc_tier"])})
	if result.has("error"):
		return "MSG_MASTER_FAILED"
	var lines := BackgroundRules.performed(session, Catalog.data, int(result["total"]), bool(result["success"]))
	_add(GameSession.effect_entry(lines))
	EventBus.state_changed.emit()
	_request("action", text + " [движок уже бросил Выступление %d — %s; %s — эффекты coins не нужны, опиши выступление и публику]" %
		[int(result["total"]), "успех" if bool(result["success"]) else "провал", ", ".join(lines)])
	return ""


## Natural Explorer (v0.7.10): in the ranger's favored terrain (`terrain` of the pack's location) a proficient INT or
## WIS skill gets the proficiency bonus twice.
func _terrain_bonus(params: Dictionary) -> int:
	var c := session.character
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	if skill.is_empty() or not str(Catalog.rules()["skills"].get(skill, "")) in ["int", "wis"]:
		return 0
	var terrain := str(world().location(world().location_id(session.room_id)).get("terrain", ""))
	if terrain.is_empty() or not CharacterRules.has_feature(c, "natural_explorer_" + terrain):
		return 0
	var proficient := (c.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(c, "skill_prof_" + skill)
	return CharacterRules.prof_bonus(c, Catalog.data) if proficient else 0


## The NPC of the scene a Sleight of Hand check aims at (theft by words, v0.6.5), or "".
func _theft_target(params: Dictionary) -> String:
	if str(params.get("skill", "")) != "sleight_of_hand" or CombatRules.active(session):
		return ""
	var tid := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	return tid if session.npcs_alive(world().npcs_in(session.room_id)).has(tid) else ""


## Theft by words: the engine gives the loot (rules.theft) or the NPC notices; the master narrates the note.
func _theft(npc_id: String, ok: bool) -> String:
	var who := str(world().npc(npc_id).get("name", npc_id))
	var lines: Array[String] = []
	var note := ""
	var cp := TheftRules.take_purse(session, Catalog.data, npc_id) if ok else 0
	if ok and cp <= 0:
		note = "Кража: у %s в кошеле больше ничего нет" % who
	elif ok:
		lines.append("%s — украдено: %s" % [who, Money.format(cp)])
		note = "Кража удалась, %s ничего не заметил(а): движок уже выдал %s (зм — золотые, см — серебряные, мм — медные) — опиши добычу ровно так" % [who, Money.format(cp)]
	else:
		session.caught_by[npc_id] = session.day
		lines.append("%s замечает руку в кармане" % who)
		lines.append_array(TheftRules.react(session, Catalog.data, npc_id))
		note = "Кража провалилась: " + "; ".join(lines) + " — движок уже всё применил"
	if not lines.is_empty():
		_add(GameSession.effect_entry(lines))
		_log("События: " + ", ".join(lines))
	return note


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
